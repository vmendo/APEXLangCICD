#!/usr/bin/env bash
# Shared validation, state loading, and SQLcl execution.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup_env.sh"
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_tools() {
  local tool
  for tool in "$@"; do command -v "$tool" >/dev/null || die "Required tool not found: $tool"; done
}
validate_name() { [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || die "Invalid name: $1"; }
validate_version() { [[ "$1" =~ ^[0-9]+(\.[0-9]+){1,2}([_-][A-Za-z0-9]+)*$ ]] || die "Invalid release version: $1"; }
validate_identifier() { [[ "$1" =~ ^[A-Z][A-Z0-9_]{0,127}$ ]] || die "Use an unquoted uppercase Oracle identifier: $1"; }
load_project() {
  [[ -f "$DEMO_HOME/.state/project.env" ]] || die "No active project. Run create_project.sh first."
  source "$DEMO_HOME/.state/project.env"
  export DB_CONNECT_DEV DB_CONNECT_PRO DB_CONNECT_ADMIN SCHEMA_NAME SCHEMA_NAME_PRO APEX_WORKSPACE_DEV APEX_WORKSPACE_PRO APEX_APP_ID APEX_APP_ID_PRO APEX_APP_ID_PRO_PREFERRED
  validate_name "$PROJECT_NAME"
  [[ -d "$PROJECT_DIR/.dbtools" ]] || die "Active project directory is missing: $PROJECT_DIR"
}
run_sql() {
  local connection="$1" label="$2"
  require_tools python3 grep
  [[ "$connection" =~ ^[A-Za-z0-9_-]+$ ]] || die "Invalid saved connection name."
  [[ "$label" =~ ^[A-Za-z0-9_.-]+$ ]] || die "Invalid log label."
  [[ -x "$SQLCL_BIN" ]] || die "Controlled SQLcl 26.3 runtime is missing."
  # Enforce the pinned runtime on every stage, including disconnected commands.
  "$SQLCL_BIN" -version | grep -Eq 'Release 26\.3\.0\.0([[:space:]]|$)' || die "SQLcl must be exactly 26.3.0.0."
  mkdir -p "$DEMO_HOME/logs"
  python3 "$DEMO_HOME/run/aux/sqlcl_runner.py" "$SQLCL_BIN" "$connection" "$DEMO_HOME/logs/$label-$(date -u +%Y%m%dT%H%M%S)-$$.log" "$SQLCL_TIMEOUT"
}
