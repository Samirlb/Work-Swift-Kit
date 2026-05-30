#!/usr/bin/env bash
set -euo pipefail

install_terminals() {
  local selections
  selections=$(ui_multiselect "Select terminals/editors to install (space to select, enter to confirm):" \
    "Warp" "iTerm2" "Alacritty" "WezTerm" "Kitty" "Neovim")

  [[ -z "$selections" ]] && return

  while IFS= read -r item; do
    case "$item" in
      Warp)      ui_spin "Installing Warp..."      -- brew install --cask warp ;;
      iTerm2)    ui_spin "Installing iTerm2..."    -- brew install --cask iterm2 ;;
      Alacritty) ui_spin "Installing Alacritty..." -- brew install --cask alacritty ;;
      WezTerm)   ui_spin "Installing WezTerm..."   -- brew install --cask wezterm ;;
      Kitty)     ui_spin "Installing Kitty..."     -- brew install --cask kitty ;;
      Neovim)    ui_spin "Installing Neovim..."    -- brew install neovim ;;
    esac
    log_success "Installed $item."
  done <<< "$selections"
}
