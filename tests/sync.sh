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

# Root sync runs against the Omarchy install, so this suite needs an Omarchy
# machine like the live checks; everything it writes stays in the fixture home.
[[ -f /usr/share/omarchy/default/hypr/bootstrap.lua ]] || {
  printf 'SKIP: root sync needs an Omarchy Quattro install\n'
  exit 0
}

source_repo="$fixture_dir/source"
mkdir -p "$source_repo/themes/demo/backgrounds"
printf 'mode = "dark"\nbackground = "#111111"\n' > "$source_repo/themes/demo/colors.toml"
printf 'image\n' > "$source_repo/themes/demo/backgrounds/demo.png"
git -C "$source_repo" init -q -b main
git -C "$source_repo" add .
git -C "$source_repo" -c user.name=Test -c user.email=test@example.invalid commit -qm initial
commit="$(git -C "$source_repo" rev-parse HEAD)"

test_home="$fixture_dir/home"
cache="$test_home/.local/share/hyprdots/theme-sources/demo-source"
mkdir -p "$(dirname "$cache")"
git clone -q "$source_repo" "$cache"
git -C "$cache" remote set-url origin git@github.com:example/themes.git
git -C "$cache" checkout -q --detach "$commit"

printf 'demo\tdemo-source\tgit@github.com:example/themes.git\t%s\tthemes/demo\n' "$commit" > "$fixture_dir/themes.lock.tsv"
: > "$fixture_dir/plugins.lock.tsv"
: > "$fixture_dir/retired-links.txt"
printf 'README.md\t.config/demo/blocked\nMANUAL.md\t.config/demo/linked\n' > "$fixture_dir/links.tsv"
mkdir -p "$test_home/.config/demo"
printf 'owned by something else\n' > "$test_home/.config/demo/blocked"

run_sync() {
  HOME="$test_home" HYPRDOTS_OFFLINE=1 \
    LINKS_MANIFEST="$fixture_dir/links.tsv" RETIRED_LINKS="$fixture_dir/retired-links.txt" \
    THEMES_LOCK="$fixture_dir/themes.lock.tsv" PLUGINS_LOCK="$fixture_dir/plugins.lock.tsv" \
    bash "$REPO_DIR/sync.sh" > "$fixture_dir/out" 2>&1
}

# A refused path must not hide the later links or the theme and plugin steps.
! run_sync || fail "sync passed while a managed path was blocked"
grep -q 'Refusing real path' "$fixture_dir/out" || fail "blocked path was not reported"
[[ -L "$test_home/.config/demo/linked" ]] || fail "a later manifest link was skipped"
[[ "$(cat "$test_home/.config/demo/blocked")" == 'owned by something else' ]] || fail "blocked path was overwritten"
[[ "$(readlink "$test_home/.config/omarchy/themes/demo")" == "$cache/themes/demo" ]] ||
  fail "theme step did not run after the blocked path"
grep -q 'Reconciling pinned community plugins' "$fixture_dir/out" || fail "plugin step did not run"
grep -q 'Hyprdots sync incomplete: owned configuration' "$fixture_dir/out" || fail "incomplete sync was not summarized"
grep -q 'Hyprdots sync complete' "$fixture_dir/out" && fail "blocked sync claimed completion"

rm "$test_home/.config/demo/blocked"
run_sync || { cat "$fixture_dir/out" >&2; fail "sync failed once the path was cleared"; }
grep -q 'Hyprdots sync complete' "$fixture_dir/out" || fail "clear sync did not report completion"

# An unsafe managed parent stops sync before themes or plugins touch the home.
rm "$test_home/.config/omarchy/themes/demo"
mv "$test_home/.local/bin" "$fixture_dir/bin-elsewhere" 2>/dev/null || mkdir -p "$fixture_dir/bin-elsewhere"
ln -s "$fixture_dir/bin-elsewhere" "$test_home/.local/bin"
! run_sync || fail "sync passed with a foreign managed parent"
grep -q 'Managed configuration roots are unsafe' "$fixture_dir/out" || fail "unsafe parent was not reported"
[[ ! -e "$test_home/.config/omarchy/themes/demo" ]] || fail "themes ran after an unsafe parent"

# Sync runs the plugin step in a conditional, where errexit is off. A failed
# plugin must still fail the step when a later plugin succeeds.
plugin_repo="$fixture_dir/plugin-good"
mkdir -p "$plugin_repo"
printf '{"id":"good"}\n' > "$plugin_repo/manifest.json"
git -C "$plugin_repo" init -q -b main
git -C "$plugin_repo" add .
git -C "$plugin_repo" -c user.name=Test -c user.email=test@example.invalid commit -qm initial
plugin_commit="$(git -C "$plugin_repo" rev-parse HEAD)"
plugin_home="$fixture_dir/plugin-home"
mkdir -p "$plugin_home/.config/omarchy/plugins"
git clone -q "$plugin_repo" "$plugin_home/.config/omarchy/plugins/good"
git -C "$plugin_home/.config/omarchy/plugins/good" remote set-url origin https://github.com/example/good.git
printf 'missing\thttps://github.com/example/missing.git\t%s\ngood\thttps://github.com/example/good.git\t%s\n' \
  "$plugin_commit" "$plugin_commit" > "$fixture_dir/plugins-mixed.lock.tsv"
if HOME="$plugin_home" PLUGINS_LOCK="$fixture_dir/plugins-mixed.lock.tsv" HYPRDOTS_OFFLINE=1 REPO_DIR="$REPO_DIR" bash -c '
  set -euo pipefail
  source "$REPO_DIR/lib/log.sh"
  source "$REPO_DIR/lib/plugins.sh"
  run_omarchy() { :; }
  reconcile_locked_plugins || exit 1
' > "$fixture_dir/out" 2>&1; then
  fail "a failed plugin was hidden by a later successful one"
fi
grep -q 'Locked plugin is current: good' "$fixture_dir/out" || fail "a failed plugin kept later plugins from reconciling"
grep -q '1 locked plugin(s) could not be reconciled' "$fixture_dir/out" || fail "plugin failures were not counted"

printf 'PASS: root sync reports refused paths and failed plugins, still converges links, themes and plugins, and stops on unsafe parents\n'
