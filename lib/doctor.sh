#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# ---------------------------------------------------------------------------
# _audit_gh_login <acct_name> <github_user>
# Checks that github_user appears in `gh auth status` output and whether the
# account is currently active. Emits check_pass/check_warn/check_fail.
# ---------------------------------------------------------------------------
_audit_gh_login() {
  local acct="$1" gh_user="$2"

  if ! command -v gh >/dev/null 2>&1; then
    check_warn "gh CLI not found — skipping gh identity checks"
    return 0
  fi

  local status_output
  status_output="$(gh auth status 2>&1 || true)"

  # Exact line match: "  Logged in to github.com account <user> ..."
  local logged_in=0 is_active=0

  # Check if the user appears as a logged-in account
  if echo "$status_output" | grep -qF "Logged in to github.com account ${gh_user}"; then
    logged_in=1
    # Check if active account line follows
    if echo "$status_output" | grep -qF "Active account: true"; then
      # The active: true line needs to be associated with our user.
      # gh auth status groups output per account; check that the user line
      # appears before "Active account: true" without another "Logged in" between.
      local found_user=0
      while IFS= read -r line; do
        if echo "$line" | grep -qF "Logged in to github.com account ${gh_user}"; then
          found_user=1
        elif echo "$line" | grep -qF "Logged in to github.com account"; then
          # A different user appeared — reset
          found_user=0
        fi
        if [[ "$found_user" -eq 1 ]] && echo "$line" | grep -qF "Active account: true"; then
          is_active=1
          break
        fi
      done <<< "$status_output"
    fi
  fi

  if [[ "$logged_in" -eq 0 ]]; then
    check_warn "${acct}: gh not logged in for ${gh_user} — run: gh auth login"
  elif [[ "$is_active" -eq 1 ]]; then
    check_pass "${acct}: gh logged in as ${gh_user} (active)"
  else
    check_warn "${acct}: gh logged in as ${gh_user} (not active — run: gh auth switch)"
  fi
}

# ---------------------------------------------------------------------------
# _scan_remotes <projects_dir>
# Scans <projects_dir>/*/.git at maxdepth 2 (flat layout). Reads origin remote
# URL for each repo. Flags HTTPS github.com remotes with a check_warn.
# Stores found repos in _SCAN_REMOTES_REPOS (associative-free: uses parallel
# arrays for bash 3.2 compat).
# ---------------------------------------------------------------------------
_scan_remotes() {
  local projects_dir="$1"

  [[ -d "$projects_dir" ]] || return 0

  local found_repos=0

  # Glob for <dir>/<repo>/.git — bash 3.2 safe (no nullglob needed since we
  # check -d before acting).
  local git_dir repo_path remote_url repo_name
  for git_dir in "${projects_dir}"/*/.git; do
    [[ -d "$git_dir" ]] || continue
    repo_path="${git_dir%/.git}"
    repo_name="${repo_path##*/}"
    found_repos=1

    remote_url="$(git -C "$repo_path" remote get-url origin 2>/dev/null || true)"
    if [[ -z "$remote_url" ]]; then
      continue
    fi

    if echo "$remote_url" | grep -qF "https://github.com"; then
      check_warn "${repo_name}: remote origin is https — will use active gh account (consider: wsk fix-git)"
    fi
  done

  if [[ "$found_repos" -eq 0 ]]; then
    check_pass "no git repos found under ${projects_dir##"$HOME"/}"
  fi
}

# ---------------------------------------------------------------------------
# _audit_alias_dir <acct_name> <projects_dir>
# Scans repos under projects_dir. For each repo with a github SSH remote,
# checks that the remote alias matches the account name. Emits check_warn on
# mismatch.
# ---------------------------------------------------------------------------
_audit_alias_dir() {
  local acct="$1" projects_dir="$2"

  [[ -d "$projects_dir" ]] || return 0

  local git_dir repo_path repo_name remote_url remote_acct
  for git_dir in "${projects_dir}"/*/.git; do
    [[ -d "$git_dir" ]] || continue
    repo_path="${git_dir%/.git}"
    repo_name="${repo_path##*/}"

    remote_url="$(git -C "$repo_path" remote get-url origin 2>/dev/null || true)"
    [[ -z "$remote_url" ]] && continue
    # Only check SSH remotes with a github-{acct} alias
    if ! echo "$remote_url" | grep -q "git@github-"; then
      continue
    fi
    # Extract alias: git@github-work:org/repo.git → work
    remote_acct="${remote_url#git@github-}"
    remote_acct="${remote_acct%%:*}"

    if [[ "$remote_acct" != "$acct" ]]; then
      check_warn "${repo_name}: remote alias 'github-${remote_acct}' does not match directory account '${acct}'"
    fi
  done
}

