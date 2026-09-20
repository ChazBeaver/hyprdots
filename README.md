# Hyprdots

Hyprdots is the small personal layer applied after a fresh Omarchy Quattro
installation. It persists intentional Hyprland behavior, a custom Quattro lock
and idle experience, and a curated list of non-default packages without taking
ownership of application configs managed by
[appdots](../appdots/README.md).

## Fresh Omarchy Quattro build

Clone the repository anywhere under your home directory, then run:

```bash
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

It deliberately does not manage Ghostty, Neovim, Zsh, Git, Yazi, Starship,
KeePassXC settings, browser profiles, Waybar, UWSM, Alacritty, or broad
Omarchy configuration. Appdots-owned and other foreign links are never
replaced.

## Theme persistence

Hyprdots installs selected Omarchy themes from exact Git commits recorded in
`config/themes.lock.tsv`. Theme source repositories are checked out under
`~/.local/share/hyprdots/theme-sources/`, and their theme directories are
linked into `~/.config/omarchy/themes/`. Routine sync never changes the active
theme; select one manually with `omarchy theme set <name>`.

Draft personal themes share the private `omarchy-theme-drafts` repository.
A stable, rights-cleared theme should be promoted to its own public repository
named `omarchy-<name>-theme`, then have its lock entry changed to that canonical
source. Wallpaper provenance belongs in each theme's `WALLPAPERS.md`; images
with unknown redistribution rights remain private.

To update a pin, fetch and review the source, replace its 40-character commit
in `config/themes.lock.tsv`, and run `./sync.sh` followed by `./doctor.sh`.
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
- `SUPER+ALT+CTRL+W` toggles the repo-owned Meteobar panel. Temperatures use
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

Keep a new personal plugin here while its behavior is specific to this desktop.
If it becomes reusable and stable, promote it to one public repository with a
globally unique id, root manifest, README, license, dependency documentation,
tests, and an optional preview. Verify the source plugin's license and
attribution before publishing a customized clone. Marketplace submission is an
optional discovery step after that extraction; the plugin repository remains
its source of truth.

## After an Omarchy upgrade

Run `./sync.sh` and `./doctor.sh`. The two plugin `UPSTREAM` files record the
Omarchy version they were cloned from; doctor warns when the installed version
has changed. Rebase the clones against the matching directories under
`/usr/share/omarchy/shell/plugins/`, never by editing packaged files directly.
Doctor also requires the repo-managed bar to contain exactly the widgets from
the installed Quattro default and retain the intentional AM/PM clock, with
`chaz-weather` accepted as the personal replacement for `omarchy.weather` and
the configured AI usage widget accepted as the replacement for `omarchy.agents`.
Rebase `chaz-weather` manually from the installed `mryll.meteobar` plugin when
adopting upstream frontend changes. Widget reordering and bar-edge changes
remain allowed, while a partial or stale widget set fails visibly instead of
silently replacing the default bar.

The Meteobar clone's `UPSTREAM` file records its source tag, immutable commit,
and structured JSON schema. Doctor warns when the installed backend version
moves while retaining a compatible schema and fails when the schema changes.
For an update, compare upstream from the recorded commit, bring over only the
wanted frontend changes, validate the panel against the new backend, and then
advance the tag, commit, and schema record together.

## Privacy boundary

Never commit vaults, KeePassXC configuration, KeeShare keys, browser profiles or
bookmarks, account tokens, SSH keys, Wi-Fi profiles, weather locations, or
machine runtime state. Package names and non-secret desktop preferences are
appropriate to persist.
