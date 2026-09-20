#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")/.." &>/dev/null && pwd)"
source "$REPO_DIR/lib/log.sh"
source "$REPO_DIR/lib/plugin-requirements.sh"

if ! plugin_requirements_validate; then
  log_err "Invalid plugin requirements: $PLUGIN_REQUIREMENTS"
  exit 1
fi

drift=0
while IFS=$'\t' read -r plugin_id source package; do
  [[ -n "$plugin_id" ]] || continue
  if ! pacman -Q "$package" >/dev/null 2>&1; then
    log_err "$plugin_id: missing $source package $package"
    drift=1
  fi
done < <(plugin_requirements_package_rows)

while IFS=$'\t' read -r plugin_id type target severity message; do
  [[ -n "$plugin_id" ]] || continue
  if ! plugin_requirement_check_passes "$plugin_id" "$type" "$target"; then
    if [[ "$severity" == required ]]; then
      log_err "$plugin_id: $message"
      drift=1
    else
      log_warn "$plugin_id: $message"
    fi
  fi
done < <(plugin_requirements_check_rows)

while IFS=$'\t' read -r plugin_id title command; do
  [[ -n "$plugin_id" ]] || continue
  log_warn "$plugin_id manual setup: $title"
  [[ -z "$command" ]] || printf '  %s\n' "$command"
done < <(plugin_requirements_manual_rows)

mapfile -t locked_ids < <(awk -F '\t' '!/^#/ && NF { print $1 }' "$REPO_DIR/config/plugins.lock.tsv")
declare -A known_plugin_ids=()
for plugin_id in "${locked_ids[@]}"; do
  known_plugin_ids[$plugin_id]=1
  jq -e --arg id "$plugin_id" '.plugins[$id] != null' "$PLUGIN_REQUIREMENTS" >/dev/null || {
    log_err "Pinned plugin has no readiness declaration: $plugin_id"
    drift=1
  }
done
while IFS= read -r plugin_dir; do
  known_plugin_ids["$(basename "$plugin_dir")"]=1
done < <(find "$REPO_DIR/active/omarchy/.config/omarchy/plugins" -mindepth 1 -maxdepth 1 -type d -print)
while IFS= read -r plugin_id; do
  if [[ -z "${known_plugin_ids[$plugin_id]:-}" ]]; then
    log_err "Readiness declaration refers to an unmanaged plugin: $plugin_id"
    drift=1
  fi
done < <(jq -r '.plugins | keys[]' "$PLUGIN_REQUIREMENTS")

plugin_packages="$(jq -r '.plugins[].packages[]?.name' "$PLUGIN_REQUIREMENTS" | sort -u)"
declared_packages="$({ sed 's/#.*//' "$REPO_DIR/packages/linux/pacman.txt"; sed 's/#.*//' "$REPO_DIR/packages/linux/aur.txt"; } | awk 'NF' | sort -u)"
duplicates="$(comm -12 <(printf '%s\n' "$plugin_packages") <(printf '%s\n' "$declared_packages"))"
if [[ -n "$duplicates" ]]; then
  log_err "Plugin-specific packages duplicated in personal package manifests:"
  sed 's/^/  /' <<< "$duplicates"
  drift=1
fi

if (( drift )); then exit 1; fi
log_ok "Enabled plugin runtime requirements are ready"
