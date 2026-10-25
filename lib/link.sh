#!/usr/bin/env bash
# Safe, manifest-driven link installation. Depends on lib/log.sh.

path_points_into_repo() {
  local path="$1" resolved
  [[ -L "$path" ]] || return 1
  resolved="$(readlink -f -- "$path" 2>/dev/null || true)"
  [[ "$resolved" == "$REPO_DIR" || "$resolved" == "$REPO_DIR/"* ]]
}

prepare_managed_parent() {
  local target="$1"
  if [[ -L "$target" ]]; then
    if path_points_into_repo "$target"; then
      unlink "$target" || return 1
      mkdir -p "$target" || return 1
      log_replace "Materialized legacy repository link: $target"
    else
      log_err "Refusing foreign parent symlink: $target -> $(readlink "$target")"
      return 1
    fi
  elif [[ -e "$target" && ! -d "$target" ]]; then
    log_err "Expected a directory but found a file: $target"
    return 1
  else
    mkdir -p "$target" || return 1
  fi
}

# Callers run these in conditionals, where errexit is off, so every failure
# is returned explicitly.
prepare_config_roots() {
  prepare_managed_parent "$HOME/.config" &&
    prepare_managed_parent "$HOME/.config/hypr" &&
    prepare_managed_parent "$HOME/.config/omarchy" &&
    prepare_managed_parent "$HOME/.config/omarchy/plugins" &&
    prepare_managed_parent "$HOME/.local" &&
    prepare_managed_parent "$HOME/.local/bin"
}

remove_retired_repo_links() {
  local target_rel target
  [[ -f "$RETIRED_LINKS" ]] || return 0
  while IFS= read -r target_rel; do
    [[ -n "$target_rel" && "$target_rel" != \#* ]] || continue
    target="$HOME/$target_rel"
    if path_points_into_repo "$target"; then
      unlink "$target" || return 1
      log_clean "Retired repository link: $target"
    fi
  done < "$RETIRED_LINKS"
}

link_item() {
  local source="$1" target="$2" actual

  if [[ ! -e "$source" && ! -L "$source" ]]; then
    log_err "Manifest source is missing: $source"
    return 1
  fi

  if [[ -L "$target" ]]; then
    actual="$(readlink "$target")"
    if [[ "$actual" == "$source" ]]; then
      log_ok "Already linked: $target"
      return 0
    fi
    if path_points_into_repo "$target"; then
      unlink "$target" || return 1
      log_replace "Replacing stale hyprdots link: $target"
    else
      log_err "Refusing foreign symlink: $target -> $actual"
      return 1
    fi
  elif [[ -e "$target" ]]; then
    log_err "Refusing real path: $target (run ./backup.sh first)"
    return 1
  fi

  mkdir -p "$(dirname "$target")" || return 1
  ln -s "$source" "$target" || return 1
  log_link "$source -> $target"
}

# Returns 2 when the managed parents or the manifest itself are unusable, and
# 1 when only individual paths were refused. A refused path must not keep the
# remaining links, themes, or plugins from converging.
install_manifest() {
  local link_failures=0

  prepare_config_roots || return 2
  remove_retired_repo_links || return 2
  install_manifest_item() {
    link_item "$@" || link_failures=$((link_failures + 1))
  }
  manifest_each install_manifest_item || return 2
  (( link_failures == 0 )) || {
    log_err "$link_failures managed path(s) could not be linked"
    return 1
  }
}
