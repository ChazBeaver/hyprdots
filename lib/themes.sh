#!/usr/bin/env bash
# Reconcile Omarchy themes to the exact sources in config/themes.lock.tsv.
# Depends on lib/log.sh and THEMES_LOCK. Source this file; do not execute it.

validate_theme_repository_url() {
  local repository="$1"

  [[ "$repository" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.git$ ||
     "$repository" =~ ^git@github\.com:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.git$ ]]
}

validate_theme_subdirectory() {
  local subdirectory="$1"

  [[ "$subdirectory" == "." ]] ||
    [[ "$subdirectory" =~ ^[A-Za-z0-9._/-]+$ &&
       "$subdirectory" != /* && "$subdirectory" != *..* &&
       "$subdirectory" != *//* ]]
}

locked_themes_each() {
  local callback="$1"
  local slug source_id repository commit subdirectory extra

  while IFS=$'\t' read -r slug source_id repository commit subdirectory extra; do
    [[ -n "$slug" && "$slug" != \#* ]] || continue
    if [[ ! "$slug" =~ ^[a-z0-9][a-z0-9-]*$ || "$slug" == *--* ||
          ! "$source_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ || "$source_id" == *..* ||
          -z "$repository" || ! "$commit" =~ ^[0-9a-f]{40}$ ||
          -z "$subdirectory" || -n "$extra" ]] ||
       ! validate_theme_repository_url "$repository" ||
       ! validate_theme_subdirectory "$subdirectory"; then
      log_err "Invalid locked theme entry: $slug $source_id $repository $commit $subdirectory $extra"
      return 1
    fi
    "$callback" "$slug" "$source_id" "$repository" "$commit" "$subdirectory"
  done < "$THEMES_LOCK"
}

verify_theme_contents() {
  local slug="$1" directory="$2"

  [[ -f "$directory/colors.toml" ]] || {
    log_err "Locked theme is missing colors.toml: $slug"
    return 1
  }
  [[ -d "$directory/backgrounds" ]] || {
    log_err "Locked theme is missing backgrounds/: $slug"
    return 1
  }
  find "$directory/backgrounds" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
       -o -iname '*.gif' -o -iname '*.bmp' \) -print -quit | grep -q . || {
    log_err "Locked theme has no supported background images: $slug"
    return 1
  }
}

ensure_theme_source_commit() {
  local source_id="$1" directory="$2" commit="$3"

  if git -C "$directory" cat-file -e "$commit^{commit}" 2>/dev/null; then
    return 0
  fi
  if [[ "${HYPRDOTS_OFFLINE:-0}" == "1" ]]; then
    log_err "Pinned commit for theme source $source_id is unavailable offline: $commit"
    return 1
  fi
  git -C "$directory" fetch --quiet origin "$commit" ||
    git -C "$directory" fetch --quiet origin
  git -C "$directory" cat-file -e "$commit^{commit}" 2>/dev/null || {
    log_err "Pinned commit for theme source $source_id was not found upstream: $commit"
    return 1
  }
}

reconcile_existing_theme_source() {
  local source_id="$1" repository="$2" commit="$3" directory="$4"
  local actual_repository current_commit

  [[ -d "$directory/.git" ]] || {
    log_err "Refusing non-git theme source path: $directory"
    return 1
  }
  actual_repository="$(git -C "$directory" remote get-url origin 2>/dev/null || true)"
  [[ "$actual_repository" == "$repository" ]] || {
    log_err "Refusing theme source with unexpected origin: $source_id ($actual_repository)"
    return 1
  }
  [[ -z "$(git -C "$directory" status --porcelain)" ]] || {
    log_err "Refusing to overwrite local changes in theme source: $source_id"
    return 1
  }

  ensure_theme_source_commit "$source_id" "$directory" "$commit"
  current_commit="$(git -C "$directory" rev-parse HEAD)"
  if [[ "$current_commit" != "$commit" ]]; then
    git -C "$directory" checkout --quiet --detach "$commit"
    log_replace "Restored theme source: $source_id@$commit"
  else
    log_ok "Theme source is current: $source_id@$commit"
  fi
}

install_theme_source() {
  local source_id="$1" repository="$2" commit="$3" sources_dir="$4"
  local target="$sources_dir/$source_id" stage

  if [[ "${HYPRDOTS_OFFLINE:-0}" == "1" ]]; then
    log_err "Theme source is missing and cannot be cloned offline: $source_id"
    return 1
  fi
  validate_theme_repository_url "$repository" || {
    log_err "Unsafe locked theme repository URL: $repository"
    return 1
  }

  stage="$(mktemp -d "$sources_dir/.hyprdots-theme.XXXXXX")"
  if ! git clone --quiet --no-checkout -- "$repository" "$stage"; then
    rm -rf -- "$stage"
    log_err "Failed to clone locked theme source: $source_id"
    return 1
  fi
  if ! ensure_theme_source_commit "$source_id" "$stage" "$commit" ||
     ! git -C "$stage" checkout --quiet --detach "$commit"; then
    rm -rf -- "$stage"
    return 1
  fi
  mv -- "$stage" "$target"
  log_link "$source_id@$commit -> $target"
}

reconcile_theme_source() {
  local source_id="$1" repository="$2" commit="$3"
  local sources_dir="$HOME/.local/share/hyprdots/theme-sources"
  local target="$sources_dir/$source_id"

  if [[ -L "$target" ]]; then
    log_err "Refusing symlink at managed theme source path: $target"
    return 1
  elif [[ -e "$target" ]]; then
    reconcile_existing_theme_source "$source_id" "$repository" "$commit" "$target"
  else
    install_theme_source "$source_id" "$repository" "$commit" "$sources_dir"
  fi
}

reconcile_locked_theme_link() {
  local slug="$1" source_id="$2" repository="$3" commit="$4" subdirectory="$5"
  local source_dir="$HOME/.local/share/hyprdots/theme-sources/$source_id"
  local theme_dir target actual backup_root

  theme_dir="$(realpath -m "$source_dir/$subdirectory")"
  [[ "$theme_dir" == "$source_dir" || "$theme_dir" == "$source_dir/"* ]] || {
    log_err "Locked theme escapes its source checkout: $slug ($subdirectory)"
    return 1
  }
  verify_theme_contents "$slug" "$theme_dir"

  target="$HOME/.config/omarchy/themes/$slug"
  if [[ -L "$target" ]]; then
    actual="$(readlink -f "$target" 2>/dev/null || true)"
    [[ "$actual" == "$theme_dir" ]] || {
      log_err "Refusing foreign theme link: $target -> $actual"
      return 1
    }
    log_ok "Managed theme link is current: $slug"
    return 0
  elif [[ -e "$target" ]]; then
    backup_root="${THEME_BACKUP_ROOT:-$HOME/.local/state/hyprdots/backups/$(date +%Y%m%d-%H%M%S)/themes}"
    THEME_BACKUP_ROOT="$backup_root"
    mkdir -p "$backup_root"
    mv -- "$target" "$backup_root/$slug"
    log_backup "$target -> $backup_root/$slug"
  fi

  ln -s "$theme_dir" "$target"
  log_link "$theme_dir -> $target"
}

reconcile_locked_themes() {
  local sources_dir="$HOME/.local/share/hyprdots/theme-sources"
  local slug source_id repository commit subdirectory THEME_BACKUP_ROOT=""
  local -A source_repositories=() source_commits=() seen_slugs=()

  [[ -f "$THEMES_LOCK" ]] || {
    log_err "Missing locked theme manifest: $THEMES_LOCK"
    return 1
  }
  mkdir -p "$sources_dir" "$HOME/.config/omarchy/themes"

  collect_theme_source() {
    local item_slug="$1" item_source="$2" item_repository="$3" item_commit="$4"
    if [[ -n "${seen_slugs[$item_slug]+_}" ]]; then
      log_err "Duplicate locked theme slug: $item_slug"
      return 1
    fi
    seen_slugs[$item_slug]=1
    if [[ -n "${source_repositories[$item_source]+_}" &&
          ( "${source_repositories[$item_source]}" != "$item_repository" ||
            "${source_commits[$item_source]}" != "$item_commit" ) ]]; then
      log_err "Theme source has conflicting repository or commit: $item_source"
      return 1
    fi
    source_repositories[$item_source]="$item_repository"
    source_commits[$item_source]="$item_commit"
  }
  locked_themes_each collect_theme_source

  for source_id in "${!source_repositories[@]}"; do
    reconcile_theme_source "$source_id" "${source_repositories[$source_id]}" "${source_commits[$source_id]}"
  done
  locked_themes_each reconcile_locked_theme_link
}
