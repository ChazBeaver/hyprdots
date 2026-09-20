#!/usr/bin/env bash
# hyprdots/lib/detect.sh
# OS detection. Source this; do not execute.
# hyprdots is Linux/Omarchy only — this exists for parity with appdots
# and to allow shared doctor/ scripts to call detect_os safely.

detect_os() {
  case "$(uname -s)" in
    Linux)  echo "linux" ;;
    Darwin) echo "macos" ;;
    *)      echo "unknown" ;;
  esac
}

assert_linux() {
  if [ "$(detect_os)" != "linux" ]; then
    echo "❌ hyprdots is Linux only. Detected OS: $(uname -s)" >&2
    exit 1
  fi
}
