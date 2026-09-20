#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")" &>/dev/null && pwd)"
source "$REPO_DIR/lib/log.sh"
source "$REPO_DIR/lib/detect.sh"
source "$REPO_DIR/lib/env.sh"

assert_linux
ensure_hyprdots_env "$REPO_DIR"
log_info "HYPR_DOTS_DIR: $HYPR_DOTS_DIR"

if [[ ! -d /usr/share/omarchy || ! -f /usr/share/omarchy/default/hypr/bootstrap.lua ]]; then
  log_err "Install Omarchy Quattro before bootstrapping hyprdots"
  exit 1
fi

log_step "1/5 Backing up conflicting owned paths"
"$REPO_DIR/backup.sh"

log_step "2/5 Installing declared personal packages"
"$REPO_DIR/packages/linux/install.sh"

log_step "3/5 Installing configuration"
"$REPO_DIR/sync.sh"

log_step "4/5 Preparing enabled plugin dependencies"
plugin_setup_status=0
"$REPO_DIR/setup-plugins.sh" || plugin_setup_status=$?

log_step "5/5 Validating installation"
doctor_status=0
"$REPO_DIR/doctor.sh" || doctor_status=$?

if (( plugin_setup_status != 0 || doctor_status != 0 )); then
  log_err "Bootstrap completed its safe changes, but the installation is incomplete"
  exit 1
fi

log_ok "Fresh Omarchy Quattro bootstrap complete"
