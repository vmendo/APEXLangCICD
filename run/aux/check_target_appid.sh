#!/usr/bin/env bash
# Check instance-wide application ID ownership before provisioning or deployment.
# A parsing-schema session may not see applications in other workspaces.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
[[ $# -eq 0 ]] || die "Usage: $0"
[[ ! -f "$DEMO_HOME/.state/project.env" ]] || load_project
validate_identifier "$SCHEMA_NAME_PRO"
validate_identifier "$APEX_WORKSPACE_PRO"
[[ "$APEX_APP_ID_PRO" =~ ^[1-9][0-9]*$ ]] || die "Invalid target application ID."
expected_db=''
expected_service=''
if [[ -f "$DEMO_HOME/.state/production-setup.json" ]]; then
  identity="$(python3 - "$DEMO_HOME/.state/production-setup.json" "$SCHEMA_NAME_PRO" "$APEX_WORKSPACE_PRO" <<'PY'
import json,re,sys
m=json.load(open(sys.argv[1]))
if (m['schema'],m['workspace'])!=tuple(sys.argv[2:]):raise SystemExit('Production setup identity differs from active settings.')
if not all(re.fullmatch(r'[A-Za-z0-9_.-]+',m[k]) for k in ('database','service')):raise SystemExit('Invalid recorded production identity.')
print(m['database']+'|'+m['service'])
PY
)" || die "Could not verify production setup identity."
  IFS='|' read -r expected_db expected_service <<< "$identity"
fi
run_sql "$DB_CONNECT_ADMIN" check-target-appid <<EOF
set serveroutput on
declare n number;begin
  if user<>'ADMIN' then raise_application_error(-20070,'Instance-wide application ID check requires ADMIN');end if;
  if '$expected_db' is not null and
     (sys_context('USERENV','DB_NAME')<>'$expected_db' or sys_context('USERENV','SERVICE_NAME')<>'$expected_service') then
    raise_application_error(-20071,'Administrative connection differs from verified production database');
  end if;
  select count(*) into n from apex_applications where application_id=$APEX_APP_ID_PRO
    and (workspace<>'$APEX_WORKSPACE_PRO' or owner<>'$SCHEMA_NAME_PRO');
  if n>0 then
    raise_application_error(-20072,'Target application $APEX_APP_ID_PRO belongs to another workspace/schema; choose an unused ID');
  end if;
  dbms_output.put_line('Target application ID $APEX_APP_ID_PRO has no cross-workspace collision.');
end;
/
EOF
