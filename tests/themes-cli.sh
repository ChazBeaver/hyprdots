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

git_commit() { git -C "$1" -c user.name=Test -c user.email=test@example.invalid commit -qm "$2"; }
make_theme() { mkdir -p "$1/backgrounds"; printf 'mode = "dark"\nbackground = "#111111"\n' > "$1/colors.toml"; printf 'image\n' > "$1/backgrounds/bg.png"; }

# Upstream community theme reachable through a rewritten GitHub URL.
upstream="$fixture_dir/upstream"
make_theme "$upstream"
git -C "$upstream" init -q -b main
git -C "$upstream" add . && git_commit "$upstream" initial
c1="$(git -C "$upstream" rev-parse HEAD)"

# Upstream drafts repository (bare, so pushes land) seeded with one theme.
drafts_seed="$fixture_dir/drafts-seed"
make_theme "$drafts_seed/themes/existing"
printf '# Drafts\n\n## Layout\n\n- `themes/existing` — Existing.\n' > "$drafts_seed/README.md"
git -C "$drafts_seed" init -q -b main
git -C "$drafts_seed" add . && git_commit "$drafts_seed" seed
drafts_bare="$fixture_dir/drafts.git"
git clone -q --bare "$drafts_seed" "$drafts_bare"
d1="$(git -C "$drafts_bare" rev-parse HEAD)"

export HOME="$fixture_dir/home"
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
export THEMES_LOCK="$fixture_dir/themes.lock.tsv"
export HYPRDOTS_THEME_DRAFTS_DIR="$fixture_dir/drafts-clone"
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0="url.$upstream.insteadOf" GIT_CONFIG_VALUE_0="https://github.com/example/omarchy-demo-theme.git"
export GIT_CONFIG_KEY_1="url.$drafts_bare.insteadOf" GIT_CONFIG_VALUE_1="git@github.com:example/drafts.git"
themes="$HOME/.config/omarchy/themes"
sources="$HOME/.local/share/hyprdots/theme-sources"
mkdir -p "$themes"
printf '# header\nexisting\tpersonal-drafts\tgit@github.com:example/drafts.git\t%s\tthemes/existing\n' "$d1" > "$THEMES_LOCK"

