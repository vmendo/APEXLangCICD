#!/usr/bin/env bash
# Copy an existing SQLcl 26.3 distribution without changing system tooling.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../aux/common.sh"
[[ $# -eq 1 ]] || die "Usage: $0 <existing_sqlcl_distribution_directory>"
require_tools python3 grep
source_dir="$(cd "$1" && pwd)"
[[ -x "$source_dir/bin/sql" ]] || die "Source directory is not a SQLcl distribution."
"$source_dir/bin/sql" -version | grep -Eq 'Release 26\.3\.0\.0([[:space:]]|$)' || die "Source must be SQLcl 26.3.0.0."
[[ ! -e "$DEMO_HOME/tools/sqlcl-26.3" ]] || die "Controlled runtime already exists; it will not be overwritten."
mkdir -p "$DEMO_HOME/tools"
cp -R "$source_dir" "$DEMO_HOME/tools/sqlcl-26.3"
python3 "$DEMO_HOME/run/setup/runtime_manifest.py"
