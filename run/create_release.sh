#!/usr/bin/env bash
# Propose a release, wait for manual PR merge, then publish its artifact.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/aux/common.sh"
wait_and_publish() {
  bash "$SCRIPT_DIR/aux/publish_release.sh" "$1" --wait
  printf 'Next: ./run/deploy_project.sh PRO %s\n' "$1"
}
if [[ "${1:-}" == --resume ]]; then
  [[ $# -eq 2 ]] || die "Usage: $0 --resume <version>"
  wait_and_publish "$2"
  exit 0
fi
[[ $# -eq 2 || ( $# -eq 4 && "$3" == --custom ) ]] || die "Usage: $0 <release_name> <version> [--custom SQL_file]"
custom_file=''
if [[ $# -eq 4 ]]; then
  custom_file="$(python3 - "$4" <<'PYCODE'
from pathlib import Path
import re,sys
p=Path(sys.argv[1])
if p.is_symlink() or not p.is_file() or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]*\.sql',p.name):
    raise SystemExit('Custom migration must be a regular SQL file with a simple filename.')
print(p.resolve())
PYCODE
)" || die "Invalid custom migration file."
fi
require_tools git gh python3
load_project
"$SCRIPT_DIR/aux/check_environment.sh" DEV
release_name="$1"
version="$2"
validate_name "$release_name"
validate_version "$version"
base="${PROJECT_BRANCH:-main}"
# SQLcl 26.3 verification treats '/' as a changelog directory separator.
# Keep generated release branch names flat so stage verification can resolve them.
branch="${release_name}-${version}"
git check-ref-format --branch "$branch" >/dev/null || die "Invalid release branch name."
[[ "$branch" != "$base" ]] || die "Release branch must differ from the project base branch."
tag="${RELEASE_TAG_PREFIX:-v}${version}"
cd "$PROJECT_DIR"
[[ -z "$(git status --porcelain)" ]] || die "The project working tree must be clean."
git fetch origin
git checkout "$base"
git pull --ff-only origin "$base"
! git show-ref --verify --quiet "refs/heads/$branch" || die "Release branch already exists: $branch"
! git show-ref --verify --quiet "refs/remotes/origin/$branch" || die "Remote release branch already exists: $branch"
if gh release view "$tag" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  die "GitHub release already exists: $tag"
fi
git checkout -b "$branch"
echo "Exporting database structures and native APEXlang sources with SQLcl Projects; output appears when the stage finishes..."
run_sql "$DB_CONNECT_DEV" "export-$version" <<'EOF'
project export
EOF
python3 "$SCRIPT_DIR/aux/normalize_staged_sql.py" --project-dir "$PROJECT_DIR" --source-files --app-id "$APEX_APP_ID"
git add src
if git diff --cached --quiet; then
  [[ -n "$custom_file" ]] || die "No source changes were exported."
else
  git commit -m "feat: capture sources for release $version ($release_name)"
fi
echo "Staging release $version..."
run_sql "$DB_CONNECT_DEV" "stage-$version" <<EOF
project stage -branch-name $base
EOF
if [[ -n "$custom_file" ]]; then
  custom_name="$(basename "$custom_file")"
  run_sql "$DB_CONNECT_DEV" "custom-$version" <<EOF
project stage add-custom -file-name $custom_name
EOF
  python3 - "$custom_file" "$custom_name" <<'PYCODE'
from pathlib import Path
import sys
source=Path(sys.argv[1]);root=Path('dist/releases/next')
for ancestor in (root,*root.parents):
    if ancestor.is_symlink():raise SystemExit('Symlinked custom migration ancestor is forbidden.')
files=list(root.rglob(sys.argv[2]))
if len(files)!=1 or files[0].is_symlink() or files[0].parent.name!='_custom':
    raise SystemExit('SQLcl custom migration destination is missing or ambiguous.')
p=files[0]
if any(a.is_symlink() for a in (p,*p.parents)) or not p.resolve(strict=True).is_relative_to(root.resolve(strict=True)):
    raise SystemExit('Custom migration destination escapes the staged project.')
p.write_text(p.read_text()+'\n'+source.read_text())
PYCODE
fi
[[ -d dist/releases/next ]] || die "SQLcl did not create the next release staging directory."
python3 "$SCRIPT_DIR/aux/normalize_staged_sql.py" --project-dir "$PROJECT_DIR"
git add dist
git diff --cached --quiet && die "SQLcl staging produced no changes."
git commit -m "build: stage migration for release $version"
echo "Verifying database migrations and compiling native APEXlang..."
run_sql "$DB_CONNECT_DEV" "verify-$version" <<'EOF'
project verify -verbose
EOF
run_sql "$DB_CONNECT_DEV" "release-$version" <<EOF
project release -version $version
EOF
[[ -d "dist/releases/$version" ]] || die "Expected release directory was not created: dist/releases/$version"
git add dist .dbtools/project.config.json
git commit -m "build: finalize release $version"
git push -u origin "$branch"
body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT
cat > "$body_file" <<EOF
Promote Training Hub application and DEMO_TRN_ database structures for release $version ($release_name).

Generated with SQLcl 26.3 Projects. Source table data is excluded.
Review the source changes and generated migrations before merging.
The local create_release.sh process waits for manual merge, then publishes the release artifact automatically. Closing this PR without merging cancels publication.
EOF
pr_url="$(gh pr create --repo "$GITHUB_REPO" --base "$base" --head "$branch" --title "Release $version: $release_name" --body-file "$body_file")"
mkdir -p "$DEMO_HOME/.state/releases"
umask 077
{
  printf 'RELEASE_PROJECT=%q\n' "$PROJECT_NAME"
  printf 'RELEASE_REPO=%q\n' "$GITHUB_REPO"
  printf 'RELEASE_DIR=%q\n' "$PROJECT_DIR"
  printf 'RELEASE_VERSION=%q\n' "$version"
  printf 'RELEASE_BRANCH=%q\n' "$branch"
  printf 'RELEASE_BASE=%q\n' "$base"
  printf 'RELEASE_TAG=%q\n' "$tag"
  printf 'RELEASE_PR=%q\n' "$pr_url"
} > "$DEMO_HOME/.state/releases/$version.env"
printf 'Release proposal: %s\nReview and merge the PR manually in GitHub. Waiting; close the PR or press Ctrl+C to cancel.\n' "$pr_url"
wait_and_publish "$version"