# ---------------------------------------------------------------------------
# _audit_ssh_agent <acct_name> <ssh_key_filename>
# Per-account SSH agent checks:
#   (a) Key file exists at ~/.ssh/<ssh_key_filename>
#   (b) Key fingerprint or path is listed in the agent via ssh-add -l
#       → check_pass if loaded; check_warn with the exact fix command if not
# check_warn is emitted when ssh-add is unavailable (non-fatal).
# ---------------------------------------------------------------------------
_audit_ssh_agent() {
  local acct="$1" ssh_key="$2"
  local key_path="$HOME/.ssh/${ssh_key}"

  # (a) Key file existence
  if [[ ! -f "$key_path" ]]; then
    check_fail "${acct}: SSH key missing: ~/.ssh/${ssh_key}"
    return 0
  fi

  # ssh-add must be available for the agent check
  if ! command -v ssh-add >/dev/null 2>&1; then
    check_warn "${acct}: ssh-add not found — cannot check agent for ~/.ssh/${ssh_key}"
    return 0
  fi

  # (b) Agent check: match key path or filename in ssh-add -l output
  local agent_list
  agent_list="$(ssh-add -l 2>/dev/null || true)"
  local key_name="${ssh_key##*/}"

  if echo "$agent_list" | grep -qF "$key_path" || \
     echo "$agent_list" | grep -qE "(^| )${key_name}( |\$)"; then
    check_pass "${acct}: SSH key loaded in agent: ~/.ssh/${ssh_key}"
    return 0
  fi

  # Not loaded — warn with the exact fix command
  local fix_cmd
  if [[ "${WSK_OS:-}" == "macos" ]]; then
    fix_cmd="ssh-add --apple-use-keychain ~/.ssh/${ssh_key}"
  else
    fix_cmd="ssh-add ~/.ssh/${ssh_key}"
  fi
  check_warn "${acct}: SSH key not loaded in agent: ~/.ssh/${ssh_key} — run: ${fix_cmd}"
}

# ---------------------------------------------------------------------------
# _audit_ssh_connectivity <acct_name> <github_user> <ssh_key_filename>
# Optional SSH connectivity check: tests git@github-{acct} with BatchMode and
# ConnectTimeout so it fast-fails in offline or restricted environments.
# Only runs when WSK_SSH_CHECK=1 is set (opt-in; off by default).
# "Successfully authenticated" in stderr → check_pass. Anything else → check_warn.
# ---------------------------------------------------------------------------
_audit_ssh_connectivity() {
  local acct="$1" gh_user="$2" ssh_key="$3"

  # Skip unless explicitly opted in
  [[ "${WSK_SSH_CHECK:-}" == "1" ]] || return 0

  if ! command -v ssh >/dev/null 2>&1; then
    check_warn "${acct}: ssh not found — skipping connectivity check"
    return 0
  fi

  local ssh_output
  # GitHub returns exit 1 even on success; capture stderr for the message.
  ssh_output="$(ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no \
    -i "$HOME/.ssh/${ssh_key}" \
    -T "git@github-${acct}" 2>&1 || true)"

  if echo "$ssh_output" | grep -qi "successfully authenticated"; then
    check_pass "${acct}: SSH connectivity OK for ${gh_user} via github-${acct}"
  else
    check_warn "${acct}: SSH connectivity failed for github-${acct} — ${ssh_output%%$'\n'*}"
  fi
}

# Inspect a path expected to be a stow symlink into WSK_DIR/stow.
_check_link() {
  local target="$1" short="${1/#$HOME/~}"
  if [[ -L "$target" ]]; then
    if [[ -e "$target" ]]; then
      check_pass "linked: $short"
    else
      check_warn "broken link: $short"
    fi
  elif [[ -e "$target" ]]; then
    check_warn "exists but not linked: $short"
  else
    check_fail "missing: $short"
  fi
}

