#!/usr/bin/env bash
# Safe, side-effect-free preview of the raw-terminal menu (WSK_UI=tui).
# Runs no bootstrap, installs nothing, touches no dotfiles. Just renders
# the custom TUI so you can judge how it looks and how fragile it feels.
set -euo pipefail

WSK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WSK_DIR

source "${WSK_DIR}/lib/ui.sh"   # palette only (gum present check is fine)
source "${WSK_DIR}/lib/tui.sh"

tui_detect
printf 'Detected terminal : %s\n' "$TUI_TERM"
printf 'COLORTERM         : %s\n' "${TUI_COLORTERM:-<unset>}"
printf 'Icon set          : %s   (override with WSK_ICONS=geom|ascii|nerd)\n\n' "$TUI_ICONS"
printf 'Press Enter to open the menu...'; read -r _

CHOICE=$(tui_menu \
  "setup::Full setup::Install everything and configure all tools" \
  "accounts::Accounts only::Configure accounts and authentication" \
  "terminals::Terminals only::Setup shells, aliases and terminal tools" \
  "check::Check configuration::Verify installed tools, links and accounts" \
  "update::Update::Pull latest kit and upgrade packages" \
  "relink::Re-link configs::Re-symlink existing configuration files" \
  "quit::Quit::Exit the installer") || CHOICE=""

printf '\nSelected: %s\n' "${CHOICE:-<cancelled>}"
