#!/bin/bash

# Export the configured applications as split APEXlang source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

: "${DB_CONNECT_DEV:?}"
: "${APEX_WORKSPACE_ID_DEV:?}"
: "${APEXLANG_SOURCE_DIR:?}"

mkdir -p "$APEXLANG_SOURCE_DIR"

for app_id in $APEX_APP_IDS; do
  app_dir="$APEXLANG_SOURCE_DIR/f${app_id}"
  echo "Exporting APEX application ${app_id} as APEXlang to ${app_dir}"
  mkdir -p "$app_dir"
  (
    cd "$app_dir"
    "$SQLCL_BIN" -name "$DB_CONNECT_DEV" <<EOF
apex export-application -api ${app_id} -exptype APEXLANG -split -force -skipexportdate
exit
EOF
  )
  [[ -n "$(find "$app_dir" -name application.apx -type f -print -quit)" ]] || {
    echo "APEXlang export did not create application.apx for app ${app_id}" >&2
    exit 1
  }
done
