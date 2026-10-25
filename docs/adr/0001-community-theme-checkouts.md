# Keep community themes as real checkouts

Status: accepted; records the existing design.
Recorded: 2026-10-25.

Community themes remain real Git checkouts at their installed theme paths.
Omarchy identifies repository themes by a real directory containing `.git`,
and excludes Lua, terminal configuration, and VS Code extension configuration
from their staged content. Replacing those directories with symlinks would
bypass that identification and allow community-provided executable content
to be treated as user-authored configuration.

A shared source cache with a link per theme would make every theme use the
same installation layout. We accept separate community checkouts to preserve
Omarchy's filtering boundary. Personally authored vault themes use a shared
source checkout and per-theme links; they are intentionally treated as the
user's own configuration. Extending that layout to third-party themes requires
revisiting this decision and preserving equivalent protection.

See [the theme procedure](../../.agents/skills/hyprdots-themes/SKILL.md) for
operations and [the glossary](../../GLOSSARY.md) for vocabulary. The relevant
implementation is `lib/themes.sh`; the installed Omarchy behavior can be
inspected read-only in `/usr/share/omarchy/bin/omarchy-theme-set`, particularly
its `theme_came_from_a_repo` predicate and staging filters.
