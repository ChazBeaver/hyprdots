#!/usr/bin/env bash
# Compatibility entrypoint. Package declarations live in pacman.txt and aur.txt.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")" &>/dev/null && pwd)"
exec "$SCRIPT_DIR/install.sh"
