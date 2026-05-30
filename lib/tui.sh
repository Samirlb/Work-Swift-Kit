#!/usr/bin/env bash
# Raw-terminal custom menu — the "looks like the screenshot" renderer.
# Pure bash + ANSI, no gum. Fragile by nature (raw mode, key parsing,
# glyph widths), so it stays optional behind WSK_UI=tui and a demo script.
set -euo pipefail

# Colors come from ui.sh (WSK_ACCENT/VIOLET/MUTED/FAINT). Provide defaults
# so tui.sh can be sourced standalone.
WSK_ACCENT="${WSK_ACCENT:-51}"
WSK_VIOLET="${WSK_VIOLET:-141}"
WSK_MUTED="${WSK_MUTED:-244}"
WSK_FAINT="${WSK_FAINT:-240}"

# ── Capability detection (the "names per OS" part) ────────────────────
# Picks an icon set based on the terminal. Override with WSK_ICONS=geom|ascii|nerd.
tui_detect() {
  TUI_TERM="${TERM_PROGRAM:-unknown}"
  # shellcheck disable=SC2034  # read by tools/tui-demo.sh for the caps report
  TUI_COLORTERM="${COLORTERM:-}"
  TUI_ICONS="${WSK_ICONS:-auto}"

  if [[ "$TUI_ICONS" == auto ]]; then
    case "$TUI_TERM" in
      # These ship/recommend a Nerd Font often, but we can't *prove* it —
      # geometric unicode renders everywhere, so default to it.
      WezTerm | iTerm.app | ghostty | kitty | Alacritty | vscode) TUI_ICONS=geom ;;
      Apple_Terminal) TUI_ICONS=geom ;;
      *) TUI_ICONS=geom ;;
    esac
  fi
}

# Map a logical name to a glyph for the active icon set.
tui_icon() {
  case "$TUI_ICONS" in
    nerd)
      case "$1" in
        setup) printf '' ;; accounts) printf '' ;; terminals) printf '' ;;
        check) printf '' ;; update) printf '' ;; relink) printf '' ;;
        quit) printf '' ;;
      esac ;;
    ascii)
      case "$1" in
        setup) printf '>' ;; accounts) printf '@' ;; terminals) printf '#' ;;
        check) printf '?' ;; update) printf '^' ;; relink) printf '~' ;; quit) printf 'x' ;;
      esac ;;
    *) # geom — width-1 unicode, broad font coverage
      case "$1" in
        setup) printf '▸' ;; accounts) printf '◆' ;; terminals) printf '▪' ;;
        check) printf '✓' ;; update) printf '↻' ;; relink) printf '↔' ;; quit) printf '✕' ;;
      esac ;;
  esac
}

# ── Low-level helpers ─────────────────────────────────────────────────
_repeat() { local c="$1" n="$2" o=''; while ((n-- > 0)); do o+="$c"; done; printf '%s' "$o"; }
_fg()    { printf '\033[38;5;%sm' "$1"; }
_reset() { printf '\033[0m'; }

# Read one keypress; expand arrow escape sequences. Requires raw mode.
_tui_read_key() {
  local k k2 k3
  IFS= read -rsn1 k || return
  if [[ $k == $'\x1b' ]]; then
    IFS= read -rsn1 -t 0.0005 k2 || true
    if [[ $k2 == '[' ]]; then
      IFS= read -rsn1 -t 0.0005 k3 || true
      printf '\x1b[%s' "$k3"; return
    fi
    printf '\x1b'; return
  fi
  printf '%s' "$k"
}

# ── Frame rendering ───────────────────────────────────────────────────
_tui_header() {
  _fg "$WSK_ACCENT"; printf '   \\  /\\  /'; _reset
  printf '   '; _fg "$WSK_ACCENT"; printf '\033[1mWork-Swift-Kit'; _reset; printf '\n'
  _fg "$WSK_ACCENT"; printf '    \\/  \\/ '; _reset
  printf '   '; _fg "$WSK_MUTED"; printf 'Customizable macOS dev environment setup'; _reset; printf '\n\n'
  printf '   '
  _fg "$WSK_ACCENT"; printf '⚡ Fast    ⊞ Modular    ⚿ Safe    ◎ Yours'; _reset; printf '\n'
  _fg "$WSK_FAINT"; printf '   %s' "$(_repeat '─' 48)"; _reset; printf '\n'
}

# Render one item as a 3-line rounded card: icon chip + title + description.
_tui_item() {
  local selected="$1" icon="$2" title="$3" desc="$4"
  local box="$WSK_FAINT" label="$WSK_MUTED"
  ((selected)) && { box="$WSK_ACCENT"; label="$WSK_ACCENT"; }

  _fg "$box"; printf '  ╭────╮'; _reset; printf '\n'
  _fg "$box"; printf '  │ %s  │' "$icon"; _reset
  printf '  '
  if ((selected)); then _fg "$WSK_ACCENT"; printf '\033[1m'; else _fg "$label"; fi
  printf '%-20s' "$title"; _reset
  printf ' '; _fg "$WSK_MUTED"; printf '%s' "$desc"; _reset; printf '\n'
  _fg "$box"; printf '  ╰────╯'; _reset; printf '\n'
}

# ── Public menu ───────────────────────────────────────────────────────
# Args: each item as "iconkey::Title::Description".
# Echoes the chosen Title on stdout; returns 1 if cancelled (q / Esc).
tui_menu() {
  tui_detect
  local items=("$@")
  local n=${#items[@]} sel=0 key i
  local keys=() titles=() descs=() rest
  for i in "${items[@]}"; do
    keys+=("${i%%::*}"); rest="${i#*::}"
    titles+=("${rest%%::*}"); descs+=("${rest#*::}")
  done

  local saved; saved=$(stty -g)
  stty -echo -icanon min 1 time 0

  # Drain any buffered input (e.g. the Enter used to launch the menu),
  # otherwise the first read consumes it and "selects" immediately.
  local _flush
  while IFS= read -rsn1 -t 0.02 _flush 2>/dev/null; do :; done

  printf '\033[?1049h\033[?25l'   # alt screen + hide cursor

  _restore() { printf '\033[?25h\033[?1049l'; stty "$saved" 2>/dev/null || true; }
  trap '_restore' INT TERM

  while true; do
    printf '\033[H\033[2J'
    _tui_header
    printf '\n'; _fg "$WSK_VIOLET"; printf '\033[1m  WHAT DO YOU WANT TO DO?'; _reset; printf '\n\n'
    for ((i = 0; i < n; i++)); do
      _tui_item "$((i == sel))" "$(tui_icon "${keys[i]}")" "${titles[i]}" "${descs[i]}"
    done
    printf '\n'; _fg "$WSK_FAINT"; printf '  ↑↓ Navigate     ⏎ Select     q Quit'; _reset; printf '\n'

    key=$(_tui_read_key)
    case "$key" in
      $'\x1b[A' | k) ((sel = (sel - 1 + n) % n)) ;;
      $'\x1b[B' | j) ((sel = (sel + 1) % n)) ;;
      '' | $'\n' | $'\r') break ;;
      q | Q | $'\x1b') sel=-1; break ;;
    esac
  done

  _restore
  trap - INT TERM
  ((sel < 0)) && return 1
  printf '%s' "${titles[sel]}"
}
