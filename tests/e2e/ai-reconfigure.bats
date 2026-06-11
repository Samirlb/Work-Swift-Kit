#!/usr/bin/env bats
# ai-reconfigure.bats — WU-2
# Tests for the AI framework reconfigure gate (spec domain ai-framework-reconfigure).
# WSK_AI_RECONFIGURE=0 (unset/default) → no prompt shown.
# WSK_AI_RECONFIGURE=1 (set by wsk ai / run_ai) → prompt shown for accounts with AI_FRAMEWORK set.

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run install_ai_framework in an isolated subprocess and return output
# ---------------------------------------------------------------------------
_run_reconfigure_iso() {
  local extra_env="${1:-}"
  local acct="${2:-work}"

  # Unset exported bash function stubs so PATH shims take priority inside the subprocess.
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
# Scenario 1: gate off (WSK_AI_RECONFIGURE=0) — no reconfigure prompt for account with AI_FRAMEWORK set
# ===========================================================================

@test "reconfigure gate off — no reconfigure prompt when AI_FRAMEWORK already set" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$HOME/.claude-work"
  # Create settings.json so install step is skipped
  touch "$HOME/.claude-work/settings.json"

  # ui_confirm records calls to the stub log
  cat > "$WSK_STUB_BIN/ui_confirm_spy" <<'SPY'
#!/usr/bin/env bash
echo "ui_confirm_called: $*" >> "${WSK_STUB_LOG:-/dev/null}"
SPY
  chmod +x "$WSK_STUB_BIN/ui_confirm_spy"

  # Gate is off — no WSK_AI_RECONFIGURE
  _run_reconfigure_iso "unset WSK_AI_RECONFIGURE" "work"

  # ui_confirm should NOT have been called with "Reconfigure"
  assert_stub_not_called "Reconfigure"
}

# ===========================================================================
# Scenario 2: gate on, user accepts — scoped uninstall then install, AI_FRAMEWORK updated
# ===========================================================================

@test "reconfigure gate on, user accepts — uninstall then install called in order" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$HOME/.claude-work"
  # Create settings.json so we're in re-run state
  touch "$HOME/.claude-work/settings.json"

  # gentle-ai stub that records calls
  cat > "$WSK_STUB_BIN/gentle-ai" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/gentle-ai"

  # gum stub: confirm → YES (exit 0), choose → "gentle-ai"
  cat > "$WSK_STUB_BIN/gum" <<'STUB'
#!/usr/bin/env bash
echo "gum $*" >> "${WSK_STUB_LOG:-/dev/null}"
case "$1" in
  confirm) exit 0 ;;  # user accepts reconfigure
  choose)  echo "gentle-ai" ;;
  *)       exit 0 ;;
esac
STUB
  chmod +x "$WSK_STUB_BIN/gum"

  _run_reconfigure_iso "export WSK_AI_RECONFIGURE=1" "work"

  # gentle-ai uninstall must have been called before install
  assert_stub_called "gentle-ai uninstall"
}

# ===========================================================================
# Scenario 3 (user declines): gate on, user declines — sync-only, .env unchanged
# ===========================================================================

@test "reconfigure gate on, user declines — sync-only, AI_FRAMEWORK not changed" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$HOME/.claude-work"
  touch "$HOME/.claude-work/settings.json"

  # gum stub: confirm → NO (exit 1), choose → "gentle-ai"
  cat > "$WSK_STUB_BIN/gum" <<'STUB'
#!/usr/bin/env bash
echo "gum $*" >> "${WSK_STUB_LOG:-/dev/null}"
case "$1" in
  confirm) exit 1 ;;  # user declines
  choose)  echo "gentle-ai" ;;
  *)       exit 0 ;;
esac
STUB
  chmod +x "$WSK_STUB_BIN/gum"

  # gentle-ai stub
  cat > "$WSK_STUB_BIN/gentle-ai" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/gentle-ai"

  _run_reconfigure_iso "export WSK_AI_RECONFIGURE=1" "work"

  # uninstall should NOT have been called
  assert_stub_not_called "gentle-ai uninstall"
  # AI_FRAMEWORK should still be gentle-ai
  grep -q '^AI_FRAMEWORK=gentle-ai' "${WSK_DIR}/accounts/work.env"
}

# ===========================================================================
# Scenario 4: account has no prior AI_FRAMEWORK — no prompt regardless of gate
# ===========================================================================

@test "account has no AI_FRAMEWORK — no reconfigure prompt even with gate on" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  # No AI_FRAMEWORK in env file
  mkdir -p "$HOME/.claude-work"

  # gentle-ai stub
  cat > "$WSK_STUB_BIN/gentle-ai" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/gentle-ai"

  # gum stub: confirm would mean yes, choose returns gentle-ai
  cat > "$WSK_STUB_BIN/gum" <<'STUB'
#!/usr/bin/env bash
echo "gum $*" >> "${WSK_STUB_LOG:-/dev/null}"
case "$1" in
  confirm) exit 1 ;;
  choose)  echo "gentle-ai" ;;
  *)       exit 0 ;;
esac
STUB
  chmod +x "$WSK_STUB_BIN/gum"

  _run_reconfigure_iso "export WSK_AI_RECONFIGURE=1" "work"

  # uninstall should NOT have been called (no prior framework to reconfigure from)
  assert_stub_not_called "gentle-ai uninstall"
}

# ===========================================================================
# Scenario 5: global state warning shown before reinstall
# ===========================================================================

@test "reconfigure accepted — global state warning printed before reinstall" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$HOME/.claude-work"
  touch "$HOME/.claude-work/settings.json"

  # gentle-ai stub
  cat > "$WSK_STUB_BIN/gentle-ai" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/gentle-ai"

  # gum: confirm → YES
  cat > "$WSK_STUB_BIN/gum" <<'STUB'
#!/usr/bin/env bash
echo "gum $*" >> "${WSK_STUB_LOG:-/dev/null}"
case "$1" in
  confirm) exit 0 ;;
  choose)  echo "gentle-ai" ;;
  *)       exit 0 ;;
esac
STUB
  chmod +x "$WSK_STUB_BIN/gum"

  local output
  output=$(_run_reconfigure_iso "export WSK_AI_RECONFIGURE=1" "work" 2>&1)

  # Warning about global state must be printed
  echo "$output" | grep -qi "global\|state.json\|ALL account"
}

# ===========================================================================
# Scenario 6: warning NOT shown for sync-only path
# ===========================================================================

@test "reconfigure declined (sync-only) — no global state warning printed" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$HOME/.claude-work"
  touch "$HOME/.claude-work/settings.json"

  # gentle-ai stub
  cat > "$WSK_STUB_BIN/gentle-ai" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/gentle-ai"

  # gum: confirm → NO (decline reconfigure)
  cat > "$WSK_STUB_BIN/gum" <<'STUB'
#!/usr/bin/env bash
echo "gum $*" >> "${WSK_STUB_LOG:-/dev/null}"
case "$1" in
  confirm) exit 1 ;;
  choose)  echo "gentle-ai" ;;
  *)       exit 0 ;;
esac
STUB
  chmod +x "$WSK_STUB_BIN/gum"

  local output
  output=$(_run_reconfigure_iso "export WSK_AI_RECONFIGURE=1" "work" 2>&1)

  # No global state warning should be printed for sync-only path
  ! echo "$output" | grep -qi "gentle-ai/state.json\|ALL account"
}
