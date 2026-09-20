#!/usr/bin/env bash
set -euo pipefail

state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
state_dir="$state_home/hyprdots"
state_file="$state_dir/opacity-mode"
mkdir -p "$state_dir"

current="transparent"
[[ -r "$state_file" ]] && read -r current < "$state_file"

case "$current" in
  transparent) next="blur" ;;
  blur) next="opaque" ;;
  opaque) next="transparent" ;;
  *) next="transparent" ;;
esac

temporary="$state_file.$$"
printf '%s\n' "$next" > "$temporary"
mv "$temporary" "$state_file"
hyprctl reload >/dev/null
omarchy-notification-send -u low "Visual mode" "${next^}" >/dev/null 2>&1 || true
