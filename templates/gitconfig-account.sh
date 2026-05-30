#!/usr/bin/env bash
set -euo pipefail

render_gitconfig_account() {
  for acct in "${WSK_ACCOUNTS[@]}"; do
    local env_file="${WSK_DIR}/accounts/${acct}.env"

    local git_name git_email github_user ssh_key
    git_name=$(grep '^GIT_NAME=' "$env_file" | cut -d= -f2-)
    git_email=$(grep '^GIT_EMAIL=' "$env_file" | cut -d= -f2-)
    github_user=$(grep '^GIT_GITHUB_USER=' "$env_file" | cut -d= -f2-)
    ssh_key=$(grep '^WSK_SSH_KEY=' "$env_file" | cut -d= -f2-)

    cat > "${WSK_DIR}/stow/.gitconfig-${acct}" <<EOF
[user]
	name = ${git_name}
	email = ${git_email}

[github]
	user = ${github_user}

[core]
	sshCommand = ssh -i ~/.ssh/${ssh_key}
EOF
  done
}
