#!/usr/bin/env bash
# Safe, side-effect-free preview of the gum menu (the default UI).
# No bootstrap, installs nothing, touches no dotfiles — just renders the
# header card + interactive menu so you can see and navigate it.
set -euo pipefail

WSK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WSK_DIR

source "${WSK_DIR}/lib/log.sh"
source "${WSK_DIR}/lib/ui.sh"

CHOICE=$(ui_menu \
  "Full setup::Install everything and configure all tools" \
  "Accounts only::Configure accounts and authentication" \
  "Terminals only::Setup shells, aliases and terminal tools" \
  "Check configuration::Verify installed tools, links and accounts" \
  "Update::Pull latest kit and upgrade packages" \
  "Re-link configs::Re-symlink existing configuration files" \
  "Quit::Exit the installer") || CHOICE=""

printf '\nSelected: %s\n' "${CHOICE:-<cancelled>}"
