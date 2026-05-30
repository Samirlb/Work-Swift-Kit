#!/usr/bin/env bash
set -euo pipefail

if ! command -v gum &>/dev/null; then
  echo "[ERROR] gum is not installed or not in PATH. Run bootstrap first." >&2
  exit 1
fi

ui_input() {
  local prompt="$1"
  local placeholder="${2:-}"
  gum input --prompt "$prompt " --placeholder "$placeholder"
}

ui_confirm() {
  local prompt="$1"
  gum confirm "$prompt"
}

ui_choose() {
  local prompt="$1"
  shift
  gum choose --header "$prompt" "$@"
}

ui_multiselect() {
  local prompt="$1"
  shift
  gum choose --no-limit --header "$prompt" "$@"
}

ui_header() {
  local title="$1"
  local subtitle="${2:-}"
  gum style --border double --padding "1 2" --foreground 212 --border-foreground 212 "$title" "$subtitle"
}

ui_spin() {
  local title="$1"
  shift
  gum spin --title "$title" -- "$@"
}
