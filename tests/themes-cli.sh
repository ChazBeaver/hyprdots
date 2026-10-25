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
git -C "$drafts_bare" cat-file -e HEAD:themes/mine/backgrounds/bg.png || fail "draft did not persist its wallpaper upstream"
grep -Eiq 'remain private|Do not include them in a public|Private; rights unverified' "$sources/personal-drafts/themes/mine/WALLPAPERS.md" && fail "draft regenerated a private-only wallpaper rule"
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

# Removal tests use the existing isolated home and fake only Omarchy's UI and
# native remover. No real desktop commands or installed themes are touched.
export THEME_REMOVE_TEST_DIR="$themes"
export THEME_REMOVE_TEST_LOG="$fixture_dir/native-removal.log"
export THEME_REMOVE_TEST_OPTIONS="$fixture_dir/menu-options"
export THEME_REMOVE_TEST_NOTIFICATIONS="$fixture_dir/notifications"
export THEME_REMOVE_TEST_MODE=remove THEME_REMOVE_TEST_SELECTION=demo
omarchy() {
  case "$1 $2" in
    'menu select')
      printf '%s\n' "${@:3}" > "$THEME_REMOVE_TEST_OPTIONS"
      [[ "$THEME_REMOVE_TEST_MODE" != cancel ]] || return 1
      printf '%s\n' "$THEME_REMOVE_TEST_SELECTION"
      ;;
    'theme remove')
      printf '%s\n' "$3" >> "$THEME_REMOVE_TEST_LOG"
      case "$THEME_REMOVE_TEST_MODE" in
        fail) return 42 ;;
        noop) return 0 ;;
      esac
      rm -rf -- "$THEME_REMOVE_TEST_DIR/$3"
      printf 'Removed %s\n' "$3"
      ;;
    *) return 64 ;;
  esac
}
omarchy-notification-send() { printf '%s\n' "$@" >> "$THEME_REMOVE_TEST_NOTIFICATIONS"; }
export -f omarchy omarchy-notification-send

"$REPO_DIR/themes.sh" pin demo >/dev/null || fail "re-pin before removal failed"
printf 'lost\tlost\thttps://github.com/example/omarchy-demo-theme.git\t%s\t.\n' "$c2" >> "$THEMES_LOCK"
cp "$THEMES_LOCK" "$fixture_dir/before-remove.tsv"
"$REPO_DIR/themes.sh" unpin --removed demo >/dev/null 2>&1 && fail "removed unpin accepted an installed theme"
"$REPO_DIR/themes.sh" unpin --removed ../escape >/dev/null 2>&1 && fail "removed unpin accepted an unsafe slug"
ln -s "$fixture_dir/missing" "$themes/broken"
"$REPO_DIR/themes.sh" unpin --removed broken >/dev/null 2>&1 && fail "removed unpin accepted a dangling link"
"$REPO_DIR/themes.sh" remove ../escape >/dev/null 2>&1 && fail "remove accepted an unsafe path"
"$REPO_DIR/themes.sh" remove demo extra >/dev/null 2>&1 && fail "remove accepted multiple selections"
[[ ! -e "$THEME_REMOVE_TEST_LOG" ]] || fail "invalid input reached native removal"

THEME_REMOVE_TEST_MODE=fail "$REPO_DIR/themes.sh" remove demo >/dev/null 2>&1 && fail "remove ignored native failure"
THEME_REMOVE_TEST_MODE=noop "$REPO_DIR/themes.sh" remove demo >/dev/null 2>&1 && fail "remove believed success without deletion"
[[ -d "$themes/demo" ]] || fail "failed native removal lost the theme"
chmod a-w "$THEMES_LOCK"
"$REPO_DIR/themes.sh" remove demo >/dev/null 2>&1 && fail "remove accepted a read-only lock"
chmod u+w "$THEMES_LOCK"
[[ "$(wc -l < "$THEME_REMOVE_TEST_LOG")" -eq 2 ]] || fail "read-only pin reached native removal"

