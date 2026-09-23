#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")/.." &>/dev/null && pwd)"
THEMES_LOCK="$REPO_DIR/config/themes.lock.tsv"
source "$REPO_DIR/lib/log.sh"
source "$REPO_DIR/lib/themes.sh"

declare -A checked_sources=() seen_slugs=()

check_locked_theme() {
  local slug="$1" source_id="$2" repository="$3" commit="$4" subdirectory="$5"
  local source_dir theme_dir target actual_repository actual_commit

  [[ -z "${seen_slugs[$slug]+_}" ]] || {
    log_err "Duplicate locked theme slug: $slug"
    return 1
  }
  seen_slugs[$slug]=1
  if [[ "$subdirectory" == "." ]]; then
    source_dir="$HOME/.config/omarchy/themes/$slug"
  else
    source_dir="$HOME/.local/share/hyprdots/theme-sources/$source_id"
  fi

  if [[ -z "${checked_sources[$source_id]+_}" ]]; then
    [[ ! -L "$source_dir" && -d "$source_dir/.git" ]] || {
      log_err "Locked theme source is not an installed git checkout: $source_id"
      return 1
    }
    actual_repository="$(git -C "$source_dir" config --get remote.origin.url 2>/dev/null || true)"
    [[ "$actual_repository" == "$repository" ]] || {
      log_err "Locked theme source origin drifted: $source_id ($actual_repository)"
      return 1
    }
    actual_commit="$(git -C "$source_dir" rev-parse HEAD 2>/dev/null || true)"
    [[ "$actual_commit" == "$commit" ]] || {
      log_err "Locked theme source commit drifted: $source_id (${actual_commit:-<missing>})"
      return 1
    }
    [[ -z "$(git -C "$source_dir" status --porcelain)" ]] || {
      log_err "Locked theme source has local changes: $source_id"
      return 1
    }
    checked_sources[$source_id]=1
  fi

  if [[ "$subdirectory" == "." ]]; then
    verify_theme_contents "$slug" "$source_dir"
    return 0
  fi
  theme_dir="$(realpath -m "$source_dir/$subdirectory")"
  [[ "$theme_dir" == "$source_dir/"* ]] || {
    log_err "Locked theme escapes its source checkout: $slug"
    return 1
  }
  verify_theme_contents "$slug" "$theme_dir"

  target="$HOME/.config/omarchy/themes/$slug"
  [[ -L "$target" ]] || {
    log_err "Locked theme is not linked into Omarchy: $slug"
    return 1
  }
  [[ "$(readlink -f "$target" 2>/dev/null || true)" == "$theme_dir" ]] || {
    log_err "Locked theme link drifted: $slug"
    return 1
  }
}

locked_themes_each check_locked_theme

# Installed themes that nothing persists yet are reported without failing.
for entry in "$HOME/.config/omarchy/themes"/*; do
  [[ -e "$entry" || -L "$entry" ]] || continue
  name="$(basename "$entry")"
  if [[ -L "$entry" && ! -e "$entry" ]]; then
    log_warn "Broken theme link: $name -> $(readlink "$entry")"
  elif [[ ! -L "$entry" && -d "$entry/.git" ]]; then
    [[ -n "${seen_slugs[$name]+_}" ]] || log_warn "Installed theme is not pinned: $name (./themes.sh pin $name)"
  elif [[ ! -L "$entry" && -d "$entry" && ( -f "$entry/colors.toml" || -f "$entry/alacritty.toml" ) ]]; then
    log_warn "Hand-made theme is not persisted: $name (./themes.sh draft $name)"
  elif [[ ! -L "$entry" && -d "$entry" ]]; then
    log_warn "Empty theme directory: $name"
  fi
done
log_ok "Pinned Omarchy themes and source checkouts are valid"