# ~/.zshrc is not symlinked: WSK splices a managed block into the user's own
# file. Verify the block is present rather than checking for a symlink.
_check_zshrc_block() {
  local rc="$HOME/.zshrc"
  if [[ ! -f "$rc" ]]; then
    check_fail "missing: ~/.zshrc"
  elif grep -qF '# >>> work-swift-kit >>>' "$rc" 2>/dev/null; then
    check_pass "managed block: ~/.zshrc"
  else
    check_warn "$HOME/.zshrc exists but has no Work-Swift-Kit block — run: wsk relink"
  fi
}

# Read-only health check of dependencies, packages, links and accounts.
_run_doctor_output() {
  ui_section "Check configuration"
  load_accounts

  ui_subhead "Dependencies"
  for bin in brew gum stow fzf; do
    if command -v "$bin" &>/dev/null; then check_pass "$bin installed"; else check_fail "$bin missing"; fi
  done
  if command -v envsubst &>/dev/null; then check_pass "gettext (envsubst) installed"; else check_fail "gettext missing"; fi

  ui_subhead "Base packages"
  # label:binary — ripgrep ships the `rg` binary, the rest match their name.
  local entry label bin
  for entry in git gh fzf ripgrep:rg bat eza fd sd starship zoxide jq tree; do
    label="${entry%%:*}"; bin="${entry##*:}"
    if command -v "$bin" &>/dev/null; then check_pass "$label"; else check_warn "$label not on PATH"; fi
  done

  # ── OS / Package manager ─────────────────────────────────────────────
  ui_subhead "OS / Package manager"
  # Run detection only when not already exported (preserves test-injected values).
  if [[ -z "${WSK_OS+x}" ]]; then
    detect_os
  fi
  if [[ -z "${WSK_PKG_MGR+x}" ]]; then
    detect_pkg_mgr || true
  fi

  if [[ -n "${WSK_OS:-}" ]]; then
    check_pass "OS: ${WSK_OS}"
  fi

  if [[ -n "${WSK_PKG_MGR:-}" ]]; then
    check_pass "pkg manager: ${WSK_PKG_MGR}"
  else
    check_warn "no recognized package manager detected"
  fi

  # ── Node / pnpm ──────────────────────────────────────────────────────
  ui_subhead "Node / pnpm"
  if command -v node &>/dev/null; then
    check_pass "node installed"
  else
    check_fail "node missing — run: wsk ai"
  fi
  if command -v pnpm &>/dev/null; then
    check_pass "pnpm installed"
  else
    check_fail "pnpm missing"
  fi

  # ── Claude Code ──────────────────────────────────────────────────────
  ui_subhead "Claude Code"
  if command -v claude &>/dev/null; then
    check_pass "claude installed"
  else
    check_fail "claude not installed — run: wsk ai"
  fi

  # ── Claude productivity tools ─────────────────────────────────────────
  ui_subhead "Claude productivity tools"
  if command -v rtk &>/dev/null; then
    check_pass "rtk installed"
  else
    check_warn "rtk not installed (optional) — run: wsk ai"
  fi

  local _tool_acct _settings
  for _tool_acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    _settings="${HOME}/.claude-${_tool_acct}/settings.json"

    if command -v rtk &>/dev/null; then
      if [[ -f "$_settings" ]] && grep -q 'rtk hook claude' "$_settings" 2>/dev/null; then
        check_pass "${_tool_acct}: rtk hook wired"
      else
        check_warn "${_tool_acct}: rtk hook missing — run: wsk ai"
      fi
    fi

    if [[ -f "$_settings" ]] && grep -q '"caveman@caveman"' "$_settings" 2>/dev/null; then
      check_pass "${_tool_acct}: caveman plugin enabled"
    else
      check_warn "${_tool_acct}: caveman plugin not enabled (optional) — run: wsk ai"
    fi

    # Duplicate-install guard: standalone caveman hooks alongside the plugin
    # cause every hook to fire twice.
    if [[ -f "$_settings" ]] && grep -q '"caveman@caveman"' "$_settings" 2>/dev/null \
       && grep -q 'caveman-activate.js' "$_settings" 2>/dev/null; then
      check_warn "${_tool_acct}: caveman installed twice (plugin + manual hooks) — remove manual hook entries from settings.json"
    fi
  done

  # ── ~/.claude ancestor-traversal guard ───────────────────────────────
  ui_subhead "Claude config hygiene"
  local _dot_claude="$HOME/.claude"
  local _has_account_dirs=0
  local _check_acct
  for _check_acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    if [[ -d "$HOME/.claude-${_check_acct}" ]]; then
      _has_account_dirs=1
      break
    fi
  done
  if [[ -L "$_dot_claude" ]] && [[ "$(readlink "$_dot_claude")" == "$HOME/.claude-"* ]]; then
    # Symlink pointing into a WSK account dir — definite double-load.
    check_fail "ancestor-traversal double-load: ~/.claude is a symlink into ~/.claude-* — CLAUDE.md and skills load twice; run: wsk fix-claude"
  elif [[ $_has_account_dirs -eq 1 ]] && [[ -e "$_dot_claude" || -L "$_dot_claude" ]]; then
    # Real directory (or foreign symlink) coexisting with WSK account dirs.
    check_warn "~/.claude exists alongside ~/.claude-{acct} dirs — may cause double-load of CLAUDE.md and skills; run: wsk fix-claude if this is unintentional"
  elif [[ $_has_account_dirs -eq 0 ]]; then
    check_pass "~/.claude ancestor-traversal check: no account dirs provisioned — not applicable"
  else
    check_pass "~/.claude absent — no ancestor-traversal risk"
  fi

  # ── AI frameworks (per account) ──────────────────────────────────────
  ui_subhead "AI frameworks (per account)"

  # Global codegraph check
  if command -v codegraph &>/dev/null; then
    check_pass "codegraph installed"
  else
    check_warn "codegraph not installed (optional)"
  fi

  local acct env_file framework
  for acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    env_file="${WSK_DIR}/accounts/${acct}.env"
    framework=""
    if [[ -f "$env_file" ]]; then
      framework="$(grep '^AI_FRAMEWORK=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"
    fi

    if [[ -z "$framework" ]]; then
      check_warn "${acct}: AI_FRAMEWORK not set — run: wsk ai"
      continue
    fi

    local cfg_dir="${HOME}/.claude-${acct}"

    case "$framework" in
      gentle-ai)
        if command -v gentle-ai &>/dev/null; then
          check_pass "${acct}: AI_FRAMEWORK=gentle-ai (installed)"
        else
          check_fail "${acct}: gentle-ai not found on PATH"
        fi
        ;;
      gsd)
        if command -v get-shit-done-cc &>/dev/null || command -v gsd &>/dev/null; then
          check_pass "${acct}: AI_FRAMEWORK=gsd (installed)"
        else
          check_fail "${acct}: gsd not found on PATH"
        fi
        ;;
      superpowers)
        if [[ -d "${cfg_dir}/superpowers" ]]; then
          check_pass "${acct}: AI_FRAMEWORK=superpowers (installed)"
        else
          check_fail "${acct}: superpowers dir missing at ${cfg_dir}/superpowers"
        fi
        ;;
      *)
        check_warn "${acct}: unknown framework '${framework}'"
        ;;
    esac
  done

  # ── Skills (per account) ─────────────────────────────────────────────
  ui_subhead "Skills (per account)"
  local skill skills_dir
  for acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    env_file="${WSK_DIR}/accounts/${acct}.env"
    framework=""
    if [[ -f "$env_file" ]]; then
      framework="$(grep '^AI_FRAMEWORK=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"
    fi

    if [[ "$framework" == "gentle-ai" ]]; then
      check_pass "${acct}: skills bundled by gentle-ai"
      continue
    fi

    skills_dir="${HOME}/.claude-${acct}/skills"
    for skill in branch-pr chained-pr work-unit-commits comment-writer issue-creation judgment-day; do
      if [[ -d "${skills_dir}/${skill}" ]]; then
        check_pass "${acct}: ${skill} skill present"
      else
        check_warn "${acct}: ${skill} skill missing"
      fi
    done
  done

  ui_subhead "Dotfile links"
  _check_link "$HOME/.gitconfig"
  _check_link "$HOME/.gitignore_global"
  _check_zshrc_block
  _check_link "$HOME/.ssh/config"

  ui_subhead "Accounts (${#WSK_ACCOUNTS[@]})"
  if ((${#WSK_ACCOUNTS[@]} == 0)); then
    check_warn "No accounts configured yet — run: wsk setup"
  else
    local ssh_key acct_fw
    for acct in "${WSK_ACCOUNTS[@]}"; do
      check_pass "account: $acct"
      _check_link "$HOME/.gitconfig-${acct}"
      acct_fw=$(grep '^AI_FRAMEWORK=' "${WSK_DIR}/accounts/${acct}.env" 2>/dev/null | cut -d= -f2- || true)
      if [[ "$acct_fw" == "gentle-ai" ]]; then
        if [[ -f "$HOME/.claude-${acct}/CLAUDE.md" ]]; then
          check_pass "CLAUDE.md: managed by gentle-ai"
          # Check for @RTK.md import when RTK.md is absent from the account dir.
          if grep -qF '@RTK.md' "$HOME/.claude-${acct}/CLAUDE.md" 2>/dev/null \
             && [[ ! -f "$HOME/.claude-${acct}/RTK.md" ]]; then
            check_warn "${acct}: CLAUDE.md references @RTK.md but RTK.md is missing — run: wsk fix-claude"
          fi
          # Check for Sub-Agent Context Minimalism block markers.
          if ! grep -qF '<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:BEGIN -->' "$HOME/.claude-${acct}/CLAUDE.md" 2>/dev/null; then
            check_warn "${acct}: CLAUDE.md missing minimalism block (drift after raw gentle-ai sync) — run: wsk fix-claude"
          fi
        else
          check_warn "CLAUDE.md: missing — run gentle-ai install"
        fi
      else
        _check_link "$HOME/.claude-${acct}/CLAUDE.md"
      fi
      ssh_key=$(grep '^WSK_SSH_KEY=' "${WSK_DIR}/accounts/${acct}.env" 2>/dev/null | cut -d= -f2- || true)
      if [[ -z "$ssh_key" ]]; then
        check_warn "ssh key: not configured — run: wsk accounts"
      elif [[ -f "$HOME/.ssh/${ssh_key}" ]]; then
        check_pass "ssh key: ~/.ssh/${ssh_key}"
      else
        check_fail "ssh key missing: ~/.ssh/${ssh_key}"
      fi
    done
  fi

  # ── SSH agent (per account) ───────────────────────────────────────────
  ui_subhead "SSH agent"
  local _sa_acct _sa_key _sa_gh_user
  for _sa_acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    _sa_key="$(grep '^WSK_SSH_KEY=' "${WSK_DIR}/accounts/${_sa_acct}.env" 2>/dev/null | cut -d= -f2- || true)"
    _sa_gh_user="$(grep '^GIT_GITHUB_USER=' "${WSK_DIR}/accounts/${_sa_acct}.env" 2>/dev/null | cut -d= -f2- || true)"
    if [[ -n "$_sa_key" ]]; then
      _audit_ssh_agent "$_sa_acct" "$_sa_key"
      if [[ -n "$_sa_gh_user" ]]; then
        _audit_ssh_connectivity "$_sa_acct" "$_sa_gh_user" "$_sa_key"
      fi
    fi
  done

  ui_subhead "GitHub auth"
  if command -v gh &>/dev/null; then
    if gh auth status &>/dev/null; then check_pass "gh authenticated"; else check_warn "gh not authenticated — run: gh auth login"; fi
  else
    check_fail "gh not installed"
  fi

  # ── git / gh identity audit (per account) ────────────────────────────
  ui_subhead "git / gh identity"
  local gh_user projects_dir env_file
  for acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    env_file="${WSK_DIR}/accounts/${acct}.env"
    gh_user="$(grep '^GIT_GITHUB_USER=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"
    projects_dir="$(grep '^PROJECTS_DIR=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"

    if [[ -n "$gh_user" ]]; then
      _audit_gh_login "$acct" "$gh_user"
    fi
    if [[ -n "$projects_dir" ]]; then
      _scan_remotes "$projects_dir"
      _audit_alias_dir "$acct" "$projects_dir"
    fi
  done

  echo
}

run_doctor() {
  load_accounts
  # Guard: abort if no accounts are configured.
  # Inline check so run_doctor works standalone (test contexts that source
  # lib/doctor.sh directly without lib/preflight.sh still get the guard).
  local _dr_count=0
  if [[ -n "${WSK_ACCOUNTS+x}" ]]; then _dr_count="${#WSK_ACCOUNTS[@]}"; fi
  if [[ "$_dr_count" -eq 0 ]]; then
    check_warn "No accounts configured — run: wsk accounts"
    return 0
  fi
  _run_doctor_output
}
