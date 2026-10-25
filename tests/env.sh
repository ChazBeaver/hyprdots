#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="$(mktemp -d)"
trap 'rm -rf -- "$fixture_dir"' EXIT
source "$REPO_DIR/lib/env.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
env_file="$fixture_dir/install home/.dotfiles-env.sh"
original_home="$HOME"
# Include shell metacharacters to verify that sourcing preserves literal paths.
repo_dir="$fixture_dir/Projects/home/a repo & pipe|quote\"dollar\$backtick\`slash\\"
ensure_hyprdots_env "$repo_dir" "$env_file"
[[ -d "$fixture_dir/install home/Projects/home" ]] || fail 'personal repo parent was not created'
[[ "$HOME" == "$original_home" ]] || fail 'registration changed HOME'
bash -n "$env_file"
expected_alias='alias hyprdots="cd \$HYPR_DOTS_DIR"'
grep -Fxq "$expected_alias" "$env_file" || fail 'navigation alias missing'
registered="$(bash -c 'source "$1"; printf "%s" "$HYPR_DOTS_DIR"' bash "$env_file")"
[[ "$registered" == "$repo_dir" ]] || fail 'literal checkout path was not preserved'
cp "$env_file" "$fixture_dir/expected"
ensure_hyprdots_env "$repo_dir" "$env_file"
cmp -s "$env_file" "$fixture_dir/expected" || fail 'registration is not idempotent'
# Stale duplicates must not override the repaired export/alias when sourced.
printf '%s\n' 'export FOREIGN_DIR="/keep/me"' 'alias foreign="keep"' \
  'export HYPR_DOTS_DIR="/stale/one"' 'export HYPR_DOTS_DIR="/stale/two"' \
  'alias hyprdots="wrong-one"' 'alias hyprdots="wrong-two"' \
  '  export    HYPR_DOTS_DIR="/stale/indented"' '  alias   hyprdots="wrong-indented"' > "$env_file"

ensure_hyprdots_env "$repo_dir" "$env_file"
[[ "$(grep -c '^export HYPR_DOTS_DIR=' "$env_file")" == 1 ]] || fail 'duplicate exports remain'
[[ "$(grep -c '^alias hyprdots=' "$env_file")" == 1 ]] || fail 'duplicate aliases remain'
grep -Fxq 'export FOREIGN_DIR="/keep/me"' "$env_file" || fail 'foreign export changed'
grep -Fxq 'alias foreign="keep"' "$env_file" || fail 'foreign alias changed'
grep -Fxq "$expected_alias" "$env_file" || fail 'stale alias was not repaired'
registered="$(bash -c 'source "$1"; printf "%s" "$HYPR_DOTS_DIR"' bash "$env_file")"
[[ "$registered" == "$repo_dir" ]] || fail 'stale export was not repaired'

printf 'PASS: registration creates the parent, preserves literal paths and foreign entries, repairs duplicates, and is idempotent\n'
