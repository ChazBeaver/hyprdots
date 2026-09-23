# Hyprdots agent instructions

Hyprdots is the personal layer over an Omarchy Quattro install: Hyprland Lua
config, the Omarchy shell bar and personal plugins, pinned community plugins
and themes, and a short package list. `README.md` explains the design; this
file covers only what an agent must do differently here.

## Boundaries

- Never edit anything under `/usr/share/omarchy/`. Read it freely.
- Only paths listed in `config/links.tsv` are owned here. Do not add
  application configs (appdots owns those) or agent skills (agentdots owns
  those). When unsure which repo owns a file, ask before adding it.
- Do not commit or push unless asked. Leave changes in the working tree and
  offer a Conventional Commit message.
- Never write secrets, tokens, or machine-local state into the repo.

## Verify every change

```bash
./sync.sh            # converge links, pinned themes, pinned plugins
./doctor.sh          # read-only drift check; must end with "All checks passed"
bash tests/*.sh      # self-contained fixtures, no network
hyprctl reload && hyprctl configerrors   # after any change under active/omarchy/.config/hypr
```

`bootstrap.sh` is for a fresh machine only. Do not run it to test a change.

## Themes

- `config/themes.lock.tsv` is machine-written. Use `./themes.sh` (`status`,
  `pin`, `unpin`, `update`, `draft`); never edit the lock by hand.
- A community theme must be a real git clone at
  `~/.config/omarchy/themes/<slug>`, never a symlink. Omarchy strips
  executable files from a theme only when its directory is a real clone, so
  linking one silently disables that protection.
- Hand-made themes are persisted only through `./themes.sh draft`, which moves
  them into the private drafts repository. Stock themes are never pinned.
- Full procedure: `.agents/skills/hyprdots-themes/SKILL.md`.

## Plugins

- `config/plugins.lock.tsv` pins third-party plugins by commit;
  `active/omarchy/.config/omarchy/shell.json` owns enabled state and bar
  placement. Change both when adding a plugin, and record package needs in
  `config/plugin-requirements.json`.
- Personal `chaz.*` plugins are edited in place under `active/omarchy/`.

## Code conventions

- Bash with `set -euo pipefail` and `IFS=$'\n\t'`; log through `lib/log.sh`
  helpers rather than bare `echo`.
- Library files under `lib/` are sourced, never executed. Each `doctor/*.sh`
  is a standalone read-only check that exits non-zero on drift.
- Validate every value read from a manifest before using it in a path.
