#!/usr/bin/env bash
# Empty demo repository content while preserving the GitHub repository itself.
# Default is a read-only dry-run; use --confirm or --yes to perform the reset.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../aux/common.sh"
mode=(--dry-run)
case "${1:-}" in
  --yes|--confirm) mode=("$1"); shift ;;
  --dry-run) shift ;;
  -h|--help)
    echo "Usage: $0 [--dry-run|--confirm|--yes]"
    echo "Default: inventory only. --confirm requires the exact repository name."
    echo "The repository/default branch/settings remain; content and demo delivery history are removed."
    exit 0 ;;
esac
[[ $# -eq 0 ]] || die "Usage: $0 [--dry-run|--confirm|--yes]"
require_tools python3 git gh
load_project
mkdir -p "$DEMO_HOME/logs/remote-cleanup"
plan="$DEMO_HOME/logs/remote-cleanup/plan-$(date -u +%Y%m%dT%H%M%S)-$$.json"
python3 "$SCRIPT_DIR/aux/remote_cleanup.py" --repo "$GITHUB_REPO" --url "$GITHUB_URL" \
  --project-name "$PROJECT_NAME" --project-dir "$PROJECT_DIR" --plan "$plan" "${mode[@]}"
