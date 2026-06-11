#!/usr/bin/env bats
# frameworks-gsd.bats — WU-2
# Tests for gsd package migration to @opengsd/get-shit-done-redux
# with fallback-with-deprecation-warning (spec domain gsd-install).

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

  # npx stub exits 0 (already in default shims)

  _run_gsd_iso "" "work"

  # Should have called npx with the redux package
  assert_stub_called "@opengsd/get-shit-done-redux@latest"
}

# ===========================================================================
# Scenario 2: redux package unavailable — fallback with deprecation warning
# ===========================================================================

@test "gsd install: redux unavailable — fallback to old package with deprecation warning" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.claude-work"

  # Make npx fail for the redux package but succeed for the old package
  cat > "$WSK_STUB_BIN/npx" <<'STUB'
#!/usr/bin/env bash
echo "npx $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == *"@opengsd/get-shit-done-redux"* ]]; then
  exit 1
fi
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/npx"

  local output
  output=$(_run_gsd_iso "" "work" 2>&1)

  # Should print a deprecation warning mentioning both packages
  echo "$output" | grep -qi "deprecat"
}
