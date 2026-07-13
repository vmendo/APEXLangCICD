#!/bin/bash

# Create a database release plus a validated APEXlang source bundle.
# Usage: create_release.sh <release_name> <version>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <release_name> <version>" >&2
  exit 1
fi

release_name="$1"
release_version="$2"
release_branch="release_${release_name// /_}_${release_version}"
project_dir="$PROJECTS_HOME/$PROJECT_NAME"
release_dir="$project_dir/dist/releases/$release_version"

[[ -d "$project_dir/.git" ]] || { echo "Not a Git repository: $project_dir" >&2; exit 1; }

cd "$project_dir"
if git rev-parse --verify "$release_branch" >/dev/null 2>&1; then
  echo "Release branch already exists: $release_branch" >&2
  exit 1
fi

git checkout main
git pull --ff-only
git checkout -b "$release_branch"

# Capture database source with SQLcl Projects. The project configuration selects
# APEXLANG for its APEX application export.
"$SQLCL_BIN" -name "$DB_CONNECT_DEV" <<EOF
project export
exit
EOF

# Keep a canonical, split APEXlang tree independent of SQLcl Project internals.
bash "$SCRIPT_DIR/export_apexlang.sh"
bash "$SCRIPT_DIR/validate_apexlang.sh"

git add src apexlang .dbtools/project.config.json README.md
git commit -m "feat: export database and APEXlang sources for ${release_version}" || true

"$SQLCL_BIN" -name "$DB_CONNECT_DEV" <<EOF
project stage
exit
EOF

git add dist
git commit -m "feat: stage SQLcl migration for release ${release_version}"

"$SQLCL_BIN" -name "$DB_CONNECT_DEV" <<EOF
project verify
project release -version ${release_version}
exit
EOF

mkdir -p "$release_dir/apexlang"
cp -a "$APEXLANG_SOURCE_DIR/." "$release_dir/apexlang/"

cat > "$release_dir/APEXLANG-IMPORT.md" <<EOF
# APEXlang release source

This release contains the validated APEXlang source for application ${APEX_APP_IDS}.
It is intentionally not imported by this release-generation workflow.

To import in an explicitly approved target session, validate and import the same
directory with SQLcl 26.1+ and the target workspace identity:

    apex validate -input apexlang/f115 -workspace DEMO
    apex import -input apexlang/f115 -workspace DEMO
EOF

git add dist VERSION .dbtools/project.config.json
git commit -m "feat: stage database and APEXlang release ${release_version}"
git push -u origin "$release_branch"

echo "Release ${release_version} created on ${release_branch}."
