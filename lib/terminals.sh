#!/usr/bin/env bash
set -euo pipefail

install_terminals() {
  local selections
  selections=$(ui_multiselect "Select terminals/editors to install (space to select, enter to confirm):" \
    "Warp" "iTerm2" "Alacritty" "WezTerm" "Kitty" "Neovim")

  [[ -z "$selections" ]] && return

  local os="${WSK_OS:-macos}"

  while IFS= read -r item; do
    local installed=1
    case "$item" in
      Warp)
        case "$os" in
          macos)   pkg_install warp --cask ;;
          windows) check_warn "$item: install manually on Windows"; installed=0 ;;
          *)       check_warn "$item not available on Linux"; installed=0 ;;
        esac
        ;;
      iTerm2)
        case "$os" in
          macos)   pkg_install iterm2 --cask ;;
          windows) check_warn "$item: install manually on Windows"; installed=0 ;;
          *)       check_warn "$item not available on Linux"; installed=0 ;;
        esac
        ;;
      Alacritty)
        case "$os" in
          macos)   pkg_install alacritty --cask ;;
          windows) check_warn "$item: install manually on Windows"; installed=0 ;;
          *)       pkg_install alacritty ;;
        esac
        ;;
      WezTerm)
        case "$os" in
          macos)   pkg_install wezterm --cask ;;
          windows) check_warn "$item: install manually on Windows"; installed=0 ;;
          *)       pkg_install wezterm ;;
        esac
        ;;
      Kitty)
        case "$os" in
          macos)   pkg_install kitty --cask ;;
          windows) check_warn "$item: install manually on Windows"; installed=0 ;;
          *)       pkg_install kitty ;;
        esac
        ;;
      Neovim)
        case "$os" in
          windows) check_warn "$item: install manually on Windows"; installed=0 ;;
          *)       pkg_install neovim ;;
        esac
        ;;
    esac
    [[ "$installed" -eq 1 ]] && log_success "Installed $item."
  done <<< "$selections"
  # Warnings for unavailable terminals are not failures — always succeed.
  return 0
}
