-- Release 1.1: record certificates awarded to employees for training courses.
-- Save in APEX SQL Workshop > SQL Scripts; run manually after baseline 1.0.
-- Pure SQL/PLSQL: no SQLcl commands, source data DML or application changes.
-- All objects belong to the literal DEMO_TRN_ export scope.
-- Oracle DDL commits implicitly; inspect CURRENT_SCHEMA before execution.
declare
    l_schema varchar2(128) := sys_context('USERENV', 'CURRENT_SCHEMA');
    l_owner varchar2(261);
    l_count number;
begin
    l_owner := dbms_assert.enquote_name(dbms_assert.schema_name(l_schema), false);

    -- Validate every object/constraint collision before the first DDL statement.
    select count(*) into l_count
      from all_objects
     where owner = l_schema and object_name in (
         'DEMO_TRN_CERTIFICATIONS', 'DEMO_TRN_CERTIFICATIONS_SEQ',
         'DEMO_TRN_CERTIFICATIONS_PK', 'DEMO_TRN_CERTIFICATIONS_UQ1',
         'DEMO_TRN_CERTIFICATIONS_FK1_IX', 'DEMO_TRN_CERTIFICATIONS_FK2_IX');
    if l_count > 0 then
        raise_application_error(-20011, 'A certification object already exists; inspect it before retrying.');
    end if;
    select count(*) into l_count
      from all_constraints
     where owner = l_schema and constraint_name in (
         'DEMO_TRN_CERTIFICATIONS_PK', 'DEMO_TRN_CERTIFICATIONS_UQ1',
         'DEMO_TRN_CERTIFICATIONS_FK1', 'DEMO_TRN_CERTIFICATIONS_FK2',
         'DEMO_TRN_CERTIFICATIONS_DATES_CK', 'DEMO_TRN_CERTIFICATIONS_STATUS_CK',
         'DEMO_TRN_CERTIFICATIONS_EMPLOYEE_ID_NN', 'DEMO_TRN_CERTIFICATIONS_COURSE_ID_NN',
         'DEMO_TRN_CERTIFICATIONS_CERTIFICATE_CODE_NN', 'DEMO_TRN_CERTIFICATIONS_ISSUED_ON_NN',
         'DEMO_TRN_CERTIFICATIONS_STATUS_NN');
    if l_count > 0 then
        raise_application_error(-20012, 'A certification constraint name already exists.');
    end if;

    for parent in (
        select 'DEMO_TRN_EMPLOYEES' table_name from dual
        union all select 'DEMO_TRN_COURSES' from dual
    ) loop
        select count(*) into l_count
          from all_tab_columns
         where owner = l_schema and table_name = parent.table_name
           and column_name = 'ID' and data_type = 'NUMBER';
        if l_count <> 1 then
            raise_application_error(-20013, 'CURRENT_SCHEMA must contain ' || parent.table_name || '.ID NUMBER.');
        end if;
        select count(*) into l_count
          from all_constraints c
          join all_cons_columns cc
            on cc.owner = c.owner and cc.constraint_name = c.constraint_name
         where c.owner = l_schema and c.table_name = parent.table_name
           and c.constraint_type = 'P' and c.status = 'ENABLED'
           and c.validated = 'VALIDATED' and cc.column_name = 'ID' and cc.position = 1
           and not exists (
               select 1 from all_cons_columns extra
                where extra.owner = c.owner and extra.constraint_name = c.constraint_name
                  and extra.position > 1);
        if l_count <> 1 then
            raise_application_error(-20014, parent.table_name || ' requires an enabled primary key on ID.');
        end if;
    end loop;

    execute immediate 'create sequence ' || l_owner ||
        '.DEMO_TRN_CERTIFICATIONS_SEQ start with 1000 increment by 1 cache 20 nocycle';
    execute immediate 'create table ' || l_owner || q'~.DEMO_TRN_CERTIFICATIONS (
        ID number default ~' || l_owner || q'~.DEMO_TRN_CERTIFICATIONS_SEQ.nextval,
        EMPLOYEE_ID number constraint DEMO_TRN_CERTIFICATIONS_EMPLOYEE_ID_NN not null,
        COURSE_ID number constraint DEMO_TRN_CERTIFICATIONS_COURSE_ID_NN not null,
        CERTIFICATE_CODE varchar2(40) constraint DEMO_TRN_CERTIFICATIONS_CERTIFICATE_CODE_NN not null,
        ISSUED_ON date default trunc(sysdate) constraint DEMO_TRN_CERTIFICATIONS_ISSUED_ON_NN not null,
        EXPIRES_ON date,
        STATUS varchar2(20) default 'VALID' constraint DEMO_TRN_CERTIFICATIONS_STATUS_NN not null,
        NOTES varchar2(1000),
        constraint DEMO_TRN_CERTIFICATIONS_PK primary key (ID),
        constraint DEMO_TRN_CERTIFICATIONS_UQ1 unique (CERTIFICATE_CODE),
        constraint DEMO_TRN_CERTIFICATIONS_FK1 foreign key (EMPLOYEE_ID)
            references ~' || l_owner || q'~.DEMO_TRN_EMPLOYEES (ID),
        constraint DEMO_TRN_CERTIFICATIONS_FK2 foreign key (COURSE_ID)
            references ~' || l_owner || q'~.DEMO_TRN_COURSES (ID),
        constraint DEMO_TRN_CERTIFICATIONS_DATES_CK
            check (EXPIRES_ON is null or EXPIRES_ON >= ISSUED_ON),
        constraint DEMO_TRN_CERTIFICATIONS_STATUS_CK
            check (STATUS in ('VALID', 'EXPIRED', 'REVOKED'))
    )~';
    execute immediate 'create index ' || l_owner || '.DEMO_TRN_CERTIFICATIONS_FK1_IX on ' ||
        l_owner || '.DEMO_TRN_CERTIFICATIONS (EMPLOYEE_ID)';
    execute immediate 'create index ' || l_owner || '.DEMO_TRN_CERTIFICATIONS_FK2_IX on ' ||
        l_owner || '.DEMO_TRN_CERTIFICATIONS (COURSE_ID)';
end;
/
