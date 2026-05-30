#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

WSK_DIR="${WSK_DIR:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"}"
export WSK_DIR

source "${WSK_DIR}/lib/log.sh"
source "${WSK_DIR}/lib/bootstrap.sh"

bootstrap

source "${WSK_DIR}/lib/ui.sh"
source "${WSK_DIR}/lib/accounts.sh"
source "${WSK_DIR}/lib/terminals.sh"
source "${WSK_DIR}/lib/packages.sh"
source "${WSK_DIR}/lib/render.sh"
source "${WSK_DIR}/lib/stow.sh"

if [[ "${1:-}" == "--relink" ]]; then
  render_all
  link_dotfiles
  log_success "Dotfiles re-linked."
  exit 0
fi

ui_header "Work-Swift-Kit" "Customizable macOS dev environment setup"

ACTION=$(ui_choose "What do you want to do?" "Full setup" "Accounts only" "Terminals only" "Re-link configs" "Quit")

case "$ACTION" in
  "Full setup")
    collect_accounts
    install_packages
    install_terminals
    render_all
    link_dotfiles
    ;;
  "Accounts only")
    collect_accounts
    render_all
    link_dotfiles
    ;;
  "Terminals only")
    install_terminals
    ;;
  "Re-link configs")
    render_all
    link_dotfiles
    ;;
  "Quit")
    exit 0
    ;;
esac

log_success "Work-Swift-Kit setup complete!"
log_info "Restart your terminal or run: source ~/.zshrc"
