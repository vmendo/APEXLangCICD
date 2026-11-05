#!/usr/bin/env bash
# Read only: list applications/pages inside the configured workspace and schema.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../aux/common.sh"
[[ $# -ge 3 && $# -le 4 ]] || die "Usage: $0 DEV|PRO apps|pages output.json [application_id]"
environment="$1"; kind="$2"; output="$3"; app_id="${4:-0}"
[[ "$kind" == apps || "$kind" == pages ]] || die "Invalid inventory kind."
[[ "$app_id" =~ ^[0-9]+$ ]] || die "Invalid application ID."
[[ "$kind" != pages || "$app_id" -gt 0 ]] || die "A page inventory needs an application ID."
if [[ -f "$DEMO_HOME/.state/project.env" ]]; then source "$DEMO_HOME/.state/project.env"; fi
case "$environment" in
  DEV) connection="$DB_CONNECT_DEV"; schema="$SCHEMA_NAME"; workspace="$APEX_WORKSPACE_DEV" ;;
  PRO) connection="$DB_CONNECT_PRO"; schema="$SCHEMA_NAME_PRO"; workspace="$APEX_WORKSPACE_PRO" ;;
  *) die "Environment must be DEV or PRO." ;;
esac
validate_identifier "$schema"; validate_identifier "$workspace"
work="$(mktemp)"
trap 'rm -f "$work"' EXIT
status=0
run_sql "$connection" apex-cleanup-inventory <<SQL > "$work" || status=$?
set serveroutput on size unlimited
set heading off feedback off pagesize 0 linesize 32767
declare
  j clob;
  n number;
  pos number := 1;
  encoded varchar2(32767);
begin
  if user <> '$schema' then raise_application_error(-20001,'Cleanup schema mismatch'); end if;
  select count(*) into n from apex_workspace_schemas where workspace_name='$workspace' and schema='$schema';
  if n <> 1 then raise_application_error(-20002,'Cleanup workspace mapping mismatch'); end if;
  select json_object(
    'database' value sys_context('USERENV','DB_NAME'),
    'service' value sys_context('USERENV','SERVICE_NAME'),
    'schema' value user, 'workspace' value '$workspace', 'app_id' value $app_id,
    'apps' value (select coalesce(json_arrayagg(json_object('id' value application_id,'name' value application_name) order by application_id returning clob),to_clob('[]')) from apex_applications where workspace='$workspace' and owner='$schema' and application_id=trunc(application_id)) format json,
    'pages' value (select coalesce(json_arrayagg(json_object('id' value p.page_id,'name' value p.page_name) order by p.page_id returning clob),to_clob('[]')) from apex_application_pages p where p.application_id=$app_id and exists(select 1 from apex_applications a where a.application_id=p.application_id and a.workspace='$workspace' and a.owner='$schema')) format json returning clob) into j from dual;
  while pos <= dbms_lob.getlength(j) loop
    encoded := utl_raw.cast_to_varchar2(utl_encode.base64_encode(utl_raw.cast_to_raw(dbms_lob.substr(j,6000,pos))));
    dbms_output.put_line('APEXCICD_JSON_CHUNK|' || replace(replace(encoded,chr(13)),chr(10)));
    pos := pos + 6000;
  end loop;
end;
/
SQL
if [[ "$status" -ne 0 ]]; then cat "$work"; exit "$status"; fi
python3 - "$work" "$output" "$environment" "$DEMO_HOME/.state/production-setup.json" "$connection" "$schema" "$workspace" <<'PY'
import base64,json,os,sys
from pathlib import Path
source,output,environment,setup,connection,schema,workspace=sys.argv[1:]
marker='APEXCICD_JSON_CHUNK|'
chunks=[line.split(marker,1)[1].strip() for line in Path(source).read_text().splitlines() if line.startswith(marker)]
if not chunks: raise SystemExit('Cleanup inventory output is missing.')
value=json.loads(b''.join(base64.b64decode(c,validate=True) for c in chunks))
if value['schema']!=schema or value['workspace']!=workspace: raise SystemExit('Cleanup identity mismatch.')
if environment=='PRO':
    if not Path(setup).is_file(): raise SystemExit('Verified production setup is required for production cleanup.')
    expected=json.loads(Path(setup).read_text())
    for key,actual in [('connection',connection),('schema',schema),('workspace',workspace),('database',value['database']),('service',value['service'])]:
        if str(expected.get(key,'')).upper()!=str(actual).upper(): raise SystemExit(f'Production cleanup identity mismatch: {key}')
    if expected.get('connection_pending',True): raise SystemExit('Production connection is not verified.')
p=Path(output);p.parent.mkdir(parents=True,exist_ok=True)
fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as stream: json.dump(value,stream,indent=2);stream.write('\n')
print(f"Captured cleanup inventory for {environment}: {len(value['apps'])} applications, {len(value['pages'])} pages.")
PY
