#!/usr/bin/env bash
# Navigation-only preview of the menu. Loops so you can browse every option;
# selecting one just prints a simulated line — NO bootstrap, installs nothing,
# touches no dotfiles. Pure UI test.
set -euo pipefail

WSK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WSK_DIR

source "${WSK_DIR}/lib/log.sh"
source "${WSK_DIR}/lib/ui.sh"

while true; do
  CHOICE=$(ui_menu \
    "Full setup::Install everything and configure all tools" \
    "Accounts only::Configure accounts and authentication" \
    "Terminals only::Setup shells, aliases and terminal tools" \
    "AI dev tools::Install Claude Code, framework, codegraph and skills per account" \
    "Check configuration::Verify installed tools, links and accounts" \
    "Update::Pull latest kit and upgrade packages" \
    "Re-link configs::Re-symlink existing configuration files" \
    "Quit::Exit the installer") || CHOICE="Quit"

  case "$CHOICE" in
    Quit | "")
      log_info "Bye (demo)."
      exit 0
      ;;
    *)
      log_success "[simulado] Selected: ${CHOICE} — would run this action (nothing executed)."
      gum style --foreground 240 "Press Enter to go back to the menu..."
      read -r _
      ;;
  esac
done
