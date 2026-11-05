-- Baseline 1.0 employee training model. Review CURRENT_SCHEMA before running.
-- No tables are replaced, dropped, or truncated. Oracle DDL commits implicitly.
-- All generated model objects use the DEMO_TRN_ prefix; sequences start at 1000
-- so the fixed seed identifiers remain separate from later application inserts.
declare
    l_count number;
    l_schema varchar2(128) := sys_context('USERENV', 'CURRENT_SCHEMA');
begin
    select count(*) into l_count from all_objects
     where owner = l_schema and object_name like 'DEMO\_TRN\_%' escape '\';
    if l_count > 0 then
        raise_application_error(-20100, 'Training objects already exist in CURRENT_SCHEMA; no model objects were created.');
    end if;

    execute immediate q'~create sequence DEMO_TRN_DEPARTMENTS_SEQ start with 1000 increment by 1 cache 20 nocycle~';

    execute immediate q'~create table DEMO_TRN_DEPARTMENTS (
    ID NUMBER default DEMO_TRN_DEPARTMENTS_SEQ.NEXTVAL,
    DEPARTMENT_NAME VARCHAR2(100) constraint DEMO_TRN_DEPARTMENTS_DEPARTMENT_NAME_NN not null,
    COST_CENTER VARCHAR2(20) constraint DEMO_TRN_DEPARTMENTS_COST_CENTER_NN not null,
    constraint DEMO_TRN_DEPARTMENTS_PK primary key (ID),
    constraint DEMO_TRN_DEPARTMENTS_UQ1 unique (DEPARTMENT_NAME),
    constraint DEMO_TRN_DEPARTMENTS_UQ2 unique (COST_CENTER)
)~';

    execute immediate q'~create sequence DEMO_TRN_LOCATIONS_SEQ start with 1000 increment by 1 cache 20 nocycle~';

    execute immediate q'~create table DEMO_TRN_LOCATIONS (
    ID NUMBER default DEMO_TRN_LOCATIONS_SEQ.NEXTVAL,
    LOCATION_NAME VARCHAR2(100) constraint DEMO_TRN_LOCATIONS_LOCATION_NAME_NN not null,
    CITY VARCHAR2(100) constraint DEMO_TRN_LOCATIONS_CITY_NN not null,
    COUNTRY VARCHAR2(100) constraint DEMO_TRN_LOCATIONS_COUNTRY_NN not null,
    constraint DEMO_TRN_LOCATIONS_PK primary key (ID),
    constraint DEMO_TRN_LOCATIONS_UQ1 unique (LOCATION_NAME)
)~';

    execute immediate q'~create sequence DEMO_TRN_ROOMS_SEQ start with 1000 increment by 1 cache 20 nocycle~';

    execute immediate q'~create table DEMO_TRN_ROOMS (
    ID NUMBER default DEMO_TRN_ROOMS_SEQ.NEXTVAL,
    LOCATION_ID NUMBER constraint DEMO_TRN_ROOMS_LOCATION_ID_NN not null,
    ROOM_NAME VARCHAR2(100) constraint DEMO_TRN_ROOMS_ROOM_NAME_NN not null,
    CAPACITY NUMBER(4) constraint DEMO_TRN_ROOMS_CAPACITY_NN not null,
    constraint DEMO_TRN_ROOMS_PK primary key (ID),
    constraint DEMO_TRN_ROOMS_UQ1 unique (LOCATION_ID, ROOM_NAME),
    constraint DEMO_TRN_ROOMS_CAPACITY_CK check (CAPACITY BETWEEN 1 AND 500),
    constraint DEMO_TRN_ROOMS_FK1 foreign key (LOCATION_ID) references DEMO_TRN_LOCATIONS (ID)
)~';

    execute immediate q'~create sequence DEMO_TRN_EMPLOYEES_SEQ start with 1000 increment by 1 cache 20 nocycle~';

    execute immediate q'~create table DEMO_TRN_EMPLOYEES (
    ID NUMBER default DEMO_TRN_EMPLOYEES_SEQ.NEXTVAL,
    DEPARTMENT_ID NUMBER constraint DEMO_TRN_EMPLOYEES_DEPARTMENT_ID_NN not null,
    EMPLOYEE_NUMBER VARCHAR2(20) constraint DEMO_TRN_EMPLOYEES_EMPLOYEE_NUMBER_NN not null,
    FIRST_NAME VARCHAR2(100) constraint DEMO_TRN_EMPLOYEES_FIRST_NAME_NN not null,
    LAST_NAME VARCHAR2(100) constraint DEMO_TRN_EMPLOYEES_LAST_NAME_NN not null,
    EMAIL VARCHAR2(255) constraint DEMO_TRN_EMPLOYEES_EMAIL_NN not null,
    HIRE_DATE DATE constraint DEMO_TRN_EMPLOYEES_HIRE_DATE_NN not null,
    STATUS VARCHAR2(20) default 'ACTIVE' constraint DEMO_TRN_EMPLOYEES_STATUS_NN not null,
    constraint DEMO_TRN_EMPLOYEES_PK primary key (ID),
    constraint DEMO_TRN_EMPLOYEES_UQ1 unique (EMPLOYEE_NUMBER),
    constraint DEMO_TRN_EMPLOYEES_UQ2 unique (EMAIL),
    constraint DEMO_TRN_EMPLOYEES_STATUS_CK check (STATUS IN ('ACTIVE','INACTIVE')),
    constraint DEMO_TRN_EMPLOYEES_FK1 foreign key (DEPARTMENT_ID) references DEMO_TRN_DEPARTMENTS (ID)
)~';

    execute immediate q'~create index DEMO_TRN_EMPLOYEES_FK1_IX on DEMO_TRN_EMPLOYEES (DEPARTMENT_ID)~';

    execute immediate q'~create sequence DEMO_TRN_CATEGORIES_SEQ start with 1000 increment by 1 cache 20 nocycle~';

    execute immediate q'~create table DEMO_TRN_CATEGORIES (
    ID NUMBER default DEMO_TRN_CATEGORIES_SEQ.NEXTVAL,
    CATEGORY_NAME VARCHAR2(100) constraint DEMO_TRN_CATEGORIES_CATEGORY_NAME_NN not null,
    DESCRIPTION VARCHAR2(500),
    constraint DEMO_TRN_CATEGORIES_PK primary key (ID),
    constraint DEMO_TRN_CATEGORIES_UQ1 unique (CATEGORY_NAME)
)~';

    execute immediate q'~create sequence DEMO_TRN_COURSES_SEQ start with 1000 increment by 1 cache 20 nocycle~';

    execute immediate q'~create table DEMO_TRN_COURSES (
    ID NUMBER default DEMO_TRN_COURSES_SEQ.NEXTVAL,
    CATEGORY_ID NUMBER constraint DEMO_TRN_COURSES_CATEGORY_ID_NN not null,
    COURSE_CODE VARCHAR2(20) constraint DEMO_TRN_COURSES_COURSE_CODE_NN not null,
    COURSE_NAME VARCHAR2(200) constraint DEMO_TRN_COURSES_COURSE_NAME_NN not null,
    DESCRIPTION VARCHAR2(1000),
    DURATION_HOURS NUMBER(4,1) constraint DEMO_TRN_COURSES_DURATION_HOURS_NN not null,
    COURSE_FEE NUMBER(10,2) default 0 constraint DEMO_TRN_COURSES_COURSE_FEE_NN not null,
    STATUS VARCHAR2(20) default 'ACTIVE' constraint DEMO_TRN_COURSES_STATUS_NN not null,
    constraint DEMO_TRN_COURSES_PK primary key (ID),
    constraint DEMO_TRN_COURSES_UQ1 unique (COURSE_CODE),
    constraint DEMO_TRN_COURSES_DURATION_CK check (DURATION_HOURS > 0 AND DURATION_HOURS <= 80),
    constraint DEMO_TRN_COURSES_FEE_CK check (COURSE_FEE >= 0),
    constraint DEMO_TRN_COURSES_STATUS_CK check (STATUS IN ('ACTIVE','RETIRED')),
    constraint DEMO_TRN_COURSES_FK1 foreign key (CATEGORY_ID) references DEMO_TRN_CATEGORIES (ID)
)~';

    execute immediate q'~create index DEMO_TRN_COURSES_FK1_IX on DEMO_TRN_COURSES (CATEGORY_ID)~';

    execute immediate q'~create sequence DEMO_TRN_INSTRUCTORS_SEQ start with 1000 increment by 1 cache 20 nocycle~';

    execute immediate q'~create table DEMO_TRN_INSTRUCTORS (
    ID NUMBER default DEMO_TRN_INSTRUCTORS_SEQ.NEXTVAL,
    FIRST_NAME VARCHAR2(100) constraint DEMO_TRN_INSTRUCTORS_FIRST_NAME_NN not null,
    LAST_NAME VARCHAR2(100) constraint DEMO_TRN_INSTRUCTORS_LAST_NAME_NN not null,
    EMAIL VARCHAR2(255) constraint DEMO_TRN_INSTRUCTORS_EMAIL_NN not null,
    SPECIALTY VARCHAR2(200),
    ACTIVE_FLAG VARCHAR2(1) default 'Y' constraint DEMO_TRN_INSTRUCTORS_ACTIVE_FLAG_NN not null,
    constraint DEMO_TRN_INSTRUCTORS_PK primary key (ID),
    constraint DEMO_TRN_INSTRUCTORS_UQ1 unique (EMAIL),
    constraint DEMO_TRN_INSTRUCTORS_ACTIVE_CK check (ACTIVE_FLAG IN ('Y','N'))
)~';

    execute immediate q'~create sequence DEMO_TRN_SESSIONS_SEQ start with 1000 increment by 1 cache 20 nocycle~';

    execute immediate q'~create table DEMO_TRN_SESSIONS (
    ID NUMBER default DEMO_TRN_SESSIONS_SEQ.NEXTVAL,
    COURSE_ID NUMBER constraint DEMO_TRN_SESSIONS_COURSE_ID_NN not null,
    INSTRUCTOR_ID NUMBER constraint DEMO_TRN_SESSIONS_INSTRUCTOR_ID_NN not null,
    ROOM_ID NUMBER constraint DEMO_TRN_SESSIONS_ROOM_ID_NN not null,
    SESSION_CODE VARCHAR2(30) constraint DEMO_TRN_SESSIONS_SESSION_CODE_NN not null,
    START_DATE DATE constraint DEMO_TRN_SESSIONS_START_DATE_NN not null,
    END_DATE DATE constraint DEMO_TRN_SESSIONS_END_DATE_NN not null,
    CAPACITY NUMBER(4) constraint DEMO_TRN_SESSIONS_CAPACITY_NN not null,
    STATUS VARCHAR2(20) default 'SCHEDULED' constraint DEMO_TRN_SESSIONS_STATUS_NN not null,
    constraint DEMO_TRN_SESSIONS_PK primary key (ID),
    constraint DEMO_TRN_SESSIONS_UQ1 unique (SESSION_CODE),
    constraint DEMO_TRN_SESSIONS_DATES_CK check (END_DATE > START_DATE),
    constraint DEMO_TRN_SESSIONS_CAPACITY_CK check (CAPACITY BETWEEN 1 AND 500),
    constraint DEMO_TRN_SESSIONS_STATUS_CK check (STATUS IN ('SCHEDULED','COMPLETED','CANCELLED')),
    constraint DEMO_TRN_SESSIONS_FK1 foreign key (COURSE_ID) references DEMO_TRN_COURSES (ID),
    constraint DEMO_TRN_SESSIONS_FK2 foreign key (INSTRUCTOR_ID) references DEMO_TRN_INSTRUCTORS (ID),
    constraint DEMO_TRN_SESSIONS_FK3 foreign key (ROOM_ID) references DEMO_TRN_ROOMS (ID)
)~';

    execute immediate q'~create index DEMO_TRN_SESSIONS_FK1_IX on DEMO_TRN_SESSIONS (COURSE_ID)~';

    execute immediate q'~create index DEMO_TRN_SESSIONS_FK2_IX on DEMO_TRN_SESSIONS (INSTRUCTOR_ID)~';

    execute immediate q'~create index DEMO_TRN_SESSIONS_FK3_IX on DEMO_TRN_SESSIONS (ROOM_ID)~';

    execute immediate q'~create sequence DEMO_TRN_ENROLLMENTS_SEQ start with 1000 increment by 1 cache 20 nocycle~';

    execute immediate q'~create table DEMO_TRN_ENROLLMENTS (
    ID NUMBER default DEMO_TRN_ENROLLMENTS_SEQ.NEXTVAL,
    SESSION_ID NUMBER constraint DEMO_TRN_ENROLLMENTS_SESSION_ID_NN not null,
    EMPLOYEE_ID NUMBER constraint DEMO_TRN_ENROLLMENTS_EMPLOYEE_ID_NN not null,
    ENROLLED_AT DATE default SYSDATE constraint DEMO_TRN_ENROLLMENTS_ENROLLED_AT_NN not null,
    STATUS VARCHAR2(20) default 'ENROLLED' constraint DEMO_TRN_ENROLLMENTS_STATUS_NN not null,
    constraint DEMO_TRN_ENROLLMENTS_PK primary key (ID),
    constraint DEMO_TRN_ENROLLMENTS_UQ1 unique (SESSION_ID, EMPLOYEE_ID),
    constraint DEMO_TRN_ENROLLMENTS_STATUS_CK check (STATUS IN ('ENROLLED','COMPLETED','CANCELLED')),
    constraint DEMO_TRN_ENROLLMENTS_FK1 foreign key (SESSION_ID) references DEMO_TRN_SESSIONS (ID),
    constraint DEMO_TRN_ENROLLMENTS_FK2 foreign key (EMPLOYEE_ID) references DEMO_TRN_EMPLOYEES (ID)
)~';

    execute immediate q'~create index DEMO_TRN_ENROLLMENTS_FK2_IX on DEMO_TRN_ENROLLMENTS (EMPLOYEE_ID)~';

    execute immediate q'~create sequence DEMO_TRN_EVALUATIONS_SEQ start with 1000 increment by 1 cache 20 nocycle~';

    execute immediate q'~create table DEMO_TRN_EVALUATIONS (
    ID NUMBER default DEMO_TRN_EVALUATIONS_SEQ.NEXTVAL,
    ENROLLMENT_ID NUMBER constraint DEMO_TRN_EVALUATIONS_ENROLLMENT_ID_NN not null,
    SCORE NUMBER(1) constraint DEMO_TRN_EVALUATIONS_SCORE_NN not null,
    COMMENTS VARCHAR2(1000),
    SUBMITTED_AT DATE default SYSDATE constraint DEMO_TRN_EVALUATIONS_SUBMITTED_AT_NN not null,
    constraint DEMO_TRN_EVALUATIONS_PK primary key (ID),
    constraint DEMO_TRN_EVALUATIONS_UQ1 unique (ENROLLMENT_ID),
    constraint DEMO_TRN_EVALUATIONS_SCORE_CK check (SCORE BETWEEN 1 AND 5),
    constraint DEMO_TRN_EVALUATIONS_FK1 foreign key (ENROLLMENT_ID) references DEMO_TRN_ENROLLMENTS (ID)
)~';
end;
/
