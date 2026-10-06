#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%N}}")/.." &>/dev/null && pwd)"
source "$REPO_DIR/lib/log.sh"

shell_config="$REPO_DIR/active/omarchy/.config/omarchy/shell.json"
shell_defaults="/usr/share/omarchy/config/omarchy/shell.json"

if ! jq -e --slurpfile defaults "$shell_defaults" '
  def widget_ids($layout):
    [$layout.left[], $layout.center[], $layout.right[]
      | .id
      | if . == "chaz-weather" then "omarchy.weather"
        elif . == "akitaonrails.ai-usagebar" then "omarchy.agents"
        else . end
      | select(startswith("omarchy."))] | sort;
  widget_ids(.bar.layout) == widget_ids($defaults[0].bar.layout)
    and any(.bar.layout.center[]; .id == "omarchy.clock" and .format == "dddd h:mm AP")
    and any(.bar.layout.center[]; .id == "chaz-weather" and .units == "imperial")
    and ([.bar.layout.center[].id] | index("chaz-weather") + 1 == index("omarchy.clock"))
' "$shell_config" >/dev/null; then
  log_err "Omarchy bar widgets, AM/PM clock, or imperial weather settings drifted: $shell_config"
  exit 1
fi

plugin_root="$REPO_DIR/active/omarchy/.config/omarchy/plugins"
PLUGINS_LOCK="$REPO_DIR/config/plugins.lock.tsv"
source "$REPO_DIR/lib/plugins.sh"
for plugin in chaz.lock chaz.idle; do
  manifest="$plugin_root/$plugin/manifest.json"
  jq -e --arg id "$plugin" '.schemaVersion == 1 and .id == $id and .keepLoaded == true and .omarchy.clonedFrom' "$manifest" >/dev/null || {
    log_err "Invalid plugin manifest: $manifest"
    exit 1
  }
done

todo_manifest="$plugin_root/chaz.todo/manifest.json"
jq -e '.schemaVersion == 1 and .id == "chaz.todo" and .barWidget and .omarchy.clonedFrom == "tathagat11.checklist-todo"' "$todo_manifest" >/dev/null || {
  log_err "Invalid plugin manifest: $todo_manifest"
  exit 1
}

check_locked_plugin() {
  local id="$1" repository="$2" commit="$3"
  local directory="$HOME/.config/omarchy/plugins/$id"
  local actual_repository actual_commit

  [[ ! -L "$directory" && -d "$directory/.git" ]] || {
    log_err "Locked plugin is not an installed git checkout: $id"
    return 1
  }
  actual_repository="$(git -C "$directory" remote get-url origin 2>/dev/null || true)"
  [[ "$actual_repository" == "$repository" ]] || {
    log_err "Locked plugin origin drifted: $id ($actual_repository)"
    return 1
  }
  actual_commit="$(git -C "$directory" rev-parse HEAD 2>/dev/null || true)"
  [[ "$actual_commit" == "$commit" ]] || {
    log_err "Locked plugin commit drifted: $id (${actual_commit:-<missing>})"
    return 1
  }
  [[ -z "$(git -C "$directory" status --porcelain)" ]] || {
    log_err "Locked plugin has local changes: $id"
    return 1
  }
  verify_locked_plugin_contents "$id" "$directory"
}

locked_plugins_each check_locked_plugin

locked_plugin_ids=()
collect_locked_plugin_id() { locked_plugin_ids+=("$1"); }
locked_plugins_each collect_locked_plugin_id

