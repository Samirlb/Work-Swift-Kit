#!/usr/bin/env bash
set -euo pipefail

install_packages() {
  local pkgs=(git gh fzf ripgrep bat eza fd sd starship zoxide jq tree)

  log_info "Installing base packages..."
  for pkg in "${pkgs[@]}"; do
    if ! brew list "$pkg" &>/dev/null; then
      ui_spin "Installing $pkg..." -- brew install "$pkg"
      log_success "Installed $pkg."
    else
      log_info "$pkg already installed, skipping."
    fi
  done
}
