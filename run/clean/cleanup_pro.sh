#!/usr/bin/env bash
# Select an application within verified production scope; remove only owned DB objects.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../aux/common.sh"
assume_yes=false
skip_app=false
selected=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) assume_yes=true; shift ;;
    --skip-app) skip_app=true; shift ;;
    --app-id) [[ $# -ge 2 ]] || die "--app-id requires an ID."; selected="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--yes] [--skip-app | --app-id ID]"; exit 0 ;;
    *) die "Usage: $0 [--yes] [--skip-app | --app-id ID]" ;;
  esac
done
[[ "$skip_app" != true || -z "$selected" ]] || die "Use either --skip-app or --app-id."
[[ -z "$selected" || "$selected" =~ ^[1-9][0-9]*$ ]] || die "Application ID must be a positive integer."
require_tools python3
active=false
if [[ -f "$DEMO_HOME/.state/project.env" ]]; then
  # Cleanup remains usable when the generated project directory was removed.
  source "$DEMO_HOME/.state/project.env"
  active=true
fi
manifest="$DEMO_HOME/.state/deployment.json"
if [[ ! -f "$manifest" && "$skip_app" == true ]]; then
  echo "Application deletion skipped. No deployment manifest exists; no database objects were removed."
  exit 0
fi
[[ ! -f "$DEMO_HOME/.state/deployment-attempt.json" ]] || die "An incomplete deployment requires ownership reconciliation before cleanup."
[[ -f "$DEMO_HOME/.state/production-setup.json" ]] || die "Verified production setup identity is required."
[[ "$DB_CONNECT_DEV" != "$DB_CONNECT_PRO" ]] || die "Development and production connections must differ."
validate_identifier "$SCHEMA_NAME_PRO"
validate_identifier "$APEX_WORKSPACE_PRO"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
"$SCRIPT_DIR/aux/apex_cleanup_inventory.sh" PRO apps "$work/inventory.json"
if [[ -f "$manifest" ]]; then
  recorded="$(python3 - "$manifest" <<'PYID'
import json,sys
m=json.load(open(sys.argv[1]));value=m.get('app_id')
if isinstance(value,bool) or not isinstance(value,int) or value<=0:
    raise SystemExit('Deployment manifest has no valid recorded application ID.')
print(value)
PYID
)"
  [[ -z "$selected" || "$selected" == "$recorded" ]] || die "Use the recorded deployed application ID $recorded, or --skip-app."
  selected="$recorded"
  present="$(python3 - "$work/inventory.json" "$recorded" <<'PYPRESENT'
import json,sys
print('yes' if int(sys.argv[2]) in {a['id'] for a in json.load(open(sys.argv[1]))['apps']} else 'no')
PYPRESENT
)"
  if [[ "$present" == no && "$skip_app" != true ]]; then
    echo "Recorded application $recorded is already absent from the configured target scope; app deletion skipped."
    skip_app=true
  fi
fi
set -- --inventory "$work/inventory.json" --kind app
if [[ "$skip_app" == true ]]; then set -- "$@" --skip
elif [[ -n "$selected" ]]; then set -- "$@" --selected "$selected"
fi
if [[ "$assume_yes" == true ]]; then set -- "$@" --yes; fi
app="$(python3 "$SCRIPT_DIR/aux/cleanup_selection.py" "$@")"
[[ "$app" == SKIP || "$app" =~ ^[1-9][0-9]*$ ]] || die "Invalid cleanup application selection."
if [[ ! -f "$manifest" && "$app" == SKIP ]]; then
  echo "Application deletion skipped. No deployment manifest exists; no database objects were removed."
  exit 0
fi
python3 - "$DEMO_HOME/.state/production-setup.json" "$manifest" "$PROJECT_NAME" "$PROJECT_DIR" "$SCHEMA_NAME_PRO" "$APEX_WORKSPACE_PRO" "$app" "$work" "$active" "$work/inventory.json" <<'PY'
import json, re, sys
from pathlib import Path
setup_path, manifest_path, project, directory, schema, workspace, app, work, active, inventory_path = sys.argv[1:]
s = json.loads(Path(setup_path).read_text())
m = json.loads(Path(manifest_path).read_text()) if Path(manifest_path).is_file() else None
inventory = json.loads(Path(inventory_path).read_text())
for key in ('database','service','schema','workspace'):
    if inventory[key] != s[key]: raise SystemExit(f'Production inventory/setup mismatch: {key}')
