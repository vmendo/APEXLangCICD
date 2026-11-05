# Optional presentation data

These scripts generate fictional data locally in the selected database. They are manual presentation helpers outside SQLcl Projects releases: the CI/CD flow still migrates structures only. Neither script is called by the demo, setup, deployment or cleanup commands. Both are plain SQL/PLSQL suitable for manually uploading to APEX SQL Workshop > SQL Scripts, or running with the controlled SQLcl26.3 runtime. Use the intended parsing schema and a dedicated session without unrelated pending work.

## Fill the new certifications page in development

After creating the release1.1 table, run:

`scripts/demo_data/01_seed_certifications.sql`

It adds up to 12 certificates using existing completed enrollments and their employee/course foreign keys. With the supplied initial development dataset, it adds 8 VALID, 2 EXPIRED and 2 REVOKED certificates. Issue dates follow the completed sessions; expiry dates satisfy the date constraint. IDs come from the table's named sequence default.

The script changes only `DEMO_TRN_CERTIFICATIONS`; baseline employees, courses and enrollments remain intact. Stable `TH-DEMO-<enrollment ID>` certificate codes let a repeat run skip those certificates without overwriting rows. An empty database with no completed training is rejected; load the production sample first if applicable. Development cleanup removes the new table and its presentation rows as part of the existing release1.1 reset.

## Populate a migrated production application

After the **final** release deployment and its structures-only validation, optionally run:

`scripts/demo_data/02_seed_production.sql`

It requires all ten baseline tables to be empty and inserts in foreign-key order using generated sequence IDs:

| Table content | Rows |
| --- | ---: |
| Departments / locations / rooms | 3 / 2 / 3 |
| Employees / categories / courses / instructors | 12 / 3 / 6 / 3 |
| Sessions: completed / scheduled | 3 / 3 |
| Enrollments: completed / enrolled | 12 / 12 |
| Evaluations | 12 |

Dates are relative to execution day; emails use `example.com`. This is a separate synthetic dataset generated in production, not an export of development rows. No tables, columns, users, workspaces or applications are created. It supports baseline1.0 and release1.1 and does not depend on the certification column/table. A repeat run refuses nonempty tables before inserting anything; existing records are never cleared, updated or replaced.

For the new page after release1.1, run `01_seed_certifications.sql` **after** the production sample. The production sample intentionally leaves certificates to that separate script.

`validate_deployment.sh` checks that production training tables are empty to demonstrate structures-only delivery. Run that validation before optional seeding. If continuing the full 1.0-to-1.1 demo, defer production seeding until after 1.1 validation; otherwise subsequent empty-table validation will correctly reject populated tables. The optional helpers do not change or bypass that check. Existing production cleanup removes the owned training tables and their sample rows.

## Transactions

Each script commits on success. On failure, it rolls back its own changes to its starting savepoint and re-raises the error. A failure can consume sequence values even though inserted rows roll back; gaps are normal. Finish any unrelated transaction before running a helper.
