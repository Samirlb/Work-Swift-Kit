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

  # _switch_profile helper — written once, shared by all profile functions
  cat >> "$out" <<'EOF'
function _wsk_switch_profile() {
  local gh_user="$1" claude_config="$2" base="$3"
  shift 3
  local arg="${1:-}"

  gh auth switch --user "$gh_user" 2>/dev/null && \
    echo "gh → $gh_user" || echo "gh: could not switch to $gh_user"

  if [[ "$arg" == "-p" ]]; then
    ls "$base"; return
  fi

  local project
  if [[ -n "$arg" ]]; then
    if [[ -d "$base/$arg" ]]; then
      project="$arg"
    else
      project=$(find "$base" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | grep -i "^$arg" | head -1)
    fi
    [[ -z "$project" ]] && echo "no project matching '$arg'" && return 1
  else
    project=$(find "$base" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; \
      | fzf --prompt="${base##*/} › " --height=40%)
    [[ -z "$project" ]] && return
  fi

  cd "$base/$project" && CLAUDE_CONFIG_DIR="$claude_config" claude
}

EOF

  for acct in "${WSK_ACCOUNTS[@]}"; do
    local env_file="${WSK_DIR}/accounts/${acct}.env"

    local projects_dir github_user
    projects_dir=$(grep '^PROJECTS_DIR=' "$env_file" | cut -d= -f2-)
    github_user=$(grep '^GIT_GITHUB_USER=' "$env_file" | cut -d= -f2-)

    local fn_base="$projects_dir"
    local fn_claude_dir="$HOME/.claude-${acct}"
    local fn_gh_user="$github_user"

    # unified profile function: switches gh + opens claude
    cat >> "$out" <<EOF
function ${acct}() {
  _wsk_switch_profile "${fn_gh_user}" "${fn_claude_dir}" "${fn_base}" "\$@"
}

# gh-only shorthand
function gh-${acct}() {
  gh auth switch --user "${fn_gh_user}" 2>/dev/null && gh "\$@"
}

EOF
  done
}
