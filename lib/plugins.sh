#!/usr/bin/env bash
# Reconcile enabled third-party Omarchy plugins to config/plugins.lock.tsv.
# Depends on lib/log.sh and PLUGINS_LOCK. Source this file; do not execute it.

run_omarchy() {
  local omarchy_bin

  omarchy_bin="$(command -v omarchy 2>/dev/null || true)"
  if [[ -z "$omarchy_bin" && -x /usr/share/omarchy/bin/omarchy ]]; then
    omarchy_bin="/usr/share/omarchy/bin/omarchy"
  fi
  [[ -n "$omarchy_bin" ]] || {
    log_err "Omarchy command is unavailable"
    return 1
  }
  "$omarchy_bin" "$@"
}

validate_locked_plugin_url() {
  local repository="$1" checker

  checker="$(command -v omarchy-git-url-check 2>/dev/null || true)"
  if [[ -z "$checker" && -x /usr/share/omarchy/bin/omarchy-git-url-check ]]; then
    checker="/usr/share/omarchy/bin/omarchy-git-url-check"
  fi
  if [[ -n "$checker" ]]; then
    "$checker" "$repository" >/dev/null
    return
  fi

  # Compatibility fallback for Omarchy versions without the shared checker.
  # The lockfile currently permits only ordinary credential-free GitHub HTTPS
  # repository URLs, never git options or transport helpers.
  [[ "$repository" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.git$ &&
     "$repository" != *..* ]]
}

locked_plugins_each() {
  local callback="$1"
  local id repository commit extra

  while IFS=$'\t' read -r id repository commit extra; do
    [[ -n "$id" && "$id" != \#* ]] || continue
    if [[ ! "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ || "$id" == *..* ||
          -z "$repository" || ! "$commit" =~ ^[0-9a-f]{40}$ || -n "$extra" ]]; then
      log_err "Invalid locked plugin entry: $id $repository $commit $extra"
      return 1
    fi
    "$callback" "$id" "$repository" "$commit"
  done < "$PLUGINS_LOCK"
}

verify_locked_plugin_contents() {
  local id="$1" directory="$2"
  local manifest="$directory/manifest.json" manifest_id

  [[ -f "$manifest" ]] || {
    log_err "Locked plugin is missing its manifest: $directory"
    return 1
  }
  manifest_id="$(jq -r '.id // empty' "$manifest")"
  [[ "$manifest_id" == "$id" ]] || {
    log_err "Locked plugin id mismatch: expected $id, found ${manifest_id:-<empty>}"
    return 1
  }
  run_omarchy plugin validate "$directory" >/dev/null || {
    log_err "Locked plugin failed validation: $id"
    return 1
  }
}

ensure_locked_commit() {
  local id="$1" directory="$2" commit="$3"

  if git -C "$directory" cat-file -e "$commit^{commit}" 2>/dev/null; then
    return 0
  fi
  if [[ "${HYPRDOTS_OFFLINE:-0}" == "1" ]]; then
    log_err "Pinned commit for $id is unavailable offline: $commit"
    return 1
  fi
  git -C "$directory" fetch --quiet origin "$commit" ||
    git -C "$directory" fetch --quiet origin
  git -C "$directory" cat-file -e "$commit^{commit}" 2>/dev/null || {
    log_err "Pinned commit for $id was not found upstream: $commit"
    return 1
  }
}

reconcile_existing_plugin() {
  local id="$1" repository="$2" commit="$3" directory="$4"
  local actual_repository current_commit

  [[ -d "$directory/.git" ]] || {
    log_err "Refusing non-git locked plugin path: $directory"
    return 1
  }
  actual_repository="$(git -C "$directory" remote get-url origin 2>/dev/null || true)"
  [[ "$actual_repository" == "$repository" ]] || {
    log_err "Refusing locked plugin with unexpected origin: $id ($actual_repository)"
    return 1
  }
  [[ -z "$(git -C "$directory" status --porcelain)" ]] || {
    log_err "Refusing to overwrite local changes in locked plugin: $id"
    return 1
  }

  ensure_locked_commit "$id" "$directory" "$commit"
  current_commit="$(git -C "$directory" rev-parse HEAD)"
  if [[ "$current_commit" != "$commit" ]]; then
    git -C "$directory" checkout --quiet --detach "$commit"
    log_replace "Restored locked plugin: $id@$commit"
  else
    log_ok "Locked plugin is current: $id@$commit"
  fi
  verify_locked_plugin_contents "$id" "$directory"
}

install_locked_plugin() {
  local id="$1" repository="$2" commit="$3" plugins_dir="$4"
  local target="$plugins_dir/$id" stage

  if [[ "${HYPRDOTS_OFFLINE:-0}" == "1" ]]; then
    log_err "Locked plugin is missing and cannot be cloned offline: $id"
    return 1
  fi
  validate_locked_plugin_url "$repository" || {
    log_err "Unsafe locked plugin repository URL: $repository"
    return 1
  }

  stage="$(mktemp -d "$plugins_dir/.hyprdots-plugin.XXXXXX")"
  if ! git clone --quiet --no-checkout -- "$repository" "$stage"; then
    rm -rf -- "$stage"
    log_err "Failed to clone locked plugin: $id"
    return 1
  fi
  if ! ensure_locked_commit "$id" "$stage" "$commit" ||
     ! git -C "$stage" checkout --quiet --detach "$commit" ||
     ! verify_locked_plugin_contents "$id" "$stage"; then
    rm -rf -- "$stage"
    return 1
  fi
  mv -- "$stage" "$target"
  log_link "$id@$commit -> $target"
}

reconcile_locked_plugin() {
  local id="$1" repository="$2" commit="$3"
  local plugins_dir="$HOME/.config/omarchy/plugins" target

  target="$plugins_dir/$id"
  if [[ -L "$target" ]]; then
    log_err "Refusing symlink at locked plugin path: $target"
    return 1
  elif [[ -e "$target" ]]; then
    reconcile_existing_plugin "$id" "$repository" "$commit" "$target"
  else
    install_locked_plugin "$id" "$repository" "$commit" "$plugins_dir"
  fi
}

reconcile_locked_plugins() {
  [[ -f "$PLUGINS_LOCK" ]] || {
    log_err "Missing locked plugin manifest: $PLUGINS_LOCK"
    return 1
  }
  mkdir -p "$HOME/.config/omarchy/plugins"
  locked_plugins_each reconcile_locked_plugin
}
