#!/usr/bin/env bash
set -euo pipefail

render_all() {
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