# Exercise the manifest-installed launcher through a symlink, as the menu does.
mkdir -p "$fixture_dir/bin"
ln -s "$REPO_DIR/bin/linux/hyprdots-theme-remove.sh" "$fixture_dir/bin/hyprdots-theme-remove"
THEME_REMOVE_TEST_MODE=cancel "$fixture_dir/bin/hyprdots-theme-remove" >/dev/null 2>&1 && fail "cancelled picker reported success"
THEME_REMOVE_TEST_SELECTION='' "$fixture_dir/bin/hyprdots-theme-remove" >/dev/null 2>&1 && fail "empty selection reported success"
[[ ! -e "$THEME_REMOVE_TEST_NOTIFICATIONS" ]] || fail "cancelled picker emitted a notification"
THEME_REMOVE_TEST_SELECTION=final-name "$REPO_DIR/themes.sh" remove >/dev/null 2>&1 && fail "picker accepted a symlink it did not offer"
[[ "$(wc -l < "$THEME_REMOVE_TEST_LOG")" -eq 2 ]] || fail "cancelled or invalid selection reached native removal"
cmp -s "$THEMES_LOCK" "$fixture_dir/before-remove.tsv" || fail "failed removal changed the pins"

"$fixture_dir/bin/hyprdots-theme-remove" > "$fixture_dir/remove.out" || fail "menu launcher removal failed"
[[ ! -e "$themes/demo" && ! -L "$themes/demo" ]] || fail "native removal left the clone"
grep -q '^demo	' "$THEMES_LOCK" && fail "successful menu removal retained its pin"
grep -q '^lost	' "$THEMES_LOCK" || fail "menu removal pruned unrelated missing theme"
grep -Fxq demo "$THEME_REMOVE_TEST_OPTIONS" || fail "picker did not offer the clone"
grep -Fxq final-name "$THEME_REMOVE_TEST_OPTIONS" && fail "picker offered a vault symlink"
grep -q 'commit config/themes.lock.tsv' "$THEME_REMOVE_TEST_NOTIFICATIONS" || fail "launcher omitted persistence reminder"
awk -F'\t' '$1 != "demo"' "$fixture_dir/before-remove.tsv" > "$fixture_dir/expected-remove.tsv"
cmp -s "$THEMES_LOCK" "$fixture_dir/expected-remove.tsv" || fail "menu removal changed more than the selected pin"

# Explicitly named shared-source removals affect the installation, not vault
# files, sibling links, or the source cache, even after the last pin is removed.
"$REPO_DIR/themes.sh" remove mine >/dev/null || fail "shared-source removal failed"
[[ ! -e "$themes/mine" && ! -L "$themes/mine" ]] || fail "removal recreated a vault theme"
[[ -f "$sources/personal-drafts/themes/mine/colors.toml" && -f "$themes/final-name/colors.toml" ]] || fail "removal damaged the vault or sibling"
grep -q '^mine	' "$THEMES_LOCK" && fail "shared-source removal retained its pin"
unlink "$themes/final-name"
"$REPO_DIR/themes.sh" unpin --removed final-name >/dev/null || fail "prior vault removal was not recorded"
[[ ! -e "$themes/final-name" && ! -L "$themes/final-name" && -d "$sources/personal-drafts/.git" ]] || fail "last removal recreated the theme or deleted the source"
"$REPO_DIR/themes.sh" unpin --removed final-name >/dev/null || fail "removed unpin was not idempotent"
mkdir "$themes/Theme With Spaces"
"$REPO_DIR/themes.sh" remove 'Theme With Spaces' >/dev/null || fail "unmanaged native theme name was rejected"
[[ ! -d "$themes/Theme With Spaces" ]] || fail "unmanaged removal did not run"

# An atomic write failure must preserve the lock and give a recovery command.
cp "$THEMES_LOCK" "$fixture_dir/before-write-failure.tsv"
if (
  mv() { return 1; }
  export -f mv
  "$REPO_DIR/themes.sh" unpin --removed lost
) > "$fixture_dir/write-failure.out" 2>&1; then
  fail "failed lock replacement reported success"
fi
cmp -s "$THEMES_LOCK" "$fixture_dir/before-write-failure.tsv" || fail "failed replacement damaged the lock"
grep -q 'unpin --removed lost' "$fixture_dir/write-failure.out" || fail "write failure omitted the recovery command"
if (
  cat() { printf 'partial'; return 1; }
  export -f cat
  "$REPO_DIR/themes.sh" unpin --removed lost
) >/dev/null 2>&1; then
  fail "partial lock write reported success"
fi
cmp -s "$THEMES_LOCK" "$fixture_dir/before-write-failure.tsv" || fail "partial write replaced the lock"
"$REPO_DIR/themes.sh" unpin --removed lost >/dev/null || fail "prior community removal was not recorded"
grep -q '^lost	' "$THEMES_LOCK" && fail "prior community removal retained its pin"

