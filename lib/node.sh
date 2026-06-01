#!/usr/bin/env bash
set -euo pipefail

# node.sh — Node.js and pnpm installers.
# Depends on: lib/log.sh, lib/ui.sh, lib/os.sh (pkg_install, WSK_OS, WSK_PKG_MGR).
# Both functions are idempotent and OS-aware.

# Guard against double-source.
if declare -f install_node > /dev/null 2>&1; then
  return 0
fi

# ---------------------------------------------------------------------------
# install_node
# Installs Node.js using the OS-appropriate method. Idempotent via command -v node.
# ---------------------------------------------------------------------------
install_node() {
  if command -v node &>/dev/null; then
    check_pass "node already installed"
    return 0
  fi

  if [[ "${WSK_OS:-}" == "windows" ]]; then
    log_info "Install Node via winget: winget install OpenJS.NodeJS"
    return 0
  fi

  pkg_install node
}

# ---------------------------------------------------------------------------
# install_pnpm
# Installs pnpm using the OS-appropriate method. Idempotent via command -v pnpm.
# On macOS ALWAYS uses brew (never the standalone script which fails on Intel).
# On Linux uses corepack if available, else falls back to get.pnpm.io.
# Enforces Node prereq: returns 1 if node is not installed.
# ---------------------------------------------------------------------------
install_pnpm() {
  if command -v pnpm &>/dev/null; then
    check_pass "pnpm already installed"
    return 0
  fi

  if [[ "${WSK_OS:-}" == "windows" ]]; then
    log_info "Install pnpm via winget: winget install pnpm.pnpm"
    return 0
  fi

  # Node prereq guard (checked after Windows path so Windows doesn't need node)
  if ! command -v node &>/dev/null; then
    log_error "Node.js is required before pnpm"
    return 1
  fi

  case "${WSK_OS:-}" in
    macos)
      # Must use brew explicitly — never the standalone script (fails on Intel darwin-x64).
      ui_spin "Installing pnpm..." brew install pnpm
      ;;
    linux)
      if command -v corepack &>/dev/null; then
        corepack enable pnpm
      else
        curl -fsSL https://get.pnpm.io/install.sh | sh -
      fi
      ;;
    *)
      log_warn "install_pnpm: unknown OS '${WSK_OS:-}'; skipping."
      ;;
  esac
}
