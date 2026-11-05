#!/usr/bin/env bash
# Delete selected development pages and revert only the two database demo changes.
# Page deletion uses the internal WWV_FLOW_API.REMOVE_PAGE API verified on APEX
# 26.1. Its signature is checked before use; no full-application restore occurs.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../aux/common.sh"
assume_yes=false
skip_page=false
requested_pages=''
usage() {
  echo "Usage: $0 [--page-id ID ... | --skip-page] [--yes]"
  echo "Without a selection, list application pages and prompt; Enter skips page deletion."
  echo "--yes requires explicit --page-id choices or --skip-page."
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) assume_yes=true; shift ;;
    --skip-page) skip_page=true; shift ;;
    --page-id)
      [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || die "--page-id requires a positive page ID; global page 0 is not eligible."
      requested_pages="${requested_pages:+$requested_pages,}$2"
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown cleanup argument: $1" ;;
  esac
done
[[ "$skip_page" != true || -z "$requested_pages" ]] || die "--skip-page and --page-id are mutually exclusive."
[[ "$assume_yes" != true || "$skip_page" == true || -n "$requested_pages" ]] || die "--yes requires explicit --page-id choices or --skip-page."
require_tools python3 mktemp
# Standalone cleanup remains available after the generated project was removed.
if [[ -f "$DEMO_HOME/.state/project.env" ]]; then
  # Cleanup needs the saved identity, not a surviving generated checkout.
  source "$DEMO_HOME/.state/project.env"
fi
validate_name "$PROJECT_NAME"
validate_identifier "$SCHEMA_NAME"
validate_identifier "$APEX_WORKSPACE_DEV"
[[ "$APEX_APP_ID" =~ ^[1-9][0-9]*$ ]] || die "Invalid source application ID."
umask 077
mkdir -p "$DEMO_HOME/.state"
temporary="$(mktemp -d "$DEMO_HOME/.state/cleanup-dev.XXXXXX")"
inventory="$temporary/inventory.json"
trap 'rm -rf -- "$temporary"' EXIT
bash "$SCRIPT_DIR/aux/apex_cleanup_inventory.sh" DEV pages "$inventory" "$APEX_APP_ID"
# Bind cleanup to the freshly queried source identity.
verified_identity="$(python3 - "$inventory" "$SCHEMA_NAME" "$APEX_WORKSPACE_DEV" "$APEX_APP_ID" <<'PY_IDENTITY'
import json, re, sys
from pathlib import Path
inventory, schema, workspace, app = sys.argv[1:]
m = json.loads(Path(inventory).read_text())
if (m.get('schema'), m.get('workspace'), str(m.get('app_id'))) != (schema, workspace, app):
    raise SystemExit('Development inventory does not match the configured schema/workspace/application.')
for key in ('database', 'service'):
    if not isinstance(m.get(key), str) or not re.fullmatch(r'[A-Za-z0-9_.-]+', m[key]):
        raise SystemExit('Invalid development database identity in inventory.')
print(m['database'] + '|' + m['service'])
PY_IDENTITY
)" || die "Development identity validation failed. No database changes performed."
IFS='|' read -r verified_database verified_service <<< "$verified_identity"
selection_args=(--inventory "$inventory" --kind page)
[[ -z "$requested_pages" ]] || selection_args+=(--selected "$requested_pages")
[[ "$skip_page" != true ]] || selection_args+=(--skip)
[[ "$assume_yes" != true ]] || selection_args+=(--yes)
selected_pages="$(python3 "$SCRIPT_DIR/aux/cleanup_selection.py" "${selection_args[@]}")" || die "Page selection failed."
# Revalidate helper output independently before interpolating any page IDs.
python3 - "$inventory" "$selected_pages" <<'PY_SELECTION'
import json, re, sys
inventory = json.load(open(sys.argv[1]))
selected = sys.argv[2]
if selected == 'SKIP':
    print('Page deletion skipped; no application pages will be changed.')
    raise SystemExit(0)
if not re.fullmatch(r'[1-9][0-9]*(,[1-9][0-9]*)*', selected):
    raise SystemExit('Invalid selected page list; global page 0 is not eligible.')
pages = {int(page['id']): page['name'] for page in inventory['pages']}
for page in dict.fromkeys(map(int, selected.split(','))):
    if page not in pages:
        raise SystemExit(f'Page {page} is not in the configured development application.')
    print(f'Selected development page {page}: {pages[page]}')
PY_SELECTION

preflight_sql="$(cat <<EOF
set serveroutput on
declare
  l_count number;
  l_rows number;
