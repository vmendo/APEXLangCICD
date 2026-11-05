# Training Hub APEX CI/CD demo

## Current scope

The demo promotes **Training Hub**, source application `110`, and database objects beginning with the literal prefix `DEMO_TRN_` from development to production. Each presentation creates a fresh native SQLcl Projects project. The project name, repository, connections, schema/workspace, and application IDs are configurable.

The supplied baseline contains ten tables, ten named sequences, approximately 48 database objects, and an 11-page application with reports/dashboard and employee, course, and enrollment forms. Create it in your development environment using [INITIAL_SETUP.md](INITIAL_SETUP.md). It contains 30 fictional employees, ten courses, six instructors, 16 sessions, 80 enrollments, and 40 evaluations. [TRAINING_MODEL.md](TRAINING_MODEL.md) defines the model; [TRAINING_APP.md](TRAINING_APP.md) describes the application. The complete baseline 1.0, incremental 1.1, and cleanup workflow was validated with SQLcl 26.3, development APEX 26.1.5, and target APEX 26.1.6. Verify your own database permissions, APEX patch levels, and static-resource configuration during setup.

Training CI/CD releases transfer structures and application definitions only. Development synthetic rows are not exported to production. There is no supporting-object data installer, separate application source archive, or recovery snapshot stage. Run structures-only validation before any optional production sample-data helper.

Release 1.1 introduces `DEMO_TRN_CERTIFICATIONS`, a named sequence and indexes, `DEMO_TRN_COURSES.CERTIFICATION_REQUIRED`, and one manually created Certifications report page. Those changes remain absent from baseline 1.0. Supplied scripts may be uploaded to development SQL Scripts in advance; execute them only at the manual change checkpoint.

## Defaults and configuration

| Setting | Demo value |
| --- | --- |
| Demo home | This source repository checkout; resolved automatically |
| Controlled runtime | `$DEMO_HOME/tools/sqlcl-26.3/bin/sql` |
| Source connection | `ADB_LOCAL_DEMO` |
| Production administrative connection | `ADMIN_ADBFREE` |
| Production schema connection | `DEMO_ADBFREE` |
| Source and target schema/workspace | `DEMO` |
| Source application ID | `110` |
| Preferred production ID | Source ID; next free integer if occupied |
| Object prefix | Literal `DEMO_TRN_` |
| Disposable delivery repository | `<your-account>/<your-demo-repo>` (example; configure your own) |
| Project root | `$DEMO_HOME/projects` |
| Example project name | `TrainingHubCICD` |
| Delivery branch / release tag prefix | `main` / `v` |
| This source repository branch | `master` |
| General stage timeout | `SQLCL_TIMEOUT=180` seconds |
| Deployment timeout | `SQLCL_DEPLOY_TIMEOUT=1800` seconds |
| PR status polling | `PR_POLL_SECONDS=5` seconds |

Two repositories have distinct roles:

- `vmendo/APEXLangCICD` is this reusable source repository, with default branch `master`.
- `GITHUB_REPO` is a separate disposable delivery repository, with default project branch `main`. Generated Projects sources, PRs, tags, and release assets go there; full cleanup empties it.

**Never set `GITHUB_REPO` or `GITHUB_URL` to this source repository.** Choose a dedicated repository you control, such as `<your-account>/<your-demo-repo>`. It must be safe to empty during cleanup. Do not use a shared production-code repository as the delivery target.

Copy `config/example.env` to `config/local.env` during initial configuration and edit non-secret settings. Stage scripts load it automatically. Explicit local-file assignments take precedence over inherited environment values. The selected project identity and connections are retained outside its checkout so release, deployment, and cleanup use the same target.

Use only SQLcl 26.3, controlled build `26.3.0.0` / `26.3.0.260.1620`. Runtime checksums are recorded in `config/sqlcl-runtime.json`; system tooling is not updated. Keep credentials and wallets out of Git.

## One-time preparation

Runtime installation and production schema/workspace provisioning live under `run/setup/`; do not repeat them for every presentation:

```bash
./run/setup/install_sqlcl.sh /path/to/existing/sqlcl-distribution
./run/setup/setup_production.sh
```