if (s['schema'],s['workspace']) != (schema,workspace):
    raise SystemExit('Production setup differs from configured target scope.')
if app != 'SKIP' and (not app.isdigit() or int(app)<=0 or int(app) not in {a['id'] for a in inventory['apps']}):
    raise SystemExit('Selected application is outside the verified target inventory.')
if m is None:
    m = dict(s, project=project, project_dir=str(Path(directory).resolve()), objects=[], changelog=[], application_owned=False)
    owned = False
else:
    owned = True
    if active != 'true':
        project = m['project']; directory = m['project_dir']
    if app != 'SKIP' and int(app) != m['app_id']:
        raise SystemExit('Application selection differs from the recorded deployed application.')
expected = dict(project=project, project_dir=str(Path(directory).resolve()), schema=schema, workspace=workspace)
for key, value in expected.items():
    if m.get(key) != value: raise SystemExit(f'Deployment ownership mismatch: {key}')
for key in ('database', 'service', 'schema', 'workspace'):
    if m[key] != s[key]: raise SystemExit(f'Production setup mismatch: {key}')
if owned and not m.get('application_owned'): raise SystemExit('Application ownership is not recorded.')
ident = re.compile(r'[A-Z][A-Z0-9_$#]{0,127}')
allowed = {'TABLE','VIEW','MATERIALIZED VIEW','INDEX','SEQUENCE','PACKAGE','PACKAGE BODY','PROCEDURE','FUNCTION','TRIGGER','TYPE','TYPE BODY','SYNONYM'}
meta = {'DATABASECHANGELOG','DATABASECHANGELOGLOCK','DATABASECHANGELOG_ACTIONS','DATABASECHANGELOG_DETAILS','DATABASECHANGELOG_ACTIONS_TRG','DATABASECHANGELOG_ACTIONS_PK'}
objects = {(o['name'], o['type']) for o in m['objects']}
if owned and not objects: raise SystemExit('Deployment object manifest is empty.')
for name, kind in objects:
    if not ident.fullmatch(name) or kind not in allowed or not (name.startswith('DEMO_TRN_') or name in meta):
        raise SystemExit('Manifest contains an unsupported object.')
if any(n in meta for n, _ in objects) and m.get('changelog') is None:
    raise SystemExit('Migration metadata ownership rows are missing. Refusing production cleanup.')
def q(v): return "'" + str(v).replace("'", "''") + "'"
def assertion(condition, text): return f"if {condition} then raise_application_error(-20080,{q(text)}); end if;\n"
names = ','.join(q(n) for n, _ in sorted(objects)) or "'__NONE__'"; tables = ','.join(q(n) for n,t in sorted(objects) if t=='TABLE') or "'__NONE__'"
identity = assertion(f"user <> {q(schema)} or sys_context('USERENV','DB_NAME') <> {q(m['database'])} or sys_context('USERENV','SERVICE_NAME') <> {q(m['service'])}", 'Production identity differs from deployment manifest')
# Administrative dictionary access catches incoming dependencies from other schemas.
pre = "declare n number; begin\n"
pre += assertion(f"user <> 'ADMIN' or sys_context('USERENV','DB_NAME') <> {q(m['database'])}", 'Administrative dependency check reached another database/user')
pre += f"select count(*) into n from dba_dependencies where referenced_owner={q(schema)} and referenced_name in ({names}) and not(owner={q(schema)} and name in ({names}));\n"
pre += assertion('n>0', 'External object dependencies exist; cleanup stopped')
pre += f"select count(*) into n from dba_constraints c join dba_constraints p on p.owner=c.r_owner and p.constraint_name=c.r_constraint_name where c.constraint_type='R' and p.owner={q(schema)} and p.table_name in ({tables}) and not(c.owner={q(schema)} and c.table_name in ({tables}));\n"
pre += assertion('n>0', 'External foreign keys exist; cleanup stopped') + 'end;\n/\n'
Path(work,'admin.sql').write_text(pre)
# Verify DEV is not the production schema on the same database.
dev = 'begin\n' + assertion(f"user={q(schema)} and sys_context('USERENV','DB_NAME')={q(m['database'])}", 'Development resolves to production schema/database') + 'end;\n/\n'
Path(work,'dev.sql').write_text(dev)
body='set serveroutput on\ndeclare n number; begin\n'+identity
if app != 'SKIP':
    body += f"select count(*) into n from apex_applications where application_id={int(app)} and workspace={q(workspace)} and owner={q(schema)};\n"
    body += assertion('n<>1', 'Selected application left the verified target scope')