begin
  if user <> '$SCHEMA_NAME' or sys_context('USERENV','DB_NAME') <> '$verified_database'
     or sys_context('USERENV','SERVICE_NAME') <> '$verified_service' then
    raise_application_error(-20040, 'Development database identity changed after inventory.');
  end if;
  select count(*) into l_count from apex_applications
   where application_id = $APEX_APP_ID and workspace = '$APEX_WORKSPACE_DEV'
     and owner = '$SCHEMA_NAME';
  if l_count <> 1 then
    raise_application_error(-20041, 'Development application identity differs from configuration.');
  end if;
  select count(*) into l_count from user_objects where object_name = 'DEMO_TRN_CERTIFICATIONS' and object_type <> 'TABLE';
  if l_count > 0 then
    raise_application_error(-20042, 'Unexpected object type uses the demo table name.');
  end if;
  select count(*) into l_count from user_tables where table_name = 'DEMO_TRN_CERTIFICATIONS';
  if l_count = 1 then
    select count(*) into l_count from user_tab_columns
     where table_name = 'DEMO_TRN_CERTIFICATIONS'
       and column_name in ('ID','EMPLOYEE_ID','COURSE_ID','CERTIFICATE_CODE','ISSUED_ON','EXPIRES_ON','STATUS','NOTES');
    if l_count <> 8 then
      raise_application_error(-20043, 'Demo table does not have the expected column signature.');
    end if;
    select count(*) into l_count from user_tab_columns
     where table_name = 'DEMO_TRN_CERTIFICATIONS';
    if l_count <> 8 then
      raise_application_error(-20047, 'Demo table has additional columns; review before cleanup.');
    end if;
    select count(*) into l_count from user_tab_columns
     where table_name = 'DEMO_TRN_CERTIFICATIONS' and (
       (column_name in ('ID','EMPLOYEE_ID','COURSE_ID') and data_type='NUMBER' and nullable='N') or
       (column_name='CERTIFICATE_CODE' and data_type='VARCHAR2' and char_length=40 and nullable='N') or
       (column_name='ISSUED_ON' and data_type='DATE' and nullable='N') or
       (column_name='EXPIRES_ON' and data_type='DATE' and nullable='Y') or
       (column_name='STATUS' and data_type='VARCHAR2' and char_length=20 and nullable='N') or
       (column_name='NOTES' and data_type='VARCHAR2' and char_length=1000 and nullable='Y'));
    if l_count <> 8 then
      raise_application_error(-20051, 'Certification column definitions differ from release 1.1; review before cleanup.');
    end if;
    select count(*) into l_count from user_indexes
     where table_name='DEMO_TRN_CERTIFICATIONS'
       and index_name not in ('DEMO_TRN_CERTIFICATIONS_PK','DEMO_TRN_CERTIFICATIONS_UQ1',
                              'DEMO_TRN_CERTIFICATIONS_FK1_IX','DEMO_TRN_CERTIFICATIONS_FK2_IX');
    if l_count > 0 then
      raise_application_error(-20052, 'Additional certification indexes exist; review before cleanup.');
    end if;
    select count(*) into l_count from user_constraints
     where table_name='DEMO_TRN_CERTIFICATIONS' and generated='USER NAME'
       and constraint_name not in ('DEMO_TRN_CERTIFICATIONS_PK','DEMO_TRN_CERTIFICATIONS_UQ1',
                                   'DEMO_TRN_CERTIFICATIONS_FK1','DEMO_TRN_CERTIFICATIONS_FK2',
                                   'DEMO_TRN_CERTIFICATIONS_DATES_CK','DEMO_TRN_CERTIFICATIONS_STATUS_CK',
                                   'DEMO_TRN_CERTIFICATIONS_EMPLOYEE_ID_NN',
                                   'DEMO_TRN_CERTIFICATIONS_COURSE_ID_NN',
                                   'DEMO_TRN_CERTIFICATIONS_CERTIFICATE_CODE_NN',
                                   'DEMO_TRN_CERTIFICATIONS_ISSUED_ON_NN',
                                   'DEMO_TRN_CERTIFICATIONS_STATUS_NN');
    if l_count > 0 then
      raise_application_error(-20053, 'Additional certification constraints exist; review before cleanup.');
    end if;
    execute immediate 'select count(*) from DEMO_TRN_CERTIFICATIONS' into l_rows;
    dbms_output.put_line('Certification rows to remove: ' || l_rows);
    dbms_output.put_line(dbms_metadata.get_ddl('TABLE', 'DEMO_TRN_CERTIFICATIONS'));
    select count(*) into l_count from user_dependencies
     where referenced_name = 'DEMO_TRN_CERTIFICATIONS' and name <> 'DEMO_TRN_CERTIFICATIONS';
    if l_count > 0 then
      raise_application_error(-20044, 'Dependent database objects reference the demo table; review them first.');
    end if;
    select count(*) into l_count from user_constraints child_constraint
     where child_constraint.constraint_type = 'R'
       and child_constraint.r_constraint_name in (
         select constraint_name from user_constraints
          where table_name = 'DEMO_TRN_CERTIFICATIONS' and constraint_type in ('P','U'));
    if l_count > 0 then
      raise_application_error(-20045, 'Foreign keys reference the demo table; review them first.');
    end if;
  end if;
  select count(*) into l_count from user_objects
   where object_name='DEMO_TRN_CERTIFICATIONS_SEQ' and object_type<>'SEQUENCE';
  if l_count > 0 then
    raise_application_error(-20054, 'Unexpected object type uses the certification sequence name.');
  end if;
  select count(*) into l_count from user_sequences
   where sequence_name='DEMO_TRN_CERTIFICATIONS_SEQ';
  if l_count=1 then
    select count(*) into l_count from user_sequences
     where sequence_name='DEMO_TRN_CERTIFICATIONS_SEQ'
       and increment_by=1 and cycle_flag='N' and cache_size=20 and last_number>=1000;
    if l_count<>1 then
      raise_application_error(-20055, 'Certification sequence differs from release 1.1; review before cleanup.');
    end if;
    select count(*) into l_count from user_dependencies
     where referenced_name='DEMO_TRN_CERTIFICATIONS_SEQ'
       and name<>'DEMO_TRN_CERTIFICATIONS';
    if l_count>0 then
      raise_application_error(-20056, 'Other objects depend on the certification sequence; cleanup stopped.');
    end if;
    dbms_output.put_line(dbms_metadata.get_ddl('SEQUENCE','DEMO_TRN_CERTIFICATIONS_SEQ'));
  end if;
  for flag_constraint in (
    select constraint_name, table_name, constraint_type from user_constraints
     where constraint_name in ('DEMO_TRN_COURSES_CERT_REQ_CK','DEMO_TRN_COURSES_CERT_REQ_NN')
  ) loop
    if flag_constraint.table_name<>'DEMO_TRN_COURSES' or flag_constraint.constraint_type<>'C' then
      raise_application_error(-20057, 'The certification flag constraint belongs to another object.');
    end if;
    select count(*) into l_count from user_cons_columns
     where constraint_name=flag_constraint.constraint_name
       and table_name='DEMO_TRN_COURSES' and column_name='CERTIFICATION_REQUIRED';
    if l_count<>1 then
      raise_application_error(-20058, 'Certification flag constraint references another column.');
    end if;
    select count(*) into l_count from user_cons_columns
     where constraint_name=flag_constraint.constraint_name;
    if l_count<>1 then
      raise_application_error(-20059, 'Certification flag constraint references additional columns.');
    end if;
  end loop;
  select count(*) into l_count from user_tab_columns
   where table_name = 'DEMO_TRN_COURSES' and column_name = 'CERTIFICATION_REQUIRED';
  if l_count = 1 then
    select count(*) into l_count from user_tab_columns
     where table_name = 'DEMO_TRN_COURSES' and column_name = 'CERTIFICATION_REQUIRED'
       and data_type = 'VARCHAR2' and char_length = 1 and nullable = 'N';
    if l_count <> 1 then
      raise_application_error(-20046, 'Demo column definition has changed; review before cleanup.');
    end if;
    execute immediate 'select count(*) from DEMO_TRN_COURSES where CERTIFICATION_REQUIRED is not null' into l_rows;
    dbms_output.put_line('Course certification flags to remove: ' || l_rows);
  end if;
