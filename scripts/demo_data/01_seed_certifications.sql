-- Optional presentation data, outside SQLcl Projects releases/migrations.
-- Run manually in the intended parsing schema after release 1.1 exists.
-- Works in DEV, or in PRO after 02_seed_production.sql if it was empty.
-- Adds up to 12 certificates for existing completed enrollments; no parent DML.
-- Re-running skips existing TH-DEMO-<enrollment ID> codes; never overwrites rows.
-- Run in a dedicated session without unrelated uncommitted work.
declare
    c_sample_size constant pls_integer := 12;
    l_today date := trunc(sysdate);
    l_count number;
    l_seen pls_integer := 0;
    l_inserted pls_integer := 0;
    l_code varchar2(40);
    l_status varchar2(20);
    l_expires date;
begin
    savepoint training_certificates_seed;
    select count(*) into l_count from all_tables
     where owner = sys_context('USERENV', 'CURRENT_SCHEMA')
       and table_name = 'DEMO_TRN_CERTIFICATIONS';
    if l_count <> 1 then
        raise_application_error(-20120, 'Create/deploy the release 1.1 certifications table first.');
    end if;

    for r in (
        select * from (
            select n.id enrollment_id, n.employee_id, s.course_id,
                   trunc(s.end_date) issued_on,
                   row_number() over (order by n.id) sample_number
              from DEMO_TRN_ENROLLMENTS n
              join DEMO_TRN_SESSIONS s on s.id = n.session_id
             where n.status = 'COMPLETED' and s.status = 'COMPLETED'
               and s.end_date < l_today
             order by n.id
        ) where rownum <= c_sample_size
    ) loop
        l_seen := l_seen + 1;
        l_code := 'TH-DEMO-' || to_char(r.enrollment_id, 'TM9');
        if mod(r.sample_number, 5) = 0 then
            l_status := 'REVOKED';
            l_expires := greatest(r.issued_on + 365, l_today + 90);
        elsif mod(r.sample_number, 5) = 4 then
            l_status := 'EXPIRED';
            l_expires := l_today - 1;
        else
            l_status := 'VALID';
            l_expires := greatest(r.issued_on + 365, l_today + 90);
        end if;
        -- Dynamic SQL allows a clear missing-release error on baseline 1.0.
        -- ID is intentionally omitted: the named sequence supplies it.
        execute immediate q'~
            insert into DEMO_TRN_CERTIFICATIONS (
                EMPLOYEE_ID, COURSE_ID, CERTIFICATE_CODE, ISSUED_ON,
                EXPIRES_ON, STATUS, NOTES
            )
            select :employee_id, :course_id, :code, :issued_on,
                   :expires_on, :status, :notes
              from dual
             where not exists (
                 select 1 from DEMO_TRN_CERTIFICATIONS where CERTIFICATE_CODE = :existing_code
             )~'
            using r.employee_id, r.course_id, l_code, r.issued_on,
                  l_expires, l_status,
                  'Fictional presentation certificate for a completed training enrollment.', l_code;
        l_inserted := l_inserted + sql%rowcount;
    end loop;
    if l_seen = 0 then
        raise_application_error(-20121, 'No completed training enrollments found; load presentation data first.');
    end if;
    dbms_output.put_line('Synthetic certificates inserted: ' || l_inserted || '. Existing codes were preserved.');
    commit;
exception
    when others then
        rollback to training_certificates_seed;
        raise;
end;
/
