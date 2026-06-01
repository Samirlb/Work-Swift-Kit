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
  log_info "This will create shell commands: ${name} and gh-${name}"

  local display_name git_name git_email github_user projects_dir ssh_key

  display_name=$(ui_input "Display name for $display_label (label only, not the command):" "$display_label") || return 130
  git_name=$(ui_input "Git name for $display_label:") || return 130
  git_email=$(ui_input "Git email for $display_label:") || return 130
  github_user=$(ui_input "GitHub username for $display_label:") || return 130
  projects_dir=$(ui_input "Projects directory for $display_label:" "$HOME/Documents/$display_label") || return 130

  local ssh_choice
  ssh_choice=$(ui_choose "SSH key for $display_label:" "Generate new ed25519 key" "Use existing key") || return 130

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
    local existing_keys=()
    while IFS= read -r keyfile; do
      existing_keys+=("$(basename "$keyfile")")
    # only real private keys — skip .pub, known_hosts, config, authorized_keys, and any .bak files
    done < <(find "$HOME/.ssh" -maxdepth 1 -type f \
      ! -name "*.pub" ! -name "*.bak*" \
      ! -name "known_hosts*" ! -name "config*" ! -name "authorized_keys" \
      2>/dev/null | sort)

    if [[ ${#existing_keys[@]} -gt 0 ]]; then
      ssh_key=$(ui_choose "Select existing SSH key:" "${existing_keys[@]}") || return 130
    else
      ssh_key=$(ui_input "Enter existing SSH key filename (e.g. id_ed25519_work):") || return 130
    fi
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

  local mode
  mode=$(ui_choose "How many accounts do you want to configure?" \
    "Single account" \
    "Work + Personal" \
    "Work + Personal + more") || { log_warn "Account setup cancelled."; return 130; }

  WSK_ACCOUNTS=()

  case "$mode" in
    "Work + Personal")
      _collect_single_account "work" "Work" || { log_warn "Account setup cancelled."; return 130; }
      WSK_ACCOUNTS+=("work")
      _collect_single_account "personal" "Personal" || { log_warn "Account setup cancelled."; return 130; }
      WSK_ACCOUNTS+=("personal")
      ;;
    "Single account")
      local acct_name
      acct_name=$(ui_choose "Account type:" "work" "personal") || { log_warn "Account setup cancelled."; return 130; }
      local _label; _label="$(tr '[:lower:]' '[:upper:]' <<< "${acct_name:0:1}")${acct_name:1}"
      _collect_single_account "$acct_name" "$_label" || { log_warn "Account setup cancelled."; return 130; }
      WSK_ACCOUNTS+=("$acct_name")
      ;;
    "Work + Personal + more")
      _collect_single_account "work" "Work" || { log_warn "Account setup cancelled."; return 130; }
      WSK_ACCOUNTS+=("work")
      _collect_single_account "personal" "Personal" || { log_warn "Account setup cancelled."; return 130; }
      WSK_ACCOUNTS+=("personal")
      while true; do
        local extra_name
        extra_name=$(ui_input "Account name (lowercase, no spaces):") || break
        _collect_single_account "$extra_name" || break
        WSK_ACCOUNTS+=("$extra_name")
        ui_confirm "Add another account?" || break
      done
      ;;
  esac

  log_success "Accounts collected: ${WSK_ACCOUNTS[*]}"
}
