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

  # Omarchy derives colors.toml from alacritty.toml for themes that predate it.
  [[ -f "$directory/colors.toml" || -f "$directory/alacritty.toml" ]] || {
    log_err "Locked theme is missing colors.toml (or legacy alacritty.toml): $slug"
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
  actual_repository="$(git -C "$directory" config --get remote.origin.url 2>/dev/null || true)"
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
  local source_id="$1" repository="$2" commit="$3" target="$4"
  local stage

  if [[ "${HYPRDOTS_OFFLINE:-0}" == "1" ]]; then
    log_err "Theme source is missing and cannot be cloned offline: $source_id"
    return 1
  fi
  validate_theme_repository_url "$repository" || {
    log_err "Unsafe locked theme repository URL: $repository"
    return 1
  }

  mkdir -p "$(dirname "$target")"
  stage="$(mktemp -d "$(dirname "$target")/.hyprdots-theme.XXXXXX")"
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

# A whole-repository theme (subdirectory ".") is checked out directly at
# ~/.config/omarchy/themes/<slug>. Omarchy only strips executable files from a
# theme whose directory is a real git clone, never from a symlink, so pinning
# through a link would silently lift that protection. Multi-theme sources live
# under ~/.local/share/hyprdots/theme-sources and are linked per theme.
theme_source_checkout_dir() {
  local source_id="$1" whole_repository="$2"

  if [[ "$whole_repository" == 1 ]]; then
    printf '%s\n' "$HOME/.config/omarchy/themes/$source_id"
  else
    printf '%s\n' "$HOME/.local/share/hyprdots/theme-sources/$source_id"
  fi
}

# Earlier layouts linked whole-repository themes from theme-sources; move such
# a checkout into place so Omarchy sees a real clone again.
materialize_linked_theme_source() {
  local target="$1" linked

  linked="$(readlink -f "$target" 2>/dev/null || true)"
  [[ -n "$linked" && -d "$linked/.git" &&
     "$linked" == "$HOME/.local/share/hyprdots/theme-sources/"* ]] || {
    log_err "Refusing foreign link at pinned theme path: $target -> $(readlink "$target")"
    return 1
  }
  unlink "$target"
  mv -- "$linked" "$target"
  log_replace "Materialized theme clone in place: $target"
}

reconcile_theme_source() {
  local source_id="$1" repository="$2" commit="$3" whole_repository="$4"
  local target backup_root

  target="$(theme_source_checkout_dir "$source_id" "$whole_repository")"
  if [[ -L "$target" ]]; then
    if [[ "$whole_repository" == 1 ]]; then
      materialize_linked_theme_source "$target"
    else
      log_err "Refusing symlink at managed theme source path: $target"
      return 1
    fi
  fi
  if [[ -e "$target" && ! -d "$target/.git" && "$whole_repository" == 1 ]]; then
    backup_root="${THEME_BACKUP_ROOT:-$HOME/.local/state/hyprdots/backups/$(date +%Y%m%d-%H%M%S)/themes}"
    THEME_BACKUP_ROOT="$backup_root"
    mkdir -p "$backup_root"
    mv -- "$target" "$backup_root/$source_id"
    log_backup "$target -> $backup_root/$source_id"
  fi
  if [[ -e "$target" ]]; then
    reconcile_existing_theme_source "$source_id" "$repository" "$commit" "$target"
  else
    install_theme_source "$source_id" "$repository" "$commit" "$target"
  fi
}

reconcile_locked_theme_link() {
  local slug="$1" source_id="$2" repository="$3" commit="$4" subdirectory="$5"
  local source_dir theme_dir target actual backup_root

  if [[ "$subdirectory" == "." ]]; then
    target="$HOME/.config/omarchy/themes/$slug"
    verify_theme_contents "$slug" "$target"
    log_ok "Pinned theme clone is in place: $slug"
    return 0
  fi

  source_dir="$HOME/.local/share/hyprdots/theme-sources/$source_id"
  theme_dir="$(realpath -m "$source_dir/$subdirectory")"
  [[ "$theme_dir" == "$source_dir/"* ]] || {
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
  local slug source_id repository commit subdirectory THEME_BACKUP_ROOT=""
  local -A source_repositories=() source_commits=() source_whole=() seen_slugs=()

  [[ -f "$THEMES_LOCK" ]] || {
    log_err "Missing locked theme manifest: $THEMES_LOCK"
    return 1
  }
  mkdir -p "$HOME/.local/share/hyprdots/theme-sources" "$HOME/.config/omarchy/themes"

  collect_theme_source() {
    local item_slug="$1" item_source="$2" item_repository="$3" item_commit="$4" item_subdirectory="$5"
    local whole=0
    if [[ -n "${seen_slugs[$item_slug]+_}" ]]; then
      log_err "Duplicate locked theme slug: $item_slug"
      return 1
    fi
    seen_slugs[$item_slug]=1
    if [[ "$item_subdirectory" == "." ]]; then
      whole=1
      [[ "$item_slug" == "$item_source" ]] || {
        log_err "A whole-repository theme must use its slug as source id: $item_slug ($item_source)"
        return 1
      }
    fi
    if [[ -n "${source_repositories[$item_source]+_}" &&
          ( "${source_repositories[$item_source]}" != "$item_repository" ||
            "${source_commits[$item_source]}" != "$item_commit" ||
            "${source_whole[$item_source]}" != "$whole" ) ]]; then
      log_err "Theme source has conflicting repository, commit, or layout: $item_source"
      return 1
    fi
    source_repositories[$item_source]="$item_repository"
    source_commits[$item_source]="$item_commit"
    source_whole[$item_source]="$whole"
  }
  locked_themes_each collect_theme_source

  for source_id in "${!source_repositories[@]}"; do
    reconcile_theme_source "$source_id" "${source_repositories[$source_id]}" \
      "${source_commits[$source_id]}" "${source_whole[$source_id]}"
  done
  locked_themes_each reconcile_locked_theme_link
}

# --- Lock editing and the themes.sh workflow -------------------------------

theme_slug_valid() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ && "$1" != *--* ]]
}

