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

printf 'PASS: themes.sh pin, status, update, unpin, and draft work\n'
