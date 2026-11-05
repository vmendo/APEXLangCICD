# Training Hub baseline application

Training Hub is a small employee-learning application for the `DEMO_TRN_` model. The supplied baseline uses application ID `110`, alias `TRAINING-HUB`, workspace/schema `DEMO`, and APEX Accounts authentication. These values describe the initial snapshot; choose an available source ID and update configuration if your environment differs.

Install it using [INITIAL_SETUP.md](INITIAL_SETUP.md). Open it from App Builder or use the runtime URL supplied by your own ORDS/APEX installation. A workspace account must exist; no user or password is included in this repository.

## Baseline content

- Ten related tables and approximately 48 schema objects, including named sequences, primary/unique indexes, and supporting indexes.
- Fictional development data: 30 employees, ten courses, six instructors, 16 sessions, 80 enrollments, and 40 evaluations, plus reference rows.
- Dates relative to seed execution, with completed and upcoming sessions.
- Example.com email addresses and English UI/data.

## Pages

| Page | Purpose |
| --- | --- |
| 1 | Overview: four metrics, participation percentage bars, upcoming sessions |
| 2 | Employee report with create/edit links |
| 3 | Course catalog with create/edit links |
| 4 | Sessions with instructor, location, capacity, and enrollment totals |
| 5 | Enrollments and evaluation score, with create/edit links |
| 6 | Evaluation feedback |
| 11–13 | Employee, course, and enrollment forms with native initialization/DML and LOVs |
| 0 / 9999 | Global page / APEX Accounts login |

Business pages require authentication. Model constraints enforce required values, allowed statuses, foreign keys, and natural keys. Forms return to their parent reports.

The dashboard uses native report percentage bars. Interactive Reports can still load Oracle JET resources even when their optional Chart actions are disabled. The supplied initial snapshot includes Oracle's version-matched static-resource CDN prefix for APEX 26.1.5; it requires Internet access. Review this application-level setting for your APEX patch level or use your installation's correctly deployed static resources. PWA is disabled in this baseline.

## Sources

- `scripts/setup/training-hub/initial_application.sql`: fixed baseline SQL snapshot for initial development installation only.
- `scripts/training/01_create_model.sql`, `02_seed_data.sql`, and `03_verify.sql`: initial structures, synthetic data, and verification.
- `scripts/training/model.json`: typed schema contract.
- `applications/training-hub/`: editable APEXlang application sources.

No supporting-object installer or workspace account is included. Model setup and initial snapshot import are one-time preparation. Normal releases export the live application through native SQLcl Projects; they do not install this fixed SQL snapshot or transfer the development seed rows.

## Release 1.1 exercise

The baseline contains no Certifications page, certification table/sequence, or `CERTIFICATION_REQUIRED` course column. Add them manually at the documented checkpoint in [MANUAL_APEX_CHANGES.md](MANUAL_APEX_CHANGES.md), then promote them through the second release. Record your actual new page ID for validation and cleanup.

## Validation example

The baseline application/model, release 1.0, manual certification extension/release 1.1, and cleanup were tested with SQLcl 26.3, APEX 26.1.5 development, and APEX 26.1.6 target. The reference Overview screenshot is `docs/training-hub-overview.png`. Repeat metadata and browser checks in your own installation, particularly authentication and static-resource loading. Version-specific setup details can differ.
