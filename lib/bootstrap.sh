#!/usr/bin/env bash
set -euo pipefail

# Source os.sh for cross-OS detection and pkg_install router.
# Guard: if detect_os is already defined (double-source), skip.
if ! declare -f detect_os > /dev/null 2>&1; then
  source "${WSK_DIR}/lib/os.sh"
fi

bootstrap() {
  detect_os
  detect_pkg_mgr || true

  # Windows: print manual instructions and exit cleanly.
  if [[ "${WSK_OS:-}" == "windows" ]]; then
    log_info "Work-Swift-Kit is not supported on Windows. Please install WSL or use a Linux VM."
    log_info "Manual steps: install gum, stow, fzf, gettext, and run this script inside WSL."
    return 0
  fi

  # macOS: ensure Homebrew is available before pkg_install routes to brew.
  if [[ "${WSK_OS:-}" == "macos" ]]; then
    if ! command -v brew &>/dev/null; then
      log_info "Installing Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
  fi

  # Install core prereqs via pkg_install (cross-OS router).
  for pkg in gum stow fzf gettext; do
    pkg_install "$pkg"
  done

  log_success "Bootstrap complete."
}
