#!/usr/bin/env bash
# Create a new SQLcl 26.3 project and preserve its identity for later stages.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/aux/common.sh"
[[ $# -le 1 ]] || die "Usage: $0 [project_name]"
require_tools git gh python3
"$SCRIPT_DIR/aux/check_environment.sh" DEV
[[ ! -f "$DEMO_HOME/.state/project.env" ]] || die "An active project exists. Clean it before creating another project."
PROJECT_NAME="${1:-${PROJECT_NAME:-TrainingHubCICD}}"
validate_name "$PROJECT_NAME"
PROJECT_DIR="$PROJECTS_HOME/$PROJECT_NAME"
PROJECT_BRANCH="${PROJECT_BRANCH:-main}"
git check-ref-format --branch "$PROJECT_BRANCH" >/dev/null || die "Invalid project branch."
[[ ! -e "$PROJECT_DIR" ]] || die "Project path already exists: $PROJECT_DIR"
mkdir -p "$PROJECTS_HOME" "$DEMO_HOME/.state"
gh repo view "$GITHUB_REPO" >/dev/null
git clone "$GITHUB_URL" "$PROJECT_DIR"
cd "$PROJECT_DIR"
if git show-ref --verify --quiet "refs/remotes/origin/$PROJECT_BRANCH"; then
  git checkout -B "$PROJECT_BRANCH" "origin/$PROJECT_BRANCH"
else
  # A fresh project branch starts independently without rewriting remote history.
  git checkout --orphan "$PROJECT_BRANCH"
  git rm -rf . >/dev/null
fi
[[ ! -e .dbtools ]] || die "Remote branch already contains a SQLcl project. Run the configured full demo cleanup before creating another project on this branch."
run_sql "$DB_CONNECT_DEV" create-project <<EOF
project init -name $PROJECT_NAME -schemas $SCHEMA_NAME -directory "$PROJECT_DIR" -connection-name $DB_CONNECT_DEV
EOF
python3 - "$PROJECT_DIR" "$APEX_APP_ID" <<'PY'
import json, pathlib, sys
root, app = pathlib.Path(sys.argv[1]), int(sys.argv[2])
path = root / '.dbtools/project.config.json'
cfg = json.loads(path.read_text())
cfg['sqlcl']['version'] = '26.3.0.0'
cfg['apex']['apexlang'] = True
cfg['dml'] = False
cfg['export']['setTransform']['emitSchema'] = True
cfg['stage']['substituteSchemas'] = True
cfg['export']['apex'].update(exptype=['APEXLANG'], expSupportingObjects='N', skipExportDate=True)
path.write_text(json.dumps(cfg, indent=2) + '\n')
filters = root / '.dbtools/filters/ddl.filters'
with filters.open('a') as f:
    f.write("\n-- Training Hub demo scope: literal DEMO_TRN_ prefix; no source table data.\n")
    f.write("object_name like 'DEMO\\_TRN\\_%' escape '\\',\n")
    f.write(f'application_id = {app},\n')
(root / '.apexcicd-project.json').write_text(json.dumps({'project': cfg['project'], 'directory': str(root.resolve())}, indent=2) + '\n')
PY
# The branch may have been supplied as a non-exported shell variable.
python3 - "$PROJECT_BRANCH" <<'PY'
import json, pathlib, sys
p = pathlib.Path('.dbtools/project.config.json')
c = json.loads(p.read_text()); c['git']['defaultBranch'] = sys.argv[1]
p.write_text(json.dumps(c, indent=2) + '\n')
PY
python3 - "$DEMO_HOME/config/project-readme.md" "$PROJECT_NAME" "$APEX_APP_ID" "$SCHEMA_NAME" <<'PYCODE'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text()
for key,value in [('PROJECT_NAME',sys.argv[2]),('APP_ID',sys.argv[3]),('SCHEMA_PATH',sys.argv[4].lower())]:
    text=text.replace('{{'+key+'}}',value)
Path('README.md').write_text(text)
PYCODE
cat >> .gitignore <<'EOF'

# Deployment artifacts are published as GitHub release assets.
artifact/
artifacts/
*.log
EOF
git add .dbtools .gitignore .apexcicd-project.json README.md
git commit -m "chore: initialize $PROJECT_NAME with SQLcl 26.3"
git push -u origin "$PROJECT_BRANCH"
umask 077
{
  printf 'PROJECT_NAME=%q\n' "$PROJECT_NAME"
  printf 'PROJECT_DIR=%q\n' "$PROJECT_DIR"
  printf 'PROJECTS_HOME=%q\n' "$PROJECTS_HOME"
  printf 'PROJECT_BRANCH=%q\n' "$PROJECT_BRANCH"
  printf 'RELEASE_TAG_PREFIX=%q\n' "${RELEASE_TAG_PREFIX:-v}"
  printf 'GITHUB_REPO=%q\n' "$GITHUB_REPO"
  printf 'GITHUB_URL=%q\n' "$GITHUB_URL"
  for config_name in DB_CONNECT_DEV DB_CONNECT_PRO DB_CONNECT_ADMIN SCHEMA_NAME SCHEMA_NAME_PRO APEX_APP_ID APEX_APP_ID_PRO APEX_APP_ID_PRO_PREFERRED APEX_WORKSPACE_DEV APEX_WORKSPACE_PRO; do
    if [[ -n "${!config_name+x}" ]]; then
      printf '%s=%q\n' "$config_name" "${!config_name}"
    fi
  done
} > "$DEMO_HOME/.state/project.env"
printf 'Created project %s at %s on branch %s.\n' "$PROJECT_NAME" "$PROJECT_DIR" "$PROJECT_BRANCH"
