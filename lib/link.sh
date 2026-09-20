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
      unlink "$target"
      mkdir -p "$target"
      log_replace "Materialized legacy repository link: $target"
    else
      log_err "Refusing foreign parent symlink: $target -> $(readlink "$target")"
      return 1
    fi
  elif [[ -e "$target" && ! -d "$target" ]]; then
    log_err "Expected a directory but found a file: $target"
    return 1
  else
    mkdir -p "$target"
  fi
}

prepare_config_roots() {
  prepare_managed_parent "$HOME/.config"
  prepare_managed_parent "$HOME/.config/hypr"
  prepare_managed_parent "$HOME/.config/omarchy"
  prepare_managed_parent "$HOME/.config/omarchy/plugins"
  prepare_managed_parent "$HOME/.local"
  prepare_managed_parent "$HOME/.local/bin"
}

remove_retired_repo_links() {
  local target_rel target
  [[ -f "$RETIRED_LINKS" ]] || return 0
  while IFS= read -r target_rel; do
    [[ -n "$target_rel" && "$target_rel" != \#* ]] || continue
    target="$HOME/$target_rel"
    if path_points_into_repo "$target"; then
      unlink "$target"
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
      unlink "$target"
      log_replace "Replacing stale hyprdots link: $target"
    else
      log_err "Refusing foreign symlink: $target -> $actual"
      return 1
    fi
  elif [[ -e "$target" ]]; then
    log_err "Refusing real path: $target (run ./backup.sh first)"
    return 1
  fi

  mkdir -p "$(dirname "$target")"
  ln -s "$source" "$target"
  log_link "$source -> $target"
}

install_manifest() {
  prepare_config_roots
  remove_retired_repo_links
  manifest_each link_item
}
