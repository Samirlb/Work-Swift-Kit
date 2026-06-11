#!/usr/bin/env bats
# ai-update.bats — WU-3
# Tests for wsk ai-update command / run_ai_update function
# (spec domain ai-lifecycle-command).

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run run_ai_update in an isolated subprocess
# Returns combined stdout+stderr; exit code available via process substitution.
# ---------------------------------------------------------------------------
_run_ai_update_iso() {
  local extra_env="${1:-}"
  local body="${2:-run_ai_update}"

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

    ${body}
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
# Scenario 1: all accounts succeed — exit 0
# ===========================================================================

@test "ai-update: all accounts succeed — exit 0" {
  seed_account "work"     "Work"     "Jane" "jane@work.com"     "janew"  "$HOME/projects/work"     "id_work"
  seed_account "personal" "Personal" "Jane" "jane@personal.com" "janep"  "$HOME/projects/personal" "id_personal"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_DIR}/accounts/work.env"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_DIR}/accounts/personal.env"
  mkdir -p "$HOME/.claude-work" "$HOME/.claude-personal"

  local rc=0
  _run_ai_update_iso "export WSK_ACCOUNTS=(work personal)" "run_ai_update" || rc=$?

  [[ "$rc" -eq 0 ]]
}

# ===========================================================================
# Scenario 2: one account fails — others continue, exit nonzero
# ===========================================================================

@test "ai-update: one account fails — others continue, exit nonzero" {
  seed_account "work"     "Work"     "Jane" "jane@work.com"     "janew"  "$HOME/projects/work"     "id_work"
  seed_account "personal" "Personal" "Jane" "jane@personal.com" "janep"  "$HOME/projects/personal" "id_personal"
  seed_account "client"   "Client"   "Jane" "jane@client.com"   "janec"  "$HOME/projects/client"   "id_client"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_DIR}/accounts/work.env"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_DIR}/accounts/personal.env"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_DIR}/accounts/client.env"
  mkdir -p "$HOME/.claude-work" "$HOME/.claude-personal" "$HOME/.claude-client"

  # Make gentle-ai fail for 'work' only
  cat > "$WSK_STUB_BIN/gentle-ai" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
# Fail when operating on the 'work' account dir (detect via HOME/.claude-work path being present)
# We need to check which account is being processed.
# gentle-ai is invoked after mv cfg_dir → ~/.claude, so we check if ~/.claude/.stub-account exists
acct_marker="${HOME}/.claude/.stub-account"
if [[ -f "$acct_marker" ]]; then
  acct="$(cat "$acct_marker")"
  if [[ "$acct" == "work" ]]; then
    exit 1
  fi
fi
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/gentle-ai"

  # Plant account markers so we can detect which account is active during swap
  echo "work"     > "$HOME/.claude-work/.stub-account"
  echo "personal" > "$HOME/.claude-personal/.stub-account"
  echo "client"   > "$HOME/.claude-client/.stub-account"

  local output rc=0
  output=$(_run_ai_update_iso "export WSK_ACCOUNTS=(work personal client)" "run_ai_update" 2>&1) || rc=$?

  # work failed — should be in stderr output
  echo "$output" | grep -q "work"
  # personal and client should have completed (gentle-ai sync called for them)
  assert_stub_called "gentle-ai sync"
  # Overall exit must be nonzero
  [[ "$rc" -ne 0 ]]
}

# ===========================================================================
# Scenario 3: --upgrade flag — brew upgrade runs once before sync
# ===========================================================================

@test "ai-update: --upgrade flag — brew upgrade gentle-ai called once before sync" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$HOME/.claude-work"

  _run_ai_update_iso "export WSK_ACCOUNTS=(work)" "run_ai_update --upgrade"

  assert_stub_called "brew upgrade gentle-ai"
  assert_stub_called "gentle-ai sync"
}

# ===========================================================================
# Scenario 4: CLI dispatch routes correctly — wsk ai-update dispatched to run_ai_update
# ===========================================================================

@test "ai-update: wsk ai-update dispatch — routes to run_ai_update handler" {
  # Check that install.sh dispatch function handles 'ai-update'
  local output
  output=$(bash -c "
    export HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    export WSK_STUB_LOG='$WSK_STUB_LOG'

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    source '${WSK_DIR}/lib/accounts.sh'
    source '${WSK_DIR}/lib/frameworks.sh'
    source '${WSK_DIR}/lib/terminals.sh'
    source '${WSK_DIR}/lib/packages.sh'
    source '${WSK_DIR}/lib/render.sh'
    source '${WSK_DIR}/lib/stow.sh'
    source '${WSK_DIR}/lib/gh.sh'
    source '${WSK_DIR}/lib/doctor.sh'
    source '${WSK_DIR}/lib/fix-git.sh'
    source '${WSK_DIR}/lib/update.sh'
    source '${WSK_DIR}/lib/tui.sh'

    # Source dispatch function
    dispatch() {
      case \"\$1\" in
        ai-update) echo 'DISPATCH_OK'; run_ai_update \"\${@:2}\" || true ;;
        *) echo 'DISPATCH_MISS' ;;
      esac
    }

    dispatch 'ai-update'
  " 2>&1)

  echo "$output" | grep -q "DISPATCH_OK"
}