A fresh clone does not include the SQLcl distribution, databases, workspaces, saved connections, credentials, or generated projects. Install an externally obtained SQLcl 26.3 distribution and configure your source/target environments before creating a project. Once prepared, the runtime and production infrastructure/connection survive normal demo cleanup. Provisioning does not require a generated project. `--no-save-connection` leaves connection creation to the presenter. Database credentials are distinct from APEX workspace login accounts.

The development training setup scripts under `scripts/training/` create and seed the baseline once; they are not per-release changes and must not be rerun over occupied tables. All normal demo stages invoke identity checks through `run/aux/` automatically. A saved connection label alone is not proof of the database or schema reached.

## Presenter stages

### 1. Create the project

```bash
./run/create_project.sh TrainingHubCICD
```

The name argument determines the SQLcl `project init` name and directory under the configured project root. The example creates `projects/TrainingHubCICD`; another valid name is supported. Existing active projects/populated directories are rejected. Always initialize a fresh project for each demonstration.

Native configuration uses `apex.apexlang=true` and `export.apex.exptype=['APEXLANG']`. Application sources are exported at:

```text
src/database/<schema>/apex_apps/<application-alias>/application.apx
```

The alias determines the application directory. Page/component sources belong to that native tree; no second application export is maintained. Database filters select `DEMO_TRN_` literally, including underscores, and application 110 by default. No training data is included.

### 2. Generate release 1.0 and merge manually

```bash
./run/create_release.sh baseline 1.0
```

The script exports native project sources, stages changes, applies bounded SQLcl compatibility handling, commits generated migrations, verifies/compiles the project, finalizes the release, and opens a GitHub PR. It waits while the presenter reviews and merges the PR manually. The script never approves or merges it.

After merge, its internal publisher builds from the exact merged commit and publishes `<project>-1.0.zip` plus its SHA256 checksum. Closing the PR without merging or Ctrl+C cancels the wait; API failures stop without publishing. Branches are flat `<release-name>-<version>` names, such as `baseline-1.0`, avoiding SQLcl 26.3 slash-path interpretation.

### 3. Deploy and validate release 1.0

After the release script reports successful publication:

```bash
./run/deploy_project.sh PRO 1.0
./run/validate_deployment.sh baseline
```

Deployment downloads the GitHub artifact and verifies its checksum. ADMIN provides instance-wide application-ID visibility: the source ID is preferred if free; otherwise a free integer is selected. Source ID 110 does not change. The deployed target ID is pinned across later releases and cleanup; unknown existing applications are never adopted.

The native controller's actual alias-based parameters provide schema/workspace/application mappings. SQLcl manages the native import offset. Before/after inventories, setup identity checks, collision checks, and the ownership manifest protect preexisting resources. A pending deployment-attempt record stops ordinary retry or cleanup for inspection.

Metadata validation checks the target application, training structures, validity, and the requested release mode. Confirm login, navigation, and page rendering in the production browser too. Tables/reports and lookup choices can be empty because development rows are not migrated. Do not add seed DML to the release simply to make the production UI resemble development.

### 4. Perform the manual development changes

Only after the baseline target is validated, use development APEX workspace DEMO's **SQL Workshop > SQL Scripts** to execute:

1. `scripts/demo_changes/01_create_certifications.sql`
2. `scripts/demo_changes/02_add_certification_required.sql`

Then create one Certifications interactive report and navigation manually in Training Hub 110 App Builder. Follow [MANUAL_APEX_CHANGES.md](MANUAL_APEX_CHANGES.md), verify a free page ID, and record it. `200` is an example, not a reserved page. An associated form is optional; record any additional page ID for cleanup. No release script applies these manual development changes.

### 5. Generate, merge, and deploy release 1.1

```bash
./run/create_release.sh certifications 1.1
```

Review the new table/sequence/indexes, course flag, and native report/navigation definitions in the PR. Merge it manually while the release script waits, then wait for automatic ZIP/checksum publication. Deploy separately:

```bash
./run/deploy_project.sh PRO 1.1
./run/validate_deployment.sh incremental 200
```

Replace `200` with the actual Certifications report page ID. Check it and existing Training Hub pages in the production browser. The same release workflow handles both versions; no separate source export, source validation, or source-publication command is required.

