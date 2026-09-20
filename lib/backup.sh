#!/usr/bin/env bash
# Manifest-driven backup helpers. Depends on lib/log.sh and lib/manifest.sh.

BACKUP_STAMP="${BACKUP_STAMP:-$(date +%Y%m%d%H%M%S)}"

target_has_repo_link_ancestor() {
  local target="$1" parent resolved
  parent="$(dirname "$target")"
  while [[ "$parent" == "$HOME" || "$parent" == "$HOME/"* ]]; do
    if [[ -L "$parent" ]]; then
      resolved="$(readlink -f "$parent" 2>/dev/null || true)"
      if [[ "$resolved" == "$REPO_DIR" || "$resolved" == "$REPO_DIR/"* ]]; then
        return 0
      fi
      log_err "Refusing target below foreign parent symlink: $parent -> $(readlink "$parent")"
      return 2
    fi
    [[ "$parent" != "$HOME" ]] || break
    parent="$(dirname "$parent")"
  done
  return 1
}

backup_manifest_item() {
  local _source="$1" target="$2" backup ancestor_status
  if target_has_repo_link_ancestor "$target"; then
    log_info "Legacy repository parent will be migrated during sync: $target"
    return 0
  else
    ancestor_status=$?
    (( ancestor_status != 2 )) || return 1
  fi
  if [[ -e "$target" && ! -L "$target" ]]; then
    backup="$target.hyprdots-backup.$BACKUP_STAMP"
    if [[ -e "$backup" || -L "$backup" ]]; then
      log_err "Backup target already exists: $backup"
      return 1
    fi
    mv "$target" "$backup"
    log_backup "$target -> $backup"
  fi
}

backup_manifest() {
  manifest_each backup_manifest_item
}
