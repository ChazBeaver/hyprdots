#!/usr/bin/env bash
# Helpers for reading config/links.tsv. Source this file; do not execute it.

manifest_each() {
  local callback="$1"
  local source_rel target_rel extra

  while IFS=$'\t' read -r source_rel target_rel extra; do
    [[ -n "$source_rel" && "$source_rel" != \#* ]] || continue
    if [[ -z "$target_rel" || -n "$extra" || "$source_rel" == /* || "$target_rel" == /* ||
          "$source_rel" == *".."* || "$target_rel" == *".."* ]]; then
      log_err "Invalid ownership manifest entry: $source_rel $target_rel $extra"
      return 1
    fi
    "$callback" "$REPO_DIR/$source_rel" "$HOME/$target_rel"
  done < "$LINKS_MANIFEST"
}
