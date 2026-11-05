-- Synthetic baseline data. All people and organizations are fictional.
-- Email addresses use example.com. Dates are relative to TRUNC(SYSDATE).
-- Requires all ten training tables to exist and be empty; no rows are deleted.
-- Fixed seed IDs do not advance the default sequences, which start at 1000.
-- One transaction: failures roll back this seed operation and are re-raised.
declare
    l_today date := trunc(sysdate);
    l_count number;
begin
    select count(*) into l_count from DEMO_TRN_DEPARTMENTS;
    if l_count <> 0 then
        raise_application_error(-20101, 'DEMO_TRN_DEPARTMENTS is not empty; no seed rows were inserted.');
    end if;
    select count(*) into l_count from DEMO_TRN_LOCATIONS;
    if l_count <> 0 then
        raise_application_error(-20101, 'DEMO_TRN_LOCATIONS is not empty; no seed rows were inserted.');
    end if;
    select count(*) into l_count from DEMO_TRN_ROOMS;
    if l_count <> 0 then
        raise_application_error(-20101, 'DEMO_TRN_ROOMS is not empty; no seed rows were inserted.');
    end if;
    select count(*) into l_count from DEMO_TRN_EMPLOYEES;
    if l_count <> 0 then
        raise_application_error(-20101, 'DEMO_TRN_EMPLOYEES is not empty; no seed rows were inserted.');
    end if;
    select count(*) into l_count from DEMO_TRN_CATEGORIES;
    if l_count <> 0 then
        raise_application_error(-20101, 'DEMO_TRN_CATEGORIES is not empty; no seed rows were inserted.');
    end if;
    select count(*) into l_count from DEMO_TRN_COURSES;
    if l_count <> 0 then
        raise_application_error(-20101, 'DEMO_TRN_COURSES is not empty; no seed rows were inserted.');
    end if;
    select count(*) into l_count from DEMO_TRN_INSTRUCTORS;
    if l_count <> 0 then
        raise_application_error(-20101, 'DEMO_TRN_INSTRUCTORS is not empty; no seed rows were inserted.');
    end if;
    select count(*) into l_count from DEMO_TRN_SESSIONS;
    if l_count <> 0 then
        raise_application_error(-20101, 'DEMO_TRN_SESSIONS is not empty; no seed rows were inserted.');
    end if;
    select count(*) into l_count from DEMO_TRN_ENROLLMENTS;
    if l_count <> 0 then
        raise_application_error(-20101, 'DEMO_TRN_ENROLLMENTS is not empty; no seed rows were inserted.');
    end if;
    select count(*) into l_count from DEMO_TRN_EVALUATIONS;
    if l_count <> 0 then
        raise_application_error(-20101, 'DEMO_TRN_EVALUATIONS is not empty; no seed rows were inserted.');
    end if;

    insert all
        into DEMO_TRN_DEPARTMENTS (ID, DEPARTMENT_NAME, COST_CENTER) values (1, 'People and Culture', 'CC-110')
        into DEMO_TRN_DEPARTMENTS (ID, DEPARTMENT_NAME, COST_CENTER) values (2, 'Engineering', 'CC-210')
        into DEMO_TRN_DEPARTMENTS (ID, DEPARTMENT_NAME, COST_CENTER) values (3, 'Customer Operations', 'CC-310')
        into DEMO_TRN_DEPARTMENTS (ID, DEPARTMENT_NAME, COST_CENTER) values (4, 'Sales and Partnerships', 'CC-410')
        into DEMO_TRN_DEPARTMENTS (ID, DEPARTMENT_NAME, COST_CENTER) values (5, 'Finance', 'CC-510')
        into DEMO_TRN_DEPARTMENTS (ID, DEPARTMENT_NAME, COST_CENTER) values (6, 'Business Operations', 'CC-610')
    select 1 from dual;

    insert all
        into DEMO_TRN_LOCATIONS (ID, LOCATION_NAME, CITY, COUNTRY) values (1, 'Madrid Learning Hub', 'Madrid', 'Spain')
        into DEMO_TRN_LOCATIONS (ID, LOCATION_NAME, CITY, COUNTRY) values (2, 'Dublin Collaboration Center', 'Dublin', 'Ireland')
        into DEMO_TRN_LOCATIONS (ID, LOCATION_NAME, CITY, COUNTRY) values (3, 'Berlin Studio', 'Berlin', 'Germany')
    select 1 from dual;

    insert all
        into DEMO_TRN_ROOMS (ID, LOCATION_ID, ROOM_NAME, CAPACITY) values (1, 1, 'Olive Room', 18)
        into DEMO_TRN_ROOMS (ID, LOCATION_ID, ROOM_NAME, CAPACITY) values (2, 1, 'Cedar Lab', 24)
        into DEMO_TRN_ROOMS (ID, LOCATION_ID, ROOM_NAME, CAPACITY) values (3, 2, 'Harbor Room', 20)
        into DEMO_TRN_ROOMS (ID, LOCATION_ID, ROOM_NAME, CAPACITY) values (4, 2, 'River Workshop', 16)
        into DEMO_TRN_ROOMS (ID, LOCATION_ID, ROOM_NAME, CAPACITY) values (5, 3, 'Linden Lab', 22)
    select 1 from dual;

    insert all
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (1, 1, 'EMP-0001', 'Elena', 'Varela', 'elena.varela@example.com', l_today - 623, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (2, 2, 'EMP-0002', 'Mateo', 'Serrano', 'mateo.serrano@example.com', l_today - 646, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (3, 3, 'EMP-0003', 'Sofia', 'Navarro', 'sofia.navarro@example.com', l_today - 669, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (4, 4, 'EMP-0004', 'Daniel', 'Costa', 'daniel.costa@example.com', l_today - 692, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (5, 5, 'EMP-0005', 'Clara', 'Romero', 'clara.romero@example.com', l_today - 715, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (6, 6, 'EMP-0006', 'Hugo', 'Marin', 'hugo.marin@example.com', l_today - 738, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (7, 1, 'EMP-0007', 'Aisha', 'Rahman', 'aisha.rahman@example.com', l_today - 761, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (8, 2, 'EMP-0008', 'Omar', 'Hassan', 'omar.hassan@example.com', l_today - 784, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (9, 3, 'EMP-0009', 'Priya', 'Shah', 'priya.shah@example.com', l_today - 807, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (10, 4, 'EMP-0010', 'Arjun', 'Mehta', 'arjun.mehta@example.com', l_today - 830, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (11, 5, 'EMP-0011', 'Mei', 'Lin', 'mei.lin@example.com', l_today - 853, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (12, 6, 'EMP-0012', 'Jun', 'Tanaka', 'jun.tanaka@example.com', l_today - 876, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (13, 1, 'EMP-0013', 'Lena', 'Fischer', 'lena.fischer@example.com', l_today - 899, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (14, 2, 'EMP-0014', 'Jonas', 'Weber', 'jonas.weber@example.com', l_today - 922, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (15, 3, 'EMP-0015', 'Freya', 'Larsen', 'freya.larsen@example.com', l_today - 945, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (16, 4, 'EMP-0016', 'Erik', 'Lind', 'erik.lind@example.com', l_today - 968, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (17, 5, 'EMP-0017', 'Amara', 'Okafor', 'amara.okafor@example.com', l_today - 991, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (18, 6, 'EMP-0018', 'Kofi', 'Mensah', 'kofi.mensah@example.com', l_today - 1014, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (19, 1, 'EMP-0019', 'Nia', 'Kamau', 'nia.kamau@example.com', l_today - 1037, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (20, 2, 'EMP-0020', 'Thabo', 'Dlamini', 'thabo.dlamini@example.com', l_today - 1060, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (21, 3, 'EMP-0021', 'Lucia', 'Moretti', 'lucia.moretti@example.com', l_today - 1083, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (22, 4, 'EMP-0022', 'Marco', 'Rossi', 'marco.rossi@example.com', l_today - 1106, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (23, 5, 'EMP-0023', 'Camila', 'Duarte', 'camila.duarte@example.com', l_today - 1129, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (24, 6, 'EMP-0024', 'Rafael', 'Almeida', 'rafael.almeida@example.com', l_today - 1152, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (25, 1, 'EMP-0025', 'Chloe', 'Martin', 'chloe.martin@example.com', l_today - 1175, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (26, 2, 'EMP-0026', 'Theo', 'Dubois', 'theo.dubois@example.com', l_today - 1198, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (27, 3, 'EMP-0027', 'Maya', 'Patel', 'maya.patel@example.com', l_today - 1221, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (28, 4, 'EMP-0028', 'Noah', 'Bennett', 'noah.bennett@example.com', l_today - 1244, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (29, 5, 'EMP-0029', 'Ines', 'Laurent', 'ines.laurent@example.com', l_today - 1267, 'ACTIVE')
        into DEMO_TRN_EMPLOYEES (ID, DEPARTMENT_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, STATUS) values (30, 6, 'EMP-0030', 'Liam', 'Walsh', 'liam.walsh@example.com', l_today - 1290, 'ACTIVE')
    select 1 from dual;

    insert all
        into DEMO_TRN_CATEGORIES (ID, CATEGORY_NAME, DESCRIPTION) values (1, 'Leadership', 'People management, collaboration, and effective communication.')
        into DEMO_TRN_CATEGORIES (ID, CATEGORY_NAME, DESCRIPTION) values (2, 'Digital Skills', 'Practical data and digital productivity skills.')
        into DEMO_TRN_CATEGORIES (ID, CATEGORY_NAME, DESCRIPTION) values (3, 'Security and Compliance', 'Everyday security awareness and responsible information handling.')
        into DEMO_TRN_CATEGORIES (ID, CATEGORY_NAME, DESCRIPTION) values (4, 'Customer Experience', 'Customer communication and service improvement.')
        into DEMO_TRN_CATEGORIES (ID, CATEGORY_NAME, DESCRIPTION) values (5, 'Workplace Wellbeing', 'Inclusive, sustainable, and healthy working practices.')
    select 1 from dual;

    insert all
        into DEMO_TRN_COURSES (ID, CATEGORY_ID, COURSE_CODE, COURSE_NAME, DESCRIPTION, DURATION_HOURS, COURSE_FEE, STATUS) values (1, 1, 'LDR-101', 'Coaching Conversations', 'Practice feedback and supportive coaching conversations.', 6, 180, 'ACTIVE')
        into DEMO_TRN_COURSES (ID, CATEGORY_ID, COURSE_CODE, COURSE_NAME, DESCRIPTION, DURATION_HOURS, COURSE_FEE, STATUS) values (2, 1, 'LDR-102', 'Leading Collaborative Teams', 'Plan inclusive team decisions and productive meetings.', 8, 240, 'ACTIVE')
        into DEMO_TRN_COURSES (ID, CATEGORY_ID, COURSE_CODE, COURSE_NAME, DESCRIPTION, DURATION_HOURS, COURSE_FEE, STATUS) values (3, 2, 'DIG-101', 'Data Literacy for Everyone', 'Read business metrics and ask better questions about data.', 6, 150, 'ACTIVE')
        into DEMO_TRN_COURSES (ID, CATEGORY_ID, COURSE_CODE, COURSE_NAME, DESCRIPTION, DURATION_HOURS, COURSE_FEE, STATUS) values (4, 2, 'DIG-102', 'Practical Spreadsheet Skills', 'Build clear worksheets and reliable business calculations.', 8, 190, 'ACTIVE')
        into DEMO_TRN_COURSES (ID, CATEGORY_ID, COURSE_CODE, COURSE_NAME, DESCRIPTION, DURATION_HOURS, COURSE_FEE, STATUS) values (5, 3, 'SEC-101', 'Everyday Cybersecurity', 'Recognize phishing and protect company information.', 4, 90, 'ACTIVE')
        into DEMO_TRN_COURSES (ID, CATEGORY_ID, COURSE_CODE, COURSE_NAME, DESCRIPTION, DURATION_HOURS, COURSE_FEE, STATUS) values (6, 3, 'SEC-102', 'Responsible Data Handling', 'Apply practical privacy and information-sharing principles.', 4, 95, 'ACTIVE')
        into DEMO_TRN_COURSES (ID, CATEGORY_ID, COURSE_CODE, COURSE_NAME, DESCRIPTION, DURATION_HOURS, COURSE_FEE, STATUS) values (7, 4, 'CEX-101', 'Customer Discovery Skills', 'Explore customer needs through structured conversations.', 6, 160, 'ACTIVE')
        into DEMO_TRN_COURSES (ID, CATEGORY_ID, COURSE_CODE, COURSE_NAME, DESCRIPTION, DURATION_HOURS, COURSE_FEE, STATUS) values (8, 4, 'CEX-102', 'Resolving Difficult Conversations', 'Respond constructively to challenging service situations.', 6, 170, 'ACTIVE')
        into DEMO_TRN_COURSES (ID, CATEGORY_ID, COURSE_CODE, COURSE_NAME, DESCRIPTION, DURATION_HOURS, COURSE_FEE, STATUS) values (9, 5, 'WEL-101', 'Sustainable Work Habits', 'Build focused work patterns and realistic commitments.', 4, 80, 'ACTIVE')
        into DEMO_TRN_COURSES (ID, CATEGORY_ID, COURSE_CODE, COURSE_NAME, DESCRIPTION, DURATION_HOURS, COURSE_FEE, STATUS) values (10, 5, 'WEL-102', 'Inclusive Workplace Practices', 'Recognize barriers and improve everyday collaboration.', 4, 85, 'ACTIVE')
    select 1 from dual;

    insert all
        into DEMO_TRN_INSTRUCTORS (ID, FIRST_NAME, LAST_NAME, EMAIL, SPECIALTY, ACTIVE_FLAG) values (1, 'Mira', 'Solberg', 'mira.solberg@example.com', 'Leadership and coaching', 'Y')
        into DEMO_TRN_INSTRUCTORS (ID, FIRST_NAME, LAST_NAME, EMAIL, SPECIALTY, ACTIVE_FLAG) values (2, 'Gabriel', 'Santos', 'gabriel.santos@example.com', 'Data and digital skills', 'Y')
        into DEMO_TRN_INSTRUCTORS (ID, FIRST_NAME, LAST_NAME, EMAIL, SPECIALTY, ACTIVE_FLAG) values (3, 'Leila', 'Nasser', 'leila.nasser@example.com', 'Security and responsible data', 'Y')
        into DEMO_TRN_INSTRUCTORS (ID, FIRST_NAME, LAST_NAME, EMAIL, SPECIALTY, ACTIVE_FLAG) values (4, 'Tomas', 'Novak', 'tomas.novak@example.com', 'Customer experience', 'Y')
        into DEMO_TRN_INSTRUCTORS (ID, FIRST_NAME, LAST_NAME, EMAIL, SPECIALTY, ACTIVE_FLAG) values (5, 'Zara', 'Adeyemi', 'zara.adeyemi@example.com', 'Inclusion and wellbeing', 'Y')
        into DEMO_TRN_INSTRUCTORS (ID, FIRST_NAME, LAST_NAME, EMAIL, SPECIALTY, ACTIVE_FLAG) values (6, 'Eva', 'Keller', 'eva.keller@example.com', 'Collaboration and workplace learning', 'Y')
    select 1 from dual;

    insert all
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (1, 1, 1, 1, 'TRN-001', l_today + (-70) + 9/24, l_today + (-70) + 15/24, 12, 'COMPLETED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (2, 2, 2, 2, 'TRN-002', l_today + (-60) + 9/24, l_today + (-60) + 17/24, 12, 'COMPLETED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (3, 3, 3, 3, 'TRN-003', l_today + (-50) + 9/24, l_today + (-50) + 15/24, 12, 'COMPLETED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (4, 4, 4, 4, 'TRN-004', l_today + (-40) + 9/24, l_today + (-40) + 17/24, 12, 'COMPLETED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (5, 5, 5, 5, 'TRN-005', l_today + (-30) + 9/24, l_today + (-30) + 13/24, 12, 'COMPLETED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (6, 6, 6, 1, 'TRN-006', l_today + (-20) + 9/24, l_today + (-20) + 13/24, 12, 'COMPLETED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (7, 7, 1, 2, 'TRN-007', l_today + (-10) + 9/24, l_today + (-10) + 15/24, 12, 'COMPLETED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (8, 8, 2, 3, 'TRN-008', l_today + (-5) + 9/24, l_today + (-5) + 15/24, 12, 'COMPLETED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (9, 9, 3, 4, 'TRN-009', l_today + (5) + 9/24, l_today + (5) + 13/24, 12, 'SCHEDULED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (10, 10, 4, 5, 'TRN-010', l_today + (10) + 9/24, l_today + (10) + 13/24, 12, 'SCHEDULED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (11, 1, 5, 1, 'TRN-011', l_today + (15) + 9/24, l_today + (15) + 15/24, 12, 'SCHEDULED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (12, 2, 6, 2, 'TRN-012', l_today + (20) + 9/24, l_today + (20) + 17/24, 12, 'SCHEDULED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (13, 3, 1, 3, 'TRN-013', l_today + (25) + 9/24, l_today + (25) + 15/24, 12, 'SCHEDULED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (14, 4, 2, 4, 'TRN-014', l_today + (30) + 9/24, l_today + (30) + 17/24, 12, 'SCHEDULED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (15, 5, 3, 5, 'TRN-015', l_today + (-15) + 9/24, l_today + (-15) + 13/24, 12, 'CANCELLED')
        into DEMO_TRN_SESSIONS (ID, COURSE_ID, INSTRUCTOR_ID, ROOM_ID, SESSION_CODE, START_DATE, END_DATE, CAPACITY, STATUS) values (16, 6, 4, 1, 'TRN-016', l_today + (12) + 9/24, l_today + (12) + 13/24, 12, 'CANCELLED')
    select 1 from dual;

    insert all
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (1, 1, 1, l_today + (-84) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (2, 1, 4, l_today + (-84) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (3, 1, 7, l_today + (-84) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (4, 1, 10, l_today + (-84) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (5, 1, 13, l_today + (-84) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (6, 2, 8, l_today + (-74) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (7, 2, 11, l_today + (-74) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (8, 2, 14, l_today + (-74) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (9, 2, 17, l_today + (-74) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (10, 2, 20, l_today + (-74) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (11, 3, 15, l_today + (-64) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (12, 3, 18, l_today + (-64) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (13, 3, 21, l_today + (-64) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (14, 3, 24, l_today + (-64) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (15, 3, 27, l_today + (-64) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (16, 4, 22, l_today + (-54) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (17, 4, 25, l_today + (-54) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (18, 4, 28, l_today + (-54) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (19, 4, 1, l_today + (-54) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (20, 4, 4, l_today + (-54) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (21, 5, 29, l_today + (-44) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (22, 5, 2, l_today + (-44) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (23, 5, 5, l_today + (-44) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (24, 5, 8, l_today + (-44) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (25, 5, 11, l_today + (-44) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (26, 6, 6, l_today + (-34) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (27, 6, 9, l_today + (-34) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (28, 6, 12, l_today + (-34) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (29, 6, 15, l_today + (-34) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (30, 6, 18, l_today + (-34) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (31, 7, 13, l_today + (-24) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (32, 7, 16, l_today + (-24) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (33, 7, 19, l_today + (-24) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (34, 7, 22, l_today + (-24) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (35, 7, 25, l_today + (-24) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (36, 8, 20, l_today + (-19) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (37, 8, 23, l_today + (-19) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (38, 8, 26, l_today + (-19) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (39, 8, 29, l_today + (-19) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (40, 8, 2, l_today + (-19) + 10/24, 'COMPLETED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (41, 9, 27, l_today + (-9) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (42, 9, 30, l_today + (-9) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (43, 9, 3, l_today + (-9) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (44, 9, 6, l_today + (-9) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (45, 9, 9, l_today + (-9) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (46, 10, 4, l_today + (-4) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (47, 10, 7, l_today + (-4) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (48, 10, 10, l_today + (-4) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (49, 10, 13, l_today + (-4) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (50, 10, 16, l_today + (-4) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (51, 11, 11, l_today + (1) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (52, 11, 14, l_today + (1) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (53, 11, 17, l_today + (1) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (54, 11, 20, l_today + (1) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (55, 11, 23, l_today + (1) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (56, 12, 18, l_today + (6) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (57, 12, 21, l_today + (6) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (58, 12, 24, l_today + (6) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (59, 12, 27, l_today + (6) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (60, 12, 30, l_today + (6) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (61, 13, 25, l_today + (11) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (62, 13, 28, l_today + (11) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (63, 13, 1, l_today + (11) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (64, 13, 4, l_today + (11) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (65, 13, 7, l_today + (11) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (66, 14, 2, l_today + (16) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (67, 14, 5, l_today + (16) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (68, 14, 8, l_today + (16) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (69, 14, 11, l_today + (16) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (70, 14, 14, l_today + (16) + 10/24, 'ENROLLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (71, 15, 9, l_today + (-29) + 10/24, 'CANCELLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (72, 15, 12, l_today + (-29) + 10/24, 'CANCELLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (73, 15, 15, l_today + (-29) + 10/24, 'CANCELLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (74, 15, 18, l_today + (-29) + 10/24, 'CANCELLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (75, 15, 21, l_today + (-29) + 10/24, 'CANCELLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (76, 16, 16, l_today + (-2) + 10/24, 'CANCELLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (77, 16, 19, l_today + (-2) + 10/24, 'CANCELLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (78, 16, 22, l_today + (-2) + 10/24, 'CANCELLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (79, 16, 25, l_today + (-2) + 10/24, 'CANCELLED')
        into DEMO_TRN_ENROLLMENTS (ID, SESSION_ID, EMPLOYEE_ID, ENROLLED_AT, STATUS) values (80, 16, 28, l_today + (-2) + 10/24, 'CANCELLED')
    select 1 from dual;

    insert all
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (1, 1, 4, 'Useful examples and a clear plan to apply the learning.', l_today + (-69) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (2, 2, 5, 'The practical exercises helped connect the topic to my role.', l_today + (-69) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (3, 3, 3, 'A helpful introduction with time for questions.', l_today + (-69) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (4, 4, 4, 'Clear explanations and constructive group discussion.', l_today + (-69) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (5, 5, 5, 'Good materials; I would welcome a follow-up workshop.', l_today + (-69) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (6, 6, 3, 'Useful examples and a clear plan to apply the learning.', l_today + (-59) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (7, 7, 4, 'The practical exercises helped connect the topic to my role.', l_today + (-59) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (8, 8, 5, 'A helpful introduction with time for questions.', l_today + (-59) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (9, 9, 3, 'Clear explanations and constructive group discussion.', l_today + (-59) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (10, 10, 4, 'Good materials; I would welcome a follow-up workshop.', l_today + (-59) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (11, 11, 5, 'Useful examples and a clear plan to apply the learning.', l_today + (-49) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (12, 12, 3, 'The practical exercises helped connect the topic to my role.', l_today + (-49) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (13, 13, 4, 'A helpful introduction with time for questions.', l_today + (-49) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (14, 14, 5, 'Clear explanations and constructive group discussion.', l_today + (-49) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (15, 15, 3, 'Good materials; I would welcome a follow-up workshop.', l_today + (-49) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (16, 16, 4, 'Useful examples and a clear plan to apply the learning.', l_today + (-39) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (17, 17, 5, 'The practical exercises helped connect the topic to my role.', l_today + (-39) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (18, 18, 3, 'A helpful introduction with time for questions.', l_today + (-39) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (19, 19, 4, 'Clear explanations and constructive group discussion.', l_today + (-39) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (20, 20, 5, 'Good materials; I would welcome a follow-up workshop.', l_today + (-39) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (21, 21, 3, 'Useful examples and a clear plan to apply the learning.', l_today + (-29) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (22, 22, 4, 'The practical exercises helped connect the topic to my role.', l_today + (-29) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (23, 23, 5, 'A helpful introduction with time for questions.', l_today + (-29) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (24, 24, 3, 'Clear explanations and constructive group discussion.', l_today + (-29) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (25, 25, 4, 'Good materials; I would welcome a follow-up workshop.', l_today + (-29) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (26, 26, 5, 'Useful examples and a clear plan to apply the learning.', l_today + (-19) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (27, 27, 3, 'The practical exercises helped connect the topic to my role.', l_today + (-19) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (28, 28, 4, 'A helpful introduction with time for questions.', l_today + (-19) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (29, 29, 5, 'Clear explanations and constructive group discussion.', l_today + (-19) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (30, 30, 3, 'Good materials; I would welcome a follow-up workshop.', l_today + (-19) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (31, 31, 4, 'Useful examples and a clear plan to apply the learning.', l_today + (-9) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (32, 32, 5, 'The practical exercises helped connect the topic to my role.', l_today + (-9) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (33, 33, 3, 'A helpful introduction with time for questions.', l_today + (-9) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (34, 34, 4, 'Clear explanations and constructive group discussion.', l_today + (-9) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (35, 35, 5, 'Good materials; I would welcome a follow-up workshop.', l_today + (-9) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (36, 36, 3, 'Useful examples and a clear plan to apply the learning.', l_today + (-4) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (37, 37, 4, 'The practical exercises helped connect the topic to my role.', l_today + (-4) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (38, 38, 5, 'A helpful introduction with time for questions.', l_today + (-4) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (39, 39, 3, 'Clear explanations and constructive group discussion.', l_today + (-4) + 12/24)
        into DEMO_TRN_EVALUATIONS (ID, ENROLLMENT_ID, SCORE, COMMENTS, SUBMITTED_AT) values (40, 40, 4, 'Good materials; I would welcome a follow-up workshop.', l_today + (-4) + 12/24)
    select 1 from dual;

    commit;
exception
    when others then
        rollback;
        raise;
end;
/
