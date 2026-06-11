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

# Persist WSK to ~/.wsk and write/refresh the wsk wrapper in /usr/local/bin.
# Called immediately when running from a temp dir (curl install) and from run_update.
# Optional first argument overrides the output path (used by tests).
_wsk_write_wrapper() {
  local dest="${1:-/usr/local/bin/wsk}"
  mkdir -p "$(dirname "$dest")"
  cat > "$dest" <<'WRAPPER'
#!/usr/bin/env bash
WSK_DIR="$HOME/.wsk"
export WSK_DIR
exec bash "$WSK_DIR/install.sh" "$@"
WRAPPER
  chmod +x "$dest"
}

_wsk_self_install() {
  local dest="$HOME/.wsk"
  if [[ "$WSK_DIR" != "$dest" ]]; then
    rm -rf "$dest"
    cp -r "$WSK_DIR" "$dest"
    WSK_DIR="$dest"
    export WSK_DIR
  fi
  _wsk_write_wrapper
  log_success "wsk installed/updated → /usr/local/bin/wsk (WSK_DIR=$HOME/.wsk)"
}

# Auto-install when running from a temp dir (curl | bash flow)
if [[ "$WSK_DIR" == /tmp/* ]] || [[ "$WSK_DIR" == /var/folders/* ]]; then
  _wsk_self_install
fi

source "${WSK_DIR}/lib/ui.sh"
source "${WSK_DIR}/lib/preflight.sh"
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
source "${WSK_DIR}/lib/fix-git.sh"
source "${WSK_DIR}/lib/update.sh"
source "${WSK_DIR}/lib/tui.sh"

# ── Actions ───────────────────────────────────────────────────────────
run_full_setup() {
  ui_confirm "Run full setup? Installs packages, tools, and configures all accounts." || return 0
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
  preflight_accounts || return 0
  render_all
  link_dotfiles
  log_success "Dotfiles re-linked."
}

run_sync() {
  load_accounts
  preflight_accounts || return 0
  sync_gentle_ai_accounts
}

run_fix_claude_cmd() {
  load_accounts
  run_fix_claude
}

run_fix_git_cmd() {
  load_accounts
  shift  # remove the "fix-git" command name; remaining args forwarded to run_fix_git
  run_fix_git "$@"
}

run_help() {
  cat <<EOF
Work-Swift-Kit ${WSK_VERSION}

USAGE
  wsk [command]

COMMANDS
  (no args)        Open interactive menu
  setup            Full setup: accounts, dotfiles, tools, and AI layer
  accounts         Re-collect accounts and re-link dotfiles
  ai               Install or re-configure AI frameworks for all accounts
  sync             Run gentle-ai sync for every gentle-ai account
  fix-claude       Remove ~/.claude symlink and patch CLAUDE.md for all gentle-ai accounts
  fix-git          Convert https github remotes to per-account SSH aliases (dry-run by default)
  relink           Re-render and re-link dotfiles without re-collecting accounts
  doctor           Scrollable health check of tools, links, accounts, and AI setup
  update           Update the kit, upgrade CLI tools, sync gentle-ai, refresh dotfiles
  version          Print the current wsk version
  help             Show this help message
EOF
}

# ── Direct command dispatch (wsk <command>) ───────────────────────────
dispatch() {
  case "$1" in
    setup|full)    run_full_setup ;;
    accounts)      run_accounts ;;
    terminals)     install_terminals ;;
    relink)        run_relink ;;
    doctor|check)  run_doctor ;;
    fix-claude)    run_fix_claude_cmd ;;
    fix-git)       run_fix_git_cmd "$@" ;;
    update)        run_update ;;
    ai)            run_ai ;;
    sync)          run_sync ;;
    version|-v|--version) echo "wsk ${WSK_VERSION}" ;;
    help|-h|--help)       run_help ;;
    *)             return 1 ;;
  esac
}

COMMAND="${1:-menu}"
[[ "$COMMAND" == "--relink" ]] && COMMAND="relink"   # back-compat

if [[ "$COMMAND" != "menu" ]]; then
  if dispatch "$COMMAND" "${@:2}"; then
    log_success "Done."
    exit 0
  fi
  echo "Usage: wsk [setup|accounts|terminals|relink|doctor|fix-claude|update|ai|sync]" >&2
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
