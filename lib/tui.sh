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
# All rendering writes to /dev/tty (fd 3) so tui_menu works inside $().
_repeat() { local c="$1" n="$2" o=''; while ((n-- > 0)); do o+="$c"; done; printf '%s' "$o"; }
_fg()    { printf '\033[38;5;%sm' "$1" >&3; }
_reset() { printf '\033[0m' >&3; }
_out()   { printf '%s' "$*" >&3; }
_outn()  { printf '%s\n' "$*" >&3; }

# Read one keypress from /dev/tty; expand arrow escape sequences. Requires raw mode.
# bash 3.2 (macOS system bash) does not support fractional read -t; use integer 1.
_tui_read_key() {
  local k k2 k3
  IFS= read -rsn1 k </dev/tty || return
  if [[ $k == $'\x1b' ]]; then
    IFS= read -rsn1 -t 1 k2 </dev/tty 2>/dev/null || true
    if [[ $k2 == '[' ]]; then
      IFS= read -rsn1 k3 </dev/tty || true
      printf '\x1b[%s' "$k3"; return
    fi
    printf '\x1b'; return
  fi
  printf '%s' "$k"
}

# ── Frame rendering ───────────────────────────────────────────────────
_tui_header() {
  _fg "$WSK_ACCENT"; _out '   \  /\  /'; _reset
  _out '   '; _fg "$WSK_ACCENT"; printf '\033[1mWork-Swift-Kit\033[0m' >&3; _outn ''
  _fg "$WSK_ACCENT"; _out '    \/  \/ '; _reset
  _out '   '; _fg "$WSK_MUTED"; _out 'Customizable macOS dev environment setup'; _reset; _outn ''
  _outn ''
  _out '   '
  _fg "$WSK_ACCENT"; _out '⚡ Fast    ⊞ Modular    ⚿ Safe    ◎ Yours'; _reset; _outn ''
  _fg "$WSK_FAINT"; printf '   %s\n' "$(_repeat '─' 48)" >&3; _reset
}

# Render one item as a 3-line rounded card: icon chip + title + description.
_tui_item() {
  local selected="$1" icon="$2" title="$3" desc="$4"
  local box="$WSK_FAINT" label="$WSK_MUTED"
  ((selected)) && { box="$WSK_ACCENT"; label="$WSK_ACCENT"; }

  _fg "$box"; _outn '  ╭────╮'; _reset
  _fg "$box"; printf '  │ %s  │' "$icon" >&3; _reset
  _out '  '
  if ((selected)); then _fg "$WSK_ACCENT"; printf '\033[1m' >&3; else _fg "$label"; fi
  printf '%-20s' "$title" >&3; _reset
  _out ' '; _fg "$WSK_MUTED"; _out "$desc"; _reset; _outn ''
  _fg "$box"; _outn '  ╰────╯'; _reset
}

# ── Full-screen action wrapper ────────────────────────────────────────
# Enter alt screen, run the action (gum prompts work — no stty change),
# then show "Press any key" before returning to the main menu.
tui_wrap_action() {
  local paged=0
  [[ "${1:-}" == "--paged" ]] && { paged=1; shift; }

  local saved_stty; saved_stty=$(stty -g)

  _tui_wrap_restore() {
    stty "$saved_stty" 2>/dev/null || true
    printf '\033[?25h\033[?1049l' >/dev/tty
  }

  printf '\033[?1049h\033[?25l\033[H\033[2J' >/dev/tty

  local rc=0
  if (( paged )); then
    {
      ( stty isig 2>/dev/null || true; trap 'exit 130' INT TERM; "$@" ) || rc=$?
      printf '\n\033[38;5;240m  ↑↓ scroll · q return to menu\033[0m\n'
    } 2>&1 | less -R --quit-if-one-screen --no-init || true
  else
    ( stty isig 2>/dev/null || true; trap 'exit 130' INT TERM; "$@" ) || rc=$?
    stty -echo -icanon min 1 time 0
    printf '\n\033[38;5;240m  Press any key to return to menu...\033[0m' >/dev/tty
    local _k _last_int=0 _now
    while true; do
      IFS= read -rsn1 _k </dev/tty 2>/dev/null || break
      if [[ "$_k" == $'\x03' ]]; then
        _now=$(date +%s)
        if (( _now - _last_int <= 2 )); then _tui_wrap_restore; exit 0; fi
        _last_int=$_now
        printf '\n\033[38;5;214m  Ctrl+C again to quit\033[0m' >/dev/tty
        continue
      fi
      [[ "$_k" == $'\x1b' ]] && {
        IFS= read -rsn1 -t 0.05 _ </dev/tty 2>/dev/null || true
        IFS= read -rsn1 -t 0.05 _ </dev/tty 2>/dev/null || true
        continue
      }
      break
    done
  fi

  _tui_wrap_restore
  return $rc
}

# ── Public menu ───────────────────────────────────────────────────────
# Args: each item as "iconkey::Title::Description".
# Echoes the chosen Title on stdout; returns 1 if cancelled (q / Esc).
# Caller must manage alt screen via tui_screen_enter / tui_screen_exit.
# Works inside $() — all rendering goes to /dev/tty (fd 3), only the
# selected title is emitted on stdout.
tui_menu() {
  exec 3>/dev/tty
  tui_detect
  local items=("$@")
  local n=${#items[@]} sel=0 key i
  local keys=() titles=() descs=() rest
  for i in "${items[@]}"; do
    keys+=("${i%%::*}"); rest="${i#*::}"
    titles+=("${rest%%::*}"); descs+=("${rest#*::}")
  done

  while true; do
    printf '\033[H\033[2J' >&3
    _tui_header
    _outn ''; _fg "$WSK_VIOLET"; printf '\033[1m  WHAT DO YOU WANT TO DO?\033[0m\n' >&3; _outn ''
    for ((i = 0; i < n; i++)); do
      _tui_item "$((i == sel))" "$(tui_icon "${keys[i]}")" "${titles[i]}" "${descs[i]}"
    done
    _outn ''; _fg "$WSK_FAINT"; printf '  ↑↓ Navigate     ⏎ Select     q Quit\n' >&3; _reset

    key=$(_tui_read_key)
    case "$key" in
      $'\x1b[A' | k) ((sel = (sel - 1 + n) % n)) ;;
      $'\x1b[B' | j) ((sel = (sel + 1) % n)) ;;
      '' | $'\n' | $'\r') break ;;
      q | Q | $'\x1b') sel=-1; break ;;
    esac
  done

  exec 3>&-
  ((sel < 0)) && return 1
  printf '%s' "${titles[sel]}"
}
