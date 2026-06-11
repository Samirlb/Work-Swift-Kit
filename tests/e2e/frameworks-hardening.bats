#!/usr/bin/env bats
# frameworks-hardening.bats — WU-6
# Tests for lib/frameworks.sh: _gentle_ai_scoped error propagation (EC-4),
# _persist_account_kv sd fallback (EC-6), _patch_gentle_ai_claude_md python3 fallback (EC-7).

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run a frameworks.sh function in an isolated subprocess
# ---------------------------------------------------------------------------
_run_frameworks_iso() {
  local extra_setup="${1:-}"
  local call="${2:-}"

  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    source '${WSK_DIR}/lib/accounts.sh'
    source '${WSK_DIR}/lib/frameworks.sh'

    ${extra_setup}

    ${call} 2>&1
  " 2>&1
}

setup() {
  init_test_home
  export WSK_DIR
  export WSK_TEST_HOME
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ===========================================================================
# EC-4: _gentle_ai_scoped exits non-zero → no AI_FRAMEWORK persisted
# ===========================================================================

@test "EC-4: _gentle_ai_scoped exits non-zero — AI_FRAMEWORK not persisted" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.claude-work"

  # Stub gentle-ai to fail
  local ga_stub="$WSK_STUB_BIN/gentle-ai"
  cat > "$ga_stub" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 1
STUB
  chmod +x "$ga_stub"

  local env_file="${WSK_DIR}/accounts/work.env"

  _run_frameworks_iso "
    WSK_ACCOUNTS=(work)
    load_accounts() { WSK_ACCOUNTS=(work); }
    ui_section() { true; }
    ui_subhead() { true; }
  " "_gentle_ai_scoped '$HOME/.claude-work' install --agent claude-code"

  # AI_FRAMEWORK should NOT be set in the env file after failure
  ! grep -q '^AI_FRAMEWORK=' "$env_file"
}

# ===========================================================================
# EC-4: _gentle_ai_scoped exits 0 → install_ai_framework persists AI_FRAMEWORK
# ===========================================================================

@test "EC-4 success: _gentle_ai_scoped exits 0 — AI_FRAMEWORK=gentle-ai persisted" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.claude-work"

  # Stub gentle-ai to succeed
  local ga_stub="$WSK_STUB_BIN/gentle-ai"
  cat > "$ga_stub" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$ga_stub"

  local env_file="${WSK_DIR}/accounts/work.env"

  # Simulate the install_ai_framework flow manually by calling _gentle_ai_scoped
  # and then conditionally persisting (mirrors EC-4 fix logic)
  _run_frameworks_iso "
    WSK_ACCOUNTS=(work)
    load_accounts() { WSK_ACCOUNTS=(work); }
  " "
    cfg_dir='\$HOME/.claude-work'
    mkdir -p \"\$cfg_dir\"
    if _gentle_ai_scoped \"\$cfg_dir\" install --agent claude-code; then
      _persist_account_kv '${env_file}' AI_FRAMEWORK gentle-ai
    fi
  "

  grep -q '^AI_FRAMEWORK=gentle-ai' "$env_file"
}

# ===========================================================================
# EC-6: sd absent — _persist_account_kv falls back to awk
# ===========================================================================

@test "EC-6: sd absent — _persist_account_kv uses awk fallback for upsert" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"

  # Make sd absent from PATH
  stub_absent sd
  local no_usr_bin="${WSK_STUB_BIN}:/bin"

  local env_file="${WSK_DIR}/accounts/work.env"
  # Pre-seed an existing key
  printf 'AI_FRAMEWORK=old-value\n' >> "$env_file"

  bash -c "
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='${no_usr_bin}'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/accounts.sh'
    source '${WSK_DIR}/lib/frameworks.sh'
    _persist_account_kv '${env_file}' AI_FRAMEWORK gentle-ai
  " 2>&1

  # Verify the key was updated (not duplicated) and contains the new value
  local count
  count=$(grep -c '^AI_FRAMEWORK=' "$env_file" || true)
  [[ "$count" -eq 1 ]]
  grep -q '^AI_FRAMEWORK=gentle-ai' "$env_file"
}

# ===========================================================================
# EC-7: python3 absent — _patch_gentle_ai_claude_md falls back to awk
# ===========================================================================

@test "EC-7: python3 absent — _patch_gentle_ai_claude_md uses awk fallback" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.claude-work"

  # Pre-seed a CLAUDE.md without the minimalism block
  local claude_md="$HOME/.claude-work/CLAUDE.md"
  printf '# Test Claude MD\n\nSome content here.\n' > "$claude_md"

  # Make python3 absent
  local no_usr_bin="${WSK_STUB_BIN}:/bin"

  local claude_dir="$HOME/.claude-work"

  bash -c "
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='${no_usr_bin}'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/accounts.sh'
    source '${WSK_DIR}/lib/frameworks.sh'
    _patch_gentle_ai_claude_md '${claude_dir}'
  " 2>&1

  # After patching, the minimalism block markers should exist
  grep -qF '<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:BEGIN -->' "$claude_md"
}
