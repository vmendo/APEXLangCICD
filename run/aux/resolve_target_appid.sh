#!/usr/bin/env bash
# Select a free target ID using instance-wide ADMIN visibility, without an import.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
[[ $# -eq 0 ]] || die "Usage: $0"
load_project
validate_identifier "$SCHEMA_NAME_PRO"
validate_identifier "$APEX_WORKSPACE_PRO"
[[ "$APEX_APP_ID_PRO_PREFERRED" =~ ^[1-9][0-9]*$ ]] || die "Preferred target ID must be a positive integer."
[[ ! -f "$DEMO_HOME/.state/deployment-attempt.json" ]] || die "An incomplete deployment must be inspected before selecting an application ID."
umask 077
inventory="$(mktemp "$DEMO_HOME/.state/target-ids.XXXXXX")"
trap 'rm -f "$inventory"' EXIT
sql_status=0
run_sql "$DB_CONNECT_ADMIN" resolve-target-appid <<'EOF' > "$inventory" || sql_status=$?
set sqlformat default
set heading off feedback off pagesize 0 linesize 32767
select 'APEXCICD_IDENTITY|' || user || '|' || sys_context('USERENV','DB_NAME') || '|' || sys_context('USERENV','SERVICE_NAME') from dual;
select 'APEXCICD_APPID|' || application_id from apex_applications where application_id=trunc(application_id) order by application_id;
EOF
if [[ "$sql_status" -ne 0 ]]; then
  cat "$inventory"
  die "Could not inventory target application IDs."
fi
selected_id="$(python3 "$SCRIPT_DIR/target_appid.py" --inventory "$inventory" \
  --state "$DEMO_HOME/.state/target-application.json" --project-env "$DEMO_HOME/.state/project.env" \
  --project-name "$PROJECT_NAME" --project-dir "$PROJECT_DIR" \
  --schema "$SCHEMA_NAME_PRO" --workspace "$APEX_WORKSPACE_PRO" \
  --preferred "$APEX_APP_ID_PRO_PREFERRED" \
  --deployment "$DEMO_HOME/.state/deployment.json" --attempt "$DEMO_HOME/.state/deployment-attempt.json" \
  --setup "$DEMO_HOME/.state/production-setup.json")" || die "Could not select a safe target application ID."
printf 'Production application ID: %s (preferred: %s). Selection retained in local project state.\n' "$selected_id" "$APEX_APP_ID_PRO_PREFERRED"
