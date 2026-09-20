#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")" &>/dev/null && pwd)"
source "$REPO_DIR/lib/log.sh"
source "$REPO_DIR/lib/detect.sh"
source "$REPO_DIR/lib/plugin-requirements.sh"

usage() {
  cat <<'EOF'
Usage: ./setup-plugins.sh [--yes|--no]

  --yes  Install safe package dependencies without prompting.
  --no   Never install packages; print the commands needed instead.
EOF
}

mode=ask
case "${1:-}" in
  --yes) mode=yes ;;
  --no) mode=no ;;
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) usage >&2; exit 64 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 64; }

assert_linux
if ! plugin_requirements_validate; then
  log_err "Invalid plugin requirements: $PLUGIN_REQUIREMENTS"
  exit 1
fi

declare -a missing_repo=() missing_aur=()
declare -A seen_packages=()
while IFS=$'\t' read -r plugin_id source package; do
  [[ -n "$plugin_id" ]] || continue
  if pacman -Q "$package" >/dev/null 2>&1 || [[ -n "${seen_packages[$package]:-}" ]]; then
    continue
  fi
  seen_packages[$package]="$plugin_id"
  if [[ "$source" == repo ]]; then missing_repo+=("$package"); else missing_aur+=("$package"); fi
done < <(plugin_requirements_package_rows)

missing_count=$(( ${#missing_repo[@]} + ${#missing_aur[@]} ))
install_dependencies=false
if (( missing_count > 0 )); then
  log_step "Missing package dependencies for enabled plugins"
  for package in "${missing_repo[@]}" "${missing_aur[@]}"; do
    [[ -n "$package" ]] && printf '  %s (required by %s)\n' "$package" "${seen_packages[$package]}"
  done

  if [[ "$mode" == yes ]]; then
    install_dependencies=true
  elif [[ "$mode" == ask && -t 0 ]]; then
    printf 'Install these plugin dependencies now? [Y/n] '
    read -r reply || reply=n
    [[ ! "$reply" =~ ^[Nn]([Oo])?$ ]] && install_dependencies=true
  fi
fi

if [[ "$install_dependencies" == true ]]; then
  (( ${#missing_repo[@]} == 0 )) || omarchy pkg add "${missing_repo[@]}"
  (( ${#missing_aur[@]} == 0 )) || omarchy pkg aur add "${missing_aur[@]}"
elif (( missing_count > 0 )); then
  log_warn "Plugin dependency installation was skipped. Run:"
  if (( ${#missing_repo[@]} )); then
    printf '  omarchy pkg add'; printf ' %q' "${missing_repo[@]}"; printf '\n'
  fi
  if (( ${#missing_aur[@]} )); then
    printf '  omarchy pkg aur add'; printf ' %q' "${missing_aur[@]}"; printf '\n'
  fi
fi

manual_count=0
while IFS=$'\t' read -r plugin_id title command; do
  [[ -n "$plugin_id" ]] || continue
  ((manual_count += 1))
  log_info "$plugin_id: $title"
  [[ -z "$command" ]] || printf '  %s\n' "$command"
done < <(plugin_requirements_manual_rows)

incomplete=0
if (( missing_count > 0 )) && [[ "$install_dependencies" != true ]]; then
  incomplete=1
fi
while IFS=$'\t' read -r plugin_id type target severity message; do
  [[ -n "$plugin_id" ]] || continue
  if ! plugin_requirement_check_passes "$plugin_id" "$type" "$target"; then
    if [[ "$severity" == required ]]; then
      log_err "$plugin_id: $message"
      incomplete=1
    else
      log_warn "$plugin_id: $message"
    fi
  fi
done < <(plugin_requirements_check_rows)

if (( incomplete )); then
  log_err "Enabled plugin setup is incomplete"
  exit 2
fi
if (( manual_count )); then
  log_ok "Automatic plugin requirements are ready; review the manual steps above"
else
  log_ok "Enabled plugin requirements are ready"
fi
