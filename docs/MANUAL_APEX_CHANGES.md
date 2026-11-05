# Manual release 1.1 changes: training certifications

## Story and timing

Training Hub (default application 110) manages employees, courses, scheduled sessions, enrollments, and feedback. Release 1.1 extends it with employee certifications and a course flag identifying training that requires a certificate.

Complete [INITIAL_SETUP.md](INITIAL_SETUP.md) so the baseline model and application exist in your development environment. Keep the certification table, sequence, course column, and page absent from baseline 1.0. The change scripts may be uploaded to development APEX SQL Scripts in advance, but do not execute them until the initial production release has been deployed and validated. Uploading a script is not executing it.

## 1. Execute the supplied scripts in development APEX

Sign in to the configured development workspace (default `DEMO`). Open **SQL Workshop > SQL Scripts** and confirm the selected schema is the Training Hub parsing schema (default `DEMO`). Manually upload these local files, or open the saved copies by filename:

1. `scripts/demo_changes/01_create_certifications.sql`
2. `scripts/demo_changes/02_add_certification_required.sql`

Review and execute them one at a time, in that order, at the release 1.1 checkpoint. They contain ordinary Oracle SQL/PLSQL, no application data inserts, and no production deployment commands. Saving or uploading them does not run their DDL. They refuse existing-name collisions instead of silently accepting an earlier run. Oracle DDL commits implicitly; inspect any failure before retrying. Do not execute them again through SQLcl after using SQL Scripts.

The first script adds the named `DEMO_TRN_CERTIFICATIONS_SEQ` sequence, starting at 1000, and `DEMO_TRN_CERTIFICATIONS`:

| Column | Definition and purpose |
| --- | --- |
| `ID` | NUMBER primary key; defaults from the named sequence |
| `EMPLOYEE_ID` | Required foreign key to `DEMO_TRN_EMPLOYEES.ID` |
| `COURSE_ID` | Required foreign key to `DEMO_TRN_COURSES.ID` |
| `CERTIFICATE_CODE` | Required unique certificate reference, up to 40 characters |
| `ISSUED_ON` | Required DATE, defaulting to `TRUNC(SYSDATE)` |
| `EXPIRES_ON` | Optional DATE, no earlier than the issue date |
| `STATUS` | Required `VALID`, `EXPIRED`, or `REVOKED`; default `VALID` |
| `NOTES` | Optional notes, up to 1000 characters |

It includes named foreign-key indexes and date/status constraints. The second script adds `DEMO_TRN_COURSES.CERTIFICATION_REQUIRED VARCHAR2(1) DEFAULT 'N' NOT NULL`, restricted to `Y` or `N` by `DEMO_TRN_COURSES_CERT_REQ_CK`. Existing courses receive the default behavior without a separate data update script.

Use Object Browser to verify the table, sequence, keys/checks, and new course column before continuing.

## 2. Create one certifications report page manually

In App Builder, open the configured development **Training Hub** application (default ID `110`). Choose an unused page ID; `200` is an example and must still be checked before creation. Record the actual value for deployment validation and cleanup.

Use Create Page to add an **Interactive Report** named **Certifications**. Choose a local database table source in the configured parsing schema and select `DEMO_TRN_CERTIFICATIONS`. Add a navigation entry for the report. This exercise requires one new report page; leave the associated form option disabled unless you deliberately extend the exercise. Oracle documents the wizard in the [APEX 26.1 App Builder guide](https://docs.oracle.com/en/database/oracle/apex/26.1/htmdb/creating-an-interactive-report-using-the-create-page-wizard.html).

The report can initially show the table columns directly. To display employee/course names without changing its data model, use this optional report query:

```sql
select c.id,
       e.first_name || ' ' || e.last_name as employee_name,
       t.course_name,
       c.certificate_code,
       c.issued_on,
       c.expires_on,
       c.status,
       c.notes
  from demo_trn_certifications c
  join demo_trn_employees e on e.id = c.employee_id
  join demo_trn_courses t on t.id = c.course_id
```

No certification rows are required. Development contains fictional training data; production receives structures only, so its employee/course lookups are empty unless data is entered locally as a separate exercise. Do not add migration DML to populate them.

If you choose to add a form, record its additional page ID and include it explicitly in validation and cleanup. The form must use the named sequence default for ID and valid employee/course foreign keys; it is an optional extension rather than a required second page.

## 3. Check and record the manual changes

Save the new page and run it through the application's navigation. Confirm that it opens without missing-object/column errors. An empty report is expected and valid.

Record:

- Development application ID and actual certifications report page ID.
- Navigation/breadcrumb entries added for the page.
- Any optional form page or other deliberately changed page IDs.

Then run the standard release 1.1 creation stage. Its PR must contain the new table/sequence/indexes, the course column/check, and the native APEXlang report/navigation definitions. Review and merge the PR manually while the local release script waits; publication then runs automatically. Deployment remains a separate manual command.

## Reset boundary

Development cleanup lists pages and asks which release pages to delete; select only the report and any optional form actually created. Enter or `--skip-page` skips deletion. Cleanup then reverts only the agreed certification objects and course column after checks. Other application edits and the ten-table training baseline remain. Review shared navigation links after page removal. Cleanup never guesses page IDs from the example `200`.


## Optional presentation rows

To populate the Certifications report after creating its table, or the migrated production app after the final validation, see [OPTIONAL_DEMO_DATA.md](OPTIONAL_DEMO_DATA.md). These helpers are manual and remain outside migrations; source table data is still excluded from releases.
