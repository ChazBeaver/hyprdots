---
name: hyprdots-themes
description: Persist, pin, update, or remove Omarchy themes through hyprdots. Use when working inside the hyprdots repository and the task involves themes.lock.tsv, a theme that was installed with omarchy theme install, a hand-made theme that should survive a reinstall, theme drift reported by doctor, or moving theme pins to newer upstream commits.
---

# Hyprdots themes

Themes are pinned in `config/themes.lock.tsv` and managed only through
`./themes.sh`. Never edit the lock by hand.
Read [the glossary](../../../GLOSSARY.md) when clarifying ownership or lifecycle
terms. Before changing source checkout or link layout, read
[ADR-0001](../../../docs/adr/0001-community-theme-checkouts.md); surface a
conflict with that decision before implementing a different layout.

## Decide first

Run `./themes.sh status` and read the STATE column.

| State | Meaning | Action |
| --- | --- | --- |
| `pinned` | Source is persisted; active copy can still be stale | `./themes.sh sync` when restoring updates; doctor checks activation |
| `installed, unpinned` | Cloned by `omarchy theme install`, not yet in the lock | `./themes.sh pin <slug>` |
| `hand-made, unpinned` | A directory the user wrote; no git source | `./themes.sh draft <slug>` (pushes to the personal drafts repo; confirm with the user first) |
| `pinned, not linked` | In the lock but missing on disk | `./sync.sh` to restore; `./themes.sh unpin --removed <slug>` only when removal was intentional |
| `broken link` / `empty` | Leftover; not a theme | report it; delete only if the user agrees |
| `(stock)` | Ships with Omarchy | never pinned |

Installing a theme normally pins it automatically through the `theme-set`
hook, so `installed, unpinned` usually means the hook was disabled or the
theme predates it.

Omarchy's Remove → Theme menu is connected to this workflow through the
Hyprdots-owned user menu override. It uses the native selector and remover,
then drops the selected pin only after deletion succeeds. Cancellation and
failed deletion preserve the pin. Do not prune other missing pins or add a
filesystem watcher: missing files alone do not establish removal intent.
Direct `omarchy theme remove` calls bypass the menu override; use `remove`
below when coordinating a removal from the terminal.

## Commands

```bash
./themes.sh sync              # restore pins, refresh active managed theme and previews
./themes.sh pin <slug>        # or --all for every unpinned clone
./themes.sh unpin <slug>      # theme stays installed, just unmanaged
./themes.sh remove [slug]     # native uninstall + unpin; no slug opens the picker
./themes.sh unpin --removed <slug> # acknowledge an intentional prior deletion
./themes.sh update <slug>     # or --all; prints a diff command to review
./themes.sh draft <slug>      # hand-made theme -> drafts repo -> pinned
./themes.sh adopt <slug> [commit] # reviewed, published vault copy replaces a community pin
./themes.sh retire-stock      # apply explicitly recorded stock-theme removals
```

After changing theme pins, run `./themes.sh sync`, then verify with `./test.sh`
and `./doctor.sh` and offer a commit of `config/themes.lock.tsv`. Ordinary sync
does not change pins. It preserves the selected theme and any surviving selected
wallpaper; offline or headless runs defer refresh until a normal desktop sync.
Doctor reports stale or unverified activation as well as source/link drift.
Local activation receipts belong under user state, never in the repository.
Ordinary `unpin` can recreate a shared-source theme as an unmanaged copy;
use `unpin --removed` for prior deletions. This leaves vault source files
and sibling theme pins intact and refuses even a dangling installed symlink.

## Layout rules that must not change

- A whole-repository theme (subdirectory `.`) lives as a real git clone at
  `~/.config/omarchy/themes/<slug>`. Reconcile materializes any such link back
  into a clone. ADR-0001 records the security reason for this layout.
- Multi-theme sources (the drafts repo) are checked out under
  `~/.local/share/hyprdots/theme-sources/<source id>` and linked per theme.
  Those themes are the user's own and are unrestricted.
- Lock URLs are canonical GitHub URLs ending in `.git`; the `.` layout
  requires the source id to equal the slug.
- Themes older than `colors.toml` are valid when they ship `alacritty.toml`.

## Updating a pin safely

`update` moves the pin to the upstream default-branch tip without review.
Before the lock is committed, run the diff command it prints and look for new
executable files or changed backgrounds, then report what changed.

## Explicit stock-theme replacements

When the user requests removal of a packaged theme in favor of their own,
first publish and install the personal vault theme under the same slug.
Record the requested stock slug in `config/retired-stock-themes.txt`, then
run `./themes.sh retire-stock`. This is the narrow exception to leaving
packaged files alone: the command validates the personal replacement,
installs pacman `NoExtract` rules, and removes only those stock directories.
It authenticates for system changes when needed. Do not add retirements
that the user did not request. Run doctor and `bash tests/stock-theme-retirement.sh`.
