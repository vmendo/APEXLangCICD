# {{PROJECT_NAME}}

SQLcl 26.3 Projects CI/CD demonstration for Training Hub application {{APP_ID}} and the `DEMO_TRN_` employee training model.

- `src/database/{{SCHEMA_PATH}}/`: training database structures exported by SQLcl Projects.
- `src/database/{{SCHEMA_PATH}}/apex_apps/<application-alias>/application.apx`: native APEXlang application definition and its page/component directory.

The project uses `apex.apexlang=true` and native APEXlang export. Every release uses SQLcl Projects export, stage, verify, release, artifact generation, and deployment. GitHub receives one deployment ZIP and its SHA256 checksum. Source table data and supporting-object installation are excluded; there is no additional source archive or separate application export/validation step.

`create_release.sh` waits for manual PR review/merge, then publishes automatically through its internal helper. Closing the PR without merging or Ctrl+C cancels; `create_release.sh --resume <version>` resumes the saved proposal. Deployment is a separate manual stage.

Release 1.1 is performed manually in development: execute the uploaded certification SQL scripts through APEX SQL Workshop > SQL Scripts, then create the Certifications report page in App Builder. Release creation captures those changes; it does not apply them automatically.

The enclosing source checkout contains the reusable scripts. This generated project belongs to the separately configured disposable delivery repository; do not point delivery configuration at the reusable APEXLangCICD source repository. Each demonstration creates a fresh project with configurable name, repository, connections, schema/workspace, and application IDs. Full cleanup reverts the development certification extension, removes recorded production artifacts and remote delivery content, and deletes this checkout. It preserves the training development baseline, repository resource, production infrastructure, outer scripts/configuration, and controlled SQLcl runtime. Previous logs are cleared at full-cleanup startup; current cleanup logs remain.