end;
/
EOF
)"
page_checks=''
page_deletion=''
if [[ "$selected_pages" != SKIP ]]; then
  page_checks="$(cat <<EOF
declare
  l_count number;
  l_api_owner varchar2(128);
  l_api_package varchar2(128);
  l_version varchar2(100);
begin
  select version_no into l_version from apex_release;
  if l_version not like '26.1.%' then
    raise_application_error(-20048, 'Selected-page cleanup uses an internal API verified for APEX 26.1 only.');
  end if;
  select table_owner, table_name into l_api_owner, l_api_package
    from all_synonyms where owner = 'PUBLIC' and synonym_name = 'WWV_FLOW_API';
  select count(distinct argument_name) into l_count from all_arguments
   where owner = l_api_owner and package_name = l_api_package
     and object_name = 'REMOVE_PAGE' and data_type = 'NUMBER' and in_out = 'IN'
     and argument_name in ('P_FLOW_ID', 'P_PAGE_ID');
  if l_count <> 2 then
    raise_application_error(-20049, 'The internal page-deletion API signature is unavailable or changed.');
  end if;
  for selected_page in (
    select column_value page_id from table(sys.odcinumberlist($selected_pages))
  ) loop
    select count(*) into l_count
      from apex_application_pages p join apex_applications a
        on a.application_id = p.application_id
     where p.application_id = $APEX_APP_ID and p.page_id = selected_page.page_id
       and a.workspace = '$APEX_WORKSPACE_DEV' and a.owner = '$SCHEMA_NAME';
    if l_count <> 1 or selected_page.page_id <= 0 then
      raise_application_error(-20050, 'A selected page is missing or outside the configured development application.');
    end if;
  end loop;
