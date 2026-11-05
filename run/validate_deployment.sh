#!/usr/bin/env bash
# Verify the deployed Training Hub model and its manually added release page.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/aux/common.sh"
[[ $# -ge 1 && $# -le 2 ]] || die "Usage: $0 <baseline|incremental> [report_page_id]"
load_project
mode="$1"
[[ "$mode" == baseline || "$mode" == incremental ]] || die "Expected baseline or incremental."
page="${2:-200}"
[[ "$page" =~ ^[1-9][0-9]*$ ]] || die "Page ID must be a positive integer."
"$SCRIPT_DIR/aux/check_environment.sh" PRO
run_sql "$DB_CONNECT_PRO" "validate-$mode" <<EOF
set serveroutput on
declare
  n number;
  row_count number;
  column_default varchar2(32767);
  expected_count number := case when '$mode'='baseline' then 10 else 11 end;
begin
  select count(*) into n from apex_applications where application_id=$APEX_APP_ID_PRO
    and workspace='$APEX_WORKSPACE_PRO' and owner='$SCHEMA_NAME_PRO';
  if n<>1 then raise_application_error(-20060,'Deployed application missing');end if;
  select count(*) into n from user_objects where object_name like 'DEMO\_TRN\_%' escape '\\' and status='INVALID';
  if n>0 then raise_application_error(-20061,'Invalid DEMO_TRN_ objects found');end if;
  select count(*) into n from user_tables where table_name in (
    'DEMO_TRN_DEPARTMENTS','DEMO_TRN_LOCATIONS','DEMO_TRN_ROOMS','DEMO_TRN_EMPLOYEES',
    'DEMO_TRN_CATEGORIES','DEMO_TRN_COURSES','DEMO_TRN_INSTRUCTORS',
    'DEMO_TRN_SESSIONS','DEMO_TRN_ENROLLMENTS','DEMO_TRN_EVALUATIONS');
  if n<>10 then raise_application_error(-20065,'Training baseline tables missing');end if;
  select count(*) into n from user_tables where table_name like 'DEMO\_TRN\_%' escape '\\';
  if n<>expected_count then raise_application_error(-20066,'Unexpected training table count');end if;
  select count(*) into n from user_sequences where sequence_name like 'DEMO\_TRN\_%' escape '\\';
  if n<>expected_count then raise_application_error(-20067,'Unexpected training sequence count');end if;
  select count(*) into n from user_tab_identity_cols where table_name like 'DEMO\_TRN\_%' escape '\\';
  if n>0 then raise_application_error(-20068,'Training keys must use named sequences');end if;
  select count(*) into n from user_constraints where table_name like 'DEMO\_TRN\_%' escape '\\'
    and (status<>'ENABLED' or validated<>'VALIDATED' or constraint_name not like 'DEMO\_TRN\_%' escape '\\');
  if n>0 then raise_application_error(-20069,'Invalid or unprefixed training constraints');end if;
  select count(*) into n from user_indexes where table_name like 'DEMO\_TRN\_%' escape '\\'
    and (status<>'VALID' or index_name not like 'DEMO\_TRN\_%' escape '\\');
  if n>0 then raise_application_error(-20070,'Invalid or unprefixed training indexes');end if;
  for t in (select table_name from user_tables where table_name like 'DEMO\_TRN\_%' escape '\\') loop
    execute immediate 'select count(*) from ' || dbms_assert.enquote_name(t.table_name,false) into row_count;
    if row_count<>0 then raise_application_error(-20071,'Expected structures only: ' || t.table_name || ' has rows');end if;
  end loop;
  if '$mode'='incremental' then
    select count(*) into n from user_tables where table_name='DEMO_TRN_CERTIFICATIONS';
    if n<>1 then raise_application_error(-20062,'Certifications table missing');end if;
    select count(*) into n from user_tab_columns where table_name='DEMO_TRN_COURSES'
      and column_name='CERTIFICATION_REQUIRED' and data_type='VARCHAR2' and char_length=1 and nullable='N';
    if n<>1 then raise_application_error(-20063,'Certification-required column missing or changed');end if;
    select data_default into column_default from user_tab_columns where table_name='DEMO_TRN_COURSES'
      and column_name='CERTIFICATION_REQUIRED';
    if trim(column_default)<>'''N''' or column_default is null then
      raise_application_error(-20072,'Certification-required default must be N');end if;
    select count(*) into n from user_constraints where table_name='DEMO_TRN_COURSES'
      and constraint_name='DEMO_TRN_COURSES_CERT_REQ_CK' and constraint_type='C';
    if n<>1 then raise_application_error(-20073,'Certification-required constraint missing');end if;
    select count(*) into n from user_constraints where table_name='DEMO_TRN_CERTIFICATIONS'
      and constraint_name in ('DEMO_TRN_CERTIFICATIONS_PK','DEMO_TRN_CERTIFICATIONS_UQ1',
        'DEMO_TRN_CERTIFICATIONS_FK1','DEMO_TRN_CERTIFICATIONS_FK2',
        'DEMO_TRN_CERTIFICATIONS_DATES_CK','DEMO_TRN_CERTIFICATIONS_STATUS_CK');
    if n<>6 then raise_application_error(-20074,'Certification constraints missing');end if;
    select count(*) into n from user_indexes where table_name='DEMO_TRN_CERTIFICATIONS'
      and index_name in ('DEMO_TRN_CERTIFICATIONS_PK','DEMO_TRN_CERTIFICATIONS_UQ1',
        'DEMO_TRN_CERTIFICATIONS_FK1_IX','DEMO_TRN_CERTIFICATIONS_FK2_IX');
    if n<>4 then raise_application_error(-20075,'Certification indexes missing');end if;
    select count(*) into n from apex_application_pages where application_id=$APEX_APP_ID_PRO and page_id=$page;
    if n<>1 then raise_application_error(-20064,'Manual certifications page missing');end if;
  else
    select count(*) into n from user_tab_columns where table_name='DEMO_TRN_COURSES' and column_name='CERTIFICATION_REQUIRED';
    if n>0 then raise_application_error(-20076,'Baseline includes the release 1.1 column');end if;
  end if;
  dbms_output.put_line('Training Hub deployment metadata and structures-only validation passed.');
end;
/
EOF
printf 'Open production application %s in APEX and validate login, navigation and empty-state rendering manually.\n' "$APEX_APP_ID_PRO"
