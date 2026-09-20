#!/usr/bin/env bash
# hyprdots/scripts/misc/check-drift.sh
# Quick helper: runs doctor.sh and prints a summary.
# Useful as a cron job or post-pull hook.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")" &>/dev/null && pwd)"
HYPRDOTS_DIR="$(cd -- "$SCRIPT_DIR/../.." &>/dev/null && pwd)"

exec "$HYPRDOTS_DIR/doctor.sh"
