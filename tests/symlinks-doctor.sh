#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
fixture_dir="$(mktemp -d)"
trap 'rm -rf -- "$fixture_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_home="$fixture_dir/home"
manifest="$fixture_dir/links.tsv"
retired="$fixture_dir/retired-links.txt"
target="$test_home/.config/demo/managed"
mkdir -p "$(dirname "$target")"
printf 'README.md\t.config/demo/managed\n' > "$manifest"
: > "$retired"

run_doctor() {
  HOME="$test_home" LINKS_MANIFEST="$manifest" RETIRED_LINKS="$retired" \
    bash "$REPO_DIR/doctor/symlinks.sh" > "$fixture_dir/out" 2>&1
}

ln -s "$REPO_DIR/README.md" "$target"
run_doctor || fail "a correct link was reported as drift"

# Missing and stale hyprdots links are repaired by sync, so doctor says so.
rm "$target"
! run_doctor || fail "a missing link passed"
grep -q 'Missing managed link' "$fixture_dir/out" || fail "missing link was not named"
grep -q 'run ./sync.sh' "$fixture_dir/out" || fail "missing link did not point at sync"

ln -s "$REPO_DIR/MANUAL.md" "$target"
! run_doctor || fail "a stale repository link passed"
grep -q 'Wrong link' "$fixture_dir/out" || fail "stale repository link was not named"
rm "$target"

# Sync refuses a real path or a foreign link; doctor must name the blocker
# instead of sending the user to sync.
printf 'owned by something else\n' > "$target"
! run_doctor || fail "a real path at a managed target passed"
grep -q 'Real path blocks managed link' "$fixture_dir/out" || fail "real path was not named as a blocker"
grep -q 'Sync cannot replace a blocked path' "$fixture_dir/out" || fail "real path did not explain why sync cannot fix it"
grep -q 'Ownership drift detected; run ./sync.sh' "$fixture_dir/out" && fail "real path was reported as sync-fixable"
rm "$target"

printf 'elsewhere\n' > "$fixture_dir/foreign"
ln -s "$fixture_dir/foreign" "$target"
! run_doctor || fail "a foreign link at a managed target passed"
grep -q 'Foreign symlink blocks managed link' "$fixture_dir/out" || fail "foreign link was not named as a blocker"

printf 'PASS: symlink doctor separates sync-fixable drift from paths that block sync\n'
