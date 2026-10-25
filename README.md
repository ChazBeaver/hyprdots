# Hyprdots

Hyprdots is the small personal layer applied after a fresh Omarchy Quattro
installation. It persists intentional Hyprland behavior, a custom Quattro lock
and idle experience, and a curated list of non-default packages without taking
ownership of application configs managed by
[appdots](../appdots/README.md).

See the [manual operations guide](MANUAL.md) for complete examples of every
script, theme lifecycle, plugin/package maintenance, recovery, and tests.

## Fresh Omarchy Quattro build

Personal repositories live under `~/Projects/home/<repo>` on every machine.
Create that parent before cloning, then bootstrap this checkout:

```bash
mkdir -p ~/Projects/home
git clone <repo-url> ~/Projects/home/hyprdots
cd ~/Projects/home/hyprdots
./bootstrap.sh
```

Bootstrap is the one-time convergence command. It verifies Quattro, backs up
conflicting paths owned by this repository, installs declared packages, links
configuration, offers to install safe dependencies for enabled plugins,
reloads active services when possible, and runs diagnostics.

After pulling future changes, apply them without sudo or package work:

```bash
./sync.sh
```

Run read-only diagnostics at any time with:

```bash
./doctor.sh
```

## Environment

`bootstrap.sh` creates or repairs `HYPR_DOTS_DIR` and the `hyprdots` alias in
`~/.dotfiles-env.sh` before installation begins. `sync.sh` converges the same
entries on later runs, including when the repository has moved.

Both commands create `~/Projects/home` when it is missing and create the
shared environment file if needed. They repair this repo's export and alias,
remove duplicate entries for those keys, and preserve other repos' entries.
They register the current checkout without moving it. The file is the
installed-repository list used by appdots' `home-status`, `home-pull`,
`home-sync`, and `home-doctor`; `bash tests/env.sh` checks registration using
an isolated registry.

The shared environment file is sourced by the appdots-managed shell startup.
After opening a new shell (or sourcing `~/.dotfiles-env.sh`), running
`hyprdots` changes the working directory to `$HYPR_DOTS_DIR` from anywhere.

## Ownership

The exact source-to-target contract is [`config/links.tsv`](config/links.tsv).
Hyprdots manages only:

- Personal Hyprland Lua bindings, opacity, privacy, and square corners.
- Hyprsunset and Hyprland portal configuration, which still use `.conf` files.
- The default Omarchy bar layout with an AM/PM clock, imperial `chaz-weather`,
  a 14px Omarchy Shell font base, plus the `chaz.lock` / `chaz.idle` plugins
  and their idle settings.
- The `hypr-opacity-cycle` helper.
- Theme pin hooks and the personal override for Omarchy's Remove → Theme menu.

It deliberately does not manage Ghostty, Neovim, Zsh, Git, Yazi, Starship,
KeePassXC settings, browser profiles, Waybar, UWSM, Alacritty, or broad
Omarchy configuration. Appdots-owned and other foreign links are never
replaced.

## Theme persistence

The [glossary](GLOSSARY.md) defines theme ownership and lifecycle terms.
Operational commands remain here and in the repository's theme skill.

Every Omarchy theme that is not part of the package is pinned in
`config/themes.lock.tsv` by repository and exact commit. Doctor verifies each
source's origin, commit, cleanliness, and links. Routine sync never changes
the active theme; select one manually with `omarchy theme set <name>`.

Community themes use real Git clones at their installed theme paths; personally
authored vault themes share a source checkout with per-theme links. Preserve
that distinction when changing the installation layout.
[ADR-0001](docs/adr/0001-community-theme-checkouts.md) is the canonical explanation
of the security boundary and the tradeoff behind these layouts.

`./themes.sh` owns the lock so it is never edited by hand:

| Command | Effect |
| --- | --- |
| `./themes.sh status` | One line per theme: pinned, unpinned clone, hand-made, empty, or broken link. |
| `./themes.sh pin <slug>` / `--all` | Pin a theme that `omarchy theme install` cloned, in place. Nothing is moved or downloaded. |
| `./themes.sh unpin <slug>` | Drop the pin. The theme stays installed as an unmanaged clone or copy. |
| `./themes.sh remove [slug]` | Uninstall through Omarchy, verify deletion, then drop the pin. Omit the slug for the native removal picker. |
| `./themes.sh unpin --removed <slug>` | Record a known intentional removal that already happened. Refuses an existing directory or symlink; never recreates a vault theme. |
| `./themes.sh update <slug>` / `--all` | Move pins to the tip of each source's default branch and check it out. Review the printed diff command before committing the lock. |
| `./themes.sh rename <old> <new> [commit]` | Adopt a published `themes/<old>` to `themes/<new>` rename using the latest published revision. Update sibling pins and replace the old menu entry. Optionally supply a full commit hash to choose a revision. |
| `./themes.sh adopt <slug> [commit]` | Adopt a reviewed, published vault copy of a pinned community theme. Update shared vault pins, back up the old clone, and install the personal theme link. |
| `./themes.sh draft <slug>` | Move a hand-made theme into the personal drafts repository, push, and pin it. |
| `./themes.sh retire-stock` | Remove recorded stock themes after verifying their pinned personal replacements, and exclude them from package extraction. |

