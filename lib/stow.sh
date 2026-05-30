#!/usr/bin/env bash
set -euo pipefail

backup_if_real() {
  local target="$1"
  if [[ -e "$target" && ! -L "$target" ]]; then
    local backup
    backup="${target}.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$target" "$backup"
    log_warn "Backed up real file: $target -> $backup"
  fi
}

link_dotfiles() {
  log_info "Linking dotfiles via GNU Stow..."

  local targets=(
    "$HOME/.gitconfig"
    "$HOME/.gitignore_global"
    "$HOME/.zshrc"
    "$HOME/.ssh/config"
  )

  for acct in "${WSK_ACCOUNTS[@]}"; do
    targets+=("$HOME/.gitconfig-${acct}")
    targets+=("$HOME/.claude-${acct}/CLAUDE.md")
  done

  for t in "${targets[@]}"; do
    backup_if_real "$t"
  done

  stow --restow --no-folding --dir="${WSK_DIR}" --target="$HOME" stow

  log_success "Dotfiles linked."
}
