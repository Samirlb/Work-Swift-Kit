#!/usr/bin/env bash
set -euo pipefail

render_claude_md() {
  for acct in "${WSK_ACCOUNTS[@]}"; do
    local env_file="${WSK_DIR}/accounts/${acct}.env"
    local _fw; _fw=$(grep '^AI_FRAMEWORK=' "$env_file" 2>/dev/null | cut -d= -f2- || true)
    if [[ "$_fw" == "gentle-ai" ]]; then
      rm -f "${WSK_DIR}/stow/.claude-${acct}/CLAUDE.md"
      continue
    fi

    local display_name projects_dir
    display_name=$(grep '^DISPLAY_NAME=' "$env_file" | cut -d= -f2-)
    projects_dir=$(grep '^PROJECTS_DIR=' "$env_file" | cut -d= -f2-)

    local config_dir="${WSK_DIR}/stow/.claude-${acct}"
    mkdir -p "$config_dir"

    cat > "${config_dir}/CLAUDE.md" <<EOF
# ${display_name} — Claude Config

## Identity
Account: ${acct}
Projects: ${projects_dir}

## Rules
- Match the language the user writes in
EOF
  done
}
