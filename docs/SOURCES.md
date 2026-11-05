# References and validation context

## Official documentation

- [SQLcl 26.3 PROJECT reference](https://docs.oracle.com/en/database/oracle/sql-developer-command-line/26.3/sqcug/project.html): initialization, export, staging, verification, releases, artifacts, and deployment.
- [SQLcl 26.3 Database CI/CD introduction](https://docs.oracle.com/en/database/oracle/sql-developer-command-line/26.3/sqcug/introduction.html): source layout, filters, snapshots, and Git-based staging.
- [APEX 26.1 interactive report/form wizard](https://docs.oracle.com/en/database/oracle/apex/26.1/htmdb/creating-an-interactive-report-using-the-create-page-wizard.html): manual report creation.
- [APEX 26.1 SQL Scripts](https://docs.oracle.com/en/database/oracle/apex/26.1/aeutl/creating-sql-script.html): upload and manually execute release-change scripts.
- [Oracle Database 26 CREATE TABLE reference](https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/CREATE-TABLE.html): model definitions, named-sequence defaults, and constraints.

For version-specific options, inspect `help project` in the controlled SQLcl 26.3 client and inspect the generated artifact controller/defaults. Native APEXlang source is under `src/database/<schema>/apex_apps/<alias>/application.apx`. Schema/workspace/application mappings come from those actual native controller parameters.

## Source versus delivery

This reusable source repository is [vmendo/APEXLangCICD](https://github.com/vmendo/APEXLangCICD), default branch `master`. The configurable example delivery repository is `<your-account>/<your-demo-repo>`, with project branch `main`. There is no shared delivery repository. Use a dedicated disposable delivery repository that you control; never configure the source repository as the cleanup target.

## Tested configuration

The baseline 1.0, manual certification changes, incremental 1.1 deployment, and cleanup were validated with SQLcl `26.3.0.0`, build `26.3.0.260.1620`, APEX 26.1.5 development, and APEX 26.1.6 target. The repository contains reusable sources and tests rather than an active installation's databases, logs, credentials, or deployment state. Repeat validation for your own environment.

`config/sqlcl-runtime.json` records the reference distribution's version/checksums. `run/setup/install_sqlcl.sh` copies an externally obtained SQLcl 26.3 distribution and regenerates the local manifest. No SQLcl distribution is bundled.

The initial development application snapshot is documented and checksummed in [INITIAL_SETUP.md](INITIAL_SETUP.md). Release artifacts are generated from the live development application, published after manual PR merge, and downloaded with checksum verification. Optional sample-data scripts remain outside the release artifacts and run only after the relevant structures-only checks.
