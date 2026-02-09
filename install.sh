#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# hyprdots Install Script (layered active/{shared,omarchy}/ structure)
# - Always applies: active/shared
# - Conditionally applies: active/omarchy (only if Omarchy is detected)
#
# Rules:
# - active/*/HOME/*   → symlinked into $HOME/ (top-level items)
# - active/*/.config/* → symlinked into $HOME/.config/ (top-level entries)
# ============================================================================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")" &>/dev/null && pwd)"
ACTIVE_DIR="$SCRIPT_DIR/active"

ENV_FILE="$HOME/.dotfiles-env.sh"
VAR_NAME="HYPR_DOTS_DIR"

# ------------------------
# Detect Omarchy
# ------------------------
is_omarchy() {
  command -v omarchy-menu >/dev/null 2>&1 && return 0
  [[ -d "$HOME/.local/share/omarchy" ]] && return 0
  [[ -d "/usr/share/omarchy" ]] && return 0
  return 1
}

# ------------------------
# Persist HYPR_DOTS_DIR + alias
# ------------------------
if [[ -z "${HYPR_DOTS_DIR:-}" ]]; then
  if [[ "$SCRIPT_DIR" == "$HOME"* ]]; then
    export HYPR_DOTS_DIR="$SCRIPT_DIR"
    echo "Set HYPR_DOTS_DIR to $SCRIPT_DIR"
  else
    echo "Warning: hyprdots not inside home directory. Please set HYPR_DOTS_DIR manually."
  fi
fi

mkdir -p "$(dirname "$ENV_FILE")"

grep -q "$VAR_NAME=" "$ENV_FILE" 2>/dev/null || echo "export $VAR_NAME=\"$SCRIPT_DIR\"" >> "$ENV_FILE"
grep -q 'alias hyprdots=' "$ENV_FILE" 2>/dev/null || echo 'alias hyprdots="cd \$HYPR_DOTS_DIR"' >> "$ENV_FILE"

# shellcheck disable=SC1090
source "$ENV_FILE" 2>/dev/null || true

# ------------------------
# Symlink Function
# ------------------------
link_item() {
  local source_path="$1"
  local target_path="$2"

  if [[ -e "$target_path" || -L "$target_path" ]]; then
    if [[ "$(readlink "$target_path" 2>/dev/null || true)" == "$source_path" ]]; then
      echo "✅ Already linked correctly: $target_path -> $source_path"
    else
      echo "⚠️  Exists but differs: $target_path (skipping)"
    fi
  else
    mkdir -p "$(dirname "$target_path")"
    ln -s "$source_path" "$target_path"
    echo "🔗 Linked: $target_path -> $source_path"
  fi
}

# ------------------------
# Install HOME scope
# active/<layer>/HOME/<bucket>/<item> -> $HOME/<item>
# (matches your appdots behavior)
# ------------------------
install_home_scope() {
  local layer_dir="$1"
  local home_path="$layer_dir/HOME"
  [[ -d "$home_path" ]] || return 0

  echo "🏠 HOME scope: $home_path"
  find "$home_path" -mindepth 1 -maxdepth 1 | while read -r bucket; do
    [[ -d "$bucket" ]] || continue

    find "$bucket" -mindepth 1 -maxdepth 1 | while read -r item; do
      local name target
      name="$(basename "$item")"
      target="$HOME/$name"
      link_item "$item" "$target"
    done
  done
}

# ------------------------
# Install .config scope
# active/<layer>/.config/<entry> -> $HOME/.config/<entry>
# (links top-level dirs OR files)
# ------------------------
install_config_scope() {
  local layer_dir="$1"
  local config_path="$layer_dir/.config"
  [[ -d "$config_path" ]] || return 0

  echo "⚙️  .config scope: $config_path"
  find "$config_path" -mindepth 1 -maxdepth 1 | while read -r entry; do
    local name target
    name="$(basename "$entry")"
    target="$HOME/.config/$name"
    link_item "$entry" "$target"
  done
}

install_layer() {
  local layer_dir="$1"
  [[ -d "$layer_dir" ]] || return 0

  echo
  echo "🔍 Processing layer: $layer_dir"
  install_home_scope "$layer_dir"
  install_config_scope "$layer_dir"
}

# ------------------------
# Banner
# ------------------------
cat <<'EOF'

 _   ___   _____________      ______ _____ _____ _____
| | | \ \ / / ___ \ ___ \     |  _  \  _  |_   _/  ___|
| |_| |\ V /| |_/ / |_/ /_____| | | | | | | | | \ `--.
|  _  | \ / |  __/|    /______| | | | | | | | |  `--. \
| | | | | | | |   | |\ \      | |/ /\ \_/ / | | /\__/ /
\_| |_/ \_/ \_|   \_| \_|     |___/  \___/  \_/ \____/

                 Installing Hyprdots

EOF

# ------------------------
# Apply layers
# - shared always
# - omarchy only if detected
# ------------------------
install_layer "$ACTIVE_DIR/shared"

if is_omarchy; then
  echo
  echo "🧩 Omarchy detected — applying omarchy layer..."
  install_layer "$ACTIVE_DIR/omarchy"
else
  echo
  echo "ℹ️  Omarchy not detected — skipping omarchy layer."
fi

echo
echo "✅ Finished installing hyprdots."
