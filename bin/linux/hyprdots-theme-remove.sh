#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Resolve the manifest-installed symlink, even if HYPR_DOTS_DIR is not in the
# desktop session's environment or the repository has moved.
script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
REPO_DIR="$(cd -- "$(dirname -- "$script_path")/../.." && pwd)"

result=0
output="$("$REPO_DIR/themes.sh" remove "$@" 2>&1)" || result=$?
if [[ -n "$output" ]]; then
  printf '%s\n' "$output"
  if command -v omarchy-notification-send >/dev/null 2>&1; then
    title="Hyprdots theme removal complete"
    (( result == 0 )) || title="Hyprdots theme removal failed"
    omarchy-notification-send "$title" "$output" || true
  fi
fi
exit "$result"
