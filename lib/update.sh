#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# Update the kit itself, optionally upgrade CLI tools, optionally refresh dotfiles.
run_update() {
  ui_section "Update"
  load_accounts

  # 1) Update Work-Swift-Kit itself (git pull for ~/.wsk installs, brew for Homebrew).
  if [[ -d "${WSK_DIR}/.git" ]]; then
    log_info "Pulling latest Work-Swift-Kit..."
    if git -C "$WSK_DIR" pull --ff-only; then
      log_success "Kit updated."
    else
      log_warn "git pull failed — local changes or diverged branch."
    fi
  elif command -v brew &>/dev/null && brew list work-swift-kit &>/dev/null 2>/dev/null; then
    ui_spin "Refreshing Homebrew..." brew update
    if brew upgrade work-swift-kit; then
      log_success "Kit upgraded via Homebrew."
    else
      log_info "Already on the latest release."
    fi
  else
    log_warn "Can't auto-update: not a git checkout and not installed via Homebrew."
  fi

  # Refresh /usr/local/bin/wsk wrapper to point at current WSK_DIR.
  _wsk_write_wrapper 2>/dev/null || true

  # 2) Upgrade the CLI toolbelt.
  if ui_confirm "Upgrade CLI tools (gum, stow, fzf, base packages)?"; then
    ui_spin "brew update..." brew update
    brew upgrade gum stow fzf gettext git gh ripgrep bat eza fd sd starship zoxide jq tree 2>/dev/null || true
    log_success "Tools upgraded."
  fi

  # 2b) Upgrade gentle-ai tooling and re-sync managed configs/skills per account.
  if command -v gentle-ai &>/dev/null; then
    if ui_confirm "Upgrade & sync gentle-ai (configs + skills) for all accounts?"; then
      ui_spin "gentle-ai upgrade..." gentle-ai upgrade || true
      sync_gentle_ai_accounts
      log_success "gentle-ai synced."
    fi
  fi

  # 3) Re-render templates so config changes land on disk.
  if ui_confirm "Re-render and re-link dotfiles with the latest templates?"; then
    render_all
    link_dotfiles
    log_success "Dotfiles refreshed."
  fi

  echo
}
