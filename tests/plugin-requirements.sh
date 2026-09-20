#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
fixture_dir="$(mktemp -d)"
trap 'rm -rf -- "$fixture_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$fixture_dir/bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$fixture_dir/bin/pacman"
printf '%s\n' '#!/usr/bin/env bash' 'printf "omarchy"' 'printf " %q" "$@"' 'printf "\\n"' > "$fixture_dir/bin/omarchy"
chmod +x "$fixture_dir/bin/pacman" "$fixture_dir/bin/omarchy"
for command_name in ai-usagebar meteobar herdr; do
  ln -s /usr/bin/true "$fixture_dir/bin/$command_name"
done

test_path="$fixture_dir/bin:/usr/bin"
decline_status=0
PATH="$test_path" "$REPO_DIR/setup-plugins.sh" --no > "$fixture_dir/decline.out" 2>&1 || decline_status=$?
[[ "$decline_status" == 2 ]] || fail "--no should return 2 when required packages are missing"
grep -q 'omarchy pkg aur add ai-usagebar-bin meteobar-bin' "$fixture_dir/decline.out" || fail "decline output omitted the manual AUR command"
grep -q 'Atrium' "$fixture_dir/decline.out" && fail "disabled plugin requirements leaked into setup"

PATH="$test_path" "$REPO_DIR/setup-plugins.sh" --yes > "$fixture_dir/accept.out" 2>&1 || fail "--yes did not complete with stubbed package installation"
grep -q 'omarchy pkg aur add ai-usagebar-bin meteobar-bin' "$fixture_dir/accept.out" || fail "--yes did not invoke the expected AUR installation"

REPO_DIR="$REPO_DIR" bash -c 'source "$REPO_DIR/lib/plugin-requirements.sh"; plugin_requirements_validate' || fail "requirements schema did not validate"
printf 'PASS: plugin dependency setup accepts, declines, and ignores disabled plugins correctly\n'
