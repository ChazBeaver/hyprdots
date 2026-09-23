#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")" &>/dev/null && pwd)"
THEMES_LOCK="${THEMES_LOCK:-$REPO_DIR/config/themes.lock.tsv}"
source "$REPO_DIR/lib/log.sh"
source "$REPO_DIR/lib/themes.sh"

usage() {
  cat <<'USAGE'
Usage: ./themes.sh <command> [args]

  status                 Show every theme directory and lock entry with its owner.
  pin <slug>... | --all  Pin themes cloned by `omarchy theme install` at their
                         current commit. The clone becomes the managed source.
  unpin <slug>...        Drop themes from the lock; they stay installed, unmanaged.
  update <slug>... | --all
                         Move pins to the tip of each source's default branch,
                         then check the sources out at the new commit.
  draft <slug>...        Move hand-made themes into the private drafts
                         repository, push, and pin them.

Pins live in config/themes.lock.tsv; commit that file to keep them.
USAGE
}

unpinned_clones() {
  local entry slug
  for entry in "$HOME/.config/omarchy/themes"/*/; do
    [[ -d "$entry" && ! -L "${entry%/}" && -d "$entry/.git" ]] || continue
    slug="$(basename "$entry")"
    theme_lock_has_slug "$slug" || printf '%s\n' "$slug"
  done
}

all_source_ids() {
  awk -F'\t' '$1 !~ /^#/ && NF >= 4 { print $2 }' "$THEMES_LOCK" | sort -u
}

source_ids_for_slugs() {
  local slug
  for slug in "$@"; do
    theme_lock_entry "$slug" | cut -f2
  done | sort -u
}

command_name="${1:-}"
[[ $# -gt 0 ]] && shift
status=0

case "$command_name" in
  status)
    [[ $# -eq 0 ]] || { usage >&2; exit 64; }
    theme_status
    ;;
  pin)
    if [[ "${1:-}" == "--all" ]]; then
      mapfile -t slugs < <(unpinned_clones)
      (( ${#slugs[@]} )) || { log_ok "Every installed theme clone is already pinned"; exit 0; }
    else
      slugs=("$@")
    fi
    (( ${#slugs[@]} )) || { usage >&2; exit 64; }
    for slug in "${slugs[@]}"; do theme_pin "$slug" || status=1; done
    ;;
  unpin)
    (( $# )) || { usage >&2; exit 64; }
    for slug in "$@"; do theme_unpin "$slug" || status=1; done
    ;;
  update)
    if [[ "${1:-}" == "--all" ]]; then
      mapfile -t source_ids < <(all_source_ids)
    else
      (( $# )) || { usage >&2; exit 64; }
      for slug in "$@"; do
        theme_lock_has_slug "$slug" || { log_err "Not pinned: $slug"; status=1; }
      done
      mapfile -t source_ids < <(source_ids_for_slugs "$@")
    fi
    for source_id in "${source_ids[@]}"; do
      [[ -n "$source_id" ]] || continue
      theme_update_source "$source_id" || status=1
    done
    reconcile_locked_themes || status=1
    ;;
  draft)
    (( $# )) || { usage >&2; exit 64; }
    for slug in "$@"; do theme_draft "$slug" || status=1; done
    reconcile_locked_themes || status=1
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
exit "$status"
