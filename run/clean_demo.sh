#!/usr/bin/env bash
# Clean selected APEX changes, owned database changes, remote content and project.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/aux/common.sh"
dev_args=(); pro_args=(); final_args=(); assume_yes=false
usage() {
  echo "Usage: $0 [--page-id ID ... | --skip-page] [--app-id ID | --skip-app] [--yes]"
  echo "Lists development pages and production applications when a selection is needed."
  echo "Enter skips page/application deletion; --yes requires an explicit page choice."
  echo "Previous logs are removed at startup; logs from this cleanup are retained."
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) assume_yes=true; dev_args+=(--yes); pro_args+=(--yes); final_args=(--yes); shift ;;
    --skip-page) dev_args+=(--skip-page); shift ;;
    --skip-app) pro_args+=(--skip-app); shift ;;
    --page-id) [[ $# -ge 2 ]] || die "--page-id needs an ID."; dev_args+=(--page-id "$2"); shift 2 ;;
    --app-id) [[ $# -ge 2 ]] || die "--app-id needs an ID."; pro_args+=(--app-id "$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown cleanup argument: $1" ;;
  esac
done
active=false
if [[ -f "$DEMO_HOME/.state/project.env" ]]; then active=true; fi
[[ ! -f "$DEMO_HOME/.state/deployment-attempt.json" ]] || die "An incomplete deployment requires inspection before cleanup. See .state/deployment-attempt.json."
for step in cleanup_dev.sh cleanup_pro.sh cleanup_remote.sh delete_project.sh; do
  [[ -f "$SCRIPT_DIR/clean/$step" ]] || die "Missing cleanup stage: run/clean/$step"
done
python3 "$SCRIPT_DIR/clean/aux/reset_logs.py" "$DEMO_HOME"
bash "$SCRIPT_DIR/clean/cleanup_dev.sh" ${dev_args[@]+"${dev_args[@]}"}
bash "$SCRIPT_DIR/clean/cleanup_pro.sh" ${pro_args[@]+"${pro_args[@]}"}
if [[ "$active" != true ]]; then
  echo "No active generated project; remote and local project cleanup skipped."
  exit 0
fi
if [[ "$assume_yes" == true ]]; then
  bash "$SCRIPT_DIR/clean/cleanup_remote.sh" --yes
else
  bash "$SCRIPT_DIR/clean/cleanup_remote.sh" --confirm
fi
bash "$SCRIPT_DIR/clean/delete_project.sh" ${final_args[@]+"${final_args[@]}"}
echo "Demo cleanup completed. The GitHub repository, schemas and workspaces were preserved."
