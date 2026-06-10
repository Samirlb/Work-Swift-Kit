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
# _patch_gentle_ai_commands <cfg_dir>
# Fixes shell patterns in gentle-ai generated command files that Claude Code
# rejects at permission-check time (e.g. `basename "$(pwd)"` uses $() which
# can't be statically analyzed). Safe to run on every install/sync.
# ---------------------------------------------------------------------------
_patch_gentle_ai_commands() {
  local cfg_dir="$1"
  local commands_dir="${cfg_dir}/commands"
  [[ -d "$commands_dir" ]] || return 0
  local f
  for f in "$commands_dir"/*.md; do
    [[ -f "$f" ]] || continue
    # shellcheck disable=SC2016  # single quotes intentional: matching literal $() in file content
    sed -i '' '/basename.*\$.*pwd\|basename.*\$(pwd)/d' "$f" 2>/dev/null || true
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
      if ! command -v gentle-ai &>/dev/null; then
        brew tap Gentleman-Programming/homebrew-tap
        brew install gentle-ai
      fi
      # gentle-ai owns CLAUDE.md — drop any stale copy so install regenerates it.
      # (cfg_dir is swapped to ~/.claude by _gentle_ai_scoped, so removing it here
      # is equivalent to removing ~/.claude/CLAUDE.md after the swap.)
      rm -f "$cfg_dir/CLAUDE.md"
      # gentle-ai only operates on ~/.claude and ignores CLAUDE_CONFIG_DIR, so
      # scope each step to this account's dir via the swap helper.
      _gentle_ai_scoped "$cfg_dir" install --agent claude-code
      # Sync managed configs + skills to the current gentle-ai version.
      _gentle_ai_scoped "$cfg_dir" sync
      # gentle-ai generates `!`basename "$(pwd)"`` in sdd-new.md which Claude Code
      # rejects at permission-check time ($() can't be statically analyzed).
      _patch_gentle_ai_commands "$cfg_dir"
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

  if [[ "${#WSK_ACCOUNTS[@]}" -eq 0 ]]; then
    load_accounts
  fi

  if [[ "${#WSK_ACCOUNTS[@]}" -eq 0 ]]; then
    log_warn "No accounts configured — run accounts setup first."
    return 0
  fi

  for acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
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
# _gentle_ai_scoped <cfg_dir> <gentle-ai args...>
# Runs a gentle-ai command scoped to a single account's config dir.
#
# gentle-ai always operates on ~/.claude and IGNORES CLAUDE_CONFIG_DIR (the var
# does not appear in its binary), so the only way to target a per-account dir is
# to physically place it at ~/.claude for the duration of the command.
#
# This swap is unconditional: whatever ~/.claude currently is — a symlink, a
# real directory, or nothing — is snapshotted and restored afterward. That makes
# per-account scoping deterministic on fresh installs too, not just when the user
# happens to have pre-created a ~/.claude symlink.
#
# CLAUDE_CONFIG_DIR is intentionally NOT exported here: setting it to the old
# cfg_dir path (which no longer exists during the swap) caused newer gentle-ai
# versions to create a nested ~/.claude-{acct}/.claude/ tree on each sync run,
# accumulating duplicate skill directories. The dir is already at ~/.claude, so
# tools that honor CLAUDE_CONFIG_DIR will find it there via the default path.
# ---------------------------------------------------------------------------
_gentle_ai_scoped() {
  local cfg_dir="$1"; shift

  local dot="$HOME/.claude"
  local had_link=0 link_target="" stash=""

  # Snapshot whatever ~/.claude is now so we can put it back later.
  if [[ -L "$dot" ]]; then
    had_link=1
    link_target="$(readlink "$dot")"
    rm "$dot"
  elif [[ -e "$dot" ]]; then
    stash="${dot}.wsk-stash.$$"
    mv "$dot" "$stash"
  fi

  # Put this account's real dir at ~/.claude, run gentle-ai, move it back.
  mv "$cfg_dir" "$dot"
  gentle-ai "$@" || true
  # Remove any nested .claude/ gentle-ai may have created inside the config dir.
  rm -rf "$dot/.claude"
  mv "$dot" "$cfg_dir"

  # Restore the original ~/.claude (symlink, stashed dir, or leave absent).
  if (( had_link )); then
    ln -sfn "$link_target" "$dot"
  elif [[ -n "$stash" ]]; then
    mv "$stash" "$dot"
  fi
}

# ---------------------------------------------------------------------------
# sync_gentle_ai_accounts
# Runs `gentle-ai sync` for every account whose AI_FRAMEWORK is gentle-ai,
# scoped to each account's ~/.claude-{acct} dir. Used by `wsk update` and the
# dedicated `wsk sync` command so both new and existing installs stay current.
# ---------------------------------------------------------------------------
sync_gentle_ai_accounts() {
  if ! command -v gentle-ai &>/dev/null; then
    log_warn "gentle-ai not installed — skipping sync."
    return 0
  fi

  if [[ "${#WSK_ACCOUNTS[@]}" -eq 0 ]]; then
    load_accounts
  fi

  local acct fw env_file synced=0
  for acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    env_file="${WSK_DIR}/accounts/${acct}.env"
    fw="$(grep '^AI_FRAMEWORK=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"
    [[ "$fw" == "gentle-ai" ]] || continue

    synced=1
    log_info "Syncing gentle-ai for ${acct}..."
    local acct_dir="${HOME}/.claude-${acct}"
    _gentle_ai_scoped "$acct_dir" sync
    _patch_gentle_ai_commands "$acct_dir"
    check_pass "${acct}: gentle-ai synced"
  done

  (( synced )) || log_info "No gentle-ai accounts to sync."
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
  if ui_confirm "Install RTK (Bash output compression for Claude)?"; then
    install_rtk
  fi
  if ui_confirm "Install Caveman (response token compression for Claude)?"; then
    install_caveman
  fi
  run_ai_for_all_accounts
}
