# Employee Training baseline model

This fictional HR learning model is the baseline domain for the CI/CD demonstration. It manages a course catalog, employee registrations, scheduled teaching, and feedback. Baseline version 1.0 contains ten tables with the `DEMO_TRN_` prefix. Setup refuses existing objects with that prefix; use a dedicated development schema or review your schema inventory first.

Run the model setup once in your configured development schema/workspace after completing the prerequisites in [INITIAL_SETUP.md](INITIAL_SETUP.md). These setup files do not perform a production migration or clean up existing objects.

## Files and execution order

1. `scripts/training/01_create_model.sql`: create the empty model.
2. `scripts/training/02_seed_data.sql`: load the deterministic synthetic training data.
3. `scripts/training/03_verify.sql`: check exact baseline counts, integrity, object state, and reserved future scope.
4. `scripts/training/model.json`: authoritative machine-readable model for baseline APEX generation.

The scripts contain ordinary Oracle SQL/PLSQL and can run through SQLcl or APEX SQL Workshop SQL Scripts. Confirm the intended development schema first. Creation refuses any existing object with the training prefix before starting; it does not drop or replace anything. Oracle DDL commits implicitly, so a later DDL failure can leave earlier objects created. Inspect that state instead of rerunning or deleting objects automatically.

Seeding requires all ten tables to exist and be empty. It uses fixed IDs, inserts in dependency order, and commits only after all inserts succeed. An error rolls back the seed transaction and is re-raised. It never deletes existing rows. Use a dedicated session without unrelated uncommitted work.

Verification is read-only and expects the exact seeded baseline. Run it before adding application rows or demonstrating later schema changes; those actions can legitimately change its expected counts.

## Data model

| Table | Purpose | Seed rows |
| --- | --- | ---: |
| `DEMO_TRN_DEPARTMENTS` | Employee departments and cost centers | 6 |
| `DEMO_TRN_EMPLOYEES` | Fictional employees and their department | 30 |
| `DEMO_TRN_LOCATIONS` | Training centers in Madrid, Dublin, and Berlin | 3 |
| `DEMO_TRN_ROOMS` | Rooms and physical seating capacity | 5 |
| `DEMO_TRN_CATEGORIES` | Learning subject categories | 5 |
| `DEMO_TRN_COURSES` | Course catalog, duration, and EUR course fee | 10 |
| `DEMO_TRN_INSTRUCTORS` | Fictional instructors and teaching specialties | 6 |
| `DEMO_TRN_SESSIONS` | Course deliveries with instructor, room, and dates | 16 |
| `DEMO_TRN_ENROLLMENTS` | Employee registrations for sessions | 80 |
| `DEMO_TRN_EVALUATIONS` | Participant scores and comments after completion | 40 |

Relationships:

- Employees belong to departments; rooms belong to locations; courses belong to categories.
- Each session refers to one course, instructor, and room.
- Enrollments connect employees to sessions, with a unique employee/session pair.
- Each evaluation refers to one completed enrollment and is unique for that enrollment.

Every table has an `ID NUMBER` primary key with a default from its explicitly named `DEMO_TRN_<TABLE>_SEQ.NEXTVAL`. Sequences start at 1000; fixed seed IDs remain below that range, and later APEX inserts can omit ID. There are no identity-generated SYS sequences or database triggers.

All primary, unique, foreign-key, check, and explicit NOT NULL constraints have names beginning `DEMO_TRN_`. Indexes also use that prefix. Foreign keys use existing leading-column unique indexes where possible; six extra indexes support the remaining foreign keys. The model has approximately 48 exportable database objects: ten tables, ten sequences, ten primary-key indexes, twelve unique indexes, and six additional indexes. Constraints travel with their associated structures.

Check constraints enforce positive durations/capacities, nonnegative fees, scores from one through five, valid statuses, and end dates later than start dates. Cross-table business rules such as a session not exceeding room capacity and feedback following completion are verified by `03_verify.sql`; they are not implemented as triggers.

## Synthetic dataset

All names are fictional, and every email uses `example.com`. English course titles cover leadership, digital skills, security, customer experience, and workplace wellbeing. Fees are illustrative EUR amounts.

Dates are relative to `TRUNC(SYSDATE)` at seed execution. Eight sessions are completed, six scheduled, and two cancelled. Each has five registrations. Completed sessions produce 40 completed registrations and 40 evaluations; scheduled sessions produce 30 enrolled registrations; cancelled sessions produce ten cancelled registrations. Every employee appears in the deterministic enrollment distribution. Evaluation scores range from three to five within the permitted one-to-five range.

The same seed script reproduces the IDs, names, and relationships on a fresh empty model, while anchoring dates to that run's day. It is not a reset script and must not be used to overwrite an occupied model.

## Baseline APEX scope

The supplied baseline application has an overview and reports for employees, courses, sessions, enrollments, and evaluations, with forms for employees, courses, and enrollments. Install the fixed initial SQL snapshot as described in INITIAL_SETUP.md; editable APEXlang sources are also supplied. Supporting tables provide display values for department, category, room, instructor, and session choices.

The JSON includes table/column descriptions, Oracle types, nullability/defaults, primary keys, unique columns, check expressions, and foreign-key target columns. These definitions are authoritative; do not infer column names from labels. Use lookup labels rather than numeric IDs in reports/forms where appropriate.

The seeded rows exist to make the development baseline useful to teach and inspect. The CI/CD release workflow does not transfer these rows. Optional target presentation helpers generate separate synthetic data only after final structures-only validation; see OPTIONAL_DEMO_DATA.md.

## Reserved manual version 1.1 changes

Do not create these in baseline 1.0:

- `DEMO_TRN_CERTIFICATIONS`: a future table for the manual extension exercise.
- `DEMO_TRN_COURSES.CERTIFICATION_REQUIRED`: a future course column.
- A certification application page: a future manual APEX UI step.

Their detailed schema, scripts, and page IDs belong to the later release exercise. The baseline verification explicitly checks that the future table/object and course column are absent. No certification table, column, page, seed row, or sequence is created by these files.


## Recreate the initial demo

See [INITIAL_SETUP.md](INITIAL_SETUP.md) for the ordered model/data/check scripts and the saved post-cleanup initial application SQL export. Normal cleanup preserves the development baseline; these initial-install steps are only for an absent model/app.
