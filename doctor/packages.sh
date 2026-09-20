#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")/.." &>/dev/null && pwd)"
source "$REPO_DIR/lib/log.sh"
source "$REPO_DIR/lib/detect.sh"
assert_linux

read_manifest() {
  awk '{ sub(/#.*/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if (length) print }' "$1"
}

mapfile -t declared < <(
  read_manifest "$REPO_DIR/packages/linux/pacman.txt"
  read_manifest "$REPO_DIR/packages/linux/aur.txt"
)

drift=0
for package in "${declared[@]}"; do
  if ! pacman -Q "$package" >/dev/null 2>&1; then
    log_err "Missing declared package: $package"
    drift=1
  fi
done

omarchy_manifest="/usr/share/omarchy/install/omarchy-base.packages"
if [[ ! -r "$omarchy_manifest" ]]; then
  log_err "Missing Quattro package manifest: $omarchy_manifest"
  drift=1
else
  duplicates="$(comm -12 <(printf '%s\n' "${declared[@]}" | sort -u) <(read_manifest "$omarchy_manifest" | sort -u))"
  if [[ -n "$duplicates" ]]; then
    log_err "Packages duplicated from Omarchy's base manifest:"
    sed 's/^/  /' <<< "$duplicates"
    drift=1
  fi
fi

appdots_dir="${APP_DOTS_DIR:-}"
if [[ -z "$appdots_dir" && -r "$HOME/.dotfiles-env.sh" ]]; then
  appdots_dir="$(sed -n 's/^export APP_DOTS_DIR="\{0,1\}\([^" ]*\)"\{0,1\}$/\1/p' "$HOME/.dotfiles-env.sh" | tail -1)"
fi
if [[ -n "$appdots_dir" && -r "$appdots_dir/packages/linux/core.sh" ]]; then
  appdots_packages="$(awk '
    /^PACMAN_PKGS=\(/ || /^AUR_PKGS=\(/ { active=1; next }
    /^\)/ { active=0 }
    active { sub(/#.*/, ""); gsub(/[[:space:]]/, ""); if (length) print }
  ' "$appdots_dir/packages/linux/core.sh" | sort -u)"
  allowed_overlap="$(read_manifest "$REPO_DIR/packages/linux/appdots-overlap.txt" | sort -u)"
  overlap="$(
    comm -12 <(printf '%s\n' "${declared[@]}" | sort -u) <(printf '%s\n' "$appdots_packages") \
      | comm -23 - <(printf '%s\n' "$allowed_overlap")
  )"
  if [[ -n "$overlap" ]]; then
    log_err "Packages also owned by appdots:"
    sed 's/^/  /' <<< "$overlap"
    drift=1
  fi
fi

if (( drift )); then exit 1; fi
log_ok "All declared personal packages are installed with no ownership overlap"
