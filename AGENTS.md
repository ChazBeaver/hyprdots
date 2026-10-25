# Hyprdots agent instructions

Hyprdots is the personal layer over an Omarchy Quattro install: Hyprland Lua
config, the Omarchy shell bar and personal plugins, pinned community plugins
and themes, and a short package list. `README.md` explains the design; this
file covers only what an agent must do differently here.

## Boundaries

- Never edit anything under `/usr/share/omarchy/`. Read it freely. The only
  exception is the explicitly recorded stock-theme removals in
  `config/retired-stock-themes.txt`, applied through `./themes.sh retire-stock`.
- `config/links.tsv` lists the paths installed into the home directory.
  Libraries, tests, and documentation supporting those paths also belong here.
  Application configs belong to appdots; global agent rules and portable
  skills belong to agentdots. Repository procedures belong in `.agents/skills/`.
- Do not commit or push unless asked. Leave changes in the working tree and
  offer a Conventional Commit message labeled with the repository name.
- Never write secrets, tokens, or machine-local state into the repo.

## Verify every change

```bash
./test.sh            # run every self-contained fixture suite; no network
./sync.sh            # after changing managed paths, configuration, or pins
./doctor.sh          # read-only drift check; must end with "All checks passed"
hyprctl reload && hyprctl configerrors   # after any change under active/omarchy/.config/hypr
```

`bootstrap.sh` is for a fresh machine only. Do not run it to test a change.
Fixture tests run without a desktop session. Sync activates managed changes;
doctor checks the installed machine and needs access to live desktop sockets.
`MANUAL.md` describes the individual suites and diagnostic checks.

## Themes

For theme ownership and lifecycle work, read [GLOSSARY.md](GLOSSARY.md).
Before changing theme checkout or link layout, read
[ADR-0001](docs/adr/0001-community-theme-checkouts.md) and surface any conflict
with that decision before implementing a different layout.

- `config/themes.lock.tsv` is machine-written. Use `./themes.sh` (`status`,
  `pin`, `unpin`, `update`, `draft`); never edit the lock by hand.
- A community theme must be a real git clone at
  `~/.config/omarchy/themes/<slug>`, never a symlink; ADR-0001 explains why.
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
