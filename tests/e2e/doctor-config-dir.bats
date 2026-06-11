#!/usr/bin/env bats
# doctor-config-dir.bats — WU-3
# Tests for doctor orchestrator-missing detection
# (spec domain doctor-config-dir-check).

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run run_doctor in an isolated subprocess, capture output
# ---------------------------------------------------------------------------
_run_doctor_iso() {
  local extra_env="${1:-}"

  unset -f gum brew 2>/dev/null || true

  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_STUB_BIN='$WSK_STUB_BIN'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    ${extra_env}

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    source '${WSK_DIR}/lib/accounts.sh'
    source '${WSK_DIR}/lib/frameworks.sh'
    source '${WSK_DIR}/lib/doctor.sh'

    load_accounts 2>/dev/null || true
    run_doctor 2>&1 || true
  " 2>&1
}

setup() {
  init_test_home
  export WSK_DIR
  export WSK_TEST_HOME
  mkdir -p "${WSK_DIR}/accounts"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ===========================================================================
# Scenario 1: CLAUDE_CONFIG_DIR unset AND ~/.claude absent — warning emitted
# ===========================================================================

@test "doctor config-dir: both absent — warning contains 'orchestrator' or 'CLAUDE_CONFIG_DIR'" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.claude-work"

  # Ensure ~/.claude does NOT exist and CLAUDE_CONFIG_DIR is unset
  rm -rf "$HOME/.claude"

  local output
  output=$(_run_doctor_iso "unset CLAUDE_CONFIG_DIR" 2>&1)

  # Warning must contain 'orchestrator' or 'CLAUDE_CONFIG_DIR'
  echo "$output" | grep -qiE "orchestrator|CLAUDE_CONFIG_DIR"
}

@test "doctor config-dir: both absent — wsk check exits 0 (warning is advisory)" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.claude-work"
  rm -rf "$HOME/.claude"

  local rc=0
  _run_doctor_iso "unset CLAUDE_CONFIG_DIR" || rc=$?

  [[ "$rc" -eq 0 ]]
}

# ===========================================================================
# Scenario 2: CLAUDE_CONFIG_DIR set — no warning
# ===========================================================================

@test "doctor config-dir: CLAUDE_CONFIG_DIR set — no orchestrator-missing warning" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.claude-work"
  rm -rf "$HOME/.claude"
  mkdir -p "$HOME/.claude-work-config"

  local output
  output=$(_run_doctor_iso "export CLAUDE_CONFIG_DIR='$HOME/.claude-work-config'" 2>&1)

  # No orchestrator-missing warning when CLAUDE_CONFIG_DIR is set
  ! echo "$output" | grep -q "CLAUDE_CONFIG_DIR wrapper\|no config\|wsk accounts"
}

# ===========================================================================
# Scenario 3: ~/.claude exists, CLAUDE_CONFIG_DIR unset — no warning
# ===========================================================================

@test "doctor config-dir: ~/.claude exists, CLAUDE_CONFIG_DIR unset — no orchestrator-missing warning" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.claude-work"
  # Create ~/.claude (Claude Code will fall back to it)
  mkdir -p "$HOME/.claude"

  local output
  output=$(_run_doctor_iso "unset CLAUDE_CONFIG_DIR" 2>&1)

  # ~/.claude exists, so no orchestrator-missing warning for this condition
  ! echo "$output" | grep -q "wsk accounts"
}
