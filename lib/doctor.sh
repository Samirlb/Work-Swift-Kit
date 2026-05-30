#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# Inspect a path expected to be a stow symlink into WSK_DIR/stow.
_check_link() {
  local target="$1" short="${1/#$HOME/~}"
  if [[ -L "$target" ]]; then
    if [[ -e "$target" ]]; then
      check_pass "linked: $short"
    else
      check_warn "broken link: $short"
    fi
  elif [[ -e "$target" ]]; then
    check_warn "exists but not linked: $short"
  else
    check_fail "missing: $short"
  fi
}

# Read-only health check of dependencies, packages, links and accounts.
run_doctor() {
  ui_section "Check configuration"
  load_accounts

  ui_subhead "Dependencies"
  for bin in brew gum stow fzf; do
    if command -v "$bin" &>/dev/null; then check_pass "$bin installed"; else check_fail "$bin missing"; fi
  done
  if command -v envsubst &>/dev/null; then check_pass "gettext (envsubst) installed"; else check_fail "gettext missing"; fi

  ui_subhead "Base packages"
  # label:binary — ripgrep ships the `rg` binary, the rest match their name.
  local entry label bin
  for entry in git gh fzf ripgrep:rg bat eza fd sd starship zoxide jq tree; do
    label="${entry%%:*}"; bin="${entry##*:}"
    if command -v "$bin" &>/dev/null; then check_pass "$label"; else check_warn "$label not on PATH"; fi
  done

  ui_subhead "Dotfile links"
  _check_link "$HOME/.gitconfig"
  _check_link "$HOME/.gitignore_global"
  _check_link "$HOME/.zshrc"
  _check_link "$HOME/.ssh/config"

  ui_subhead "Accounts (${#WSK_ACCOUNTS[@]})"
  if ((${#WSK_ACCOUNTS[@]} == 0)); then
    check_warn "No accounts configured yet — run: wsk setup"
  else
    local acct ssh_key
    for acct in "${WSK_ACCOUNTS[@]}"; do
      check_pass "account: $acct"
      _check_link "$HOME/.gitconfig-${acct}"
      _check_link "$HOME/.claude-${acct}/CLAUDE.md"
      ssh_key=$(grep '^WSK_SSH_KEY=' "${WSK_DIR}/accounts/${acct}.env" | cut -d= -f2-)
      if [[ -n "$ssh_key" && -f "$HOME/.ssh/${ssh_key}" ]]; then
        check_pass "ssh key: ~/.ssh/${ssh_key}"
      else
        check_fail "ssh key missing: ~/.ssh/${ssh_key}"
      fi
    done
  fi

  ui_subhead "GitHub auth"
  if command -v gh &>/dev/null; then
    if gh auth status &>/dev/null; then check_pass "gh authenticated"; else check_warn "gh not authenticated — run: gh auth login"; fi
  else
    check_fail "gh not installed"
  fi

  echo
}
