#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

render_all() {
  # Bail early when no accounts are configured yet (bash 3.2 safe: ${var+x}).
  local _ra_count=0
  if [[ -n "${WSK_ACCOUNTS+x}" ]]; then
    _ra_count="${#WSK_ACCOUNTS[@]}"
  fi
  if [[ "$_ra_count" -eq 0 ]]; then
    return 0
  fi

  log_info "Rendering dotfiles..."

  mkdir -p "${WSK_DIR}/stow"
  mkdir -p "${WSK_DIR}/stow/.ssh"

  source "${WSK_DIR}/templates/gitconfig.sh"
  source "${WSK_DIR}/templates/gitconfig-account.sh"
  source "${WSK_DIR}/templates/gitignore-global.sh"
  source "${WSK_DIR}/templates/ssh-config.sh"
  source "${WSK_DIR}/templates/zshrc.sh"
  source "${WSK_DIR}/templates/claude-md.sh"

  render_gitconfig
  render_gitconfig_account
  render_gitignore_global
  render_ssh_config
  render_zshrc
  render_claude_md

  log_success "All dotfiles rendered."
}
