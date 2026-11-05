# Create the Training Hub starting state

This is one-time development preparation when the training model/application are absent, for example in a fresh environment. Ordinary `clean_demo.sh` preserves this starting state, so do not repeat these steps after every cleanup. A fresh clone contains source files only; it does not create a model or application in your database.

## Prerequisites

Use the configured development workspace/parsing schema (defaults: `DEMO` / `DEMO`, connection `ADB_LOCAL_DEMO`). The workspace must already exist, be mapped to that schema, and have a developer account for APEX Accounts sign-in. Schema creation privileges and the controlled SQLcl 26.3 runtime must be available. This setup recreates the demo model/data/app; it does not provision a database, ORDS, workspace users or their passwords.

Install an external SQLcl 26.3 distribution with `./run/setup/install_sqlcl.sh /path/to/sqlcl-distribution` and configure saved source/admin/target connections first. Copy `config/example.env` to `config/local.env` and adapt the environment values. The source repository is `vmendo/APEXLangCICD` (`master`); `GITHUB_REPO` must identify a separate disposable delivery repository, such as `<your-account>/<your-demo-repo>` (`main`). Cleanup will empty that delivery repository, not this source checkout.

## 1. Create and populate the initial model

In development APEX **SQL Workshop > SQL Scripts**, select the intended parsing schema and run the following local files in order:

1. `scripts/training/01_create_model.sql` — ten tables, ten named sequences, named constraints and indexes, all using the literal `DEMO_TRN_` prefix.
2. `scripts/training/02_seed_data.sql` — fictional development dataset: 30 employees, 10 courses, 16 sessions, 80 enrollments, 40 evaluations and supporting reference rows.
3. `scripts/training/03_verify.sql` — read-only exact baseline count, validity, integrity and future-change absence checks.

Alternatively, from this repository root, open the controlled client and execute the same files:

```bash
./tools/sqlcl-26.3/bin/sql -name ADB_LOCAL_DEMO
```

```sql
@scripts/training/01_create_model.sql
@scripts/training/02_seed_data.sql
@scripts/training/03_verify.sql
```

Use the configured connection when it differs from the default. Creation refuses existing training objects and never drops/replaces them. Seeding requires all ten tables to be empty. Neither is a cleanup/reset command. Use a dedicated session without unrelated pending work; Oracle DDL commits implicitly.

## 2. Import the saved initial application

In development **App Builder > Import**, choose:

`scripts/setup/training-hub/initial_application.sql`

Select the intended parsing schema and install as a **new** application. Use ID 110 if it is free; otherwise choose another free ID and update `APEX_APP_ID` in `config/local.env` before creating the CI/CD project. Avoid replacing an existing application. The SQL export itself contains application removal/recreation statements, as standard APEX exports do; do not execute it directly against an occupied ID.

This fixed SQL export was captured from the validated Training Hub baseline after cleanup, using SQLcl 26.3. It is an initial-install artifact, separate from the native APEXlang sources and Projects release artifacts.

Verified snapshot:

- Name/alias: Training Hub / `TRAINING-HUB`; version: Release 1.0; APEX 26.1.5.
- Eleven pages: 0, 1, 2, 3, 4, 5, 6, 11, 12, 13, 9999.
- No Certifications page or navigation entry and no release 1.1 table/column references.
- Supporting-object installers excluded; no business table rows or workspace users/passwords are included.
- Version-matched Oracle static-resource CDN prefix is included for the validated APEX 26.1.5 development environment; Internet access is required. Review that environment setting if installing on another APEX patch level.
- SHA256: `df78d06ca9118b3d685eba898159fa8d77ee183c520f44de0042e38b72d394fa`.

The table, sequence and course column of the future certification extension must remain absent at this point. Sign in to Training Hub with the workspace's existing APEX account and check Overview, reports and navigation before starting the CI/CD presentation.

## 3. Begin the normal presentation

Follow `docs/MANUAL_DEMO.md`, starting with `./run/create_project.sh <project_name>`. SQLcl Projects exports the live app natively as APEXlang; it does not use the initial SQL snapshot for releases. Production still receives structures only. Release 1.1 changes and optional presentation seeds remain separate manual steps.

The saved initial SQL export and model scripts live outside the generated project and survive full demo cleanup. The export is intentionally fixed at the initial state: do not replace it with a release 1.1 export. Recapture it only when deliberately changing the initial demo design.
