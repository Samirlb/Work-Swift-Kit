#!/usr/bin/env bash
set -euo pipefail

WSK_ACCOUNTS=()

# Populate WSK_ACCOUNTS from previously saved accounts/*.env (no prompts).
# Needed by relink / doctor / update, which run without re-collecting input.
load_accounts() {
  WSK_ACCOUNTS=()
  [[ -d "${WSK_DIR}/accounts" ]] || return 0
  local env_file acct_name
  for env_file in "${WSK_DIR}/accounts/"*.env; do
    [[ -e "$env_file" ]] || continue
    acct_name=$(basename "$env_file" .env)
    WSK_ACCOUNTS+=("$acct_name")
  done
}

_collect_single_account() {
  local name="$1"
  local display_label="${2:-$name}"

  log_info "Setting up account: $display_label"

  local display_name git_name git_email github_user projects_dir ssh_key

  display_name=$(ui_input "Display name for $display_label:" "$display_label")
  git_name=$(ui_input "Git name for $display_label:")
  git_email=$(ui_input "Git email for $display_label:")
  github_user=$(ui_input "GitHub username for $display_label:")
  projects_dir=$(ui_input "Projects directory for $display_label:" "$HOME/Documents/$display_label")

  local ssh_choice
  ssh_choice=$(ui_choose "SSH key for $display_label:" "Generate new ed25519 key" "Use existing key")

  if [[ "$ssh_choice" == "Generate new ed25519 key" ]]; then
    ssh_key="id_ed25519_${name}"
    local key_path="$HOME/.ssh/${ssh_key}"
    if [[ ! -f "$key_path" ]]; then
      ssh-keygen -t ed25519 -C "$git_email" -f "$key_path" -N ""
      log_success "Generated SSH key: $key_path"
    else
      log_warn "Key $key_path already exists, skipping generation."
    fi
  else
    ssh_key=$(ui_input "Enter existing SSH key filename (e.g. id_ed25519_work):")
  fi

  mkdir -p "${WSK_DIR}/accounts"
  cat > "${WSK_DIR}/accounts/${name}.env" <<EOF
ACCOUNT_NAME=${name}
DISPLAY_NAME=${display_name}
GIT_NAME=${git_name}
GIT_EMAIL=${git_email}
GIT_GITHUB_USER=${github_user}
PROJECTS_DIR=${projects_dir}
WSK_SSH_KEY=${ssh_key}
EOF

  log_success "Account $name saved."
}

collect_accounts() {
  log_info "Collecting account information..."

  _collect_single_account "work" "Work"
  _collect_single_account "personal" "Personal"

  if ui_confirm "Add another account?"; then
    while true; do
      local extra_name
      extra_name=$(ui_input "Account name (lowercase, no spaces):")
      _collect_single_account "$extra_name"
      if ! ui_confirm "Add another account?"; then
        break
      fi
    done
  fi

  for env_file in "${WSK_DIR}/accounts/"*.env; do
    local acct_name
    acct_name=$(basename "$env_file" .env)
    WSK_ACCOUNTS+=("$acct_name")
  done

  log_success "Accounts collected: ${WSK_ACCOUNTS[*]}"
}
