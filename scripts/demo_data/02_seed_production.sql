-- Optional PRO presentation data, outside SQLcl Projects releases/migrations.
-- Run manually in the intended production parsing schema after deployment
-- and the FINAL structures-only validation. No source data is copied.
-- Compatible with baseline 1.0 and release 1.1; creates no database objects.
-- Requires all ten baseline tables to be empty; never deletes/updates rows.
-- Run in a dedicated session without unrelated uncommitted work.
-- After 1.1, run 01_seed_certifications.sql separately to fill its new page.
declare
    type ids_t is table of number index by pls_integer;
    l_departments ids_t;
    l_locations ids_t;
    l_rooms ids_t;
    l_employees ids_t;
    l_categories ids_t;
    l_courses ids_t;
    l_instructors ids_t;
    l_today date := trunc(sysdate);
    l_count number;
    l_session_id number;
    l_enrollment_id number;
    l_employee_index pls_integer;
    l_start date;
    l_end date;
    l_session_status varchar2(20);
    l_enrollment_status varchar2(20);
    l_first_names sys.odcivarchar2list := sys.odcivarchar2list(
        'Elena','Mateo','Aisha','Omar','Mei','Jun','Lena','Jonas','Freya','Luca','Nia','Gabriel');
    l_last_names sys.odcivarchar2list := sys.odcivarchar2list(
        'Varela','Serrano','Rahman','Hassan','Lin','Tanaka','Fischer','Weber','Larsen','Moretti','Kamau','Santos');
    l_department_names sys.odcivarchar2list := sys.odcivarchar2list(
        'People and Culture','Engineering','Customer Operations');
    l_category_names sys.odcivarchar2list := sys.odcivarchar2list(
        'Leadership','Digital Skills','Workplace Wellbeing');
    l_course_names sys.odcivarchar2list := sys.odcivarchar2list(
        'Coaching Conversations','Data Literacy Essentials','Sustainable Work Habits',
        'Leading Collaborative Teams','Practical Spreadsheet Skills','Inclusive Workplace Practices');
begin
    savepoint training_production_seed;
    for t in (
        select column_value table_name from table(sys.odcivarchar2list(
            'DEMO_TRN_DEPARTMENTS','DEMO_TRN_LOCATIONS','DEMO_TRN_ROOMS','DEMO_TRN_EMPLOYEES',
            'DEMO_TRN_CATEGORIES','DEMO_TRN_COURSES','DEMO_TRN_INSTRUCTORS',
            'DEMO_TRN_SESSIONS','DEMO_TRN_ENROLLMENTS','DEMO_TRN_EVALUATIONS'))
    ) loop
        execute immediate 'select count(*) from ' || dbms_assert.enquote_name(t.table_name, false) into l_count;
        if l_count <> 0 then
            raise_application_error(-20122, t.table_name || ' is not empty; no presentation data was inserted.');
        end if;
    end loop;

    for i in 1..3 loop
        insert into DEMO_TRN_DEPARTMENTS (DEPARTMENT_NAME, COST_CENTER)
        values (l_department_names(i), 'DEMO-P-' || to_char(i, 'FM000'))
        returning ID into l_departments(i);
        insert into DEMO_TRN_CATEGORIES (CATEGORY_NAME, DESCRIPTION)
        values (l_category_names(i), 'Fictional learning category for the production presentation.')
        returning ID into l_categories(i);
    end loop;
    insert into DEMO_TRN_LOCATIONS (LOCATION_NAME, CITY, COUNTRY)
    values ('Madrid Learning Hub', 'Madrid', 'Spain') returning ID into l_locations(1);
    insert into DEMO_TRN_LOCATIONS (LOCATION_NAME, CITY, COUNTRY)
    values ('Dublin Collaboration Center', 'Dublin', 'Ireland') returning ID into l_locations(2);
    for i in 1..3 loop
        insert into DEMO_TRN_ROOMS (LOCATION_ID, ROOM_NAME, CAPACITY)
        values (l_locations(mod(i - 1, 2) + 1), 'Learning Room ' || i, 18)
        returning ID into l_rooms(i);
        insert into DEMO_TRN_INSTRUCTORS (FIRST_NAME, LAST_NAME, EMAIL, SPECIALTY, ACTIVE_FLAG)
        values (l_first_names(i + 6), l_last_names(i + 6),
                'training.instructor.' || i || '@example.com', l_category_names(i), 'Y')
        returning ID into l_instructors(i);
    end loop;
    for i in 1..12 loop
        insert into DEMO_TRN_EMPLOYEES (
            DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS)
        values (l_departments(mod(i - 1, 3) + 1), 'DEMO-P-' || to_char(i, 'FM000'),
                l_first_names(i), l_last_names(i), 'training.employee.' || i || '@example.com',
                l_today - 400 - i * 17, 'ACTIVE')
        returning ID into l_employees(i);
    end loop;
    for i in 1..6 loop
        insert into DEMO_TRN_COURSES (
            CATEGORY_ID, COURSE_CODE, COURSE_NAME, DESCRIPTION, DURATION_HOURS, COURSE_FEE, STATUS)
        values (l_categories(mod(i - 1, 3) + 1), 'DEMO-P-' || to_char(i, 'FM000'),
                l_course_names(i), 'Fictional course with practical exercises and group discussion.',
                4, 50 + 25 * i, 'ACTIVE')
        returning ID into l_courses(i);
        if i <= 3 then
            l_start := l_today - (35 - 7 * i) + 9/24;
            l_session_status := 'COMPLETED';
            l_enrollment_status := 'COMPLETED';
        else
            l_start := l_today + 7 * (i - 3) + 9/24;
            l_session_status := 'SCHEDULED';
            l_enrollment_status := 'ENROLLED';
        end if;
        l_end := l_start + 4/24;
        insert into DEMO_TRN_SESSIONS (
            COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS)
        values (l_courses(i), l_instructors(mod(i - 1, 3) + 1), l_rooms(mod(i - 1, 3) + 1),
                'DEMO-P-' || to_char(i, 'FM000'), l_start, l_end, 12, l_session_status)
        returning ID into l_session_id;
        for j in 1..4 loop
            l_employee_index := mod((i - 1) * 4 + j - 1, 12) + 1;
            insert into DEMO_TRN_ENROLLMENTS (SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS)
            values (l_session_id, l_employees(l_employee_index), l_start - 14, l_enrollment_status)
            returning ID into l_enrollment_id;
            if i <= 3 then
                insert into DEMO_TRN_EVALUATIONS (ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT)
                values (l_enrollment_id, 3 + mod(j, 3),
                        'Useful examples and practical exercises to apply at work.', l_end + 1);
            end if;
        end loop;
    end loop;
    dbms_output.put_line('Presentation data: 12 employees, 6 courses, 6 sessions, 24 enrollments and 12 evaluations.');
    dbms_output.put_line('No certificates were inserted. After release 1.1, run 01_seed_certifications.sql if required.');
    commit;
exception
    when others then
        rollback to training_production_seed;
        raise;
end;
/
