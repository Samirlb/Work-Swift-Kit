#!/usr/bin/env bash
set -euo pipefail

setup_gh_accounts() {
  if ! command -v gh &>/dev/null; then
    ui_spin "Installing gh CLI..." brew install gh
  fi

  log_info "Setting up gh multi-account authentication..."

  local env_file acct_name github_user
  for env_file in "${WSK_DIR}/accounts/"*.env; do
    acct_name=$(basename "$env_file" .env)
    github_user=$(grep '^GIT_GITHUB_USER=' "$env_file" | cut -d= -f2-)

    if gh auth status --hostname github.com 2>&1 | grep -q "$github_user"; then
      log_success "gh: $github_user already authenticated, skipping."
      continue
    fi

    log_info "Authenticating gh for $acct_name ($github_user)..."
    log_info "A browser window will open. Make sure you log in as: $github_user"
    gh auth login --hostname github.com --git-protocol ssh --web
    log_success "gh: $github_user authenticated."
  done

  log_success "gh multi-account setup complete. Switch with: gh auth switch"
}