end;
/
EOF
)"
  # REMOVE_PAGE is an internal APEX 26.1 API. Dynamic invocation keeps the
  # explicit skip path usable if that API is unavailable on another instance.
  page_deletion="$(cat <<EOF
declare
  l_workspace_id number;
begin
  select workspace_id into l_workspace_id from apex_applications
   where application_id = $APEX_APP_ID and workspace = '$APEX_WORKSPACE_DEV'
     and owner = '$SCHEMA_NAME';
  apex_util.set_security_group_id(l_workspace_id);
  for selected_page in (
    select column_value page_id from table(sys.odcinumberlist($selected_pages))
  ) loop
    execute immediate 'begin wwv_flow_api.remove_page(p_flow_id => :application_id, p_page_id => :page_id); end;'
      using $APEX_APP_ID, selected_page.page_id;
    dbms_output.put_line('Deleted development page ' || selected_page.page_id || ' from application $APEX_APP_ID.');
  end loop;
  commit;
end;
/
EOF
)"
fi
run_sql "$DB_CONNECT_DEV" "cleanup-dev-preflight-$PROJECT_NAME" <<EOF
$preflight_sql
$page_checks
EOF
echo "Development cleanup removes only selected pages and the two database demo changes."
echo "Database changes: certification table/sequence/indexes/constraints and DEMO_TRN_COURSES.CERTIFICATION_REQUIRED."
echo "The development application is not reimported or replaced."
echo "Review shared navigation links to deleted pages separately in APEX."
if [[ "$assume_yes" != true ]]; then
  [[ -t 0 ]] || die "Interactive confirmation requires a terminal; use --yes with an explicit page decision."
  read -r -p "Type the project name '$PROJECT_NAME' to reset the selected development artifacts: " confirmation
  [[ "$confirmation" == "$PROJECT_NAME" ]] || die "Development cleanup cancelled."
fi

# Recheck the fresh identity, API contract, selected pages, and database object
# signatures in the same session immediately before the requested changes.
run_sql "$DB_CONNECT_DEV" "cleanup-dev-$PROJECT_NAME" <<EOF
$preflight_sql
$page_checks
$page_deletion
declare
  l_count number;
begin
  select count(*) into l_count from user_tables where table_name = 'DEMO_TRN_CERTIFICATIONS';
  if l_count = 1 then
    execute immediate 'drop table DEMO_TRN_CERTIFICATIONS';
  end if;
  -- Dropping the new table removes its own named constraints and indexes.
  -- Its explicit sequence is independent and must be removed separately.
  select count(*) into l_count from user_sequences
   where sequence_name='DEMO_TRN_CERTIFICATIONS_SEQ';
  if l_count=1 then
    execute immediate 'drop sequence DEMO_TRN_CERTIFICATIONS_SEQ';
  end if;
  select count(*) into l_count from user_constraints
   where table_name='DEMO_TRN_COURSES' and constraint_name='DEMO_TRN_COURSES_CERT_REQ_CK'
     and constraint_type='C';
  if l_count=1 then
    execute immediate 'alter table DEMO_TRN_COURSES drop constraint DEMO_TRN_COURSES_CERT_REQ_CK';
  end if;
  select count(*) into l_count from user_tab_columns
   where table_name = 'DEMO_TRN_COURSES' and column_name = 'CERTIFICATION_REQUIRED';
  if l_count = 1 then
    -- The column drop also removes its own CERT_REQ_NN NOT NULL constraint.
    execute immediate 'alter table DEMO_TRN_COURSES drop column CERTIFICATION_REQUIRED';
  end if;
end;
/
EOF
echo "Development cleanup completed. Unselected application pages and audit logs were retained."
