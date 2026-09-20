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

source_repo="$fixture_dir/source"
mkdir -p "$source_repo/themes/one/backgrounds" "$source_repo/themes/two/backgrounds"
printf 'mode = "dark"\nbackground = "#111111"\nforeground = "#eeeeee"\n' > "$source_repo/themes/one/colors.toml"
cp "$source_repo/themes/one/colors.toml" "$source_repo/themes/two/colors.toml"
printf 'image\n' > "$source_repo/themes/one/backgrounds/one.png"
printf 'image\n' > "$source_repo/themes/two/backgrounds/two.jpg"
git -C "$source_repo" init -q -b main
git -C "$source_repo" add .
git -C "$source_repo" -c user.name=Test -c user.email=test@example.invalid commit -qm initial
commit="$(git -C "$source_repo" rev-parse HEAD)"

test_home="$fixture_dir/home"
cache="$test_home/.local/share/hyprdots/theme-sources/test-source"
mkdir -p "$(dirname "$cache")" "$test_home/.config/omarchy/themes/one"
printf 'old\n' > "$test_home/.config/omarchy/themes/one/old.txt"
git clone -q "$source_repo" "$cache"
git -C "$cache" remote set-url origin git@github.com:example/themes.git

lock="$fixture_dir/themes.lock.tsv"
printf 'one\ttest-source\tgit@github.com:example/themes.git\t%s\tthemes/one\n' "$commit" > "$lock"
printf 'two\ttest-source\tgit@github.com:example/themes.git\t%s\tthemes/two\n' "$commit" >> "$lock"

HOME="$test_home" THEMES_LOCK="$lock" REPO_DIR="$REPO_DIR" bash -c '
  source "$REPO_DIR/lib/log.sh"
  source "$REPO_DIR/lib/themes.sh"
  reconcile_locked_themes
' >/dev/null || fail "theme reconciliation failed"

[[ -L "$test_home/.config/omarchy/themes/one" ]] || fail "existing theme was not replaced by a link"
[[ -L "$test_home/.config/omarchy/themes/two" ]] || fail "second theme was not linked"
find "$test_home/.local/state/hyprdots/backups" -name old.txt -print -quit | grep -q . || fail "existing theme was not backed up"

HOME="$test_home" THEMES_LOCK="$lock" REPO_DIR="$REPO_DIR" bash -c '
  source "$REPO_DIR/lib/log.sh"
  source "$REPO_DIR/lib/themes.sh"
  reconcile_locked_themes
' >/dev/null || fail "idempotent reconciliation failed"

bad_lock="$fixture_dir/bad.lock.tsv"
printf 'bad\ttest-source\tgit@github.com:example/themes.git\t%s\t../escape\n' "$commit" > "$bad_lock"
if HOME="$test_home" THEMES_LOCK="$bad_lock" REPO_DIR="$REPO_DIR" bash -c '
  source "$REPO_DIR/lib/log.sh"
  source "$REPO_DIR/lib/themes.sh"
  reconcile_locked_themes
' >/dev/null 2>&1; then
  fail "unsafe subdirectory was accepted"
fi

printf 'PASS: pinned theme reconciliation, backups, idempotence, and validation work\n'
