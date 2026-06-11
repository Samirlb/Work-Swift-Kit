#!/usr/bin/env bash
set -euo pipefail

render_ssh_config() {
  mkdir -p "${WSK_DIR}/stow/.ssh"
  local out="${WSK_DIR}/stow/.ssh/config"

  : > "$out"

  for acct in "${WSK_ACCOUNTS[@]}"; do
    local env_file="${WSK_DIR}/accounts/${acct}.env"
    local ssh_key
    ssh_key=$(grep '^WSK_SSH_KEY=' "$env_file" | cut -d= -f2-)

    cat >> "$out" <<EOF
Host github-${acct}
  HostName github.com
  User git
  IdentityFile ~/.ssh/${ssh_key}
  IdentitiesOnly yes
  AddKeysToAgent yes
  IgnoreUnknown UseKeychain
  UseKeychain yes

EOF
  done
}
