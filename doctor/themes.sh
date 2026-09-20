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
  local source_dir="$HOME/.local/share/hyprdots/theme-sources/$source_id"
  local theme_dir target actual_repository actual_commit

  [[ -z "${seen_slugs[$slug]+_}" ]] || {
    log_err "Duplicate locked theme slug: $slug"
    return 1
  }
  seen_slugs[$slug]=1

  if [[ -z "${checked_sources[$source_id]+_}" ]]; then
    [[ ! -L "$source_dir" && -d "$source_dir/.git" ]] || {
      log_err "Locked theme source is not an installed git checkout: $source_id"
      return 1
    }
    actual_repository="$(git -C "$source_dir" remote get-url origin 2>/dev/null || true)"
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

  theme_dir="$(realpath -m "$source_dir/$subdirectory")"
  [[ "$theme_dir" == "$source_dir" || "$theme_dir" == "$source_dir/"* ]] || {
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
log_ok "Pinned Omarchy themes and source checkouts are valid"
