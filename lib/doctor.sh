#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

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

  ui_subhead "GitHub auth"
  if command -v gh &>/dev/null; then
    if gh auth status &>/dev/null; then check_pass "gh authenticated"; else check_warn "gh not authenticated — run: gh auth login"; fi
  else
    check_fail "gh not installed"
  fi

  echo
}

run_doctor() {
  _run_doctor_output
}
