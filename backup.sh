#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# hyprdots Backup Script (mirrors install discovery)
# - Always scans: active/shared
# - Scans ONE OS layer (same selection logic as install.sh)
# - For each target that would be installed:
#     - if exists AND not a symlink -> mv to .bak
#     - if symlink -> do nothing
#     - if .bak exists -> skip
# ============================================================================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")" &>/dev/null && pwd)"
ACTIVE_DIR="$SCRIPT_DIR/active"

cat << 'EOF'
 _                         _       _          
| |__  _   _ _ __  _ __ __| | ___ | |_ ___    
| '_ \| | | | '_ \| '__/ _` |/ _ \| __/ __|   
| | | | |_| | |_) | | | (_| | (_) | |_\__ \   
|_| |_|\__, | .__/|_|  \__,_|\___/ \__|___/   
       |___/|_|                               
 _                _                     _     
| |__   __ _  ___| | ___   _ _ __   ___| |__  
| '_ \ / _` |/ __| |/ / | | | '_ \ / __| '_ \ 
| |_) | (_| | (__|   <| |_| | |_) |\__ \ | | |
|_.__/ \__,_|\___|_|\_\\__,_| .__(_)___/_| |_|
                            |_|               

EOF

# ------------------------
# Detection helpers (same as install.sh)
# ------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  echo "linux" ;;
    Darwin) echo "macos" ;;
    *)      echo "unknown" ;;
  esac
}

is_arch() {
  [[ -f /etc/arch-release ]] && return 0
  command -v pacman >/dev/null 2>&1 && return 0
  return 1
}

is_nixos() {
  [[ -e /etc/NIXOS ]] && return 0
  grep -qi '^ID=nixos' /etc/os-release 2>/dev/null && return 0
  return 1
}

is_omarchy() {
  command -v omarchy-menu >/dev/null 2>&1 && return 0
  [[ -d "$HOME/.local/share/omarchy" ]] && return 0
  [[ -d "/usr/share/omarchy" ]] && return 0
  return 1
}

choose_layer() {
  if is_omarchy && [[ -d "$ACTIVE_DIR/omarchy" ]]; then
    echo "omarchy"
    return 0
  fi

  if is_arch && [[ -d "$ACTIVE_DIR/arch" ]]; then
    echo "arch"
    return 0
  fi

  if is_nixos && [[ -d "$ACTIVE_DIR/nixos" ]]; then
    echo "nixos"
    return 0
  fi

  if [[ -d "$ACTIVE_DIR/linux" ]]; then
    echo "linux"
    return 0
  fi

  echo ""
}

echo -e "\n📦 Backing up hyprdots targets before installation...\n"

backup_item() {
  local target="$1"
  if [[ -e "$target" && ! -L "$target" ]]; then
    if [[ -e "$target.bak" ]]; then
      echo "⚠️  Backup already exists: $target.bak (skipped)"
    else
      mv "$target" "$target.bak"
      echo "🗂  Backed up: $target → $target.bak"
    fi
  fi
}

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

backup_config_scope() {
  local layer_dir="$1"
  local cfg="$layer_dir/.config"
  [[ -d "$cfg" ]] || return 0

  echo "⚙️  .config scope: $cfg"
  find "$cfg" -mindepth 1 -maxdepth 1 | while read -r entry; do
    local name target
    name="$(basename "$entry")"
    target="$HOME/.config/$name"
    backup_item "$target"
  done
}

backup_layer() {
  local layer_dir="$1"
  [[ -d "$layer_dir" ]] || return 0
  echo "🔍 Scanning: $layer_dir"
  backup_home_scope "$layer_dir"
  backup_config_scope "$layer_dir"
}

OS="$(detect_os)"
LAYER="$(choose_layer)"

echo "📦 OS: $OS"
echo "📦 Scanning shared layer: active/shared"
backup_layer "$ACTIVE_DIR/shared"

if [[ -n "$LAYER" ]]; then
  echo "📦 Scanning OS layer: active/$LAYER"
  backup_layer "$ACTIVE_DIR/$LAYER"
else
  echo "ℹ️  No OS layer matched/found under active/. (Only shared scanned.)"
fi

echo -e "\n✅ Backup complete. You’re ready to install."
