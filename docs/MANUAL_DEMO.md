# Training Hub manual demo sequence

Prepare Training Hub (default application 110) and its ten-table `DEMO_TRN_` development baseline in your environment using [INITIAL_SETUP.md](INITIAL_SETUP.md). The baseline includes fictional data for presentation; the CI/CD releases migrate structures and application definitions only. This sequence was validated with SQLcl 26.3 and APEX 26.1.5 development / 26.1.6 target.

Each demonstration starts with a fresh SQLcl Projects project. Runtime and production infrastructure setup are one-time operations under `run/setup/`, separate from the presentation. Main scripts call their `run/aux/` helpers automatically.

## Preparation in a fresh development environment

If the initial training model/application do not exist, follow [INITIAL_SETUP.md](INITIAL_SETUP.md): create model, seed development data, verify it, then import the saved initial app. This preparation is not repeated after ordinary cleanup.

## Source and delivery repositories

Run the scripts from this source checkout (`APEXLangCICD`, default branch `master`). Configure `GITHUB_REPO`/`GITHUB_URL` in `config/local.env` to a **separate disposable delivery repository** that you control. The example is `<your-account>/<your-demo-repo>`; its project branch defaults to `main`. Full cleanup empties delivery content. Never point delivery configuration at `vmendo/APEXLangCICD` or another repository whose content must be retained.

## Presentation

1. Create the project with its configurable name:

   ```bash
   ./run/create_project.sh TrainingHubCICD
   ```

2. Generate baseline 1.0:

   ```bash
   ./run/create_release.sh baseline 1.0
   ```

   SQLcl Projects exports the `DEMO_TRN_` structures and native APEXlang application sources, stages and verifies them, then opens a GitHub PR. Review and merge the PR manually while the script waits. It then publishes one deployment ZIP and SHA256 checksum automatically. Closing the PR without merging or Ctrl+C cancels the wait; scripts never approve or merge PRs.

3. After successful publication, deploy and validate explicitly:

   ```bash
   ./run/deploy_project.sh PRO 1.0
   ./run/validate_deployment.sh baseline
   ```

   Deployment downloads the published artifact, verifies its checksum, resolves a free target application ID, and applies the native controller mappings. Source ID 110 is unchanged. Production keeps its recorded target ID for subsequent releases. Check login, navigation, and baseline pages in the production browser; empty tables/reports are expected because data is not migrated.

4. At the manual development checkpoint, execute `01_create_certifications.sql` and `02_add_certification_required.sql` through development workspace DEMO's **SQL Workshop > SQL Scripts**. Then create the single Certifications interactive report page and navigation manually in App Builder. Follow [MANUAL_APEX_CHANGES.md](MANUAL_APEX_CHANGES.md). Record the page ID; uploading the scripts before this checkpoint must not execute them.

5. Generate the incremental release:

   ```bash
   ./run/create_release.sh certifications 1.1
   ```

   Review the table/sequence/indexes, course flag, and native APEXlang page/navigation changes. Merge the PR manually while the script waits for approval, then wait for automatic publication.

6. Deploy and validate:

   ```bash
   ./run/deploy_project.sh PRO 1.1
   ./run/validate_deployment.sh incremental 200
   ```

   Replace `200` with the actual Certifications report page ID chosen in your application. The example is not reserved or a cleanup default. Check its rendering/navigation and existing Training Hub pages in production.

No separate application export/validation, source archive publication, or recovery baseline capture is required. Both releases use native SQLcl Projects and one ZIP/checksum each.

## Interrupted stages

Resume an interrupted PR wait/publication without another export or PR:

```bash
./run/create_release.sh --resume 1.0
```

An interrupted deployment is a different recovery path. Inspect its retained attempt/inventory first, then explicitly resume the same version if the checks permit:

```bash
./run/deploy_project.sh PRO 1.0 --resume
./run/validate_deployment.sh baseline
```

Do not recreate the project, rebuild the release, remove partial objects, or manually clear locks/attempt markers. Deployment recovery verifies the identical artifact and target/history, requires no remaining target-schema sessions before official lock recovery, and retains completed migration history. Deployment has a finite 1800-second default limit and a 15-second running heartbeat; general stages retain a separate 180-second default.

## Reset for the next fresh project

With an active project:

```bash
./run/clean_demo.sh
```

Select only the development release pages and the deployed production application, or skip page/app deletion if already done manually. Cleanup reverts the certification extension while preserving the ten-table development training baseline and its data, removes manifest-owned production artifacts, empties remote delivery content while retaining the repository, and deletes the generated project. Production schema/workspace/connection and outer scripts/configuration/runtime remain.

Full cleanup clears previous-cycle logs at startup after non-mutating guards, then retains logs from the current cleanup. Without an active project, database cleanup remains available but remote/local project stages are skipped. See [RUNBOOK.md](RUNBOOK.md) for confirmation, unattended selection, and reset boundaries. Start the next demonstration by creating a new project.


## Optional presentation rows

To populate the Certifications report after creating its table, or the migrated production app after the final validation, see [OPTIONAL_DEMO_DATA.md](OPTIONAL_DEMO_DATA.md). These helpers are manual and remain outside migrations; source table data is still excluded from releases.