# pin adopts the clone Omarchy made, without .git on its origin URL.
git clone -q "$upstream" "$themes/demo"
git -C "$themes/demo" remote set-url origin https://github.com/example/omarchy-demo-theme
"$REPO_DIR/themes.sh" pin demo >/dev/null || fail "pin failed"
[[ ! -L "$themes/demo" && -d "$themes/demo/.git" && ! -e "$sources/demo" ]] || fail "pin did not leave the clone in place"
grep -qx "demo	demo	https://github.com/example/omarchy-demo-theme.git	$c1	." "$THEMES_LOCK" || fail "pin wrote the wrong lock entry"
[[ "$(git -C "$themes/demo" config --get remote.origin.url)" == https://github.com/example/omarchy-demo-theme.git ]] || fail "pin did not normalize origin"
"$REPO_DIR/themes.sh" pin demo >/dev/null || fail "pin is not idempotent"
"$REPO_DIR/themes.sh" status > "$fixture_dir/status.out" || fail "status failed"; grep -q "^demo .*pinned .*demo@" "$fixture_dir/status.out" || fail "status does not show the pin"

# update follows the upstream default branch.
printf 'accent = "#ff0000"\n' >> "$upstream/colors.toml"
git -C "$upstream" add . && git_commit "$upstream" second
c2="$(git -C "$upstream" rev-parse HEAD)"
"$REPO_DIR/themes.sh" update demo >/dev/null || fail "update failed"
grep -q "	$c2	" "$THEMES_LOCK" || fail "update did not move the pin"
[[ "$(git -C "$themes/demo" rev-parse HEAD)" == "$c2" ]] || fail "update did not check out the new commit"
"$REPO_DIR/themes.sh" update --all >/dev/null || fail "update --all failed"

# unpin releases the clone back to Omarchy.
"$REPO_DIR/themes.sh" unpin demo >/dev/null || fail "unpin failed"
grep -q '^demo	' "$THEMES_LOCK" && fail "unpin left the lock entry"
[[ ! -L "$themes/demo" && -d "$themes/demo/.git" ]] || fail "unpin removed the clone"
"$REPO_DIR/themes.sh" status > "$fixture_dir/status.out" || fail "status failed after unpin"
grep -q '^demo .*installed, unpinned' "$fixture_dir/status.out" || fail "status does not show the released clone"

# A legacy symlink layout is materialized back into a real clone by sync.
"$REPO_DIR/themes.sh" pin demo >/dev/null || fail "re-pin failed"
mv "$themes/demo" "$sources/demo" && ln -s "$sources/demo" "$themes/demo"
HOME="$HOME" THEMES_LOCK="$THEMES_LOCK" REPO_DIR="$REPO_DIR" bash -c '
  source "$REPO_DIR/lib/log.sh"
  source "$REPO_DIR/lib/themes.sh"
  reconcile_locked_themes
' >/dev/null || fail "reconcile of a linked clone failed"
[[ ! -L "$themes/demo" && -d "$themes/demo/.git" && ! -e "$sources/demo" ]] || fail "reconcile did not materialize the clone"
"$REPO_DIR/themes.sh" unpin demo >/dev/null || fail "second unpin failed"

# pin refuses hand-made themes; draft publishes and pins them.
make_theme "$themes/mine"
"$REPO_DIR/themes.sh" pin mine >/dev/null 2>&1 && fail "pin accepted a hand-made theme"
"$REPO_DIR/themes.sh" draft mine >/dev/null || fail "draft failed"
d2="$(git -C "$drafts_bare" rev-parse HEAD)"
[[ "$d2" != "$d1" ]] || fail "draft did not push"
grep -qx "mine	personal-drafts	git@github.com:example/drafts.git	$d2	themes/mine" "$THEMES_LOCK" || fail "draft wrote the wrong lock entry"
grep -q "existing	personal-drafts	git@github.com:example/drafts.git	$d2	" "$THEMES_LOCK" || fail "draft did not move sibling pins"
[[ -L "$themes/mine" && "$(readlink -f "$themes/mine")" == "$sources/personal-drafts/themes/mine" ]] || fail "draft did not link the theme"
[[ -f "$sources/personal-drafts/themes/mine/WALLPAPERS.md" ]] || fail "draft did not scaffold docs"
git -C "$HYPRDOTS_THEME_DRAFTS_DIR" show HEAD:README.md | grep -q 'themes/mine' || fail "draft did not list the theme in README"
find "$HOME/.local/state/hyprdots/backups" -path '*/themes/mine/colors.toml' -print -quit | grep -q . || fail "draft did not back up the hand-made copy"

# A published rename must update the shared source pins and menu links together.
cp "$THEMES_LOCK" "$fixture_dir/before-rename.tsv"
"$REPO_DIR/themes.sh" rename existing ../escape "$d2" >/dev/null 2>&1 && fail "rename accepted an unsafe slug"
"$REPO_DIR/themes.sh" rename existing renamed "$d2" >/dev/null 2>&1 && fail "rename accepted a commit without the new directory"
"$REPO_DIR/themes.sh" rename existing renamed >/dev/null 2>&1 && fail "rename accepted an unpublished directory rename"
cmp -s "$THEMES_LOCK" "$fixture_dir/before-rename.tsv" || fail "failed rename changed the lock"

mv "$HYPRDOTS_THEME_DRAFTS_DIR/themes/existing" "$HYPRDOTS_THEME_DRAFTS_DIR/themes/renamed"
git -C "$HYPRDOTS_THEME_DRAFTS_DIR" add -A && git_commit "$HYPRDOTS_THEME_DRAFTS_DIR" rename
git -C "$HYPRDOTS_THEME_DRAFTS_DIR" push -q origin HEAD
d3="$(git -C "$drafts_bare" rev-parse HEAD)"

mkdir "$themes/renamed"
"$REPO_DIR/themes.sh" rename existing renamed "$d3" >/dev/null 2>&1 && fail "rename overwrote an existing destination"
rmdir "$themes/renamed"
printf 'local change\n' > "$sources/personal-drafts/local.txt"
"$REPO_DIR/themes.sh" rename existing renamed "$d3" >/dev/null 2>&1 && fail "rename accepted a dirty source"
rm "$sources/personal-drafts/local.txt"
cmp -s "$THEMES_LOCK" "$fixture_dir/before-rename.tsv" || fail "refused rename changed the lock"

"$REPO_DIR/themes.sh" rename existing renamed "$d3" >/dev/null || fail "rename failed"
grep -qx "renamed	personal-drafts	git@github.com:example/drafts.git	$d3	themes/renamed" "$THEMES_LOCK" || fail "rename wrote the wrong lock entry"
grep -qx "mine	personal-drafts	git@github.com:example/drafts.git	$d3	themes/mine" "$THEMES_LOCK" || fail "rename did not move sibling pins"
grep -q '^existing	' "$THEMES_LOCK" && fail "rename kept the old lock entry"
[[ ! -e "$themes/existing" && ! -L "$themes/existing" ]] || fail "rename kept the old menu entry"
[[ -L "$themes/renamed" && "$(readlink -f "$themes/renamed")" == "$sources/personal-drafts/themes/renamed" ]] || fail "rename did not link the new theme"
[[ "$(git -C "$sources/personal-drafts" rev-parse HEAD)" == "$d3" ]] || fail "rename did not check out the requested commit"
"$REPO_DIR/themes.sh" status > "$fixture_dir/status.out" || fail "status failed after rename"
grep -q '^renamed .*pinned ' "$fixture_dir/status.out" || fail "status does not show the renamed pin"

# Everyday renames discover the published default-branch revision themselves.
mv "$HYPRDOTS_THEME_DRAFTS_DIR/themes/renamed" "$HYPRDOTS_THEME_DRAFTS_DIR/themes/final-name"
git -C "$HYPRDOTS_THEME_DRAFTS_DIR" add -A && git_commit "$HYPRDOTS_THEME_DRAFTS_DIR" rename-again
git -C "$HYPRDOTS_THEME_DRAFTS_DIR" push -q origin HEAD
d4="$(git -C "$drafts_bare" rev-parse HEAD)"
"$REPO_DIR/themes.sh" rename renamed final-name >/dev/null || fail "rename without a commit failed"
grep -qx "final-name	personal-drafts	git@github.com:example/drafts.git	$d4	themes/final-name" "$THEMES_LOCK" || fail "rename did not discover the published commit"
grep -qx "mine	personal-drafts	git@github.com:example/drafts.git	$d4	themes/mine" "$THEMES_LOCK" || fail "automatic rename did not move sibling pins"
[[ ! -e "$themes/renamed" && ! -L "$themes/renamed" && -f "$themes/final-name/colors.toml" ]] || fail "automatic rename did not replace the menu entry"

printf 'PASS: themes.sh pin, status, update, unpin, draft, and rename work\n'
