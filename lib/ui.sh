#!/usr/bin/env bash
set -euo pipefail

if ! command -v gum &>/dev/null; then
  echo "[ERROR] gum is not installed or not in PATH. Run bootstrap first." >&2
  exit 1
fi

# ── Palette (256-color) ───────────────────────────────────────────────
WSK_ACCENT=51    # cyan    — brand / logo
WSK_VIOLET=141   # purple  — menu cursor / headers
WSK_MUTED=244    # slate   — tagline
WSK_WARN=214     # amber   — updates-available line
# shellcheck disable=SC2034  # WSK_FAINT consumed by lib/tui.sh
WSK_FAINT=240    # faint   — hints

# Single source of truth for the version shown in the header.
WSK_VERSION="${WSK_VERSION:-0.2.0}"

# ── Primitives ────────────────────────────────────────────────────────
ui_input() {
  local prompt="$1" placeholder="${2:-}"
  gum input --prompt "$prompt " --placeholder "$placeholder"
}

ui_confirm() {
  gum confirm "$1"
}

ui_choose() {
  local prompt="$1"; shift
  gum choose --header "$prompt" "$@"
}

ui_multiselect() {
  local prompt="$1"; shift
  gum choose --no-limit --header "$prompt" "$@"
}

ui_spin() {
  local title="$1"; shift
  gum spin --title "$title" -- "$@"
}

# ── Brand block: logo + box-drawing wordmark, side by side ────────────
# Borderless block (logo art left, "Work-Swift-Kit" wordmark right, tagline
# below). Used as the fzf header so the single frame wraps everything.
ui_brand_block() {
  local subtitle="${1:-Customizable macOS dev environment setup}"
  local logo_f="${WSK_DIR:-.}/lib/logo.ansi"
  local wm_f="${WSK_DIR:-.}/lib/wordmark.txt"
  local logo wm top

  if [[ -f "$wm_f" ]]; then
    wm=$(gum style --foreground "$WSK_ACCENT" --bold < "$wm_f")
  else
    wm=$(gum style --foreground "$WSK_ACCENT" --bold \
      '╦ ╦╔═╗╦╔═' '║║║╚═╗╠╩╗' '╚╩╝╚═╝╩ ╩')
  fi

  if [[ -f "$logo_f" ]]; then
    logo=$(< "$logo_f")
    top=$(gum join --horizontal --align center "$logo" "    " "$wm")
  else
    top="$wm"
  fi

  gum join --vertical "$top" "" \
    "$(gum style --foreground "$WSK_MUTED" "v${WSK_VERSION} — ${subtitle}")"
}

# Standalone header for sub-screens (doctor / update), borderless.
ui_header() {
  printf '\n'
  ui_brand_block "${2:-Customizable macOS dev environment setup}"
  printf '\n'
}

# Best-effort amber "Updates available" line (skipped if nothing outdated).
# Kept out of ui_header so previews/demos stay instant.
ui_updates() {
  command -v brew &>/dev/null || return 0
  local outdated
  outdated=$(brew outdated --quiet 2>/dev/null \
    | rg -x 'gum|stow|fzf|gettext|work-swift-kit' 2>/dev/null \
    | paste -sd ', ' -) || true
  [[ -n "$outdated" ]] &&
    gum style --margin "0 0 0 1" --foreground "$WSK_WARN" "Updates available: ${outdated}"
  return 0
}

# ── Single-frame interactive menu (fzf) ───────────────────────────────
# ONE rounded border around the brand header + the options list, navigable
# with arrows, robust in Warp. Each arg is "Label::Description"; the label
# shows bold, the description dim. Echoes the chosen label (empty on cancel).
ui_menu() {
  local header lines=() pair label desc row choice menu_label
  header=$(ui_brand_block)
  menu_label=$(gum style --foreground "$WSK_VIOLET" --bold 'Menu')
  # blank rows for breathing room, section title, blank before list
  header="${header}"$'\n \n \n'"${menu_label}"$'\n '

  for pair in "$@"; do
    label="${pair%%::*}"
    desc="${pair#*::}"
    [[ "$desc" == "$pair" ]] && desc=""
    printf -v row ' %-20s \033[2m%s\033[0m' "$label" "$desc"   # small indent past "Menu"
    lines+=("$row")
  done

  choice=$(printf '%s\n' "${lines[@]}" | fzf --ansi --reverse --no-input \
    --border=rounded \
    --margin='1' --padding='1,2' \
    --header="$header" --header-first \
    --pointer='▸' --info=hidden --no-multi --no-separator \
    --color="border:${WSK_ACCENT},label:${WSK_ACCENT},pointer:${WSK_ACCENT},fg+:${WSK_ACCENT},hl+:${WSK_ACCENT},hl:${WSK_VIOLET}") || return 1

  # Strip the leading indent and the description back off, return the label.
  printf '%s' "$choice" | sed -E 's/^ +//; s/ {2,}.*$//; s/ *$//'
}

# ── Sub-screen headers (doctor / update) ──────────────────────────────
ui_section() {
  echo
  gum style --border rounded --border-foreground "$WSK_VIOLET" \
    --foreground "$WSK_VIOLET" --bold --padding "0 2" "$1"
}

ui_subhead() {
  printf '\n'
  gum style --foreground "$WSK_ACCENT" --bold "$1"
}

# ── Status lines (doctor) ─────────────────────────────────────────────
check_pass() { printf '  \033[38;5;42m✓\033[0m %s\n'  "$*"; }
check_fail() { printf '  \033[38;5;196m✗\033[0m %s\n' "$*"; }
check_warn() { printf '  \033[38;5;214m!\033[0m %s\n' "$*"; }
