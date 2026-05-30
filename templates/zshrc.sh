#!/usr/bin/env bash
set -euo pipefail

render_zshrc() {
  local out="${WSK_DIR}/stow/.zshrc"

  cat > "$out" <<'EOF'
export PATH="/opt/homebrew/bin:$PATH"
export PATH="$HOME/Library/pnpm:$PATH"
export PATH="$HOME/.fzf/bin:$PATH"

autoload -Uz compinit && compinit

eval "$(starship init zsh)"
eval "$(zoxide init zsh)"

EOF

  for acct in "${WSK_ACCOUNTS[@]}"; do
    local env_file="${WSK_DIR}/accounts/${acct}.env"

    local projects_dir
    projects_dir=$(grep '^PROJECTS_DIR=' "$env_file" | cut -d= -f2-)

    # Write the function using a quoted heredoc so $1, $(), etc. are NOT expanded.
    # Account-specific values are interpolated into shell vars before the heredoc.
    local fn_name="claude-${acct}"
    local fn_base="$projects_dir"
    local fn_prompt="${acct} › "
    local fn_claude_dir="$HOME/.claude-${acct}"

    cat >> "$out" <<EOF
function ${fn_name}() {
  local base="${fn_base}"
  if [[ "\$1" == "-p" ]]; then
    ls "\$base"
  elif [[ -n "\$1" ]]; then
    cd "\$base/\$1" && CLAUDE_CONFIG_DIR="${fn_claude_dir}" claude
  else
    local project
    project=\$(ls "\$base" | fzf --prompt="${fn_prompt}" --height=40%)
    [[ -n "\$project" ]] && cd "\$base/\$project" && CLAUDE_CONFIG_DIR="${fn_claude_dir}" claude
  fi
}

EOF
  done
}
