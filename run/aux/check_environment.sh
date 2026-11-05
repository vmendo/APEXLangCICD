#!/usr/bin/env bash
# Verify saved-connection identity before any export or deployment.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
[[ $# -eq 1 ]] || die "Usage: $0 <DEV|PRO|ADMIN>"
[[ ! -f "$DEMO_HOME/.state/project.env" ]] || load_project
case "$1" in
  DEV) connection="$DB_CONNECT_DEV"; schema="$SCHEMA_NAME"; workspace="$APEX_WORKSPACE_DEV"; app="$APEX_APP_ID" ;;
  PRO) connection="$DB_CONNECT_PRO"; schema="$SCHEMA_NAME_PRO"; workspace="$APEX_WORKSPACE_PRO"; app="$APEX_APP_ID_PRO" ;;
  ADMIN) connection="$DB_CONNECT_ADMIN"; schema=ADMIN; workspace="$APEX_WORKSPACE_PRO"; app="$APEX_APP_ID_PRO" ;;
  *) die "Expected DEV, PRO, or ADMIN." ;;
esac
validate_identifier "$schema"
validate_identifier "$workspace"
[[ "$app" =~ ^[1-9][0-9]*$ ]] || die "Application ID must be a positive integer."
expected_db=''
expected_service=''
if [[ "$1" == PRO ]]; then
  [[ -f "$DEMO_HOME/.state/production-setup.json" ]] || die "Production setup identity is missing. Run run/setup/setup_production.sh first."
  read -r expected_db expected_service < <(python3 - "$DEMO_HOME/.state/production-setup.json" "$schema" "$workspace" "$connection" <<'PY'
import json, re, sys
m = json.load(open(sys.argv[1]))
if (m['schema'], m['workspace'], m['connection']) != tuple(sys.argv[2:]):
    raise SystemExit('Production configuration differs from verified setup.')
if not all(re.fullmatch(r'[A-Za-z0-9_.-]+', m[k]) for k in ('database', 'service')):
    raise SystemExit('Invalid recorded production identity.')
print(m['database'], m['service'])
PY
  )
  [[ -n "$expected_db" && -n "$expected_service" ]] || die "Could not load verified production identity."
fi
if [[ "$1" == PRO ]]; then
  bash "$SCRIPT_DIR/check_target_appid.sh"
fi
run_sql "$connection" "check-$1" <<EOF
set serveroutput on
set sqlformat csv
select user session_user, sys_context('USERENV','DB_NAME') db_name,
       sys_context('USERENV','SERVICE_NAME') service_name from dual;
select version_no apex_version from apex_release;
declare
  n number;
begin
  if user <> '$schema' then
    raise_application_error(-20001, 'Wrong session user: expected $schema, got ' || user);
  end if;
  if '$1' = 'PRO' then
    if sys_context('USERENV','DB_NAME') <> '$expected_db'
       or sys_context('USERENV','SERVICE_NAME') <> '$expected_service' then
      raise_application_error(-20004, 'Production database differs from verified setup');
    end if;
    select count(*) into n from apex_workspace_schemas
      where workspace_name='$workspace' and schema='$schema';
    if n <> 1 then raise_application_error(-20005, 'Production workspace/schema mapping missing'); end if;
    select count(*) into n from apex_applications where application_id=$app
      and (workspace <> '$workspace' or owner <> '$schema');
    if n > 0 then raise_application_error(-20006, 'Target application ID has another owner/workspace'); end if;
  end if;
  if '$1' = 'DEV' then
    select count(*) into n from apex_applications
      where application_id=$app and workspace='$workspace' and owner='$schema';
    if n <> 1 then
      raise_application_error(-20002, 'Source application $app in $workspace/$schema is missing or inaccessible');
    end if;
    select count(*) into n from user_tables where table_name like 'DEMO\_TRN\_%' escape '\';
    if n=0 then raise_application_error(-20003, 'No DEMO_TRN_ source tables found'); end if;
  end if;
  dbms_output.put_line('Environment identity verified.');
end;
/
EOF
