#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
# hyprdots/doctor.sh
# Run all diagnostic checks under doctor/. Read-only.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")" &>/dev/null && pwd)"
DOCTOR_DIR="$SCRIPT_DIR/doctor"

# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

cat <<'EOF'

     _            _
  __| | ___   ___| |_ ___  _ __
 / _` |/ _ \ / __| __/ _ \| '__|
| (_| | (_) | (__| || (_) | |
 \__,_|\___/ \___|\__\___/|_|

     hyprdots diagnostics

EOF

if [ ! -d "$DOCTOR_DIR" ]; then
  log_err "No doctor/ directory at $DOCTOR_DIR"
  exit 1
fi

overall=0
for check in "$DOCTOR_DIR"/*.sh; do
  [ -f "$check" ] || continue
  echo
  log_step "Running: $(basename "$check")"
  if ! "$check"; then
    overall=1
  fi
done

echo
if [ "$overall" -eq 0 ]; then
  log_ok "All checks passed."
else
  log_warn "Drift detected in one or more checks."
fi
exit "$overall"
