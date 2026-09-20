#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")" &>/dev/null && pwd)"

read_manifest() {
  local file="$1"
  awk '{ sub(/#.*/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if (length) print }' "$file"
}

mapfile -t pacman_packages < <(read_manifest "$SCRIPT_DIR/pacman.txt")
mapfile -t aur_packages < <(read_manifest "$SCRIPT_DIR/aur.txt")

if (( ${#pacman_packages[@]} )); then
  omarchy pkg add "${pacman_packages[@]}"
fi

if (( ${#aur_packages[@]} )); then
  omarchy pkg aur add "${aur_packages[@]}"
fi

for package in "${pacman_packages[@]}" "${aur_packages[@]}"; do
  pacman -Q "$package" >/dev/null
done