# Omarchy clones the URL as typed; the lock wants a canonical GitHub URL with .git.
normalize_theme_repository_url() {
  local url="${1%/}"
  [[ "$url" == *.git ]] || url="$url.git"
  printf '%s\n' "$url"
}

theme_lock_entry() {
  awk -F'\t' -v slug="$1" '$1 == slug { print; exit }' "$THEMES_LOCK"
}

theme_lock_has_slug() {
  [[ -n "$(theme_lock_entry "$1")" ]]
}

theme_lock_source_entries() {
  awk -F'\t' -v id="$1" '$1 !~ /^#/ && $2 == id' "$THEMES_LOCK"
}

theme_lock_rewrite() {
  local tmp
  tmp="$(mktemp "$THEMES_LOCK.XXXXXX")"
  cat > "$tmp"
  mv -- "$tmp" "$THEMES_LOCK"
}

theme_lock_remove_slug() {
  awk -F'\t' -v slug="$1" '$1 != slug' "$THEMES_LOCK" | theme_lock_rewrite
}

theme_lock_set_source_commit() {
  awk -F'\t' -v OFS='\t' -v id="$1" -v commit="$2" \
    '$1 !~ /^#/ && $2 == id { $4 = commit } { print }' "$THEMES_LOCK" | theme_lock_rewrite
}

theme_lock_append() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$THEMES_LOCK"
}

theme_sources_dir() {
  printf '%s\n' "$HOME/.local/share/hyprdots/theme-sources"
}

theme_install_dir() {
  printf '%s\n' "$HOME/.config/omarchy/themes/$1"
}

