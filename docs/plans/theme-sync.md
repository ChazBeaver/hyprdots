# Task brief: refresh managed themes during sync

Agreed: 2026-10-25. Implementation authorized; commits and pushes are separate.

## Outcome and inputs

Pulling published personal repositories and running Hyprdots sync should restore
the declared themes and refresh the current managed theme and picker previews.
The motivating report was Rose Pine Dark retaining its old appearance on another
machine after pull and sync. The previous installer restored source checkouts but
left Omarchy's separate active copy untouched; that is a confirmed code path,
although the other machine's logs were not available to confirm its exact failure.

The user accepted the presented plan to retain repository ownership and improve
Hyprdots sync. The accepted behavior is captured below. The earlier temporary
planning draft was not reviewed by the user and is not an additional specification.

## Scope and decisions

- The vault owns editable themes, selected wallpaper assets, previews and credits.
- Hyprdots owns declared themes, exact source revisions and installation. Ordinary
  sync restores the committed pins without advancing them or adding unlisted themes.
- Root `sync.sh` and `themes.sh sync` use one theme workflow; the vault keeps its
  registration-only installer. Omarchy's CLI owns desktop activation.
- Preserve ADR-0001's real community checkouts and linked vault themes. Preserve
  existing protections for dirty sources, foreign links and unexpected origins.
- Keep application evidence in user state. No credentials, receipts or desktop
  snapshots are versioned. No changes to packaged Omarchy code are in scope.

## Acceptance criteria

- C1: Both sync entry points restore declared sources and links at the committed
  pins. Sync leaves the lock unchanged and stops before activation if theme source
  reconciliation fails.
- C2: A stale currently selected managed theme is reapplied, including when the
  installed source was already updated by a previous command. Repeated successful
  syncs with unchanged inputs skip activation, and sibling-only vault updates do
  not reapply the current theme. Each machine retains its theme choice.
- C3: Keep the selected wallpaper when it survives activation, including a valid
  external image. Choose a wallpaper from the updated theme when the old image
  was removed. Rose Pine Dark retains its single wallpaper and matching preview.
- C4: Refresh previews for updated active and inactive themes, including changes
  within backgrounds that do not change the parent theme directory's timestamp.
- C5: Offline and unavailable-desktop runs explicitly defer visual refresh. A later
  normal sync completes it. Activation and preview failures return nonzero and
  leave unfinished work retryable; successful work can be retained independently.
- C6: Doctor remains read-only and distinguishes source/link validity from stale
  or unverified active content and previews. Output identifies the recovery command.
- C7: Document routine restoration, explicit pin updates, deferred work, and
  verification in the existing manuals and theme skill. Clarify active-theme
  vocabulary without expanding global agent rules or changing the existing ADR.

## Implementation notes

The source reconciler remains in `lib/themes.sh`. Its shared sync wrapper invokes
`scripts/theme-activation.py` only after successful installation. The helper uses
each theme's Git tree, source identity, stock overlay and template inputs to decide
whether activation is stale. It records successful active files separately from
preview refresh under `~/.local/state/hyprdots/themes/`.

A missing baseline, or a newly selected managed theme without matching evidence,
can require one refresh. Omarchy generates application files, so active contents
are compared with a successful activation receipt rather than with the raw source
directory. Palette, wallpaper and preview postconditions are checked before a
receipt is written. Doctor verifies files and receipts, not every application's UI.

Activation uses Omarchy's skip-background option, then applies the preserved or
replacement image explicitly. Selection is rechecked around activation. Sync
retries failed work; it does not provide a transaction that rolls back every
checkout or intercept user theme changes atomically across Omarchy processes.

## Verification

| Criteria | Required evidence |
| --- | --- |
| C1 | Existing source/CLI fixtures plus theme-only sync dispatch, unchanged lock and failure-before-activation cases. |
| C2-C6 | Isolated Git sources and simulated desktop: stale copies, repeat sync, sibling update, wallpaper preservation/removal, preview caching, offline/no session, failures/retries, selection changes and read-only doctor. |
| C1-C6 | Run `./test.sh`, live `./sync.sh` and `./doctor.sh`; inspect Rose Pine Dark's selected slug, wallpaper and preview, then verify a repeated `./themes.sh sync` skips activation. |
| C7 | Check documentation links, relative CLAUDE.md links, and whitespace. |

## Open questions

None. Receiving machines restore the committed Hyprdots pin; publishing a newer
vault revision and advancing/publishing its pin remain explicit operations.

## Completion evidence

| Criterion | Verdict | Evidence |
| --- | --- | --- |
| C1 | PASS | Source/CLI fixtures; live root and theme-only sync; committed lock unchanged. |
| C2-C4 | PASS | 18 activation fixtures; live Rose Pine Dark retains its slug, wallpaper bytes and matching preview; repeat theme sync leaves activation files untouched. |
| C5-C6 | PASS | Offline, missing-session, failure/retry and read-only doctor fixtures; live doctor ends with All checks passed. |
| C7 | PASS | Updated manuals, glossary and scoped skill; local Markdown links, relative CLAUDE.md links and whitespace verified. |
