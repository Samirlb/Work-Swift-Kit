#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# When piped via curl | bash, BASH_SOURCE[0] is unset — clone the repo first.
if [[ -z "${BASH_SOURCE[0]:-}" ]] || [[ "${BASH_SOURCE[0]}" == "bash" ]]; then
  _TMP=$(mktemp -d)
  git clone --depth 1 https://github.com/Samirlb/Work-Swift-Kit "$_TMP/wsk"
  exec bash "$_TMP/wsk/install.sh" </dev/tty
fi

WSK_DIR="${WSK_DIR:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"}"
export WSK_DIR

source "${WSK_DIR}/lib/log.sh"
source "${WSK_DIR}/lib/bootstrap.sh"

bootstrap

source "${WSK_DIR}/lib/ui.sh"
source "${WSK_DIR}/lib/accounts.sh"
source "${WSK_DIR}/lib/os.sh"
source "${WSK_DIR}/lib/node.sh"
source "${WSK_DIR}/lib/claude.sh"
source "${WSK_DIR}/lib/frameworks.sh"
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
  collect_accounts || load_accounts
  install_packages
  install_terminals
  detect_os; detect_pkg_mgr || true
  install_node
  install_pnpm
  install_claude_code
  if ui_confirm "Install RTK (Bash output compression for Claude)?"; then
    install_rtk
  fi
  if ui_confirm "Install Caveman (response token compression for Claude)?"; then
    install_caveman
  fi
  run_ai_for_all_accounts
  setup_gh_accounts
  render_all
  link_dotfiles
  log_info "Restart your terminal or run: source ~/.zshrc"
}

run_accounts() {
  collect_accounts || load_accounts
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

run_sync() {
  load_accounts
  sync_gentle_ai_accounts
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
    ai)            run_ai ;;
    sync)          run_sync ;;
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
  echo "Usage: wsk [setup|accounts|terminals|relink|doctor|update|ai|sync]" >&2
  exit 1
fi

# ── Interactive menu ──────────────────────────────────────────────────
trap 'printf "\033[?25h\033[?1049l" >/dev/tty 2>/dev/null; stty sane 2>/dev/null; echo; exit 130' INT TERM

while true; do
  if [[ "${WSK_UI:-gum}" == "tui" ]]; then
    ACTION=$(tui_menu \
      "setup::Full setup::Install everything and configure all tools" \
      "accounts::Accounts only::Configure accounts and authentication" \
      "terminals::Terminals only::Setup shells, aliases and terminal tools" \
      "ai::AI dev tools::Install Claude Code, framework, codegraph and skills per account" \
      "sync::Sync AI configs::Run gentle-ai sync (configs + skills) for all accounts" \
      "check::Check configuration::Verify installed tools, links and accounts" \
      "update::Update::Pull latest kit and upgrade packages" \
      "relink::Re-link configs::Re-symlink existing configuration files" \
      "quit::Quit::Exit the installer") || ACTION=""
  else
    ACTION=$(ui_menu \
      "Full setup::Install everything and configure all tools" \
      "Accounts only::Configure accounts and authentication" \
      "Terminals only::Setup shells, aliases and terminal tools" \
      "AI dev tools::Install Claude Code, framework, codegraph and skills per account" \
      "Sync AI configs::Run gentle-ai sync (configs + skills) for all accounts" \
      "Check configuration::Verify installed tools, links and accounts" \
      "Update::Pull latest kit and upgrade packages" \
      "Re-link configs::Re-symlink existing configuration files" \
      "Quit::Exit the installer") || ACTION=""
  fi

  case "$ACTION" in
    *"Full setup"*)          tui_wrap_action run_full_setup ;;
    *"Accounts only"*)       tui_wrap_action run_accounts ;;
    *"Terminals only"*)      tui_wrap_action install_terminals ;;
    *"AI dev tools"*)        tui_wrap_action run_ai ;;
    *"Sync AI configs"*)     tui_wrap_action run_sync ;;
    *"Check configuration"*) tui_wrap_action --paged run_doctor ;;
    *"Update"*)              tui_wrap_action run_update ;;
    *"Re-link configs"*)     tui_wrap_action --paged run_relink ;;
    *"Quit"* | "")           log_info "See you next time."; exit 0 ;;
  esac
done
