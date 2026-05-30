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
source "${WSK_DIR}/lib/gh.sh"
source "${WSK_DIR}/lib/doctor.sh"
source "${WSK_DIR}/lib/update.sh"
source "${WSK_DIR}/lib/tui.sh"

# ── Actions ───────────────────────────────────────────────────────────
run_full_setup() {
  collect_accounts
  install_packages
  install_terminals
  setup_gh_accounts
  render_all
  link_dotfiles
  log_info "Restart your terminal or run: source ~/.zshrc"
}

run_accounts() {
  collect_accounts
  render_all
  link_dotfiles
  log_info "Restart your terminal or run: source ~/.zshrc"
}

run_relink() {
  load_accounts
  render_all
  link_dotfiles
  log_success "Dotfiles re-linked."
}

# ── Direct command dispatch (wsk <command>) ───────────────────────────
dispatch() {
  case "$1" in
    setup|full)    run_full_setup ;;
    accounts)      run_accounts ;;
    terminals)     install_terminals ;;
    relink)        run_relink ;;
    doctor|check)  run_doctor ;;
    update)        run_update ;;
    *)             return 1 ;;
  esac
}

COMMAND="${1:-menu}"
[[ "$COMMAND" == "--relink" ]] && COMMAND="relink"   # back-compat

if [[ "$COMMAND" != "menu" ]]; then
  if dispatch "$COMMAND"; then
    log_success "Done."
    exit 0
  fi
  echo "Usage: wsk [setup|accounts|terminals|relink|doctor|update]" >&2
  exit 1
fi

# ── Interactive menu ──────────────────────────────────────────────────
while true; do
  if [[ "${WSK_UI:-gum}" == "tui" ]]; then
    ACTION=$(tui_menu \
      "setup::Full setup::Install everything and configure all tools" \
      "accounts::Accounts only::Configure accounts and authentication" \
      "terminals::Terminals only::Setup shells, aliases and terminal tools" \
      "check::Check configuration::Verify installed tools, links and accounts" \
      "update::Update::Pull latest kit and upgrade packages" \
      "relink::Re-link configs::Re-symlink existing configuration files" \
      "quit::Quit::Exit the installer") || ACTION=""
  else
    ACTION=$(ui_menu \
      "Full setup::Install everything and configure all tools" \
      "Accounts only::Configure accounts and authentication" \
      "Terminals only::Setup shells, aliases and terminal tools" \
      "Check configuration::Verify installed tools, links and accounts" \
      "Update::Pull latest kit and upgrade packages" \
      "Re-link configs::Re-symlink existing configuration files" \
      "Quit::Exit the installer") || ACTION=""
  fi

  case "$ACTION" in
    *"Full setup"*)          run_full_setup ;;
    *"Accounts only"*)       run_accounts ;;
    *"Terminals only"*)      install_terminals ;;
    *"Check configuration"*) run_doctor ;;
    *"Update"*)              run_update ;;
    *"Re-link configs"*)     run_relink ;;
    *"Quit"* | "")           log_info "See you next time."; exit 0 ;;
  esac

  echo
  ui_confirm "Back to the menu?" || { log_success "Work-Swift-Kit done!"; exit 0; }
done
