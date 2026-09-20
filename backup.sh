#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")" &>/dev/null && pwd)"
LINKS_MANIFEST="$REPO_DIR/config/links.tsv"

source "$REPO_DIR/lib/log.sh"
source "$REPO_DIR/lib/detect.sh"
source "$REPO_DIR/lib/manifest.sh"
source "$REPO_DIR/lib/backup.sh"

assert_linux
log_step "Backing up conflicting hyprdots-owned paths"
backup_manifest
log_ok "Backup complete"