else:
    body += "dbms_output.put_line('Application deletion skipped explicitly or application already absent.');\n"
if any(n=='DATABASECHANGELOG' and t=='TABLE' for n,t in objects):
    rows=m['changelog']
    keys={(r['id'],r['author'],r['filename']) for r in rows}
    if len(keys)!=len(rows): raise SystemExit('Duplicate migration ownership keys in manifest.')
    body += "select count(*) into n from user_tables where table_name='DATABASECHANGELOG';\nif n=1 then\n"
    body += "execute immediate 'select count(*) from databasechangelog' into n;\n"
    body += assertion(f'n<>{len(rows)}','Migration history differs from recorded deployment')
    for r in rows:
        body += "execute immediate 'select count(*) from databasechangelog where id=:1 and author=:2 and filename=:3' into n using "+q(r['id'])+','+q(r['author'])+','+q(r['filename'])+';\n'
        body += assertion('n<>1','Migration ownership key is missing or duplicated')
    body += 'end if;\n'
if app != 'SKIP':
    body += f'apex_util.set_security_group_id(apex_util.find_security_group_id(p_workspace=>{q(workspace)}));\napex_application_install.set_workspace({q(workspace)});\napex_application_install.remove_application(p_application_id=>{int(app)});\n'
# Drop dependents first. Body objects disappear with their specifications.
order={'VIEW':0,'MATERIALIZED VIEW':1,'TRIGGER':2,'PACKAGE':3,'PROCEDURE':4,'FUNCTION':5,'SYNONYM':6,'TABLE':7,'INDEX':8,'SEQUENCE':9,'TYPE':10}
for name,kind in sorted(objects,key=lambda x:(order.get(x[1],99),x[0])):
    if kind in ('PACKAGE BODY','TYPE BODY'): continue
    command=f'DROP {kind} "{name}"'+(' CASCADE CONSTRAINTS' if kind=='TABLE' else '')
    body += f'select count(*) into n from user_objects where object_name={q(name)} and object_type={q(kind)};\nif n>0 then execute immediate {q(command)}; end if;\n'
body += 'commit;\nend;\n/\n'
Path(work,'cleanup.sql').write_text(body)
PY
if [[ "$assume_yes" != true ]]; then
  [[ -t 0 ]] || die "Use a terminal for confirmation or --yes for an intentional reset."
  if [[ -f "$manifest" ]]; then
    read -r -p "Type '$PROJECT_NAME' to remove its recorded production artifacts: " response
    [[ "$response" == "$PROJECT_NAME" ]] || die "Production cleanup cancelled."
  else
    read -r -p "Type application ID '$app' to delete it from $APEX_WORKSPACE_PRO/$SCHEMA_NAME_PRO: " response
    [[ "$response" == "$app" ]] || die "Application cleanup cancelled."
  fi
fi
run_sql "$DB_CONNECT_DEV" cleanup-pro-distinct < "$work/dev.sql"
if [[ -f "$manifest" ]]; then
  run_sql "$DB_CONNECT_ADMIN" cleanup-pro-dependencies < "$work/admin.sql"
fi
run_sql "$DB_CONNECT_PRO" cleanup-pro < "$work/cleanup.sql"
if [[ -f "$manifest" ]]; then
  mv "$manifest" "$DEMO_HOME/.state/deployment.cleaned.json"
  python3 - "$DEMO_HOME/.state/production-setup.json" "$app" <<'PYSTATE'
import json,sys
from datetime import datetime,timezone
from pathlib import Path
p=Path(sys.argv[1]);m=json.loads(p.read_text())
m['deployment_state']='not_started'
m.pop('application_id',None)
m['last_cleanup_utc']=datetime.now(timezone.utc).isoformat()
m['application_cleanup']='skipped' if sys.argv[2]=='SKIP' else 'removed'
p.write_text(json.dumps(m,indent=2)+'\n')
PYSTATE
  echo "Removed recorded production database artifacts; schema and workspace were preserved."
else
  echo "Removed selected production application only. No database object ownership manifest exists; database objects were preserved."
fi