# Pin a theme that `omarchy theme install` cloned. The existing clone becomes
# the managed source checkout, so nothing is downloaded twice.
# Pin a theme that `omarchy theme install` cloned. The clone stays exactly where
# Omarchy put it, as a real directory, so Omarchy keeps treating it as a
# repository theme and stripping anything executable from it.
theme_pin() {
  local slug="$1"
  local path repository commit

  theme_slug_valid "$slug" || { log_err "Invalid theme slug: $slug"; return 1; }
  path="$(theme_install_dir "$slug")"

  if theme_lock_has_slug "$slug"; then
    log_ok "Already pinned: $slug"
    return 0
  fi
  if [[ -L "$path" ]]; then
    log_err "Refusing foreign theme link: $path -> $(readlink "$path")"
    return 1
  fi
  if [[ ! -d "$path/.git" ]]; then
    if [[ -f "$path/colors.toml" ]]; then
      log_err "$slug is hand-made, not a clone; persist it with: ./themes.sh draft $slug"
    else
      log_err "No installed git theme at $path"
    fi
    return 1
  fi
  repository="$(git -C "$path" config --get remote.origin.url 2>/dev/null || true)"
  repository="$(normalize_theme_repository_url "$repository")"
  validate_theme_repository_url "$repository" || {
    log_err "Theme origin is not a GitHub repository the lock accepts: $slug ($repository)"
    return 1
  }
  [[ -z "$(git -C "$path" status --porcelain)" ]] || {
    log_err "Refusing to pin a theme clone with local changes: $slug"
    return 1
  }
  verify_theme_contents "$slug" "$path"
  commit="$(git -C "$path" rev-parse HEAD)"

  git -C "$path" remote set-url origin "$repository"
  theme_lock_append "$slug" "$slug" "$repository" "$commit" "."
  log_link "Pinned $slug@${commit:0:12} ($repository)"
}

# Remove a theme from the lock. A single-theme checkout moves back into
# ~/.config/omarchy/themes so the theme stays installed, just unmanaged.
# Remove a theme from the lock. A whole-repository clone is left in place as an
# ordinary installed theme; a theme from a shared source is copied out of it.
theme_unpin() {
  local slug="$1"
  local entry source_id subdirectory path source_dir theme_dir

  entry="$(theme_lock_entry "$slug")"
  [[ -n "$entry" ]] || { log_err "Not pinned: $slug"; return 1; }
  IFS=$'\t' read -r _ source_id _ _ subdirectory <<< "$entry"
  path="$(theme_install_dir "$slug")"
  theme_lock_remove_slug "$slug"

  if [[ "$subdirectory" == "." ]]; then
    log_clean "Unpinned $slug; the clone at $path stays installed"
    return 0
  fi

  source_dir="$(theme_sources_dir)/$source_id"
  theme_dir="$(realpath -m "$source_dir/$subdirectory")"
  [[ -L "$path" ]] && unlink "$path"
  if [[ -d "$theme_dir" ]]; then
    cp -r -- "$theme_dir" "$path"
    log_replace "Released $slug as an unmanaged copy from source $source_id"
  else
    log_clean "Unpinned $slug"
  fi
  if [[ -z "$(theme_lock_source_entries "$source_id")" && -d "$source_dir" ]]; then
    rm -rf -- "$source_dir"
    log_clean "Removed unreferenced theme source: $source_id"
  fi
}

theme_source_default_branch() {
  git -C "$1" ls-remote --symref origin HEAD 2>/dev/null |
    awk '$1 == "ref:" { sub("refs/heads/", "", $2); print $2; exit }'
}

# Move every lock entry for a source to the tip of its upstream default branch.
# Move every lock entry for a source to the tip of its upstream default branch.
theme_update_source() {
  local source_id="$1"
  local entry subdirectory source_dir branch current new

  entry="$(theme_lock_source_entries "$source_id" | head -1)"
  [[ -n "$entry" ]] || { log_err "Unknown theme source: $source_id"; return 1; }
  IFS=$'\t' read -r _ _ _ current subdirectory <<< "$entry"
  source_dir="$(theme_source_checkout_dir "$source_id" "$([[ "$subdirectory" == "." ]] && echo 1 || echo 0)")"
  [[ ! -L "$source_dir" && -d "$source_dir/.git" ]] || {
    log_err "Theme source is not installed; run ./sync.sh first: $source_id"
    return 1
  }
  git -C "$source_dir" fetch --quiet origin || {
    log_err "Could not fetch theme source: $source_id"
    return 1
  }
  branch="$(theme_source_default_branch "$source_dir")"
  [[ -n "$branch" ]] || { log_err "Could not determine default branch: $source_id"; return 1; }
  new="$(git -C "$source_dir" rev-parse "refs/remotes/origin/$branch")"
  if [[ "$new" == "$current" ]]; then
    log_ok "Up to date: $source_id@${current:0:12}"
    return 0
  fi
  theme_lock_set_source_commit "$source_id" "$new"
  log_replace "Updated $source_id: ${current:0:12} -> ${new:0:12}"
  log_info "Review before committing: git -C $source_dir diff --stat $current $new"
}

