#!/bin/bash

# ===============================
# CLEAN FULL DEMO SCRIPT
# ===============================

set -euo pipefail

# --- Colors ---
GREEN='\033[32m'
BLUE='\033[34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLEAN_DIR="$SCRIPT_DIR/clean"

echo ""
echo -e "${BLUE}🧹 Cleaning APEXLang CI/CD demo baseline${NC}"
echo -e "${BLUE}1) Project cleanup${NC}"
"$CLEAN_DIR/delete_project.sh"

echo ""
echo -e "${BLUE}2) DEV database cleanup${NC}"
"$CLEAN_DIR/cleanup_dev.sh"

echo ""
echo -e "${GREEN}🏁 Full demo cleanup completed.${NC}"
