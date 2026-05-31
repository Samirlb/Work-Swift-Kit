#!/usr/bin/env bash
set -euo pipefail

# os.sh — OS detection, package manager detection, and pkg_install router.
# Lowest layer: only depends on lib/log.sh and lib/ui.sh (for ui_spin / check_pass).
# Sourced by bootstrap.sh and top-level in install.sh.

# Guard against double-source: if detect_os is already defined, skip.
if declare -f detect_os > /dev/null 2>&1; then
  return 0
fi

# ---------------------------------------------------------------------------
# detect_os
# Sets and exports WSK_OS ∈ {macos, linux, windows}.
# Detection order: Windows first (Git Bash / WSL can report Linux from uname).
# ---------------------------------------------------------------------------
detect_os() {
  local uname_s
  uname_s="$(uname -s 2>/dev/null || true)"

  if [[ -n "${MSYSTEM:-}" ]] \
     || [[ "$uname_s" == MINGW* || "$uname_s" == MSYS* || "$uname_s" == CYGWIN* ]] \
     || grep -qi microsoft /proc/version 2>/dev/null; then
    WSK_OS="windows"
  elif [[ "$uname_s" == "Darwin" ]]; then
    WSK_OS="macos"
  elif [[ "$uname_s" == "Linux" ]]; then
    WSK_OS="linux"
  else
    WSK_OS="linux"   # safe default for other unices
  fi
  export WSK_OS
}

# ---------------------------------------------------------------------------
# detect_pkg_mgr
# Sets and exports WSK_PKG_MGR ∈ {brew, apt, dnf, pacman, winget}.
# Returns non-zero and warns when no recognized manager is found.
# ---------------------------------------------------------------------------
detect_pkg_mgr() {
  if   command -v brew    &>/dev/null; then WSK_PKG_MGR="brew"
  elif command -v apt-get &>/dev/null; then WSK_PKG_MGR="apt"
  elif command -v dnf     &>/dev/null; then WSK_PKG_MGR="dnf"
  elif command -v pacman  &>/dev/null; then WSK_PKG_MGR="pacman"
  elif command -v winget  &>/dev/null; then WSK_PKG_MGR="winget"
  else
    WSK_PKG_MGR=""
    export WSK_PKG_MGR
    log_warn "No recognized package manager detected."
    return 1
  fi
  export WSK_PKG_MGR
}

# ---------------------------------------------------------------------------
# pkg_install <package> [--cask]
# Idempotent package installer router.
#   --cask  : install a GUI app via brew --cask (uses brew list --cask for guard)
# ---------------------------------------------------------------------------
pkg_install() {
  local pkg="" cask=0
  for arg in "$@"; do
    if [[ "$arg" == "--cask" ]]; then
      cask=1
    else
      pkg="$arg"
    fi
  done

  if [[ -z "$pkg" ]]; then
    log_warn "pkg_install: no package name provided."
    return 1
  fi

  # Idempotency guard
  if [[ "$cask" -eq 1 ]]; then
    if brew list --cask "$pkg" &>/dev/null 2>&1; then
      check_pass "$pkg already installed (cask)"
      return 0
    fi
  else
    if command -v "$pkg" &>/dev/null; then
      check_pass "$pkg already installed"
      return 0
    fi
  fi

  # Windows: print instruction only, never execute
  if [[ "${WSK_OS:-}" == "windows" ]]; then
    log_info "Please install $pkg manually via winget or the Microsoft Store."
    return 0
  fi

  # Route on WSK_PKG_MGR
  case "${WSK_PKG_MGR:-}" in
    brew)
      if [[ "$cask" -eq 1 ]]; then
        ui_spin "Installing $pkg..." -- brew install --cask "$pkg"
      else
        ui_spin "Installing $pkg..." -- brew install "$pkg"
      fi
      ;;
    apt)
      log_info "Installing $pkg..."
      sudo apt-get install -y "$pkg"
      ;;
    dnf)
      log_info "Installing $pkg..."
      sudo dnf install -y "$pkg"
      ;;
    pacman)
      log_info "Installing $pkg..."
      sudo pacman -S --noconfirm "$pkg"
      ;;
    winget)
      log_info "Please install $pkg manually via winget or the Microsoft Store."
      ;;
    "")
      log_warn "pkg_install: WSK_PKG_MGR is not set. Run detect_pkg_mgr first."
      return 1
      ;;
    *)
      log_warn "pkg_install: unknown package manager '${WSK_PKG_MGR}'."
      return 1
      ;;
  esac
}
