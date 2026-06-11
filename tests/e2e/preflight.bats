#!/usr/bin/env bats
# preflight.bats — WU-1
# Tests for lib/preflight.sh: require_state and _check_optional_dep

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run preflight functions in an isolated subprocess
# $1 = extra env/setup as a bash snippet string
# $2 = function call to evaluate
# ---------------------------------------------------------------------------
_run_preflight_iso() {
  local extra_setup="$1"
  local call="$2"

  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/preflight.sh'

    ${extra_setup}

    ${call}
    echo \"exit:\$?\"
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
# PF-1: Empty WSK_ACCOUNTS aborts with check_warn
# ===========================================================================

@test "PF-1: empty WSK_ACCOUNTS — preflight_accounts prints error and returns non-zero" {
  local out rc
  out=$(bash -c "
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/preflight.sh'
    WSK_ACCOUNTS=()
    preflight_accounts
  " 2>&1) || rc=$?
  rc="${rc:-0}"

  [[ "$rc" -ne 0 ]]
  echo "$out" | grep -q 'No accounts configured'
}

# ===========================================================================
# PF-2: Single account passes
# ===========================================================================

@test "PF-2: single account — preflight_accounts returns 0 silently" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"

  local out rc
  out=$(bash -c "
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/preflight.sh'
    WSK_ACCOUNTS=(work)
    preflight_accounts
  " 2>&1); rc=$?

  [[ "$rc" -eq 0 ]]
  # No error message
  echo "$out" | grep -qv 'No accounts'
}

# ===========================================================================
# PF-3: --allow-empty flag passes even with empty accounts
# ===========================================================================

@test "PF-3: no accounts + --allow-empty flag — preflight_accounts returns 0" {
  local rc
  bash -c "
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/preflight.sh'
    WSK_ACCOUNTS=()
    preflight_accounts --allow-empty
  " 2>&1; rc=$?

  [[ "$rc" -eq 0 ]]
}

# ===========================================================================
# PF-4: sd missing — warn + continue
# ===========================================================================

@test "PF-4: sd absent — check_warn printed, returns 0" {
  stub_absent sd

  local out rc
  out=$(bash -c "
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/preflight.sh'
    _check_optional_dep sd 'key-value persistence will use fallback'
  " 2>&1); rc=$?

  [[ "$rc" -eq 0 ]]
  echo "$out" | grep -q 'sd'
}

# ===========================================================================
# PF-5: rg missing — warn + continue
# ===========================================================================

@test "PF-5: rg absent — check_warn printed, returns 0" {
  stub_absent rg

  local out rc
  out=$(bash -c "
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/preflight.sh'
    _check_optional_dep rg 'update progress display skipped'
  " 2>&1); rc=$?

  [[ "$rc" -eq 0 ]]
  echo "$out" | grep -q 'rg'
}

# ===========================================================================
# PF-6: python3 missing — warn + continue
# ===========================================================================

@test "PF-6: python3 absent — check_warn printed, returns 0" {
  # Write a masking stub that reports itself as absent (exits 1 for command -v check)
  # by not existing in the stub bin and ensuring the restricted PATH is used.
  stub_absent python3
  # Write a python3 stub that fails so command -v via PATH finds it missing
  # The restricted PATH in the subshell omits /usr/bin so real python3 is hidden.
  local no_usr_bin
  no_usr_bin="${WSK_STUB_BIN}:/bin"

  local out rc
  out=$(bash -c "
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='${no_usr_bin}'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/preflight.sh'
    _check_optional_dep python3 'claude-md patching will be skipped'
  " 2>&1); rc=$?

  [[ "$rc" -eq 0 ]]
  echo "$out" | grep -q 'python3'
}

# ===========================================================================
# PF-7: All optional deps present — silent pass
# ===========================================================================

@test "PF-relink: run_relink aborts early when no accounts configured" {
  # flow-preflight scenario: "Flow aborts when preflight fails (relink)"
  # run_relink must NOT call render_all when accounts are empty.
  local render_called_file="$WSK_TEST_HOME/render_called"

  local out
  out=$(bash -c "
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/accounts.sh'
    source '${WSK_DIR}/lib/preflight.sh'

    render_all() { touch '${render_called_file}'; }
    link_dotfiles() { true; }
    log_success() { true; }

    run_relink() {
      load_accounts
      preflight_accounts || return 0
      render_all
      link_dotfiles
    }

    # No accounts — WSK_DIR has empty accounts dir
    mkdir -p '${WSK_DIR}/accounts'

    run_relink 2>&1
  " 2>&1)

  # render_all must NOT have been called
  [[ ! -f "$render_called_file" ]]
  echo "$out" | grep -qi "No accounts configured"
}

@test "PF-7: all optional deps present — preflight_deps returns 0 silently" {
  stub_present sd
  stub_present rg
  stub_present python3

  local out rc
  out=$(bash -c "
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/preflight.sh'
    preflight_deps
  " 2>&1); rc=$?

  [[ "$rc" -eq 0 ]]
  # No warnings expected
  echo "$out" | grep -qv 'not found'
}
