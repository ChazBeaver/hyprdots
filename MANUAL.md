# Manual operations

Examples start in `~/Projects/home/hyprdots` on an installed Omarchy Quattro
system. Requirements include Bash, Git, jq, Python 3 (plugin checks), and
the Omarchy/Arch tools. Use a terminal in the desktop session for live shell
and Hyprland checks. Replace `nvim` with another editor if needed.

## Install and update

For the first installation after cloning:

```bash
cd ~/Projects/home/hyprdots
./bootstrap.sh
source ~/.dotfiles-env.sh
```

Bootstrap backs up conflicts, installs packages, syncs configuration and
pinned sources, offers plugin dependency installation, and runs doctor.
It requires network/package privileges and returns nonzero if setup remains
incomplete. For an existing installation:

```bash
cd ~/Projects/home/hyprdots
git status --short
git pull --ff-only
./sync.sh
./doctor.sh
```

Sync updates the environment file, installs links, restores exact theme and
plugin pins, and reloads the running shell/Hyprland. It may clone/fetch missing
pins, but installs no packages and does not select a different active theme.
It refuses dirty managed community checkouts; inspect and preserve their
changes before retrying. To sync using only locally available commits:

```bash
HYPRDOTS_OFFLINE=1 ./sync.sh
```

Offline mode still changes files/links and skips live service reloads. It
fails for missing sources/commits; it is not a dry run. After returning to
the desktop, run normal sync and doctor. Root `bootstrap.sh`, `backup.sh`,
`sync.sh`, and `doctor.sh` take no options; appending `--help` does not make
them read-only. `themes.sh` and `setup-plugins.sh` do have help modes.

## Diagnostics and tests

Each check can be run from the repo root:

| Example | Purpose |
| --- | --- |
| `./doctor.sh` | Run all checks; success ends with `All checks passed.` |
| `bash doctor/hyprland.sh` | Inspect live Hyprland configuration errors. |
| `bash doctor/packages.sh` | Check personal packages and ownership overlap. |
| `bash doctor/plugin-readiness.sh` | Check enabled plugin runtime requirements. |
| `bash doctor/plugins.sh` | Validate pins, plugin manifests, bar configuration, and baselines. |
| `bash doctor/symlinks.sh` | Validate manifest-owned links and retired paths. |
| `bash doctor/themes.sh` | Check theme pins, source revisions, and links. |
| `bash scripts/misc/check-drift.sh` | Wrapper that runs the same aggregate doctor and returns its status. |

Warnings can accompany a passing doctor; errors return nonzero. A socket
connection error requires rerunning in a session that can reach the desktop,
not assuming the configuration is invalid.

Run all three self-contained test scripts individually, or use this loop:

```bash
bash tests/themes.sh
bash tests/themes-cli.sh
bash tests/plugin-requirements.sh

# Alternative: run each suite and retain any failure status.
bash -c 'result=0; for test_script in tests/*.sh; do bash "$test_script" || result=1; done; exit "$result"'
```

They use temporary fixtures and no network. `bash tests/*.sh` executes only
the first file with the others as arguments; it does not run every suite.
Files under `lib/` are sourced internal helpers, not standalone commands.

## Backup, recovery, and desktop edits

```bash
cd ~/Projects/home/hyprdots
./backup.sh
./sync.sh
./doctor.sh
```

Backup moves conflicting real manifest targets to adjacent
`.hyprdots-backup.<timestamp>` paths. Theme reconciliation separately saves
unmanaged conflicts under `~/.local/state/hyprdots/backups/`. Inspect backups:

```bash
find ~/.config -name '*.hyprdots-backup.*' -print
find ~/.local/state/hyprdots/backups -mindepth 1 -maxdepth 4 -print
```

The second command reports a missing directory if no theme backup exists.
To recover a specific file, inspect its saved copy before replacing the link;
for example, after setting `saved` to an existing backup:

```bash
saved="$HOME/.config/hypr/bindings.lua.hyprdots-backup.REPLACE_WITH_TIMESTAMP"
test -f "$saved" && test -L ~/.config/hypr/bindings.lua &&
  unlink ~/.config/hypr/bindings.lua && cp -a "$saved" ~/.config/hypr/bindings.lua
hyprctl reload
hyprctl configerrors
```

