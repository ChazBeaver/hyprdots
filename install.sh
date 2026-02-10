#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# hyprdots Install Script (active/{shared,<os-layer>}/HOME + .config)
# - Always applies: active/shared
# - Applies ONE OS layer (in priority order):
#     1) omarchy (if detected)
#     2) arch (if arch detected AND active/arch exists)
#     3) nixos (if nixos detected AND active/nixos exists)
#     4) linux (if exists)  [future-friendly fallback]
# - HOME bucket behavior matches appdots.
# ============================================================================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")" &>/dev/null && pwd)"
ACTIVE_DIR="$SCRIPT_DIR/active"

ENV_FILE="$HOME/.dotfiles-env.sh"
VAR_NAME="HYPR_DOTS_DIR"

# ------------------------
# Detection helpers
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

# Choose ONE OS layer directory name under active/
choose_layer() {
  # Priority matters
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

  # Future-friendly generic fallback if you add it
  if [[ -d "$ACTIVE_DIR/linux" ]]; then
    echo "linux"
    return 0
  fi

  echo ""  # no layer
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
# Symlink helper (same semantics as appdots)
# ------------------------
link_item() {
  local source="$1"
  local target="$2"

  if [[ -e "$target" || -L "$target" ]]; then
    if [[ "$(readlink "$target" 2>/dev/null || true)" == "$source" ]]; then
      echo "✅ Already linked: $target"
    else
      echo "⚠️  Skipped existing: $target"
    fi
  else
    mkdir -p "$(dirname "$target")"
    ln -s "$source" "$target"
    echo "🔗 Linked: $source → $target"
  fi
}

# ------------------------
# Install HOME scope (bucketed) → $HOME/
# active/<layer>/HOME/<bucket>/<item> -> $HOME/<item>
# ------------------------
install_home_scope() {
  local layer_dir="$1"
  local home_path="$layer_dir/HOME"
  [[ -d "$home_path" ]] || return 0

  echo "🏠 Installing HOME contents from: $home_path"
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
# Install .config scope → ~/.config/
# active/<layer>/.config/<entry> -> ~/.config/<entry>
# (dir OR file)
# ------------------------
install_config_scope() {
  local layer_dir="$1"
  local cfg="$layer_dir/.config"
  [[ -d "$cfg" ]] || return 0

  echo "⚙️  Installing .config contents from: $cfg"
  find "$cfg" -mindepth 1 -maxdepth 1 | while read -r entry; do
    local name target
    name="$(basename "$entry")"
    target="$HOME/.config/$name"
    link_item "$entry" "$target"
  done
}

install_layer() {
  local layer_dir="$1"
  [[ -d "$layer_dir" ]] || return 0
  echo "🔍 Processing: $layer_dir"
  install_home_scope "$layer_dir"
  install_config_scope "$layer_dir"
}

# ------------------------
# Banner
# ------------------------
cat <<'EOF'

 _   ___   ___________________ _____ _____ _____ 
| | | \ \ / / ___ \ ___ \  _  \  _  |_   _/  ___|
| |_| |\ V /| |_/ / |_/ / | | | | | | | | \ `--. 
|  _  | \ / |  __/|    /| | | | | | | | |  `--. \
| | | | | | | |   | |\ \| |/ /\ \_/ / | | /\__/ /
\_| |_/ \_/ \_|   \_| \_|___/  \___/  \_/ \____/ 
                                                 
              Installing hyprdots

EOF

OS="$(detect_os)"
LAYER="$(choose_layer)"

echo "📦 OS: $OS"
echo "📦 Applying shared layer: active/shared"
install_layer "$ACTIVE_DIR/shared"

if [[ -n "$LAYER" ]]; then
  echo "📦 Applying OS layer: active/$LAYER"
  install_layer "$ACTIVE_DIR/$LAYER"
else
  echo "ℹ️  No OS layer matched/found under active/. (Only shared applied.)"
fi

echo "✅ Finished installing hyprdots."
