#!/usr/bin/env bash
# Wait optionally for manual merge, then publish from the exact approved commit.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
[[ $# -eq 1 || ( $# -eq 2 && "$2" == --wait ) ]] || die "Usage: $0 <version> [--wait]"
wait_for_merge=false
[[ "${2:-}" != --wait ]] || wait_for_merge=true
poll_seconds="${PR_POLL_SECONDS:-5}"
[[ "$poll_seconds" =~ ^[1-9][0-9]*$ && "$poll_seconds" -le 60 ]] || die "PR_POLL_SECONDS must be between 1 and 60."
require_tools git gh python3 shasum
load_project
version="$1"
validate_version "$version"
state="$DEMO_HOME/.state/releases/$version.env"
[[ -f "$state" ]] || die "No release proposal state exists for $version."
source "$state"
[[ "${RELEASE_PROJECT:-}" == "$PROJECT_NAME" && "${RELEASE_REPO:-}" == "$GITHUB_REPO" && "${RELEASE_DIR:-}" == "$PROJECT_DIR" && "${RELEASE_BASE:-}" == "${PROJECT_BRANCH:-main}" && "${RELEASE_VERSION:-}" == "$version" && "${RELEASE_TAG:-}" == "${RELEASE_TAG_PREFIX:-v}${version}" ]] || die "Release state belongs to a different project, repository, branch, or rehearsal. Recreate the proposal for the active project."
cd "$PROJECT_DIR"
[[ -z "$(git status --porcelain)" ]] || die "The project working tree must be clean."
trap 'echo "PR wait cancelled; nothing was published. Resume with: ./run/create_release.sh --resume $version" >&2; exit 130' INT
trap 'echo "PR wait terminated; nothing was published." >&2; exit 143' TERM
announced=false
while :; do
  pr_json="$(gh pr view "$RELEASE_PR" --repo "$GITHUB_REPO" --json state,mergeCommit,baseRefName,headRefName)"
  decision="$(python3 - "$pr_json" "$RELEASE_BASE" "$RELEASE_BRANCH" <<'PY'
import json, sys
p = json.loads(sys.argv[1])
if p['baseRefName'] != sys.argv[2] or p['headRefName'] != sys.argv[3]:
    raise SystemExit('Release PR must be merged into its recorded project base branch; PR identity differs.')
if p['state'] == 'MERGED':
    print('MERGED|' + p['mergeCommit']['oid'])
elif p['state'] in ('OPEN', 'CLOSED'):
    print(p['state'])
else:
    raise SystemExit('Unknown PR state; no publication performed.')
PY
)"
  case "$decision" in
    MERGED\|*) merged_sha="${decision#MERGED|}"; break ;;
    CLOSED) die "Release PR was closed without merging. Nothing was published." ;;
    OPEN)
      [[ "$wait_for_merge" == true ]] || die "Release PR must be merged into its recorded project base branch."
      if [[ "$announced" != true ]]; then
        echo "PR is open. Checking every ${poll_seconds}s for manual merge or closure (Ctrl+C cancels): $RELEASE_PR"
        announced=true
      fi
      sleep "$poll_seconds" ;;
    *) die "Invalid release PR decision." ;;
  esac
done
trap - INT TERM
git fetch origin "$RELEASE_BASE"
git cat-file -e "$merged_sha^{commit}"
git merge-base --is-ancestor "$merged_sha" "origin/$RELEASE_BASE" || die "Merged release is not present in the remote project branch."
# Build from the exact merged commit, never from a later release or stale branch.
git checkout --detach "$merged_sha"
trap 'git checkout "$RELEASE_BASE" >/dev/null 2>&1 || true' EXIT
[[ -d "dist/releases/$version" ]] || die "Merged commit does not contain release $version."
artifact="$PROJECT_DIR/artifact/$PROJECT_NAME-$version.zip"
alternate_artifact="$PROJECT_DIR/artifacts/$PROJECT_NAME-$version.zip"
[[ ! -e "$alternate_artifact" ]] || die "Artifact already exists; inspect or remove it before regenerating: $alternate_artifact"
[[ ! -e "$artifact" ]] || die "Artifact already exists; inspect or remove it before regenerating: $artifact"
run_sql "$DB_CONNECT_DEV" "artifact-$version" <<EOF
project gen-artifact -name $PROJECT_NAME -version $version -format zip
EOF
if [[ ! -s "$artifact" && -s "$alternate_artifact" ]]; then
  artifact="$alternate_artifact"
fi
[[ -s "$artifact" ]] || die "SQLcl did not generate the expected release artifact under artifact/ or artifacts/."
checksum="$artifact.sha256"
(cd "$(dirname "$artifact")" && shasum -a 256 "$(basename "$artifact")") > "$checksum"
notes="$(mktemp)"
cat > "$notes" <<EOF
SQLcl 26.3 Projects release $version for $PROJECT_NAME.
Source commit: $merged_sha
Pull request: $RELEASE_PR
Database structures and APEX application only; source table data is excluded.
The deployment ZIP contains the native SQLcl Projects APEXlang application and database migrations.
EOF
gh release create "$RELEASE_TAG" "$artifact" "$checksum" --repo "$GITHUB_REPO" --target "$merged_sha" --title "$PROJECT_NAME $version" --notes-file "$notes"
rm -f "$notes"
printf 'Published %s from %s.\n' "$RELEASE_TAG" "$merged_sha"
