#!/usr/bin/env bash
# Persistent hyprdots environment helpers. Source this file; do not execute it.

ensure_hyprdots_env() {
  local repo_dir="$1"
  local env_file="$HOME/.dotfiles-env.sh"
  local escaped_repo_dir
  local expected_export="export HYPR_DOTS_DIR=\"$repo_dir\""
  local expected_alias='alias hyprdots="cd \$HYPR_DOTS_DIR"'

  mkdir -p "$(dirname "$env_file")"
  [[ -e "$env_file" ]] || touch "$env_file"

  escaped_repo_dir="${repo_dir//\\/\\\\}"
  escaped_repo_dir="${escaped_repo_dir//|/\\|}"
  escaped_repo_dir="${escaped_repo_dir//&/\\&}"

  if grep -Fqx "$expected_export" "$env_file"; then
    :
  elif grep -q '^export HYPR_DOTS_DIR=' "$env_file"; then
    sed -i "s|^export HYPR_DOTS_DIR=.*|export HYPR_DOTS_DIR=\"$escaped_repo_dir\"|" "$env_file"
  else
    printf 'export HYPR_DOTS_DIR="%s"\n' "$repo_dir" >> "$env_file"
  fi

  if grep -Fqx "$expected_alias" "$env_file"; then
    :
  elif grep -q '^alias hyprdots=' "$env_file"; then
    sed -i 's|^alias hyprdots=.*|alias hyprdots="cd \\$HYPR_DOTS_DIR"|' "$env_file"
  else
    printf '%s\n' "$expected_alias" >> "$env_file"
  fi

  export HYPR_DOTS_DIR="$repo_dir"
}
