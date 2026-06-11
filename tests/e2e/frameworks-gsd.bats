#!/usr/bin/env bats
# frameworks-gsd.bats — WU-R1 (remediation)
# Tests for gsd hard cutover to @opengsd/get-shit-done-redux.
# The old get-shit-done-cc package and fallback are REMOVED.
# On failure, wsk logs an error and returns nonzero — no fallback.

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run install_ai_framework for gsd in an isolated subprocess
# ---------------------------------------------------------------------------
_run_gsd_iso() {
  local extra_env="${1:-}"
  local acct="${2:-work}"

  # Unset exported bash function stubs so PATH shims take priority.
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

    # Stub gum choose to return 'gsd' so install_ai_framework picks gsd
    gum() {
      case \"\$1\" in
        choose) echo 'gsd' ;;
        confirm) exit 1 ;;
        *) exit 0 ;;
      esac
    }

    install_ai_framework '${acct}' 2>&1 || true
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
# Scenario 1: redux package available — npx @opengsd/get-shit-done-redux@latest invoked
# ===========================================================================

@test "gsd install: redux package available — npx @opengsd/get-shit-done-redux@latest invoked" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.claude-work"

  _run_gsd_iso "" "work"

  assert_stub_called "@opengsd/get-shit-done-redux@latest"
}

# ===========================================================================
# Scenario 2: redux unavailable — returns nonzero, NO fallback to get-shit-done-cc
# ===========================================================================

@test "gsd install: redux unavailable — exits nonzero, no get-shit-done-cc fallback" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.claude-work"

  # Make ALL npx calls fail
  cat > "$WSK_STUB_BIN/npx" <<'STUB'
#!/usr/bin/env bash
echo "npx $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 1
STUB
  chmod +x "$WSK_STUB_BIN/npx"

  local rc=0
  # Run in isolation; capture exit code
  unset -f gum brew 2>/dev/null || true
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

    gum() {
      case \"\$1\" in
        choose) echo 'gsd' ;;
        confirm) exit 1 ;;
        *) exit 0 ;;
      esac
    }

    install_ai_framework 'work'
  " 2>/dev/null || rc=$?

  # Must exit nonzero (hard failure, no silent fallback)
  [[ "$rc" -ne 0 ]]
  # Must NOT have attempted to call get-shit-done-cc
  assert_stub_not_called "get-shit-done-cc"
}
