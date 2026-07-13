#!/bin/bash

# Validate APEXlang source only. Import is deliberately not performed here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

for app_id in $APEX_APP_IDS; do
  app_dir="$APEXLANG_SOURCE_DIR/f${app_id}"
  app_file="$(find "$app_dir" -name application.apx -type f -print -quit)"
  [[ -n "$app_file" ]] || { echo "Missing APEXlang export: $app_dir" >&2; exit 1; }
  app_input_dir="$(dirname "$app_file")"
  echo "Validating APEXlang application ${app_id}"
  "$SQLCL_BIN" -name "$DB_CONNECT_DEV" <<EOF
apex validate -input ${app_input_dir} -workspaceid ${APEX_WORKSPACE_ID_DEV}
exit
EOF
done
