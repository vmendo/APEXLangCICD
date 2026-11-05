-- Read-only baseline verification. Run immediately after the synthetic seed.
-- Counts are intentionally exact; later application edits may change them.
-- No cleanup, DDL, DML, or automatic error suppression is performed.
declare
    l_count number;
    procedure assert_zero(p_count number, p_message varchar2) is
    begin
        if p_count <> 0 then
            raise_application_error(-20110, p_message || ' (count=' || p_count || ')');
        end if;
    end;
begin
    select count(*) into l_count from DEMO_TRN_DEPARTMENTS;
    assert_zero(abs(l_count - 6), 'DEMO_TRN_DEPARTMENTS expected 6 baseline rows');

    select count(*) into l_count from DEMO_TRN_LOCATIONS;
    assert_zero(abs(l_count - 3), 'DEMO_TRN_LOCATIONS expected 3 baseline rows');

    select count(*) into l_count from DEMO_TRN_ROOMS;
    assert_zero(abs(l_count - 5), 'DEMO_TRN_ROOMS expected 5 baseline rows');

    select count(*) into l_count from DEMO_TRN_EMPLOYEES;
    assert_zero(abs(l_count - 30), 'DEMO_TRN_EMPLOYEES expected 30 baseline rows');

    select count(*) into l_count from DEMO_TRN_CATEGORIES;
    assert_zero(abs(l_count - 5), 'DEMO_TRN_CATEGORIES expected 5 baseline rows');

    select count(*) into l_count from DEMO_TRN_COURSES;
    assert_zero(abs(l_count - 10), 'DEMO_TRN_COURSES expected 10 baseline rows');

    select count(*) into l_count from DEMO_TRN_INSTRUCTORS;
    assert_zero(abs(l_count - 6), 'DEMO_TRN_INSTRUCTORS expected 6 baseline rows');

    select count(*) into l_count from DEMO_TRN_SESSIONS;
    assert_zero(abs(l_count - 16), 'DEMO_TRN_SESSIONS expected 16 baseline rows');

    select count(*) into l_count from DEMO_TRN_ENROLLMENTS;
    assert_zero(abs(l_count - 80), 'DEMO_TRN_ENROLLMENTS expected 80 baseline rows');

    select count(*) into l_count from DEMO_TRN_EVALUATIONS;
    assert_zero(abs(l_count - 40), 'DEMO_TRN_EVALUATIONS expected 40 baseline rows');

    select count(*) into l_count from user_objects where object_name like 'DEMO\_TRN\_%' escape '\' and status <> 'VALID';
    assert_zero(l_count, 'Invalid training objects');

    select count(*) into l_count from user_constraints where table_name like 'DEMO\_TRN\_%' escape '\' and (status <> 'ENABLED' or validated <> 'VALIDATED' or constraint_name not like 'DEMO\_TRN\_%' escape '\');
    assert_zero(l_count, 'Training constraint state/name mismatch');

    select count(*) into l_count from user_indexes where table_name like 'DEMO\_TRN\_%' escape '\' and (status <> 'VALID' or index_name not like 'DEMO\_TRN\_%' escape '\');
    assert_zero(l_count, 'Training index state/name mismatch');

    select count(*) into l_count from user_tab_identity_cols where table_name like 'DEMO\_TRN\_%' escape '\';
    assert_zero(l_count, 'Unexpected identity columns');

    select abs(count(*) - 10) into l_count from user_sequences where sequence_name like 'DEMO\_TRN\_%' escape '\';
    assert_zero(l_count, 'Expected exactly ten named training sequences');

    select count(*) into l_count from DEMO_TRN_SESSIONS s join DEMO_TRN_ROOMS r on r.id=s.room_id where s.capacity>r.capacity or s.end_date<=s.start_date;
    assert_zero(l_count, 'Session room capacity/date mismatch');

    select count(*) into l_count from DEMO_TRN_ENROLLMENTS e join DEMO_TRN_SESSIONS s on s.id=e.session_id where e.enrolled_at>=s.start_date or (s.status='COMPLETED' and e.status<>'COMPLETED') or (s.status='CANCELLED' and e.status<>'CANCELLED') or (s.status='SCHEDULED' and e.status<>'ENROLLED');
    assert_zero(l_count, 'Enrollment schedule/status mismatch');

    select count(*) into l_count from (select s.id from DEMO_TRN_SESSIONS s join DEMO_TRN_ENROLLMENTS e on e.session_id=s.id and e.status<>'CANCELLED' group by s.id,s.capacity having count(*)>s.capacity);
    assert_zero(l_count, 'Session overbooked');

    select count(*) into l_count from DEMO_TRN_EVALUATIONS v join DEMO_TRN_ENROLLMENTS e on e.id=v.enrollment_id join DEMO_TRN_SESSIONS s on s.id=e.session_id where e.status<>'COMPLETED' or s.status<>'COMPLETED' or v.submitted_at<s.end_date or v.score not between 1 and 5;
    assert_zero(l_count, 'Evaluation completion/date/score mismatch');

    select count(*) into l_count from user_objects where object_name='DEMO_TRN_CERTIFICATIONS';
    assert_zero(l_count, 'Reserved future certifications object already exists');

    select count(*) into l_count from user_tab_columns where table_name='DEMO_TRN_COURSES' and column_name='CERTIFICATION_REQUIRED';
    assert_zero(l_count, 'Reserved future certification column already exists');

    dbms_output.put_line('Employee Training baseline verified.');
end;
/

select table_name, row_count from (
    select 'DEMO_TRN_DEPARTMENTS' table_name, count(*) row_count from DEMO_TRN_DEPARTMENTS
    union all
    select 'DEMO_TRN_LOCATIONS' table_name, count(*) row_count from DEMO_TRN_LOCATIONS
    union all
    select 'DEMO_TRN_ROOMS' table_name, count(*) row_count from DEMO_TRN_ROOMS
    union all
    select 'DEMO_TRN_EMPLOYEES' table_name, count(*) row_count from DEMO_TRN_EMPLOYEES
    union all
    select 'DEMO_TRN_CATEGORIES' table_name, count(*) row_count from DEMO_TRN_CATEGORIES
    union all
    select 'DEMO_TRN_COURSES' table_name, count(*) row_count from DEMO_TRN_COURSES
    union all
    select 'DEMO_TRN_INSTRUCTORS' table_name, count(*) row_count from DEMO_TRN_INSTRUCTORS
    union all
    select 'DEMO_TRN_SESSIONS' table_name, count(*) row_count from DEMO_TRN_SESSIONS
    union all
    select 'DEMO_TRN_ENROLLMENTS' table_name, count(*) row_count from DEMO_TRN_ENROLLMENTS
    union all
    select 'DEMO_TRN_EVALUATIONS' table_name, count(*) row_count from DEMO_TRN_EVALUATIONS
) order by table_name;