## Interrupted-stage recovery

Resume a saved PR wait/publication without another export or PR:

```bash
./run/create_release.sh --resume 1.0
```

Resume is bound to the recorded project/repository/PR identity. Existing artifacts are not silently overwritten; inspect partial publication before retrying. Publication never starts production deployment.

An interrupted deployment is different. After inspecting its attempt/inventory, explicitly resume the same version if the checks permit:

```bash
./run/deploy_project.sh PRO 1.0 --resume
./run/validate_deployment.sh baseline
```

The retry verifies identical artifact SHA256, original target, partial object inventory, and migration history. ADMIN must confirm no target-schema sessions remain before official `lb release-locks` recovery, then Projects deployment retains history and skips completed changes. Do not manually delete lock/history rows, attempt metadata, or partial objects, and do not rebuild the release as a retry.

Deployment has a finite 1800-second default timeout, independent of shorter-stage 180 seconds. A 15-second heartbeat means the client is running, not that a particular import step has succeeded. Failure retains the attempt for inspection; cleanup must not bypass it. These are general recovery instructions, not a claim of an interrupted Training Hub production rollout.

## Cleanup and the next presentation

```bash
./run/clean_demo.sh
```

Development cleanup lists pages and asks which release pages to remove. Enter or `--skip-page` skips page deletion. It reverts only the certification extension and course flag after checks, preserving the ten baseline tables, source rows, baseline pages, and unrelated application edits. Review shared navigation after page deletion.

Production cleanup uses the recorded deployed ID and owned inventory. Without ownership metadata it lists only applications in the configured workspace/parsing schema and permits explicit app selection; that fallback does not delete unrecorded database objects. `--skip-app` omits app deletion. Schema/workspace and saved connection remain.

Unattended operation requires actual explicit choices:

```bash
./run/clean_demo.sh --skip-page --skip-app
# Replace examples with actual release page and deployed application IDs:
./run/clean_demo.sh --yes --page-id 200 --app-id 110
```

`--yes` does not guess unknown IDs. With no active project, database cleanup remains available while remote/local project stages are skipped. Pending deployment attempts require inspection before cleanup.

For an active project, cleanup empties remote delivery content before deleting the generated local project. Remote inventory can be reviewed separately:

```bash
./run/clean/cleanup_remote.sh --dry-run
```

Interactive `--confirm` requires the exact configured repository; `--yes` allows an intentional unattended reset. Non-default branches, tags, releases/assets, Actions artifacts/runs/caches, and deployments are removed. The repository/default branch remain with one parentless empty-tree commit. Settings, secrets/environments, issues, PR conversations/internal refs, shared packages, wiki, and GitHub retention are outside the reset boundary. Protections are not bypassed.

Full cleanup clears previous-cycle logs after non-mutating guards and retains the new cleanup's logs. The outer scripts/configuration/docs/runtime and production infrastructure remain after generated project deletion. The next demo begins with a new `create_project.sh` invocation.

## Script organization and completion evidence

Only presenter entry points are directly under `run/`: project creation, release creation, deployment, validation, and full cleanup. `run/aux/` contains automatically invoked shared/publishing/checking helpers; `run/setup/` contains one-time preparation; `run/clean/` contains cleanup stages and its `aux/` contains cleanup-only helpers. Do not run internal helpers as extra presentation steps.

When resuming, inspect your saved `.state/` project/release/deployment records, generated checkout, GitHub PR/release status, and stage logs. Keep a local record of completed steps and the manually created page IDs. The reusable sources do not contain another installation’s active state. Validate both deployments and UI changes before declaring your own rehearsal complete. See [MANUAL_DEMO.md](MANUAL_DEMO.md) for the concise sequence.

## Optional presentation data

The CI/CD checks intentionally expect empty target training tables. Only after the final release and its empty-target validation, optionally use the manual helpers in [OPTIONAL_DEMO_DATA.md](OPTIONAL_DEMO_DATA.md). They generate a separate fictional dataset locally; they do not export source rows or become migrations. If demonstrating 1.0 followed by 1.1, postpone production seeding until after 1.1 validation. The development certification seed can populate the manual report after its table exists.
