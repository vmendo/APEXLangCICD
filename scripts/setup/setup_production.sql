-- Production schema and workspace setup, invoked by run/setup/setup_production.sh.
-- Inputs are bind variables initialized by the wrapper, never substitution text.
-- API references:
-- https://docs.oracle.com/en/database/oracle/apex/24.2/aeapi/ADD_WORKSPACE-Procedure.html
-- https://docs.oracle.com/en/database/oracle/apex/24.2/aeapi/ADD_SCHEMA-Procedure.html
declare
  l_schema varchar2(128) := dbms_assert.simple_sql_name(:demo_schema);
  l_workspace varchar2(128) := :demo_workspace;
  l_count number;
begin
  if user <> 'ADMIN' then
    raise_application_error(-20002, 'Production provisioning requires ADMIN.');
  end if;
  select count(*) into l_count from dba_users where username = l_schema;
  if l_count = 0 then
    if :demo_password is null then
      raise_application_error(-20001, 'A password is required for a new schema.');
    end if;
    -- The wrapper restricts generated/supplied passwords to a safe alphabet.
    execute immediate 'create user ' || l_schema || ' identified by "'
      || :demo_password || '" default tablespace DATA quota 100M on DATA';
    execute immediate 'grant create session, create table, create view, '
      || 'create sequence, create procedure, create trigger, create type to ' || l_schema;
    dbms_output.put_line('Created schema ' || l_schema || '.');
  else
    dbms_output.put_line('Reusing existing schema without changing its password, grants, or quota.');
  end if;

  select count(*) into l_count from apex_workspaces
   where workspace = l_workspace;
  if l_count = 0 then
    apex_instance_admin.add_workspace(
      p_workspace => l_workspace,
      p_primary_schema => l_schema,
      p_additional_schemas => null);
    dbms_output.put_line('Created workspace ' || l_workspace || '.');
  else
    select count(*) into l_count from apex_workspace_schemas
     where workspace_name = l_workspace and schema = l_schema;
    if l_count = 0 then
      apex_instance_admin.add_schema(
        p_workspace => l_workspace,
        p_schema => l_schema);
      dbms_output.put_line('Added workspace schema mapping.');
    else
      dbms_output.put_line('Workspace schema mapping already exists.');
    end if;
  end if;
  commit;
end;
/
