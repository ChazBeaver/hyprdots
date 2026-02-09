#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# hyprdots Backup Script (layered active/{shared,omarchy}/ structure)
# - Mirrors install.sh discovery, but instead of linking:
#   - If target exists AND is NOT a symlink → mv target target.bak
#   - If target is a symlink → do nothing
#   - If target.bak already exists → skip
# - Always scans: active/shared
# - Conditionally scans: active/omarchy (only if Omarchy is detected)
#
# Rules:
# - active/*/HOME/*   → backs up $HOME/<item>
# - active/*/.config/* → backs up $HOME/.config/<entry>
# ============================================================================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")" &>/dev/null && pwd)"
ACTIVE_DIR="$SCRIPT_DIR/active"

cat << 'EOF'
   ___           __                   __
  / _ )___ _____/ /____ _____    ___ / /
 / _  / _ `/ __/  '_/ // / _ \_ (_-</ _ \
/____/\_,_/\__/_/\_\\_,_/ .__(_)___/_//_/
                       /_/

EOF

# ------------------------
# Detect Omarchy
# ------------------------
is_omarchy() {
  command -v omarchy-menu >/dev/null 2>&1 && return 0
  [[ -d "$HOME/.local/share/omarchy" ]] && return 0
  [[ -d "/usr/share/omarchy" ]] && return 0
  return 1
}

echo -e "\n📦 Backing up hyprdots targets before installation...\n"

# ------------------------
# Backup helpers
# ------------------------
backup_item() {
  local target="$1"

  # Only back up real items; never touch symlinks
  if [[ -e "$target" && ! -L "$target" ]]; then
    if [[ -e "$target.bak" ]]; then
      echo "⚠️  Backup already exists: $target.bak (skipped)"
    else
      mv "$target" "$target.bak"
      echo "🗂  Backed up: $target → $target.bak"
    fi
  fi
}

# ------------------------
# HOME scope
# active/<layer>/HOME/<bucket>/<item> -> $HOME/<item>
# (mirrors install.sh behavior)
# ------------------------
backup_home_scope() {
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
      backup_item "$target"
    done
  done
}

# ------------------------
# .config scope
# active/<layer>/.config/<entry> -> $HOME/.config/<entry>
# (backs up top-level dirs OR files)
# ------------------------
backup_config_scope() {
  local layer_dir="$1"
  local config_path="$layer_dir/.config"
  [[ -d "$config_path" ]] || return 0

  echo "⚙️  .config scope: $config_path"
  find "$config_path" -mindepth 1 -maxdepth 1 | while read -r entry; do
    local name target
    name="$(basename "$entry")"
    target="$HOME/.config/$name"
    backup_item "$target"
  done
}

backup_layer() {
  local layer_dir="$1"
  [[ -d "$layer_dir" ]] || return 0

  echo
  echo "🔍 Scanning layer: $layer_dir"
  backup_home_scope "$layer_dir"
  backup_config_scope "$layer_dir"
}

# ------------------------
# Apply layers (mirrors install ordering)
# ------------------------
backup_layer "$ACTIVE_DIR/shared"

if is_omarchy; then
  echo
  echo "🧩 Omarchy detected — scanning omarchy layer..."
  backup_layer "$ACTIVE_DIR/omarchy"
else
  echo
  echo "ℹ️  Omarchy not detected — skipping omarchy layer."
fi

echo -e "\n✅ Backup complete. You’re ready to install."
