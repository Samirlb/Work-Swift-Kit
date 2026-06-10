#!/usr/bin/env bash
set -euo pipefail

# render_zshrc — builds the Work-Swift-Kit shell fragment.
#
# IMPORTANT: this NO LONGER owns the whole ~/.zshrc. It renders a fragment to
# ${WSK_DIR}/.rendered/wsk-zshrc; lib/stow.sh:inject_zshrc_block() then splices
# that fragment into the user's real ~/.zshrc between managed markers, so any
# pre-existing user config is preserved.
render_zshrc() {
  local out="${WSK_DIR}/.rendered/wsk-zshrc"
  mkdir -p "${WSK_DIR}/.rendered"

  cat > "$out" <<'EOF'
# typeset -U keeps $path unique — macOS path_helper already adds
# /opt/homebrew/bin, so a raw export would duplicate it.
typeset -U path PATH
path=(/opt/homebrew/bin "$HOME/Library/pnpm" "$HOME/.fzf/bin" $path)

autoload -Uz compinit && compinit

eval "$(starship init zsh)"
eval "$(zoxide init zsh)"

EOF

  # claude wrapper — bare `claude` resolves the account, then launches
  # Claude Code with that account's CLAUDE_CONFIG_DIR.
  #   - If CLAUDE_CONFIG_DIR is already set (e.g. via the work/personal helpers
  #     or claude-<acct> shorthands), honor it and skip everything.
  #   - If $PWD is inside an account's PROJECTS_DIR, use that account
  #     automatically — no prompt (mirrors git's includeIf behavior).
  #   - 0 accounts → plain claude.  1 account → use it directly, no prompt.
  #   - 2+ accounts outside any PROJECTS_DIR → fzf picker.
  local acct_list="" acct_dir_list="" _pd
  for acct in "${WSK_ACCOUNTS[@]}"; do
    acct_list+="\"${acct}\" "
    _pd=$(grep '^PROJECTS_DIR=' "${WSK_DIR}/accounts/${acct}.env" | cut -d= -f2-)
    [[ -n "$_pd" ]] && acct_dir_list+="\"${acct}:${_pd}\" "
  done

  cat >> "$out" <<EOF
function claude() {
  if [[ -n "\${CLAUDE_CONFIG_DIR:-}" ]]; then
    command claude "\$@"
    return
  fi

  local -a _wsk_accts=(${acct_list})
  local -a _wsk_acct_dirs=(${acct_dir_list})

  if (( \${#_wsk_accts[@]} == 0 )); then
    command claude "\$@"
    return
  fi

  # Auto-detect account from the current directory.
  local _pair _acct _dir
  for _pair in "\${_wsk_acct_dirs[@]}"; do
    _acct="\${_pair%%:*}"
    _dir="\${_pair#*:}"
    if [[ "\$PWD" == "\$_dir" || "\$PWD" == "\$_dir"/* ]]; then
      CLAUDE_CONFIG_DIR="\$HOME/.claude-\${_acct}" command claude "\$@"
      return
    fi
  done

  if (( \${#_wsk_accts[@]} == 1 )); then
    CLAUDE_CONFIG_DIR="\$HOME/.claude-\${_wsk_accts[1]}" command claude "\$@"
    return
  fi

  local _choice
  _choice=\$(printf '%s\\n' "\${_wsk_accts[@]}" | fzf --prompt="claude › " --height=40% --reverse) || return
  [[ -z "\$_choice" ]] && return
  CLAUDE_CONFIG_DIR="\$HOME/.claude-\${_choice}" command claude "\$@"
}

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

# claude-only shorthand: launch claude with account config, no cd, no gh switch
function claude-${acct}() {
  CLAUDE_CONFIG_DIR="${fn_claude_dir}" claude "\$@"
}

# gh-only shorthand
function gh-${acct}() {
  gh auth switch --user "${fn_gh_user}" 2>/dev/null && gh "\$@"
}

EOF
  done
}
