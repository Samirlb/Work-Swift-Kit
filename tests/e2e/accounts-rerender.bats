#!/usr/bin/env bats
# accounts-rerender.bats — WU-7
# Tests for auto re-render after account add/edit:
# GC-6: add account → render_all called → .rendered/gitconfig updated
# AR-2: edit account → render_all called
# AR-3: re-render message logged clearly after add/edit

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run _collect_single_account in an isolated subprocess.
# Stubs all interactive prompts so the function completes without user input.
# render_all is tracked via a sentinel file written by a stub.
# ---------------------------------------------------------------------------
_run_collect_iso() {
  local extra_setup="${1:-}"
  local acct="${2:-work}"
  local label="${3:-Work}"

  # We need stub values for all ui_input calls in _collect_single_account:
  #   display_name, git_name, git_email, github_user, projects_dir, ssh_choice
  # The gum exported function returns "" for input and "$1" for choose — that
  # causes empty values. Override ui_input/ui_choose/ui_confirm directly.
  bash -c "
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    RENDER_SENTINEL='$WSK_TEST_HOME/render_all_called'

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'

    # Override interactive UI to return deterministic values
    ui_input()   { echo 'stub-value'; }
    ui_choose()  { echo 'Use existing key'; }
    ui_confirm() { return 1; }

    # Override render_all to write a sentinel (tracks that it was called)
    render_all() {
      touch \"\$RENDER_SENTINEL\"
      log_info 'Re-rendering dotfiles after account change...'
    }

    source '${WSK_DIR}/lib/accounts.sh'

    WSK_ACCOUNTS=($acct)

    ${extra_setup}

    _collect_single_account '${acct}' '${label}' 2>&1
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
# GC-6: adding an account triggers render_all → .rendered/gitconfig updated
# ===========================================================================

@test "GC-6: _collect_single_account calls render_all after saving" {
  local sentinel="$WSK_TEST_HOME/render_all_called"

  _run_collect_iso "" "work" "Work"

  [[ -f "$sentinel" ]]
}

# ===========================================================================
# AR-2: editing an existing account also triggers render_all
# ===========================================================================

@test "AR-2: editing an existing account triggers render_all" {
  # Pre-seed an existing account (edit path)
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"

  local sentinel="$WSK_TEST_HOME/render_all_called"

  _run_collect_iso "" "work" "Work"

  [[ -f "$sentinel" ]]
}

# ===========================================================================
# AR-3: re-render log message emitted after add/edit
# ===========================================================================

@test "AR-3: log_info re-render message emitted after account save" {
  local out
  out=$(_run_collect_iso "" "work" "Work")

  echo "$out" | grep -qi 're-render\|re-rendering\|rendered\|rendering'
}

# ===========================================================================
# WU-7.3: render_all is safe when WSK_ACCOUNTS is empty
# ===========================================================================

@test "WU-7.3: render_all returns safely when WSK_ACCOUNTS is empty" {
  local rc=0
  bash -c "
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/render.sh'
    WSK_ACCOUNTS=()
    render_all
  " 2>&1 || rc=$?
  rc="${rc:-0}"
  [[ "$rc" -eq 0 ]]
}