That deliberately creates drift; sync manages the path again. To keep an
edit permanently, edit the source in the repo instead:

```bash
nvim active/omarchy/.config/hypr/bindings.lua
hyprctl reload
hyprctl configerrors         # expected: no error text
./doctor.sh
```

For bar, idle, or plugin settings:

```bash
nvim active/omarchy/.config/omarchy/shell.json
jq empty active/omarchy/.config/omarchy/shell.json
./sync.sh
./doctor.sh
```

Add new owned paths to `config/links.tsv`, then backup/sync/check. Never edit
packaged files under `/usr/share/omarchy/`. `hypr-opacity-cycle` (or
`bash bin/linux/hypr-opacity-cycle.sh`) cycles transparent → blur → opaque,
writes the selected state and reloads Hyprland; `SUPER+BACKSPACE` invokes it.
Run `hyprctl configerrors` afterward when diagnosing it.

## Packages and plugin setup

```bash
cd ~/Projects/home/hyprdots
nvim packages/linux/pacman.txt   # repo packages, one name per line
nvim packages/linux/aur.txt      # AUR packages, one name per line
bash packages/linux/install.sh
bash doctor/packages.sh
```

`bash packages/linux/core.sh` is a compatibility wrapper for the same
installer; it is not a declarations-only file. Both install packages through
Omarchy and require network/package privileges. Removing a name from a
manifest does not uninstall it; use `omarchy pkg --help` for the installed
package-management commands after checking whether another repo needs it.

Plugin dependencies are separate from personal packages:

```bash
./setup-plugins.sh --help
./setup-plugins.sh --no      # print missing packages/manual steps; install nothing
./setup-plugins.sh           # offer package installation in an interactive terminal
./setup-plugins.sh --yes     # accept package installation without the prompt
bash doctor/plugin-readiness.sh
```

Choose one setup mode. `--no` returns 2 when required setup is incomplete;
`--yes` does not perform authentication, daemon builds, user-unit creation,
or enrollment. It prints those manual steps for enabled plugins. For example,
the calendar's optional onboarding uses
`~/.config/omarchy/plugins/tmn73.calendar/sync/setup` after enabling that
plugin. Read its installed README before running the printed command.

## Themes

Inspect the state before choosing an operation:

```bash
cd ~/Projects/home/hyprdots
./themes.sh --help
./themes.sh status
omarchy theme list
omarchy theme current
```

To install a community theme, run `omarchy theme install` and enter its
reviewed Git URL in the prompt. This downloads and selects the theme; an
existing theme with the same slug is replaced. The installed theme-set hook
normally pins the clone automatically. For an already installed unpinned
clone, substitute its slug from `status`:

```bash
./themes.sh pin coffee       # only if coffee is installed as a real Git clone
./themes.sh pin --all        # alternative: all installed unpinned clones
git diff -- config/themes.lock.tsv
bash doctor/themes.sh
```

Whole-repository community themes must stay real clones, not symlinks.
`pin`, `unpin`, `update`, and `draft` accept multiple slugs. Stock themes
are not pinned. To upgrade an existing pin (network required):

```bash
./themes.sh update coastal-village
# Alternative: update every source deliberately.
./themes.sh update --all
```

Run only the desired update. It advances pins and checks out new commits
immediately. Review the source diff command printed by the script and
`git diff -- config/themes.lock.tsv`, then run doctor. Updating one vault
theme advances **every pin sharing that vault source**. Sync alone restores
the old pin and cannot adopt newer vault commits.

To apply a theme or refresh it after an update:

```bash
omarchy theme switcher --preload
omarchy theme set coastal-village
omarchy theme bg next
```

To stop persisting a theme while keeping an installed copy:

```bash
./themes.sh unpin coastal-village
./themes.sh status
```

For a clone, selecting it again normally auto-pins it. Suppress that hook for
one selection with `HYPRDOTS_THEME_AUTOPIN=0 omarchy theme set coffee`.
To remove a theme completely, unpin it first, select another theme, then run
`omarchy theme remove coastal-village`. Removing without unpinning makes sync
restore it. Review the lock diff and doctor before committing the decision.

The hook `bin/linux/hyprdots-theme-hook.sh` is normally called by Omarchy,
with a slug argument. Manual equivalent (for an installed unmanaged clone):