For everyday edits, change the files in `~/Projects/home/omarchy-theme-vault`,
commit and push there, then run `./themes.sh update <slug>` from hyprdots.
If the theme directory was renamed, use `./themes.sh rename <old> <new>`
instead; the script finds the new revision for you. These commands update all
pins sharing that source. Refresh the picker with
`omarchy theme switcher --preload` and select the theme again to load the edits.
Run `./doctor.sh` and commit the resulting `config/themes.lock.tsv` change.
`./sync.sh` restores the pinned revision; it does not advance to newer edits.

Installing a theme pins it automatically: sync links
`bin/linux/hyprdots-theme-hook.sh` into Omarchy's `theme-set.d` hook
directory, and the hook pins any unmanaged git clone the moment Omarchy
selects it, then sends a notification. Set `HYPRDOTS_THEME_AUTOPIN=0` to opt
out. Either way the pin is only durable once `config/themes.lock.tsv` is
committed.

Removing a theme through **Omarchy → Remove → Theme** also updates its pin
automatically. Sync installs a personal `extensions/omarchy-menu.jsonc`
override that routes that one menu entry through `hyprdots-theme-remove`.
It uses Omarchy's menu selector with the same installed-directory list, calls
`omarchy theme remove` for the selected theme, verifies the path disappeared,
then removes only that theme's pin. Cancelling or a failed removal leaves the
lock unchanged. Vault source files and sibling pins are never removed.
The notification reminds you to commit the lock change; nothing commits itself.

Omarchy currently has no theme-removal hook. Direct terminal calls to
`omarchy theme remove` bypass this menu integration; use `./themes.sh remove
<slug>` for the same coordinated removal in a terminal. If you already
removed a theme intentionally, run `./themes.sh unpin --removed <slug>`.
An unexplained missing theme remains drift for doctor and is restored by
sync; there is no automatic pruning of missing pins. The menu override and
helper live entirely in Hyprdots and user configuration, with no packaged
Omarchy files changed.

Personal Ethereal now owns the `ethereal` name. Stock Ethereal is removed,
and One Dark has been replaced by the independent `blue` theme (formerly
`deep-blue` and `blue-sky`). The normal Omarchy theme picker is used; there is
no theme-hiding filter.

`config/retired-stock-themes.txt` records explicitly requested stock removals.
After syncing the same-name personal replacement, run `./themes.sh retire-stock`.
It verifies the pinned vault link, installs a narrow `NoExtract` rule through
`/etc/pacman.d/hyprdots-retired-themes.conf`, and removes only the listed stock
directories. Administrator authentication is required when changes are needed.
Bootstrap runs this after sync; doctor detects missing exclusions or restored
stock files. Routine sync remains unprivileged. All other packaged themes are
left intact, and the personal theme receives no packaged overlay on selection.

Themes that predate `colors.toml` are accepted when they ship
`alacritty.toml`, which Omarchy converts on selection. Stock themes under
`/usr/share/omarchy/themes` come with the package and are never pinned.

Draft personal themes share the `omarchy-theme-vault` repository,
identified in the lock by the `personal-drafts` source id. `draft` uses the
working clone next to this repository (override with
`HYPRDOTS_THEME_DRAFTS_DIR`), scaffolds a `README.md` and a `WALLPAPERS.md`
that records the committed wallpapers and their source/license details, and moves every
`personal-drafts` pin to the new commit. A stable, rights-cleared theme should
be promoted to its own public repository named `omarchy-<name>-theme`, then
have its lock entry changed to that canonical source.

Existing unmanaged directories at a newly locked theme path are moved into a
timestamped `~/.local/state/hyprdots/backups/.../themes/` directory before the
managed link is created.

## Personal packages

Repository packages are one-per-line in:

- `packages/linux/pacman.txt` for packages available through configured Arch or
  Omarchy repositories.
- `packages/linux/aur.txt` for packages available only from the AUR.

Add package names, not versions. `bootstrap.sh` uses `omarchy pkg add` and
`omarchy pkg aur add`, so installation is idempotent and follows Quattro's
package tooling. Packages already owned by Quattro or appdots must not be
duplicated here.

The current personal set includes Terraform, 1Password and its CLI, GitHub CLI,
Signal, Spotify, Typora, Rust, fwupd, and KeePassXC. KeePassXC is deliberately
also listed by appdots so either repository's bootstrap can install the app;
neither repository persists its vault or sensitive settings.

Packages needed only by shell plugins are declared separately in
`config/plugin-requirements.json`. This keeps plugin ownership visible and
prevents those dependencies from being duplicated in the general package
manifests.

## Personal behavior

- `SUPER+BACKSPACE` cycles transparent, blur, and opaque modes. The selected
  mode is stored in `~/.local/state/hyprdots/opacity-mode` and survives reloads.
- The personal lock screen uses Quattro's PAM/fingerprint service with a blurred
  wallpaper, large clock, date, weather, and lower password field.