theme_drafts_source_id() {
  printf '%s\n' "${HYPRDOTS_THEME_DRAFTS_SOURCE:-personal-drafts}"
}

theme_drafts_clone_dir() {
  printf '%s\n' "${HYPRDOTS_THEME_DRAFTS_DIR:-$(dirname "$REPO_DIR")/omarchy-theme-drafts}"
}

theme_title_from_slug() {
  local word out=""
  for word in ${1//-/ }; do
    out+="${word^} "
  done
  printf '%s\n' "${out% }"
}

# Ensure a clean, current working clone of the drafts repository and print it.
theme_drafts_checkout() {
  local repository="$1" clone_dir actual

  clone_dir="$(theme_drafts_clone_dir)"
  if [[ ! -d "$clone_dir/.git" ]]; then
    git clone --quiet -- "$repository" "$clone_dir" || {
      log_err "Could not clone drafts repository: $repository"
      return 1
    }
    log_link "$repository -> $clone_dir" >&2
  fi
  actual="$(git -C "$clone_dir" config --get remote.origin.url 2>/dev/null || true)"
  [[ "$actual" == "$repository" ]] || {
    log_err "Drafts clone has unexpected origin: $clone_dir ($actual)"
    return 1
  }
  [[ -z "$(git -C "$clone_dir" status --porcelain)" ]] || {
    log_err "Drafts clone has uncommitted changes: $clone_dir"
    return 1
  }
  git -C "$clone_dir" pull --quiet --ff-only || {
    log_err "Could not fast-forward drafts clone: $clone_dir"
    return 1
  }
  printf '%s\n' "$clone_dir"
}

theme_draft_scaffold_docs() {
  local slug="$1" source="$2" dest="$3"
  local title blurb file

  title="$(theme_title_from_slug "$slug")"
  blurb="$(sed -n '1{/^#/{s/^#[[:space:]]*//;p}}' "$source/colors.toml")"
  [[ -n "$blurb" ]] || blurb="Personal Omarchy theme."
  {
    printf '# %s\n\n%s\n\n' "$title" "$blurb"
    printf 'The palette in `colors.toml` is the source of truth. Omarchy generates matching\n'
    printf 'Quickshell, terminal, Neovim, and application themes when it is selected.\n'
  } > "$dest/README.md"
  {
    printf '# Wallpaper provenance\n\n'
    printf 'These files are retained for private personal use while provenance and\n'
    printf 'redistribution rights are being verified. Do not include them in a public\n'
    printf 'theme release until the creator, source URL, and redistribution license have\n'
    printf 'been recorded here.\n\n'
    printf '| File | Original local source | Publication status |\n| --- | --- | --- |\n'
    for file in "$dest/backgrounds"/*; do
      [[ -f "$file" ]] || continue
      printf '| `%s` | `~/.config/omarchy/themes/%s/backgrounds/%s` (hand-installed; origin not recorded) | Private; rights unverified |\n' \
        "$(basename "$file")" "$slug" "$(basename "$file")"
    done
  } > "$dest/WALLPAPERS.md"
}

# Move a hand-made theme into the drafts repository, publish it, and pin it.
theme_draft() {
  local slug="$1"
  local path source_id repository clone_dir dest commit file

  theme_slug_valid "$slug" || { log_err "Invalid theme slug: $slug"; return 1; }
  path="$(theme_install_dir "$slug")"
  source_id="$(theme_drafts_source_id)"

  theme_lock_has_slug "$slug" && { log_err "Already pinned: $slug"; return 1; }
  [[ -d "$path" && ! -L "$path" ]] || { log_err "No hand-made theme directory at $path"; return 1; }
  [[ ! -d "$path/.git" ]] || {
    log_err "$slug is a git clone; pin it with: ./themes.sh pin $slug"
    return 1
  }
  verify_theme_contents "$slug" "$path"

  repository="$(theme_lock_source_entries "$source_id" | head -1 | cut -f3)"
  [[ -n "$repository" ]] || {
    log_err "No '$source_id' entry in the lock names the drafts repository"
    return 1
  }
  clone_dir="$(theme_drafts_checkout "$repository")" || return 1
  dest="$clone_dir/themes/$slug"
  [[ ! -e "$dest" ]] || { log_err "Drafts repository already has themes/$slug"; return 1; }

  mkdir -p "$dest/backgrounds"
  cp -- "$path/colors.toml" "$dest/colors.toml"
  [[ ! -f "$path/icons.theme" ]] || cp -- "$path/icons.theme" "$dest/icons.theme"
  for file in "$path/backgrounds"/*; do
    [[ -f "$file" ]] && cp -- "$file" "$dest/backgrounds/"
  done
  chmod 644 "$dest/backgrounds"/*
  theme_draft_scaffold_docs "$slug" "$path" "$dest"
  if [[ -f "$clone_dir/README.md" ]] && grep -q '^- `themes/' "$clone_dir/README.md"; then
    awk -v line="- \`themes/$slug\` — $(theme_title_from_slug "$slug")." '
      /^- `themes\// { last = NR } { lines[NR] = $0 }
      END { for (i = 1; i <= NR; i++) { print lines[i]; if (i == last) print line } }
    ' "$clone_dir/README.md" | theme_lock_rewrite_to "$clone_dir/README.md"
  fi

  git -C "$clone_dir" add -A -- "themes/$slug" README.md
  git -C "$clone_dir" commit --quiet -m "feat: add $slug theme" || {
    log_err "Could not commit $slug in $clone_dir"
    return 1
  }
  git -C "$clone_dir" push --quiet origin HEAD || {
    log_err "Could not push drafts repository; the commit is local in $clone_dir"
    return 1
  }
  commit="$(git -C "$clone_dir" rev-parse HEAD)"

  theme_lock_set_source_commit "$source_id" "$commit"
  theme_lock_append "$slug" "$source_id" "$repository" "$commit" "themes/$slug"
  log_link "Drafted $slug into $source_id@${commit:0:12}"
}

theme_lock_rewrite_to() {
  local target="$1" tmp
  tmp="$(mktemp "$target.XXXXXX")"
  cat > "$tmp"
  mv -- "$tmp" "$target"
}

# One line per theme directory and lock entry, describing who owns it.
theme_status() {
  local themes_dir entry slug name kind detail source_id commit subdirectory
  local -A pinned=()

  themes_dir="$HOME/.config/omarchy/themes"
  printf '%-34s %-22s %s\n' "THEME" "STATE" "DETAIL"
  while IFS=$'\t' read -r slug source_id _ commit subdirectory; do
    [[ -n "$slug" && "$slug" != \#* ]] || continue
    pinned[$slug]="$source_id@${commit:0:12} ($subdirectory)"
  done < "$THEMES_LOCK"

  for entry in "$themes_dir"/*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name="$(basename "$entry")"
    if [[ -L "$entry" ]]; then
      if [[ ! -e "$entry" ]]; then
        kind="broken link"; detail="$(readlink "$entry")"
      elif [[ -n "${pinned[$name]+_}" ]]; then
        kind="pinned"; detail="${pinned[$name]}"
      else
        kind="foreign link"; detail="$(readlink "$entry")"
      fi
    elif [[ -d "$entry/.git" && -n "${pinned[$name]+_}" ]]; then
      kind="pinned"; detail="${pinned[$name]}"
    elif [[ -d "$entry/.git" ]]; then
      kind="installed, unpinned"; detail="./themes.sh pin $name"
    elif [[ -f "$entry/colors.toml" || -f "$entry/alacritty.toml" ]]; then
      kind="hand-made, unpinned"; detail="./themes.sh draft $name"
    else
      kind="empty"; detail="no colors.toml; safe to delete"
    fi
    printf '%-34s %-22s %s\n' "$name" "$kind" "$detail"
    unset 'pinned[$name]'
  done
  for name in "${!pinned[@]}"; do
    printf '%-34s %-22s %s\n' "$name" "pinned, not linked" "./sync.sh"
  done | sort
  printf '%-34s %-22s %s\n' "(stock)" "packaged" "$(command ls /usr/share/omarchy/themes 2>/dev/null | wc -l) themes in /usr/share/omarchy/themes"
}
