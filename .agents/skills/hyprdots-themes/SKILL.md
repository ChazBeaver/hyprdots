---
name: hyprdots-themes
description: Persist, pin, update, or remove Omarchy themes through hyprdots. Use when working inside the hyprdots repository and the task involves themes.lock.tsv, a theme that was installed with omarchy theme install, a hand-made theme that should survive a reinstall, theme drift reported by doctor, or moving theme pins to newer upstream commits.
---

# Hyprdots themes

Themes are pinned in `config/themes.lock.tsv` and managed only through
`./themes.sh`. Never edit the lock by hand.

## Decide first

Run `./themes.sh status` and read the STATE column.

| State | Meaning | Action |
| --- | --- | --- |
| `pinned` | Persisted; nothing to do | none |
| `installed, unpinned` | Cloned by `omarchy theme install`, not yet in the lock | `./themes.sh pin <slug>` |
| `hand-made, unpinned` | A directory the user wrote; no git source | `./themes.sh draft <slug>` (pushes to the private drafts repo; confirm with the user first) |
| `pinned, not linked` | In the lock but missing on disk | `./sync.sh` |
| `broken link` / `empty` | Leftover; not a theme | report it; delete only if the user agrees |
| `(stock)` | Ships with Omarchy | never pinned |

Installing a theme normally pins it automatically through the `theme-set`
hook, so `installed, unpinned` usually means the hook was disabled or the
theme predates it.

## Commands

```bash
./themes.sh pin <slug>        # or --all for every unpinned clone
./themes.sh unpin <slug>      # theme stays installed, just unmanaged
./themes.sh update <slug>     # or --all; prints a diff command to review
./themes.sh draft <slug>      # hand-made theme -> drafts repo -> pinned
```

After any of these, verify with `./doctor.sh` and `bash tests/themes.sh
tests/themes-cli.sh`, then offer a commit of `config/themes.lock.tsv`.

## Layout rules that must not change

- A whole-repository theme (subdirectory `.`) lives as a real git clone at
  `~/.config/omarchy/themes/<slug>`. Omarchy strips `*.lua`, terminal configs,
  and `vscode.json` from a theme only when its directory is a real clone, so a
  symlink there would let community code load. Reconcile materializes any
  such link back into a clone.
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
