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
    if command -v sd >/dev/null 2>&1; then
      sd "^${key}=.*" "${key}=${val}" "$file"
    else
      # Fallback: POSIX awk in-place rewrite when sd is absent.
      local tmp
      tmp="$(mktemp)"
      awk -v k="$key" -v v="$val" '
        $0 ~ ("^"k"=") { print k"="v; next }
        { print }
      ' "$file" > "$tmp" && mv "$tmp" "$file"
    fi
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
  # Derive the per-account dir name from cfg_dir (e.g. ~/.claude-work → .claude-work)
  local cfg_dir_name="${cfg_dir##*/}"
  local f
  for f in "$commands_dir"/*.md; do
    [[ -f "$f" ]] || continue
    # shellcheck disable=SC2016  # single quotes intentional: matching literal $() in file content
    # NOTE: keep the pattern BSD-sed compatible — `\|` alternation is GNU-only
    # and silently never matches on macOS, turning this patch into a no-op.
    sed -i '' '/basename.*pwd/d' "$f" 2>/dev/null || true
    # Rewrite hardcoded ~/.claude/skills/ to the per-account skills path.
    # Delimiter | avoids conflicts with path separators.
    # Pattern is idempotent: after the first rewrite ~/.claude/skills/ is gone,
    # so subsequent runs are no-ops.
    # NOTE: `\|` alternation in sed is GNU-only and silently no-ops on macOS BSD sed.
    # We use a single literal pattern here — no alternation needed.
    sed -i '' "s|~/.claude/skills|~/${cfg_dir_name}/skills|g" "$f" 2>/dev/null || true
  done
}

# ---------------------------------------------------------------------------
# _patch_gentle_ai_claude_md <cfg_dir>
# Idempotently ensures two things in <cfg_dir>/CLAUDE.md after a gentle-ai
# install or sync:
#   1. A marker-guarded Sub-Agent Context Minimalism block is present (replaces
#      any existing block between the markers; appends if absent).
#   2. An @RTK.md import line appears at the end of the file (only when RTK.md
#      exists in the same cfg_dir; the line is added once, not duplicated).
# Safe to call multiple times — both operations are idempotent.
# ---------------------------------------------------------------------------
_patch_gentle_ai_claude_md() {
  local cfg_dir="$1"
  local md_file="${cfg_dir}/CLAUDE.md"
  [[ -f "$md_file" ]] || return 0

  local begin_marker="<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:BEGIN -->"
  local end_marker="<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:END -->"

  # Build the minimalism block content (no leading/trailing blank lines so
  # sed multiline replacement stays predictable).
  local block
  block="${begin_marker}
## Sub-Agent Context Minimalism (MANDATORY)

Every sub-agent (SDD phases included) loads ONLY what its task requires. Saturating sub-agent context is a discipline failure.

- Inject only the skill paths that match the phase's code context and task context. Never pass the full skill registry or unrelated skills.
- Pass artifact references (engram topic keys or file paths), never inline artifact content the sub-agent can fetch itself.
- Forward only the role contract for that phase — not the orchestrator's full instructions, persona, or conversation history.
- SDD phases read only their declared dependencies from the phase read/write table. No \"context just in case\".
- Sub-agents must not load skills outside the injected list, must not orchestrate or spawn further agents, and must not re-read the registry unless their \`skill_resolution\` fallback fires.
- When in doubt between passing more or less context, pass less and include the reference needed to fetch the rest.
${end_marker}"

  # Replace or append the minimalism block.
  if grep -qF "$begin_marker" "$md_file" 2>/dev/null; then
    # Block already present — replace the entire region between markers (inclusive).
    if command -v python3 >/dev/null 2>&1; then
      # Use a Python one-liner for reliable multi-line replacement.
      python3 - "$md_file" "$begin_marker" "$end_marker" "$block" <<'PYEOF'
import sys, re
path, begin, end, replacement = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(path, 'r') as f:
    content = f.read()
pattern = re.escape(begin) + r'.*?' + re.escape(end)
new_content = re.sub(pattern, lambda m: replacement, content, flags=re.DOTALL)
with open(path, 'w') as f:
    f.write(new_content)
PYEOF
    else
      # Fallback: awk strip-and-reappend when python3 is absent.
      local tmp
      tmp="$(mktemp)"
      awk -v b="$begin_marker" -v e="$end_marker" '
        $0==b {skip=1; next}
        $0==e {skip=0; next}
        !skip {print}
      ' "$md_file" > "$tmp"
      printf '%s\n' "$block" >> "$tmp"
      mv "$tmp" "$md_file"
    fi
  else
    # Block absent — append it with a preceding blank line for readability.
    printf '\n%s\n' "$block" >> "$md_file"
  fi

  # Append @RTK.md import if RTK.md exists in the same dir and the line is absent.
  if [[ -f "${cfg_dir}/RTK.md" ]] && ! grep -qF '@RTK.md' "$md_file" 2>/dev/null; then
    printf '\n@RTK.md\n' >> "$md_file"
  fi
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

  # Reconfigure gate: opt-in, only active when WSK_AI_RECONFIGURE=1 (set by run_ai).
  # When an account already has a framework set and the gate is on, ask the user
  # whether they want to reconfigure (default No). This keeps unattended runs clean.
  local _force_install=0
  if [[ -n "$choice" && "${WSK_AI_RECONFIGURE:-0}" == "1" ]]; then
    if ui_confirm "Reconfigure AI framework for ${acct}? (currently ${choice})" --default-no; then
      # Warn: ~/.gentle-ai/state.json is global — persona/model changes affect ALL accounts.
      log_warn "Note: ~/.gentle-ai/state.json is GLOBAL — persona and model assignments affect ALL configured accounts."
      local _uninstall_rc=0
      _gentle_ai_scoped "$cfg_dir" uninstall --agent claude-code --yes || _uninstall_rc=$?
      if [[ "$_uninstall_rc" -eq 0 ]]; then
        _force_install=1
        choice=""
      else
        log_warn "${acct}: gentle-ai uninstall failed (rc=${_uninstall_rc}) — keeping existing framework"
      fi
    fi
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
      # gentle-ai only operates on ~/.claude and ignores CLAUDE_CONFIG_DIR, so
      # scope each step to this account's dir via the swap helper.
      #
      # `install` registers marketplace plugin entries in Claude Code's internal
      # registry. Running it more than once stacks duplicate entries (visible as
      # duplicate skills in /skills). Only run install when this account has not
      # been initialized yet (settings.json is the canonical marker gentle-ai
      # creates during install). Subsequent runs use sync-only, which is idempotent.
      # _force_install=1 when reconfigure was accepted: bypass the settings.json guard
      # so the full install re-runs (upstream uninstall removed plugin entries).
      if [[ ! -f "$cfg_dir/settings.json" || "$_force_install" -eq 1 ]]; then
        # gentle-ai owns CLAUDE.md — drop any stale copy so install regenerates it.
        rm -f "$cfg_dir/CLAUDE.md"
        local _ga_install_rc=0
        _gentle_ai_scoped "$cfg_dir" install --agent claude-code || _ga_install_rc=$?
        if [[ "$_ga_install_rc" -ne 0 ]]; then
          check_warn "gentle-ai install failed for ${acct} — AI_FRAMEWORK not saved"
          return "$_ga_install_rc"
        fi
      fi
      # Sync managed configs + skills to the current gentle-ai version.
      _gentle_ai_scoped "$cfg_dir" sync
      # gentle-ai generates `!`basename "$(pwd)"`` in sdd-new.md which Claude Code
      # rejects at permission-check time ($() can't be statically analyzed).
      _patch_gentle_ai_commands "$cfg_dir"
      # Ensure CLAUDE.md contains WSK-managed content (minimalism block + @RTK.md).
      _patch_gentle_ai_claude_md "$cfg_dir"
      ;;

    gsd)
      # Primary: npx @opengsd/get-shit-done-redux@latest
      # Fallback: old package with deprecation warning (community fork must not block install)
      if ! CLAUDE_CONFIG_DIR="$cfg_dir" npx @opengsd/get-shit-done-redux@latest --global; then
        log_warn "DEPRECATED: @opengsd/get-shit-done-redux unavailable — falling back to get-shit-done-cc. Migrate to: npx @opengsd/get-shit-done-redux@latest"
        if ! CLAUDE_CONFIG_DIR="$cfg_dir" npx get-shit-done-cc --global; then
          log_info "npx gsd fallback failed — trying git clone"
          git clone https://github.com/open-gsd/get-shit-done-redux "$cfg_dir/gsd"
        fi
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
  # Hide `gemini` from PATH: the caveman installer detects it and runs
  # `gemini extensions install` which hangs on its interactive trust prompt.
  local _gemini_path
  _gemini_path="$(command -v gemini 2>/dev/null || true)"
  local _tmp_mask=""
  if [[ -n "$_gemini_path" ]]; then
    _tmp_mask="$(mktemp -d)"
    # Stub that exits 0 immediately — caveman's `command -v gemini` still succeeds
    # but the extension install becomes a no-op instead of blocking.
    printf '#!/usr/bin/env bash\nexit 0\n' > "$_tmp_mask/gemini"
    chmod +x "$_tmp_mask/gemini"
    export PATH="$_tmp_mask:$PATH"
  fi

  mv "$cfg_dir" "$dot"
  local _ga_rc=0
  command gentle-ai "$@" || _ga_rc=$?

  if [[ -n "$_tmp_mask" ]]; then
    rm -rf "$_tmp_mask"
    # Restore PATH by removing the prepended dir
    export PATH="${PATH#"$_tmp_mask:"}"
  fi
  # Remove any nested .claude/ gentle-ai may have created inside the config dir.
  rm -rf "$dot/.claude"
  mv "$dot" "$cfg_dir"

  # Restore phase: put ~/.claude back exactly as it was before the swap.
  #
  # If the pre-swap state was a WSK-managed symlink (pointing into ~/.claude-*)
  # or simply absent, do NOT recreate it.  Claude Code performs ancestor-directory
  # traversal from $PWD up to $HOME; a symlink at ~/.claude resolves to the last
  # account's real dir and causes that account's CLAUDE.md and skills/ to load in
  # EVERY session, even ones under a different account's PROJECTS_DIR — doubling
  # CLAUDE.md (~10 k extra tokens/session) and listing all skills twice.
  #
  # We remove the symlink rather than recreating it.  The per-account wrapper in
  # ~/.zshrc already sets CLAUDE_CONFIG_DIR at launch time, so ~/.claude is never
  # needed for normal operation.
  #
  # Exception: if the pre-swap ~/.claude was a real directory not managed by WSK
  # (i.e. stash is set), it belongs to the user — restore it untouched.
  if [[ -n "$stash" ]]; then
    mv "$stash" "$dot"
  fi
  # had_link case: do nothing — leave ~/.claude absent to prevent ancestor-traversal double-load.
  return "$_ga_rc"
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

  local acct fw env_file synced=0 _sync_fail_count=0
  for acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    env_file="${WSK_DIR}/accounts/${acct}.env"
    fw="$(grep '^AI_FRAMEWORK=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"
    [[ "$fw" == "gentle-ai" ]] || continue

    synced=1
    log_info "Syncing gentle-ai for ${acct}..."
    local acct_dir="${HOME}/.claude-${acct}"
    local _sync_rc=0
    _gentle_ai_scoped "$acct_dir" sync || _sync_rc=$?
    if [[ "$_sync_rc" -ne 0 ]]; then
      log_warn "${acct}: gentle-ai sync failed (rc=${_sync_rc})" >&2
      _sync_fail_count=$(( _sync_fail_count + 1 ))
    fi
    _patch_gentle_ai_commands "$acct_dir"
    _patch_gentle_ai_claude_md "$acct_dir"
    if [[ "$_sync_rc" -eq 0 ]]; then
      check_pass "${acct}: gentle-ai synced"
    fi
  done

  (( synced )) || log_info "No gentle-ai accounts to sync."
  if [[ "$_sync_fail_count" -gt 0 ]]; then
    log_warn "${_sync_fail_count} account(s) failed gentle-ai sync"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# run_fix_claude
# One-shot remediation for the ~/.claude ancestor-traversal double-load problem.
#
# 1. Removes ~/.claude if it is a symlink (the leftover from the old restore step).
#    Backs it up with a timestamp if it is a real directory not managed by WSK.
#    Reports "already clean" if absent.
# 2. For every account with AI_FRAMEWORK=gentle-ai:
#    - Ensures RTK.md exists in the account dir (copies from any sibling account
#      that already has one).
#    - Runs _patch_gentle_ai_claude_md to ensure CLAUDE.md is up to date.
# Idempotent — safe to re-run.
# ---------------------------------------------------------------------------
run_fix_claude() {
  local dot="$HOME/.claude"

  ui_subhead "~/.claude cleanup"
  if [[ -L "$dot" ]]; then
    local target
    target="$(readlink "$dot")"
    if ! rm "$dot"; then
      check_fail "failed to remove symlink ~/.claude → ${target}"
      return 1
    fi
    check_pass "removed symlink ~/.claude → ${target}"
  elif [[ -d "$dot" ]]; then
    local backup
    backup="${dot}.wsk-backup-$(date '+%Y%m%d-%H%M%S')"
    mv "$dot" "$backup"
    check_pass "moved real ~/.claude directory → ${backup}"
  else
    check_pass "~/.claude already absent — nothing to do"
  fi

  if [[ "${#WSK_ACCOUNTS[@]}" -eq 0 ]]; then
    load_accounts
  fi

  # Find any account dir that already has RTK.md so we can copy it to others.
  local rtk_source=""
  local _a
  for _a in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    if [[ -f "${HOME}/.claude-${_a}/RTK.md" ]]; then
      rtk_source="${HOME}/.claude-${_a}/RTK.md"
      break
    fi
  done

  ui_subhead "CLAUDE.md patches (per gentle-ai account)"
  local acct fw env_file acct_dir
  for acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    env_file="${WSK_DIR}/accounts/${acct}.env"
    fw="$(grep '^AI_FRAMEWORK=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"
    [[ "$fw" == "gentle-ai" ]] || continue

    acct_dir="${HOME}/.claude-${acct}"
    [[ -d "$acct_dir" ]] || continue

    # Copy RTK.md from another account dir if this one is missing it.
    if [[ -n "$rtk_source" && ! -f "${acct_dir}/RTK.md" ]]; then
      cp "$rtk_source" "${acct_dir}/RTK.md"
      check_pass "${acct}: RTK.md installed"
    fi

    if [[ -f "${acct_dir}/CLAUDE.md" ]]; then
      _patch_gentle_ai_claude_md "$acct_dir"
      check_pass "${acct}: CLAUDE.md patched"
    else
      check_warn "${acct}: CLAUDE.md missing — run: wsk ai"
    fi
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
  if ui_confirm "Install RTK (Bash output compression for Claude)?"; then
    install_rtk
  fi
  if ui_confirm "Install Caveman (response token compression for Claude)?"; then
    install_caveman
  fi
  # Gate: enable reconfigure prompts only for interactive wsk ai / menu "AI dev tools" runs.
  # Unattended callers (run_full_setup) never set this, so they get the silent re-run path.
  export WSK_AI_RECONFIGURE=1
  run_ai_for_all_accounts
  unset WSK_AI_RECONFIGURE
}
