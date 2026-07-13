#!/bin/bash

# Set project base directory
export DEMO_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECTS_HOME="$DEMO_HOME/projects"

# SQLcl 26.1+ is required for APEXlang export, validate, and import.
# Use the installed SQLcl unless a caller supplies an explicit executable.
export SQLCL_BIN="${SQLCL_BIN:-$(command -v sql)}"
if [[ -z "$SQLCL_BIN" || ! -x "$SQLCL_BIN" ]]; then
  echo "ERROR: SQLcl 26.1+ was not found in PATH. Set SQLCL_BIN explicitly." >&2
  return 1 2>/dev/null || exit 1
fi

# GitHub Configuration (user-specific)
export GITHUB_USER="vmendo"
export GITHUB_REPO="apex_ci_cd_demo"
export GITHUB_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO.git"

export PROJECT_NAME="MyDemo"
export SCHEMA_NAME="WKSP_DEMO"

export DB_CONNECT_DEV="apex_dev"

# Development APEX identity. Production deployment is intentionally out of scope.
export APEX_WORKSPACE_NAME_DEV="DEMO"
export APEX_WORKSPACE_ID_DEV="9037671942551503"

# APEX apps and database objects included in this project.
export APEX_APP_IDS="115"
export DB_OBJECTS_FILTER="EBA_DEMO%"
export APEXLANG_SOURCE_DIR="$PROJECTS_HOME/$PROJECT_NAME/apexlang"

# Ensure PROJECTS_HOME exists
if [[ ! -d "$PROJECTS_HOME" ]]; then
  echo "📁 Creating base projects directory: $PROJECTS_HOME"
  mkdir -p "$PROJECTS_HOME"
fi
