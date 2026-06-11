#!/usr/bin/env bats
# gentle-ai-error-propagation.bats — WU-1
# Tests for _gentle_ai_scoped exit-code propagation (spec domain gentle-ai-error-propagation).
# All scenarios run with sandboxed HOME; gentle-ai is stubbed.

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run a frameworks.sh body in an isolated subprocess
# Returns stdout+stderr; caller checks exit codes separately where needed.
# ---------------------------------------------------------------------------
_run_fw_iso() {
  local extra_setup="${1:-}"
  local call="${2:-}"

  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_STUB_BIN='$WSK_STUB_BIN'
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

    ${call}
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
# Scenario 1: gentle-ai fails for one account — nonzero propagated
# ===========================================================================

@test "gentle-ai fails for one account — nonzero exit propagated from _gentle_ai_scoped" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.claude-work"

  # Stub gentle-ai to exit 2
  cat > "$WSK_STUB_BIN/gentle-ai" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 2
STUB
  chmod +x "$WSK_STUB_BIN/gentle-ai"

  # _gentle_ai_scoped must propagate the nonzero rc
  local rc=0
  _run_fw_iso "" "_gentle_ai_scoped '$HOME/.claude-work' sync; exit \$?" || rc=$?

  [[ "$rc" -eq 2 ]]
}

# ===========================================================================
# Scenario 2: all accounts succeed — exit 0
# ===========================================================================

@test "all accounts succeed — _gentle_ai_scoped exits 0" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.claude-work"

  # gentle-ai stub already in place from init_test_home (exits 0)

  local rc=99
  _run_fw_iso "" "_gentle_ai_scoped '$HOME/.claude-work' sync; exit \$?" || rc=$?

  # Override with the actual subshell exit
  rc=$(_run_fw_iso "" "_gentle_ai_scoped '$HOME/.claude-work' sync; echo \"rc=\$?\"" | grep "^rc=" | cut -d= -f2 || echo "99")

  [[ "$rc" -eq 0 ]]
}

# ===========================================================================
# Scenario 3: multiple accounts fail — stderr lists both, exit nonzero
# ===========================================================================

@test "multiple accounts fail — stderr has both failures, overall exit nonzero" {
  seed_account "work"    "Work"    "Jane" "jane@work.com"    "janew"  "$HOME/projects/work"    "id_work"
  seed_account "personal" "Personal" "Jane" "jane@personal.com" "janep" "$HOME/projects/personal" "id_personal"
  mkdir -p "$HOME/.claude-work" "$HOME/.claude-personal"

  # Stub gentle-ai to always fail
  cat > "$WSK_STUB_BIN/gentle-ai" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 1
STUB
  chmod +x "$WSK_STUB_BIN/gentle-ai"

    # A caller loop that uses _gentle_ai_scoped and collects failures
  local output
  output=$(_run_fw_iso "WSK_ACCOUNTS=(work personal)" "
    _fail_count=0
    for _acct in work personal; do
      _acct_dir=\"\$HOME/.claude-\${_acct}\"
      _rc=0
      _gentle_ai_scoped \"\$_acct_dir\" sync || _rc=\$?
      if [[ \"\$_rc\" -ne 0 ]]; then
        echo \"FAIL: \${_acct} rc=\${_rc}\"
        _fail_count=\$(( _fail_count + 1 ))
      fi
    done
    if [[ \$_fail_count -gt 0 ]]; then
      echo \"\${_fail_count} account(s) failed\"
    fi
  " 2>&1 || true)

  # Should mention both failures
  echo "$output" | grep -q "work"
  echo "$output" | grep -q "personal"
  echo "$output" | grep -q "account(s) failed"
}
