#!/usr/bin/env bash
# Capture target metadata only, for deployment collision checks and owned cleanup.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
[[ $# -eq 1 ]] || die "Usage: $0 <output.json>"
load_project
validate_identifier "$SCHEMA_NAME_PRO"
validate_identifier "$APEX_WORKSPACE_PRO"
[[ "$APEX_APP_ID_PRO" =~ ^[1-9][0-9]*$ ]] || die "Invalid target app ID."
output="$1"
work="$(mktemp)"
trap 'rm -f "$work"' EXIT
sql_status=0
run_sql "$DB_CONNECT_PRO" target-inventory <<EOF > "$work" || sql_status=$?
set serveroutput on size unlimited
set heading off feedback off pagesize 0 linesize 32767
set long 10000000
set longchunksize 32767
declare
  j clob;
  c clob;
  n number;
  pos number := 1;
  encoded varchar2(32767);
begin
  select count(*) into n from user_tables where table_name='DATABASECHANGELOG';
  if n=1 then
    execute immediate q'~select coalesce(json_arrayagg(json_object('id' value id,'author' value author,'filename' value filename) returning clob),to_clob('[]')) from databasechangelog~' into c;
  else c := '[]'; end if;
  select json_object(
    'database' value sys_context('USERENV','DB_NAME'),
    'service' value sys_context('USERENV','SERVICE_NAME'),
    'schema' value user,
    'workspace' value '$APEX_WORKSPACE_PRO',
    'app_id' value $APEX_APP_ID_PRO,
    'application_exists' value case when exists(select 1 from apex_applications where application_id=$APEX_APP_ID_PRO) then 'true' else 'false' end format json,
    'objects' value (select coalesce(json_arrayagg(json_object('name' value object_name,'type' value object_type) returning clob),to_clob('[]')) from user_objects where subobject_name is null and object_type not in ('LOB')) format json,
    'changelog' value c format json returning clob) into j from dual;
  while pos <= dbms_lob.getlength(j) loop
    encoded := utl_raw.cast_to_varchar2(utl_encode.base64_encode(utl_raw.cast_to_raw(dbms_lob.substr(j,6000,pos))));
    dbms_output.put_line('APEXCICD_JSON_CHUNK|' || replace(replace(encoded,chr(13)),chr(10)));
    pos := pos + 6000;
  end loop;
end;
/
EOF
if [[ "$sql_status" -ne 0 ]]; then
  cat "$work"
  exit "$sql_status"
fi
python3 - "$work" "$output" <<'PY'
import base64, json, os, sys
from pathlib import Path
text=Path(sys.argv[1]).read_text()
marker='APEXCICD_JSON_CHUNK|'
chunks=[line.split(marker,1)[1].strip() for line in text.splitlines() if line.startswith(marker)]
if not chunks: raise SystemExit('Target inventory output is missing.')
value=json.loads(b''.join(base64.b64decode(c,validate=True) for c in chunks))
p=Path(sys.argv[2]);p.parent.mkdir(parents=True,exist_ok=True)
fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as f: json.dump(value,f,indent=2);f.write('\n')
print(f"Captured target metadata: {len(value['objects'])} objects, application {value['app_id']} present={value['application_exists']}; {p}")
PY
