#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")/.." &>/dev/null && pwd)"
LINKS_MANIFEST="$REPO_DIR/config/links.tsv"
RETIRED_LINKS="$REPO_DIR/config/retired-links.txt"

source "$REPO_DIR/lib/log.sh"
source "$REPO_DIR/lib/detect.sh"
source "$REPO_DIR/lib/manifest.sh"

assert_linux
DRIFT=0

check_item() {
  local source="$1" target="$2" actual
  if [[ ! -e "$source" && ! -L "$source" ]]; then
    log_err "Missing manifest source: $source"
    DRIFT=1
  elif [[ ! -L "$target" ]]; then
    log_err "Missing managed link: $target"
    DRIFT=1
  else
    actual="$(readlink "$target")"
    if [[ "$actual" != "$source" ]]; then
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

if (( DRIFT )); then
  log_warn "Ownership drift detected; run ./sync.sh"
  exit 1
fi
log_ok "All explicitly owned links are correct"
