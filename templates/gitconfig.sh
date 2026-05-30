#!/usr/bin/env bash
set -euo pipefail

render_gitconfig() {
  local first_account="${WSK_ACCOUNTS[0]}"
  local first_env="${WSK_DIR}/accounts/${first_account}.env"

  local first_name first_email
  first_name=$(grep '^GIT_NAME=' "$first_env" | cut -d= -f2-)
  first_email=$(grep '^GIT_EMAIL=' "$first_env" | cut -d= -f2-)

  local out="${WSK_DIR}/stow/.gitconfig"

  cat > "$out" <<EOF
[user]
	name = ${first_name}
	email = ${first_email}

[core]
	excludesfile = ~/.gitignore_global

[pull]
	rebase = true

[push]
	default = current

[alias]
	st = status
	co = checkout
	br = branch
	lg = log --oneline --graph --decorate --all

EOF

  for acct in "${WSK_ACCOUNTS[@]}"; do
    local env_file="${WSK_DIR}/accounts/${acct}.env"
    local projects_dir
    projects_dir=$(grep '^PROJECTS_DIR=' "$env_file" | cut -d= -f2-)

    cat >> "$out" <<EOF
[includeIf "gitdir:${projects_dir}/"]
	path = ~/.gitconfig-${acct}

EOF
  done
}
