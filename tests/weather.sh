#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
plugin_dir="${1:-$REPO_DIR/active/omarchy/.config/omarchy/plugins/chaz-weather}"

node "$REPO_DIR/tests/weather/model.cjs" "$plugin_dir"
python3 "$REPO_DIR/tests/weather/runtime.py" "$plugin_dir"