# Explicit adoption changes a community pin into a published personal source,
# validates the new content before writing, and backs up the original clone.
vault_current="$(git -C "$sources/personal-drafts" rev-parse HEAD)"
printf 'final-name\tpersonal-drafts\tgit@github.com:example/drafts.git\t%s\tthemes/final-name\n' "$vault_current" >> "$THEMES_LOCK"
"$REPO_DIR/themes.sh" update final-name >/dev/null || fail "could not restore vault fixture"
git clone -q "$upstream" "$themes/adoptee"
git -C "$themes/adoptee" remote set-url origin https://github.com/example/omarchy-demo-theme.git
"$REPO_DIR/themes.sh" pin adoptee >/dev/null || fail "could not pin adoption fixture"
cp "$THEMES_LOCK" "$fixture_dir/before-adopt.tsv"
"$REPO_DIR/themes.sh" adopt ../escape >/dev/null 2>&1 && fail "adopt accepted an unsafe slug"
"$REPO_DIR/themes.sh" adopt adoptee short-hash >/dev/null 2>&1 && fail "adopt accepted a short hash"
"$REPO_DIR/themes.sh" adopt adoptee "$vault_current" >/dev/null 2>&1 && fail "adopt accepted a missing vault theme"
printf local > "$themes/adoptee/untracked"
"$REPO_DIR/themes.sh" adopt adoptee >/dev/null 2>&1 && fail "adopt accepted local community changes"
rm "$themes/adoptee/untracked"
cmp -s "$THEMES_LOCK" "$fixture_dir/before-adopt.tsv" || fail "failed adoption changed the lock"
[[ -d "$themes/adoptee/.git" && ! -L "$themes/adoptee" ]] || fail "failed adoption replaced the clone"

make_theme "$HYPRDOTS_THEME_DRAFTS_DIR/themes/adoptee"
ln -s backgrounds/bg.png "$HYPRDOTS_THEME_DRAFTS_DIR/themes/adoptee/preview.png"
git -C "$HYPRDOTS_THEME_DRAFTS_DIR" add themes/adoptee
git_commit "$HYPRDOTS_THEME_DRAFTS_DIR" 'feat: personal adoption fixture'
git -C "$HYPRDOTS_THEME_DRAFTS_DIR" push -q
adopted_commit="$(git -C "$HYPRDOTS_THEME_DRAFTS_DIR" rev-parse HEAD)"
"$REPO_DIR/themes.sh" adopt adoptee >/dev/null || fail "adoption failed"
expected_adoption="$(printf 'adoptee\tpersonal-drafts\tgit@github.com:example/drafts.git\t%s\tthemes/adoptee' "$adopted_commit")"
grep -Fxq "$expected_adoption" "$THEMES_LOCK" || fail "adoption recorded the wrong owner"
awk -F'\t' -v commit="$adopted_commit" '$1 == "final-name" && $2 == "personal-drafts" && $4 == commit { found=1 } END { exit !found }' "$THEMES_LOCK" || fail "adoption left sibling pins behind"
[[ -L "$themes/adoptee" && -f "$themes/adoptee/colors.toml" ]] || fail "adoption did not install the personal theme link"
[[ "$(readlink "$themes/adoptee/preview.png")" == backgrounds/bg.png ]] || fail "adoption lost the relative preview link"
find "$HOME/.local/state/hyprdots/backups" -path '*/themes/adoptee/.git' -print -quit | grep -q . || fail "original community checkout was not preserved"
cp "$THEMES_LOCK" "$fixture_dir/after-adopt.tsv"
"$REPO_DIR/themes.sh" adopt adoptee >/dev/null 2>&1 && fail "adopt accepted an existing personal theme"
cmp -s "$THEMES_LOCK" "$fixture_dir/after-adopt.tsv" || fail "repeated adoption changed the lock"

# The theme-only sync dispatches through the same source reconciler and refresh
# helper as root sync. Stub only the desktop helper in this existing fixture.
export THEME_SYNC_TEST_LOG="$fixture_dir/theme-sync.log"
python3() { printf '%s\n' "$@" >> "$THEME_SYNC_TEST_LOG"; }
export -f python3
cp "$THEMES_LOCK" "$fixture_dir/before-sync.tsv"
"$REPO_DIR/themes.sh" sync >/dev/null || fail "theme-only sync failed"
cmp -s "$THEMES_LOCK" "$fixture_dir/before-sync.tsv" || fail "sync changed committed pins"
grep -Fxq -- "$REPO_DIR/scripts/theme-activation.py" "$THEME_SYNC_TEST_LOG" || fail "sync did not refresh activation"
grep -Fxq -- "$HOME" "$THEME_SYNC_TEST_LOG" || fail "sync used the wrong desktop paths"
: > "$THEME_SYNC_TEST_LOG"
printf 'local changes\n' > "$sources/personal-drafts/untracked"
"$REPO_DIR/themes.sh" sync >/dev/null 2>&1 && fail "sync ignored a dirty source"
[[ ! -s "$THEME_SYNC_TEST_LOG" ]] || fail "sync activated after source reconciliation failed"
rm "$sources/personal-drafts/untracked"

