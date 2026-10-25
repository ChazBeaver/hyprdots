#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/lib/log.sh"

[[ $# -eq 0 ]] || { log_err "Usage: ./test.sh"; exit 64; }
shopt -s nullglob
test_scripts=("$REPO_DIR"/tests/*.sh)
(( ${#test_scripts[@]} )) || { log_err "No test suites found in tests/"; exit 1; }

result=0
for test_script in "${test_scripts[@]}"; do
  log_step "Running: $(basename "$test_script")"
  if ! bash "$test_script"; then
    result=1
  fi
done

if (( result == 0 )); then
  log_ok "All ${#test_scripts[@]} test suites passed."
else
  log_err "One or more test suites failed."
fi
exit "$result"
