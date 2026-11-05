-- Release 1.1: identify courses that require a certificate.
-- Save in APEX SQL Workshop > SQL Scripts; run manually after baseline 1.0.
-- Pure SQL/PLSQL: no SQLcl commands or explicit data DML.
-- Existing course rows receive the default N through the column definition.
-- Oracle DDL commits implicitly; inspect CURRENT_SCHEMA before execution.
declare
    l_schema varchar2(128) := sys_context('USERENV', 'CURRENT_SCHEMA');
    l_owner varchar2(261);
    l_count number;
begin
    l_owner := dbms_assert.enquote_name(dbms_assert.schema_name(l_schema), false);
    select count(*) into l_count from all_tables
     where owner = l_schema and table_name = 'DEMO_TRN_COURSES';
    if l_count <> 1 then
        raise_application_error(-20015, 'CURRENT_SCHEMA must contain the DEMO_TRN_COURSES table.');
    end if;
    select count(*) into l_count from all_tab_columns
     where owner = l_schema and table_name = 'DEMO_TRN_COURSES'
       and column_name = 'CERTIFICATION_REQUIRED';
    if l_count > 0 then
        raise_application_error(-20016, 'CERTIFICATION_REQUIRED already exists; inspect it before retrying.');
    end if;
    select count(*) into l_count from all_constraints
     where owner = l_schema and constraint_name in ('DEMO_TRN_COURSES_CERT_REQ_CK', 'DEMO_TRN_COURSES_CERT_REQ_NN');
    if l_count > 0 then
        raise_application_error(-20017, 'The certification-required constraint name already exists.');
    end if;
    execute immediate 'alter table ' || l_owner || q'~.DEMO_TRN_COURSES add (
        CERTIFICATION_REQUIRED varchar2(1) default 'N' constraint DEMO_TRN_COURSES_CERT_REQ_NN not null
            constraint DEMO_TRN_COURSES_CERT_REQ_CK check (CERTIFICATION_REQUIRED in ('Y', 'N'))
    )~';
end;
/