- Idle locking occurs after 30 minutes and suspend after 45 minutes. Quattro's
  stay-awake toggle suppresses both.
- `SUPER+ALT+CTRL+W` toggles the repo-owned Chaz Weather panel. Temperatures use
  Fahrenheit, and forecast and update times use AM/PM labels.
- Monitor scaling and input behavior inherit portable Quattro defaults.

## Plugin persistence

Plugins have three ownership tiers:

1. Personal `chaz.*` plugins are source-controlled directly under
   `active/omarchy/.config/omarchy/plugins/`. They are part of the desktop and
   are linked into place by `bootstrap.sh` and `sync.sh`.
2. Selected third-party plugins are recorded by repository and exact commit in
   `config/plugins.lock.tsv`, whether currently enabled or merely kept for
   future use. Sync installs missing checkouts and restores clean checkouts to
   those pins; doctor verifies their origin, commit, and manifest.
3. Any other downloaded plugins are experiments. They remain machine-local and
   are neither removed nor reproduced by this repository.

The lockfile owns installation; `active/omarchy/.config/omarchy/shell.json`
independently owns enabled state, bar placement, and plugin settings. This
avoids duplicating activation state. Doctor requires every configured
third-party plugin to be present in the lockfile and, when the shell is
running, confirms that installed plugins match the enabled state in
`shell.json`.

`config/plugin-requirements.json` describes what an enabled plugin needs after
its checkout exists. `./setup-plugins.sh` checks only enabled plugins, offers
once to install validated Arch/AUR packages, and prints any remaining manual
steps. Use `--yes` to accept safe package installation without a prompt or
`--no` to print the commands without installing. Declining a hard dependency
leaves bootstrap incomplete and returns a nonzero status.

Authentication, OAuth, payment enrollment, hardware enrollment, tokens,
plugin-provided setup scripts, and user-service creation are never launched
automatically. The helper displays those instructions, and doctor fails only
for a missing runtime requirement while warning about optional integrations.
`sync.sh` remains the routine, non-interactive convergence command and never
installs packages.

Pinned plugins are upgraded deliberately. Fetch and review upstream without
moving the checkout, replace its commit in `config/plugins.lock.tsv`, then run
`./sync.sh` and `./doctor.sh`. A blanket `omarchy plugin update` can move a
managed checkout, but doctor reports the drift and sync restores the recorded
pin. Local edits inside a locked community checkout are never overwritten.

The [plugin walkthrough](MANUAL.md#plugins) includes concrete commands for
fetching, selecting a commit, editing the pin, enabling a plugin, and checking
its dependencies.

Keep a new personal plugin here while its behavior is specific to this desktop.
If it becomes reusable and stable, promote it to one public repository with a
globally unique id, root manifest, README, license, dependency documentation,
tests, and an optional preview. Verify the source plugin's license and
attribution before publishing a customized clone. Marketplace submission is an
optional discovery step after that extraction; the plugin repository remains
its source of truth.

## After an Omarchy upgrade

Run `./sync.sh` and `./doctor.sh`. The Omarchy-based plugins’ `UPSTREAM` files record the
Omarchy version they were cloned from; doctor warns when the installed version
has changed. Rebase the clones against the matching directories under
`/usr/share/omarchy/shell/plugins/`, never by editing packaged files directly.
Doctor also requires the repo-managed bar to contain exactly the widgets from
the installed Quattro default and retain the intentional AM/PM clock, with
`chaz-weather` accepted as the personal replacement for `omarchy.weather` and
the configured AI usage widget accepted as the replacement for `omarchy.agents`.
Rebase `chaz-weather` against the installed Omarchy weather implementation for
shell integration changes. Its existing forecast presentation remains based
on Meteobar, with that project's MIT attribution retained. Widget reordering
and bar-edge changes remain allowed, while a partial or stale widget set fails
visibly instead of silently replacing the default bar.

Chaz Weather fetches Open-Meteo directly through Quickshell and `curl`; it does
not require Meteobar or any weather-specific AUR package. Its plugin-specific
location, icon, color, unit, and refresh settings remain unchanged. Automatic
location tries ipinfo.io then ipwho.is, matching the former 0.5.4 backend.
The private cache is under `$XDG_CACHE_HOME/chaz-weather` (normally
`~/.cache/chaz-weather`), separated by location and units. Fresh data is reused
for 60 seconds; failed fetches retain the last good forecast with a stale mark.
No location or cache contents belong in Git.

The weather `UPSTREAM` record separates the Omarchy fetching architecture from
its Meteobar presentation and behavior references. `bash tests/weather.sh`
checks stored synthetic reference output and exercises the QML service offline,
including cache recovery and settings changes during requests. It needs Node,
Python 3, and Quickshell for tests; Node and Python are not weather runtime
dependencies. After an upgrade, preserve those comparisons and inspect the live
panel before advancing the recorded baseline.

## Privacy boundary

Never commit vaults, KeePassXC configuration, KeeShare keys, browser profiles or
bookmarks, account tokens, SSH keys, Wi-Fi profiles, weather locations, or
machine runtime state. Package names and non-secret desktop preferences are
appropriate to persist.
