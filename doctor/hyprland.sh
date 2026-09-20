#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")/.." &>/dev/null && pwd)"
source "$REPO_DIR/lib/log.sh"

for file in hyprland.lua bindings.lua looknfeel.lua privacy.lua opacity.lua; do
  [[ -r "$REPO_DIR/active/omarchy/.config/hypr/$file" ]] || {
    log_err "Missing Hyprland source: $file"
    exit 1
  }
done

if [[ "${HYPRDOTS_OFFLINE:-0}" == "1" ]]; then
  log_info "Offline mode: live Hyprland validation skipped"
elif hyprctl instances >/dev/null 2>&1; then
  errors="$(hyprctl configerrors 2>/dev/null || true)"
  if [[ -n "$errors" ]]; then
    log_err "Hyprland configuration errors:"
    printf '%s\n' "$errors"
    exit 1
  fi
  log_ok "Hyprland reports no configuration errors"
else
  log_info "Hyprland is not running; live config validation skipped"
fi
