#!/usr/bin/env bash
# Shared, read-only parsing and checking for config/plugin-requirements.json.

PLUGIN_REQUIREMENTS="${PLUGIN_REQUIREMENTS:-$REPO_DIR/config/plugin-requirements.json}"
PLUGIN_SHELL_CONFIG="${PLUGIN_SHELL_CONFIG:-$REPO_DIR/active/omarchy/.config/omarchy/shell.json}"

plugin_requirements_validate() {
  jq -e '
    .schemaVersion == 1 and
    (.plugins | type == "object") and
    all(.plugins | to_entries[];
      (.key | test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) and
      ((.value.packages // []) | type == "array") and
      all((.value.packages // [])[];
        (.source == "repo" or .source == "aur") and
        (.name | type == "string" and test("^[A-Za-z0-9@._+:-]+$"))) and
      ((.value.checks // []) | type == "array") and
      all((.value.checks // [])[];
        (.type == "command" or .type == "pluginExecutable" or .type == "userService" or .type == "pathGlob") and
        (.target | type == "string" and length > 0) and
        (.severity == "required" or .severity == "optional") and
        (.message | type == "string" and length > 0)) and
      ((.value.manual // []) | type == "array") and
      all((.value.manual // [])[];
        (.title | type == "string" and length > 0) and
        ((.command // "") | type == "string"))
    )
  ' "$PLUGIN_REQUIREMENTS" >/dev/null
}

plugin_requirements_query() {
  local suffix="$1"
  jq -r --slurpfile shell "$PLUGIN_SHELL_CONFIG" "
    def enabled_ids:
      [
        \$shell[0].bar.id?,
        \$shell[0].bar.layout.left[]?.id,
        \$shell[0].bar.layout.center[]?.id,
        \$shell[0].bar.layout.right[]?.id,
        \$shell[0].plugins[]?.id
      ] | map(select(type == \"string\")) | unique;
    enabled_ids as \$enabled |
    .plugins | to_entries[] |
    .key as \$plugin_id |
    select(\$enabled | index(\$plugin_id)) |
    $suffix
  " "$PLUGIN_REQUIREMENTS"
}

plugin_requirements_active_ids() {
  plugin_requirements_query '.key'
}

plugin_requirements_package_rows() {
  plugin_requirements_query '.key as $id | .value.packages[]? | [$id, .source, .name] | @tsv'
}

plugin_requirements_check_rows() {
  plugin_requirements_query '.key as $id | .value.checks[]? | [$id, .type, .target, .severity, .message] | @tsv'
}

plugin_requirements_manual_rows() {
  plugin_requirements_query '.key as $id | .value.manual[]? | [$id, .title, (.command // "")] | @tsv'
}

plugin_requirement_check_passes() {
  local plugin_id="$1" type="$2" target="$3"
  case "$type" in
    command)
      command -v "$target" >/dev/null 2>&1
      ;;
    pluginExecutable)
      [[ -x "$HOME/.config/omarchy/plugins/$plugin_id/$target" ]]
      ;;
    userService)
      systemctl --user is-active --quiet "$target" 2>/dev/null
      ;;
    pathGlob)
      compgen -G "${target/#\~/$HOME}" >/dev/null
      ;;
    *)
      return 1
      ;;
  esac
}
