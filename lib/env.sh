#!/usr/bin/env bash
# Persistent repository registration. Source this file; do not execute it.

ensure_hyprdots_env() {
  local repo_dir="$1"
  # An explicit registry path lets fixtures avoid the real home directory.
  local env_file="${2:-$HOME/.dotfiles-env.sh}"
  local escaped_repo_dir temporary
  escaped_repo_dir="${repo_dir//\\/\\\\}"
  escaped_repo_dir="${escaped_repo_dir//\"/\\\"}"
  escaped_repo_dir="${escaped_repo_dir//\$/\\\$}"
  escaped_repo_dir="${escaped_repo_dir//\`/\\\`}"
  local expected_export="export HYPR_DOTS_DIR=\"$escaped_repo_dir\""
  local expected_alias='alias hyprdots="cd \$HYPR_DOTS_DIR"'

  mkdir -p -- "$(dirname -- "$env_file")/Projects/home" || return 1
  [[ -e "$env_file" ]] || touch -- "$env_file" || return 1
  temporary="$(mktemp "${env_file}.XXXXXX")" || return 1
  # ENVIRON preserves literal backslashes; awk -v would interpret them.
  if ! DOTFILES_REGISTER_EXPORT="$expected_export" \
       DOTFILES_REGISTER_ALIAS="$expected_alias" awk '
    BEGIN {
      desired_export = ENVIRON["DOTFILES_REGISTER_EXPORT"]
      desired_alias = ENVIRON["DOTFILES_REGISTER_ALIAS"]
    }
    $0 ~ /^[[:space:]]*export[[:space:]]+HYPR_DOTS_DIR=/ {
      if (!seen_export++) print desired_export
      next
    }
    $0 ~ /^[[:space:]]*alias[[:space:]]+hyprdots=/ {
      if (!seen_alias++) print desired_alias
      next
    }
    { print }
    END {
      if (!seen_export) print desired_export
      if (!seen_alias) print desired_alias
    }
  ' "$env_file" > "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  if ! mv -- "$temporary" "$env_file"; then
    rm -f -- "$temporary"
    return 1
  fi
  export HYPR_DOTS_DIR="$repo_dir"
}