```bash
HYPR_DOTS_DIR="$PWD" bash bin/linux/hyprdots-theme-hook.sh coffee
```

It notifies on failure and exits 0, so verify the result with `themes.sh
status`. `HYPRDOTS_THEME_AUTOPIN=0` makes the hook a no-op.

To persist a new hand-made theme, follow the [vault walkthrough](../omarchy-theme-vault/README.md#new-hand-made-theme).
`./themes.sh draft my-dusk` copies its palette/icons/backgrounds into the
private vault, **commits and pushes the vault**, and updates the lock. It
requires a clean vault checkout, push access, an existing `personal-drafts`
lock entry, and an unmanaged theme directory. It is not a local preview.
Other theme files/scripts are not copied by `draft`; preserve them deliberately
in the vault if the theme needs them. Override the working vault path with
`HYPRDOTS_THEME_DRAFTS_DIR=/path/to/omarchy-theme-vault ./themes.sh draft my-dusk`.

After publishing a vault directory rename, adopt it with
`./themes.sh rename old-slug new-slug`. The full edit, publish, rename,
verify, and lock-commit sequence is in the
[vault README](../omarchy-theme-vault/README.md#rename-a-theme).

## Plugins

To enable a plugin already pinned and installed, use the Omarchy CLI; for
example, the optional calendar:

```bash
omarchy plugin enable tmn73.calendar --section right
./setup-plugins.sh --no
git diff -- active/omarchy/.config/omarchy/shell.json
./doctor.sh
```

The shell writes enabled state/settings to its config. Check the repo diff
and keep only intentional non-secret settings. To disable it again, run
`omarchy plugin disable tmn73.calendar`, inspect the diff, and run doctor.
Disabling does not remove its installation pin.

For a deliberate upgrade, fetch without moving the installed checkout:

```bash
plugin_dir="$HOME/.config/omarchy/plugins/tmn73.calendar"
git -C "$plugin_dir" status --short
git -C "$plugin_dir" fetch origin
git -C "$plugin_dir" remote show origin  # identify its default branch
git -C "$plugin_dir" log --oneline --all -10
```

Choose a revision from that output; replace `REVIEWED_REVISION` below with
its hash or remote ref. Resolve the full 40-character hash and review the diff:

```bash
plugin_revision=$(git -C "$plugin_dir" rev-parse 'REVIEWED_REVISION^{commit}')
git -C "$plugin_dir" diff HEAD "$plugin_revision"
printf '%s\n' "$plugin_revision"
nvim config/plugins.lock.tsv
./sync.sh
./setup-plugins.sh --no
./doctor.sh
```

In the editor, replace only that plugin row's third (commit) field with the
reviewed full hash. The file uses literal tabs. To add a new plugin, first
review its Git source and root `manifest.json`; add a row containing its
manifest ID, credential-free canonical HTTPS GitHub `.git` URL, and reviewed
full hash. Run sync, then `omarchy plugin enable PLUGIN_ID` (replace the ID).
Add runtime requirements to `config/plugin-requirements.json` following an
existing entry before running setup/doctor. Keep package needs there rather
than duplicating them in personal package lists.

To retire a pin, disable the plugin first, remove its row and any unused
requirements entry, and run doctor. Sync leaves the existing checkout as an
unmanaged experiment; use `omarchy plugin --help` for explicit removal.

Personal plugins live under `active/omarchy/.config/omarchy/plugins/` and
reload on save. After an Omarchy/backend upgrade, compare each plugin with
its source recorded in `UPSTREAM`, port intended changes, test the UI, and
update that record. For example:

```bash
cat active/omarchy/.config/omarchy/plugins/chaz.lock/UPSTREAM
diff -ru /usr/share/omarchy/shell/plugins/lock active/omarchy/.config/omarchy/plugins/chaz.lock
omarchy-shell shell rescanPlugins
./doctor.sh
```

`diff` exits 1 for expected personal differences. For `chaz-weather`, compare
the Omarchy weather implementation for integration changes and run
`bash tests/weather.sh` to check the retained Meteobar 0.5.4 presentation/data
contract. Weather uses Quickshell and `curl` directly; there is no Meteobar
executable to install or upgrade. Keep its cache and location out of Git.
