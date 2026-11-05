#!/usr/bin/env bash
# Remove only the generated SQLcl project, preserving the demo framework.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../aux/common.sh"

assume_yes=false
case "${1:-}" in
  --yes) assume_yes=true; shift ;;
  -h|--help)
    echo "Usage: $0 [--yes]"
    echo "Delete the active local SQLcl project. GitHub content is preserved."
    exit 0 ;;
esac
[[ $# -eq 0 ]] || die "Usage: $0 [--yes]"
require_tools python3
load_project

# Validate both the state-derived path and on-disk identity before deletion.
# The validated absolute path is the only path passed to rm.
validated_dir="$(python3 - "$DEMO_HOME" "$PROJECTS_HOME" "$PROJECT_NAME" "$PROJECT_DIR" <<'PY'
import json
import re
import sys
from pathlib import Path

demo_raw, projects_raw, name, project_raw = sys.argv[1:]
if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", name):
    raise SystemExit("Invalid project name in active state.")
demo = Path(demo_raw).resolve(strict=True)
projects = Path(projects_raw).resolve(strict=True)
raw = Path(project_raw)
if raw.is_symlink():
    raise SystemExit("Refusing to delete a symlinked project directory.")
project = raw.resolve(strict=True)
expected = projects / name
if project != expected or project.parent != projects:
    raise SystemExit("Project path does not match PROJECTS_HOME/PROJECT_NAME.")
if project in (demo, projects, Path('/')) or project in demo.parents:
    raise SystemExit("Refusing to delete a protected directory.")
if not project.is_dir():
    raise SystemExit("Project path is not a directory.")
for relative in ('.dbtools/project.config.json', '.apexcicd-project.json'):
    identity = project / relative
    if identity.is_symlink() or not identity.is_file():
        raise SystemExit(f"Missing or unsafe project identity file: {relative}")
    if json.loads(identity.read_text()).get('project') != name:
        raise SystemExit(f"Project identity mismatch in {relative}.")
print(project)
PY
)" || die "Project deletion validation failed. No files were removed."

echo "Local project to delete: $validated_dir"
echo "This removes its Git checkout and generated release artifacts."
if [[ "$assume_yes" != true ]]; then
  [[ -t 0 ]] || die "Interactive confirmation requires a terminal; use --yes for an intentional unattended reset."
  read -r -p "Type the project name '$PROJECT_NAME' to continue: " confirmation
  [[ "$confirmation" == "$PROJECT_NAME" ]] || die "Project deletion cancelled."
fi

rm -rf -- "$validated_dir"
[[ ! -e "$validated_dir" && ! -L "$validated_dir" ]] || die "Project deletion did not complete; active state was retained."
if [[ -d "$DEMO_HOME/.state/releases" && ! -L "$DEMO_HOME/.state/releases" ]]; then
  archive="$DEMO_HOME/logs/reset-metadata/$PROJECT_NAME-$(date -u +%Y%m%dT%H%M%S)-$$"
  mkdir -p "$archive"
  mv "$DEMO_HOME/.state/releases" "$archive/releases"
fi
if [[ -f "$DEMO_HOME/.state/target-application.json" ]]; then
  archive="${archive:-$DEMO_HOME/logs/reset-metadata/$PROJECT_NAME-$(date -u +%Y%m%dT%H%M%S)-$$}"
  mkdir -p "$archive"
  mv "$DEMO_HOME/.state/target-application.json" "$archive/target-application.json"
fi
rm -f -- "$DEMO_HOME/.state/project.env"
echo "Deleted local project $PROJECT_NAME and cleared its active state."
echo "Demo scripts, configuration, logs, documentation, and SQLcl were preserved."
echo "This local-only stage does not contact GitHub. Full cleanup empties remote content first."
