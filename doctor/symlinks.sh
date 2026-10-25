#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")/.." &>/dev/null && pwd)"
LINKS_MANIFEST="${LINKS_MANIFEST:-$REPO_DIR/config/links.tsv}"
RETIRED_LINKS="${RETIRED_LINKS:-$REPO_DIR/config/retired-links.txt}"

source "$REPO_DIR/lib/log.sh"
source "$REPO_DIR/lib/detect.sh"
source "$REPO_DIR/lib/manifest.sh"

assert_linux
DRIFT=0
# Sync refuses to replace real paths and foreign links and reports itself
# incomplete, so "run ./sync.sh" alone would not help.
BLOCKED=0

path_points_into_repo() {
  local resolved
  resolved="$(readlink -f -- "$1" 2>/dev/null || true)"
  [[ "$resolved" == "$REPO_DIR" || "$resolved" == "$REPO_DIR/"* ]]
}

check_item() {
  local source="$1" target="$2" actual
  if [[ ! -e "$source" && ! -L "$source" ]]; then
    log_err "Missing manifest source: $source"
    DRIFT=1
  elif [[ -e "$target" && ! -L "$target" ]]; then
    log_err "Real path blocks managed link: $target"
    BLOCKED=1
  elif [[ ! -L "$target" ]]; then
    log_err "Missing managed link: $target"
    DRIFT=1
  else
    actual="$(readlink "$target")"
    if [[ "$actual" != "$source" ]] && ! path_points_into_repo "$target"; then
      log_err "Foreign symlink blocks managed link: $target -> $actual"
      BLOCKED=1
    elif [[ "$actual" != "$source" ]]; then
      log_err "Wrong link: $target -> $actual (expected $source)"
      DRIFT=1
    elif [[ ! -e "$target" ]]; then
      log_err "Dangling managed link: $target"
      DRIFT=1
    fi
  fi
}

manifest_each check_item

while IFS= read -r target_rel; do
  [[ -n "$target_rel" && "$target_rel" != \#* ]] || continue
  target="$HOME/$target_rel"
  if [[ -L "$target" ]]; then
    resolved="$(readlink -f "$target" 2>/dev/null || true)"
    if [[ "$resolved" == "$REPO_DIR" || "$resolved" == "$REPO_DIR/"* ]]; then
      log_err "Retired hyprdots link remains: $target"
      DRIFT=1
    fi
  fi
done < "$RETIRED_LINKS"

if (( BLOCKED )); then
  log_warn "Sync cannot replace a blocked path and reports itself incomplete until it is moved"
  log_info "Check what owns each blocked path; move it aside with ./backup.sh, then run ./sync.sh"
  exit 1
fi
if (( DRIFT )); then
  log_warn "Ownership drift detected; run ./sync.sh"
  exit 1
fi
log_ok "All explicitly owned links are correct"
