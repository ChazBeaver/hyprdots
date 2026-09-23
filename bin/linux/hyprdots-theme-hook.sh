#!/usr/bin/env bash
# Omarchy theme-set hook: pin a theme that `omarchy theme install` just cloned.
# Linked to ~/.config/omarchy/hooks/theme-set.d/hyprdots-pin-theme by sync.sh.
# It only acts on an unmanaged git clone, so re-selecting a pinned, stock, or
# hand-made theme is a no-op. Opt out with HYPRDOTS_THEME_AUTOPIN=0.

slug="${1:-}"
[[ -n "$slug" ]] || exit 0
[[ "${HYPRDOTS_THEME_AUTOPIN:-1}" != "0" ]] || exit 0

if [[ -z "${HYPR_DOTS_DIR:-}" && -f "$HOME/.dotfiles-env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.dotfiles-env.sh"
fi
[[ -n "${HYPR_DOTS_DIR:-}" && -x "$HYPR_DOTS_DIR/themes.sh" ]] || exit 0

path="$HOME/.config/omarchy/themes/$slug"
[[ -d "$path" && ! -L "$path" && -d "$path/.git" ]] || exit 0
! grep -q "^$slug	" "$HYPR_DOTS_DIR/config/themes.lock.tsv" 2>/dev/null || exit 0

notify() { command -v omarchy-notification-send >/dev/null && omarchy-notification-send "$@" || true; }

if output="$("$HYPR_DOTS_DIR/themes.sh" pin "$slug" 2>&1)"; then
  notify "Hyprdots pinned theme: $slug" "Commit config/themes.lock.tsv to keep it"
else
  notify "Hyprdots could not pin theme: $slug" "$output"
fi
exit 0
