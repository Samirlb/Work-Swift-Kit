#!/usr/bin/env bash
set -euo pipefail

# frameworks.sh — Per-account AI framework selection, curated skills install, and shared loop driver.
# Depends on: lib/log.sh, lib/ui.sh, lib/os.sh, lib/node.sh, lib/claude.sh, lib/accounts.sh.

# Guard against double-source.
if declare -f install_ai_framework > /dev/null 2>&1; then
  return 0
fi

# Pinned skills source repo (LOCKED URL — do not change without tasks review).
WSK_SKILLS_REPO="${WSK_SKILLS_REPO:-https://github.com/Gentleman-Programming/gentle-ai}"

# ---------------------------------------------------------------------------
# _persist_account_kv <env_file> <key> <value>
# Idempotent upsert: if key exists, replace its line via sd; else append.
# Uses sd (base package) to avoid sed -i portability issues across macOS/Linux.
# ---------------------------------------------------------------------------
_persist_account_kv() {
  local file="$1" key="$2" val="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sd "^${key}=.*" "${key}=${val}" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$file"
  fi
}

# ---------------------------------------------------------------------------
# _fetch_skill <name> <dest>
# Shallow-clones WSK_SKILLS_REPO to a tmpdir, copies skills/<name>/ to dest.
# Idempotent: if dest already exists, returns immediately without cloning.
# Warns (check_warn) on failure; never crashes the caller.
# ---------------------------------------------------------------------------
_fetch_skill() {
  local name="$1" dest="$2"

  if [[ -d "$dest" ]]; then
    check_pass "${name} skill already present"
    return 0
  fi

  local tmp
  tmp="$(mktemp -d)"

  if git clone --depth 1 "$WSK_SKILLS_REPO" "$tmp" &>/dev/null \
     && [[ -d "$tmp/skills/$name" ]]; then
    mkdir -p "$dest"
    cp -R "$tmp/skills/$name/." "$dest/"
    check_pass "${name} skill installed"
  else
    check_warn "${name}: skill source unavailable (set WSK_SKILLS_REPO)"
  fi

  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# install_curated_skills <account> <framework>
# Installs the 6 curated skills into ~/.claude-{acct}/skills/{name}/.
# For gentle-ai accounts: skips (gentle-ai bundles equivalent skills).
# For all others: loops 6 skills, calls _fetch_skill per skill.
# ---------------------------------------------------------------------------
install_curated_skills() {
  local acct="$1" framework="$2"
  local skills_dir="${HOME}/.claude-${acct}/skills"

  if [[ "$framework" == "gentle-ai" ]]; then
    check_pass "${acct}: skills bundled by gentle-ai"
    return 0
  fi

  mkdir -p "$skills_dir"

  local name
  for name in branch-pr chained-pr work-unit-commits comment-writer issue-creation judgment-day; do
    _fetch_skill "$name" "$skills_dir/$name"
  done
}

# ---------------------------------------------------------------------------
# install_ai_framework <account>
# Presents an exclusive framework choice (or reuses an existing persisted one),
# installs the chosen framework with CLAUDE_CONFIG_DIR scoped to the account,
# and persists the choice to accounts/{acct}.env.
# ---------------------------------------------------------------------------
install_ai_framework() {
  local acct="$1"
  local env_file="${WSK_DIR}/accounts/${acct}.env"
  local cfg_dir="${HOME}/.claude-${acct}"

  mkdir -p "$cfg_dir"

  # Re-run honoring: read existing AI_FRAMEWORK from env file.
  local choice=""
  if [[ -f "$env_file" ]]; then
    choice="$(grep '^AI_FRAMEWORK=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"
  fi

  if [[ -z "$choice" ]]; then
    choice="$(ui_choose "AI framework for ${acct}:" "gentle-ai" "gsd" "superpowers")"
  fi

  # Install the chosen framework with CLAUDE_CONFIG_DIR scoped to this account.
  export CLAUDE_CONFIG_DIR="$cfg_dir"

  case "$choice" in
    gentle-ai)
      # Tap + install (idempotent via command -v gentle-ai)
      if ! command -v gentle-ai &>/dev/null; then
        brew tap Gentleman-Programming/homebrew-tap
        brew install gentle-ai
      fi
      CLAUDE_CONFIG_DIR="$cfg_dir" gentle-ai install --agent claude-code
      ;;

    gsd)
      # Primary: npx; fallback: git clone
      if ! CLAUDE_CONFIG_DIR="$cfg_dir" npx get-shit-done-cc --global; then
        log_info "npx gsd failed — falling back to git clone"
        git clone https://github.com/gsd-build/get-shit-done "$cfg_dir/gsd"
      fi
      ;;

    superpowers)
      # Clone if not already present
      if [[ ! -d "$cfg_dir/superpowers" ]]; then
        git clone https://github.com/obra/superpowers "$cfg_dir/superpowers"
      fi
      log_info "Open Claude and run: /plugin install"
      ;;

    *)
      log_warn "install_ai_framework: unknown framework '${choice}'"
      return 1
      ;;
  esac

  # Persist the choice (upsert)
  _persist_account_kv "$env_file" AI_FRAMEWORK "$choice"
}

# ---------------------------------------------------------------------------
# run_ai_for_all_accounts
# Shared per-account loop used by run_full_setup, the menu, and wsk ai.
# For each account: installs the framework, optionally installs codegraph,
# then installs curated skills.
# ---------------------------------------------------------------------------
run_ai_for_all_accounts() {
  local acct framework

  for acct in "${WSK_ACCOUNTS[@]}"; do
    install_ai_framework "$acct"

    # Read persisted framework choice (set by install_ai_framework above).
    framework=""
    local env_file="${WSK_DIR}/accounts/${acct}.env"
    if [[ -f "$env_file" ]]; then
      framework="$(grep '^AI_FRAMEWORK=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"
    fi

    if ui_confirm "Install codegraph for ${acct}?"; then
      install_codegraph "$acct"
    fi

    install_curated_skills "$acct" "$framework"
  done
}

# ---------------------------------------------------------------------------
# run_ai
# Standalone entry point for `wsk ai`.
# Loads accounts, detects env, installs global tooling, then runs the per-account loop.
# ---------------------------------------------------------------------------
run_ai() {
  load_accounts
  detect_os
  detect_pkg_mgr || true
  install_node
  install_pnpm
  install_claude_code
  run_ai_for_all_accounts
}
