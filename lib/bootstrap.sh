#!/usr/bin/env bash
set -euo pipefail

bootstrap() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    log_error "Work-Swift-Kit requires macOS."
    exit 1
  fi

  if ! command -v brew &>/dev/null; then
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  for pkg in gum stow fzf gettext; do
    if ! brew list "$pkg" &>/dev/null; then
      log_info "Installing $pkg..."
      brew install "$pkg"
    fi
  done

  log_success "Bootstrap complete."
}