# Links left by an earlier pin of the same slug, such as a community clone that
# an older layout linked from theme-sources before adoption, or a dangling link,
# are saved and replaced; their targets survive.
make_theme "$sources/adoptee"
rm "$themes/adoptee" && ln -s "$sources/adoptee" "$themes/adoptee"
rm "$themes/final-name" && ln -s "$fixture_dir/gone" "$themes/final-name"
"$REPO_DIR/themes.sh" sync >/dev/null || fail "sync refused a stale managed theme link"
[[ "$(readlink -f "$themes/adoptee")" == "$sources/personal-drafts/themes/adoptee" ]] || fail "stale source link was not replaced"
[[ "$(readlink -f "$themes/final-name")" == "$sources/personal-drafts/themes/final-name" ]] || fail "dangling link was not replaced"
find "$HOME/.local/state/hyprdots/backups" -path '*/themes/adoptee*' -type l -print -quit | grep -q . || fail "stale link was not saved"
[[ -f "$sources/adoptee/colors.toml" ]] || fail "replacing a stale link removed its target"

# A link to anything else is the user's and is refused, but it does not keep
# the other pinned themes from installing, and activation still waits.
make_theme "$fixture_dir/foreign-theme"
rm "$themes/adoptee" && ln -s "$fixture_dir/foreign-theme" "$themes/adoptee"
rm "$themes/final-name"
: > "$THEME_SYNC_TEST_LOG"
"$REPO_DIR/themes.sh" sync >/dev/null 2>&1 && fail "sync replaced a foreign theme link"
[[ "$(readlink "$themes/adoptee")" == "$fixture_dir/foreign-theme" ]] || fail "sync changed a foreign theme link"
[[ -L "$themes/final-name" ]] || fail "a foreign link blocked the remaining theme links"
[[ ! -s "$THEME_SYNC_TEST_LOG" ]] || fail "sync activated after a theme link conflict"
rm "$themes/adoptee"
"$REPO_DIR/themes.sh" sync >/dev/null || fail "sync did not recover after the foreign link was moved"
"$REPO_DIR/themes.sh" sync unexpected >/dev/null 2>&1 && fail "sync accepted unexpected arguments"

bash "$REPO_DIR/doctor/themes.sh" >/dev/null || fail "doctor rejected valid fixture sources"
for layout in whole shared; do
  invalid_slug="invalid-$layout"
  if [[ "$layout" == whole ]]; then
    invalid_source="$themes/$invalid_slug"
    invalid_subdirectory=.
  else
    invalid_source="$sources/$invalid_slug"
    invalid_subdirectory="themes/$invalid_slug"
    ln -s "$invalid_source/$invalid_subdirectory" "$themes/$invalid_slug"
  fi
  mkdir -p "$invalid_source/$invalid_subdirectory"
  printf 'background = "#111111"\n' > "$invalid_source/$invalid_subdirectory/colors.toml"
  git -C "$invalid_source" init -q -b main
  git -C "$invalid_source" add .
  git_commit "$invalid_source" missing-backgrounds
  git -C "$invalid_source" remote add origin https://github.com/example/invalid.git
  invalid_commit="$(git -C "$invalid_source" rev-parse HEAD)"
  printf '%s\t%s\thttps://github.com/example/invalid.git\t%s\t%s\n' \
    "$invalid_slug" "$invalid_slug" "$invalid_commit" "$invalid_subdirectory" > "$THEMES_LOCK"
  : > "$THEME_SYNC_TEST_LOG"
  bash "$REPO_DIR/doctor/themes.sh" > "$fixture_dir/invalid-doctor.out" 2>&1 && fail "doctor accepted missing $layout backgrounds"
  grep -Fq 'missing backgrounds/' "$fixture_dir/invalid-doctor.out" || fail "doctor reported the wrong failure"
  [[ ! -s "$THEME_SYNC_TEST_LOG" ]] || fail "doctor continued after invalid theme contents"
done
unset -f python3

printf 'PASS: themes.sh pin, status, update, unpin, draft, rename, adoption, sync, and coordinated removal work\n'
