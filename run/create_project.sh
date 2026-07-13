#!/bin/bash

# Create a repeatable SQLcl Projects baseline from the empty GitHub repository.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

project_dir="$PROJECTS_HOME/$PROJECT_NAME"

[[ ! -e "$project_dir" ]] || {
  echo "Project path already exists: $project_dir" >&2
  echo "Run the clean scripts before recreating the demo." >&2
  exit 1
}

mkdir -p "$PROJECTS_HOME"
git clone "$GITHUB_URL" "$project_dir"

"$SQLCL_BIN" -name "$DB_CONNECT_DEV" <<EOF
project init -name ${PROJECT_NAME} -schemas ${SCHEMA_NAME} -directory ${project_dir} -connection-name ${DB_CONNECT_DEV}
exit
EOF

config_file="$project_dir/.dbtools/project.config.json"
filters_file="$project_dir/.dbtools/filters/project.filters"

jq '
  .sqlcl.version = "26.1.2.0"
  | .export.setTransform.emitSchema = false
  | .export.apex.exptype = ["APEXLANG"]
  | .export.apex.expSupportingObjects = "N"
  | .export.apex.skipExportDate = true
  | .git.defaultBranch = "main"
' "$config_file" > "$config_file.tmp"
mv "$config_file.tmp" "$config_file"

cat >> "$filters_file" <<EOF

-- Demo database objects.
(object_name like '${DB_OBJECTS_FILTER}'),

-- Demo APEX applications.
application_id in (${APEX_APP_IDS// /,}),
EOF

cat > "$project_dir/README.md" <<EOF
# ${PROJECT_NAME}

Repeatable SQLcl Projects and APEXlang CI/CD demo.

## Scope

- Schema: \`${SCHEMA_NAME}\`
- Database connection: \`${DB_CONNECT_DEV}\`
- APEX workspace: \`${APEX_WORKSPACE_NAME_DEV}\`
- APEX app: ${APEX_APP_IDS}

\`project export\` captures the filtered database objects and the filtered APEX
application. \`run/export_apexlang.sh\` creates the canonical split APEXlang
source under \`apexlang/\`. Releases validate and package that source but do not
import or deploy it.
EOF

cd "$project_dir"
git add .
git commit -m "chore: initialize SQLcl 26.1 APEXlang project"
git push -u origin main

echo "Created ${PROJECT_NAME} at ${project_dir}."
