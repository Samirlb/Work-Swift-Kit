#!/usr/bin/env bash
set -euo pipefail

# Returns 0 if the public key at $1 is already uploaded to GitHub (for the
# currently authenticated user). Requires gh to be authenticated.
_ssh_key_uploaded() {
  local key_file="$1"
  [[ -f "$key_file" ]] || return 1
  local fingerprint
  fingerprint=$(ssh-keygen -lf "$key_file" 2>/dev/null | awk '{print $2}') || return 1
  [[ -z "$fingerprint" ]] && return 1
  gh ssh-key list 2>/dev/null | grep -qF "$fingerprint"
}

setup_gh_accounts() {
  if ! command -v gh &>/dev/null; then
    ui_spin "Installing gh CLI..." brew install gh
  fi

  log_info "Setting up gh multi-account authentication..."

  # Order within WSK_ACCOUNTS: work → personal → extras
  local ordered_accounts=()
  for _prio in work personal; do
    [[ " ${WSK_ACCOUNTS[*]+"${WSK_ACCOUNTS[*]}"} " == *" $_prio "* ]] && ordered_accounts+=("$_prio")
  done
  for _acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    [[ "$_acct" == "work" || "$_acct" == "personal" ]] && continue
    ordered_accounts+=("$_acct")
  done

  local acct_name github_user ssh_key env_file
  for acct_name in "${ordered_accounts[@]}"; do
    env_file="${WSK_DIR}/accounts/${acct_name}.env"
    github_user=$(grep '^GIT_GITHUB_USER=' "$env_file" | cut -d= -f2-)
    ssh_key=$(grep '^WSK_SSH_KEY=' "$env_file" 2>/dev/null | cut -d= -f2- || true)

    if gh auth status --hostname github.com 2>&1 | grep -q "$github_user"; then
      log_success "gh: $github_user already authenticated, skipping."

      # Even if already auth'd, check SSH key is uploaded
      local pub_key="${HOME}/.ssh/${ssh_key}.pub"
      if [[ -n "$ssh_key" && -f "$pub_key" ]]; then
        if _ssh_key_uploaded "$pub_key"; then
          check_pass "$acct_name: SSH key already on GitHub, skipping upload."
        else
          log_info "$acct_name: SSH key not yet on GitHub. Uploading..."
          gh ssh-key add "$pub_key" --title "WSK-${acct_name}" 2>/dev/null \
            && check_pass "$acct_name: SSH key uploaded." \
            || log_warn "$acct_name: could not upload SSH key automatically. Add manually."
        fi
      fi
      continue
    fi

    log_info "Authenticating gh for $acct_name ($github_user)..."
    log_info "A browser window will open. Make sure you log in as: $github_user"
    gh auth login --hostname github.com --scopes admin:public_key --web
    log_success "gh: $github_user authenticated."

    # gh may have already uploaded the key during --web flow — skip if so
    local pub_key="${HOME}/.ssh/${ssh_key}.pub"
    if [[ -n "$ssh_key" && -f "$pub_key" ]]; then
      if ! _ssh_key_uploaded "$pub_key"; then
        log_info "$acct_name: uploading SSH key to GitHub..."
        gh ssh-key add "$pub_key" --title "WSK-${acct_name}" \
          && check_pass "$acct_name: SSH key uploaded." \
          || log_warn "$acct_name: could not upload SSH key — add manually."
      fi
    fi
  done

  log_success "gh multi-account setup complete. Switch with: gh auth switch"
}