mapfile -t configured_third_party_ids < <(jq -r '
  [
    .bar.id?,
    .bar.layout.left[]?.id,
    .bar.layout.center[]?.id,
    .bar.layout.right[]?.id,
    .plugins[]?.id
  ]
  | unique[]
  | select(. != null and (startswith("omarchy.") | not) and (startswith("chaz.") | not) and . != "chaz-weather")
' "$shell_config")
for configured_id in "${configured_third_party_ids[@]}"; do
  found=false
  for locked_id in "${locked_plugin_ids[@]}"; do
    if [[ "$configured_id" == "$locked_id" ]]; then
      found=true
      break
    fi
  done
  [[ "$found" == true ]] || {
    log_err "Enabled third-party plugin is not pinned: $configured_id"
    exit 1
  }
done

weather_manifest="$plugin_root/chaz-weather/manifest.json"
jq -e '.schemaVersion == 1 and .id == "chaz-weather" and .barWidget and .omarchy.clonedFrom == "omarchy.weather"' "$weather_manifest" >/dev/null || {
  log_err "Invalid plugin manifest: $weather_manifest"
  exit 1
}

qmllint_bin="$(command -v qmllint || printf '%s' /usr/lib/qt6/bin/qmllint)"
qml_lint_output="$(mktemp)"
trap 'rm -f -- "$qml_lint_output"' EXIT
if ! "$qmllint_bin" --ignore-settings --max-warnings -1 -I /usr/share/omarchy/shell \
  "$plugin_root/chaz.lock/LockView.qml" \
  "$plugin_root/chaz.lock/Service.qml" \
  "$plugin_root/chaz.idle/Service.qml" \
  "$plugin_root/chaz-weather/omarchy/BarWidget.qml" \
  "$plugin_root/chaz-weather/omarchy/DiagnosticsView.qml" \
  "$plugin_root/chaz-weather/omarchy/Panel.qml" \
  "$plugin_root/chaz-weather/omarchy/WeatherService.qml" \
  "$plugin_root/chaz-weather/omarchy/WeatherRequest.qml" \
  "$plugin_root/chaz.todo/BarWidget.qml" \
  "$plugin_root/chaz.todo/Panel.qml" >"$qml_lint_output" 2>&1; then
  log_err "QML syntax validation failed"
  sed 's/^/  /' "$qml_lint_output" >&2
  exit 1
fi
rm -f -- "$qml_lint_output"
trap - EXIT

installed_version="$(pacman -Q omarchy 2>/dev/null | awk '{print $2}')"
for plugin in chaz.lock chaz.idle chaz-weather; do
  upstream="$plugin_root/$plugin/UPSTREAM"
  recorded_version="$(awk 'NR == 1 { print $2 }' "$upstream")"
  if [[ -n "$installed_version" && "$recorded_version" != "$installed_version" ]]; then
    log_warn "Plugin baseline $(dirname "$upstream") is $recorded_version; installed Omarchy is $installed_version"
  fi
done

jq -e 'all(.plugins["chaz-weather"].packages[]?; .source != "aur")' \
  "$REPO_DIR/config/plugin-requirements.json" >/dev/null || {
  log_err "Personal weather must not require AUR packages"
  exit 1
}

if [[ "${HYPRDOTS_OFFLINE:-0}" != "1" ]] && omarchy-shell shell ping >/dev/null 2>&1; then
  catalog="$(omarchy plugin list --json 2>/dev/null || omarchy-plugin-list --json)"
  for plugin in chaz.lock chaz.idle chaz-weather chaz.todo; do
    jq -e --arg id "$plugin" 'any(.[]; .id == $id and .enabled == true)' <<< "$catalog" >/dev/null || {
      log_err "Omarchy shell plugin is not enabled: $plugin"
      exit 1
    }
  done

  for plugin in "${locked_plugin_ids[@]}"; do
    expected=false
    for configured_id in "${configured_third_party_ids[@]}"; do
      if [[ "$plugin" == "$configured_id" ]]; then
        expected=true
        break
      fi
    done
    jq -e --arg id "$plugin" --argjson enabled "$expected" \
      'any(.[]; .id == $id and .enabled == $enabled)' <<< "$catalog" >/dev/null || {
      log_err "Omarchy shell plugin enabled state drifted: $plugin (expected $expected)"
      exit 1
    }
  done
fi

log_ok "Repo-managed Quattro bar and personal plugins are valid"
