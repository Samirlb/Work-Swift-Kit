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
  mkdir -p "${WSK_ACCOUNTS_DIR}"
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
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_ACCOUNTS_DIR}/work.env"
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

@test "reconfigure gate on, user accepts — uninstall called BEFORE install in stub log order" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_ACCOUNTS_DIR}/work.env"
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

  # Assert: uninstall was called
  assert_stub_called "gentle-ai uninstall"
  # Assert: install was called after uninstall
  assert_stub_called "gentle-ai install"

  # Assert ORDER: uninstall line number < install line number in the log
  local uninstall_line install_line
  uninstall_line="$(grep -n "gentle-ai uninstall" "$WSK_STUB_LOG" | head -1 | cut -d: -f1)"
  install_line="$(grep -n "gentle-ai install" "$WSK_STUB_LOG" | head -1 | cut -d: -f1)"
  if [[ -z "$uninstall_line" || -z "$install_line" ]]; then
    echo "ASSERT FAILED: uninstall_line='${uninstall_line}' install_line='${install_line}'" >&2
    cat "$WSK_STUB_LOG" >&2
    return 1
  fi
  if [[ "$uninstall_line" -ge "$install_line" ]]; then
    echo "ASSERT FAILED: uninstall (line ${uninstall_line}) must precede install (line ${install_line})" >&2
    cat "$WSK_STUB_LOG" >&2
    return 1
  fi
}

# ===========================================================================
# Scenario 3 (user declines): gate on, user declines — sync-only, .env unchanged
# ===========================================================================

@test "reconfigure gate on, user declines — sync-only, AI_FRAMEWORK not changed" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_ACCOUNTS_DIR}/work.env"
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
  grep -q '^AI_FRAMEWORK=gentle-ai' "${WSK_ACCOUNTS_DIR}/work.env"
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
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_ACCOUNTS_DIR}/work.env"
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
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_ACCOUNTS_DIR}/work.env"
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

# ===========================================================================
# Scenario 7: run_full_setup path — reconfigure prompt shown for accounts
#              with AI_FRAMEWORK already set (WSK_AI_RECONFIGURE=1 set there too)
# ===========================================================================

@test "run_full_setup path — reconfigure prompt shown for accounts with AI_FRAMEWORK set" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_ACCOUNTS_DIR}/work.env"
  mkdir -p "$HOME/.claude-work"
  touch "$HOME/.claude-work/settings.json"

  # gentle-ai stub
  cat > "$WSK_STUB_BIN/gentle-ai" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/gentle-ai"

  # gum stub: all confirms decline to keep test minimal; choose returns gentle-ai
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

  # Simulate the run_full_setup path by calling run_ai_for_all_accounts with
  # WSK_AI_RECONFIGURE=1 — this is what run_full_setup must do after the fix.
  unset -f gum brew 2>/dev/null || true
  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_STUB_BIN='$WSK_STUB_BIN'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    export WSK_ACCOUNTS=(work)
    export WSK_AI_RECONFIGURE=1

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    source '${WSK_DIR}/lib/accounts.sh'
    source '${WSK_DIR}/lib/frameworks.sh'

    run_ai_for_all_accounts 2>&1 || true
  " 2>&1

  # gum confirm must have been called with "Reconfigure"
  assert_stub_called "Reconfigure"
}

# ===========================================================================
# Scenario 8: reconfigure accepted, pre-existing rtk hook + caveman + codegraph
#              → all three re-wired after reconfigure
# ===========================================================================

@test "reconfigure accepted — rtk hook, caveman, codegraph re-wired after reconfigure" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_ACCOUNTS_DIR}/work.env"
  local cfg_dir="$HOME/.claude-work"
  mkdir -p "$cfg_dir"

  # Pre-populate settings.json with rtk hook and caveman plugin (as they would
  # be after a normal install).
  cat > "$cfg_dir/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "rtk hook claude" }] }
    ]
  },
  "enabledPlugins": { "caveman@caveman": true },
  "extraKnownMarketplaces": { "caveman": { "source": { "source": "github", "repo": "JuliusBrussee/caveman" } } }
}
JSON

  # Pre-populate .claude.json with codegraph MCP entry.
  cat > "$cfg_dir/.claude.json" <<'JSON'
{
  "mcpServers": {
    "codegraph": { "command": "codegraph", "args": ["serve", "--mcp"] }
  }
}
JSON

  # gentle-ai stub: records calls, succeeds.
  cat > "$WSK_STUB_BIN/gentle-ai" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
# Simulate uninstall wiping settings.json and .claude.json
if [[ "$1" == "uninstall" ]]; then
  rm -f "$HOME/.claude-work/settings.json"
  rm -f "$HOME/.claude-work/.claude.json"
fi
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/gentle-ai"

  # Add rtk stub (signals binary is present on PATH).
  cat > "$WSK_STUB_BIN/rtk" <<'STUB'
#!/usr/bin/env bash
echo "rtk $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/rtk"

  # Add codegraph stub.
  cat > "$WSK_STUB_BIN/codegraph" <<'STUB'
#!/usr/bin/env bash
echo "codegraph $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/codegraph"

  # claude stub for `claude mcp add`.
  cat > "$WSK_STUB_BIN/claude" <<'STUB'
#!/usr/bin/env bash
echo "claude $*" >> "${WSK_STUB_LOG:-/dev/null}"
# Write the MCP entry into .claude.json so idempotency checks pass on re-call.
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mkdir -p "$cfg"
if [[ "$1 $2 $3 $4" == "mcp add --scope user" ]]; then
  srv="$5"
  printf '{"mcpServers":{"%s":{"command":"%s","args":["serve","--mcp"]}}}\n' "$srv" "$srv" > "$cfg/.claude.json"
fi
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/claude"

  # gum: confirm → YES (accept reconfigure), choose → gentle-ai.
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

  unset -f gum brew 2>/dev/null || true
  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_STUB_BIN='$WSK_STUB_BIN'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    export WSK_AI_RECONFIGURE=1

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    source '${WSK_DIR}/lib/accounts.sh'
    source '${WSK_DIR}/lib/frameworks.sh'

    install_ai_framework 'work' 2>&1 || true
  " 2>&1

  # rtk hook must be re-wired into settings.json.
  local settings="$cfg_dir/settings.json"
  [[ -f "$settings" ]] || { echo "ASSERT FAILED: settings.json missing after reconfigure" >&2; return 1; }
  grep -q 'rtk hook claude' "$settings" || { echo "ASSERT FAILED: rtk hook missing after reconfigure" >&2; cat "$settings" >&2; return 1; }

  # caveman plugin must be re-enabled in settings.json.
  grep -q '"caveman@caveman"' "$settings" || { echo "ASSERT FAILED: caveman plugin missing after reconfigure" >&2; cat "$settings" >&2; return 1; }

  # codegraph MCP must be re-registered in .claude.json.
  local claude_json="$cfg_dir/.claude.json"
  [[ -f "$claude_json" ]] || { echo "ASSERT FAILED: .claude.json missing after reconfigure" >&2; return 1; }
  grep -q '"codegraph"' "$claude_json" || { echo "ASSERT FAILED: codegraph MCP missing after reconfigure" >&2; cat "$claude_json" >&2; return 1; }
}

# ===========================================================================
# Scenario 9: account that never had codegraph — reconfigure does NOT add it
# ===========================================================================

@test "reconfigure accepted — account without codegraph does NOT get codegraph added" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_ACCOUNTS_DIR}/work.env"
  local cfg_dir="$HOME/.claude-work"
  mkdir -p "$cfg_dir"

  # Pre-populate settings.json with rtk only — no codegraph in .claude.json.
  cat > "$cfg_dir/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "rtk hook claude" }] }
    ]
  }
}
JSON

  # No .claude.json at all (account never had codegraph).

  # gentle-ai stub: uninstall wipes settings.json.
  cat > "$WSK_STUB_BIN/gentle-ai" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$1" == "uninstall" ]]; then
  rm -f "$HOME/.claude-work/settings.json"
  rm -f "$HOME/.claude-work/.claude.json"
fi
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/gentle-ai"

  # codegraph stub present on PATH (binary exists globally, but was NOT registered
  # for this account — the fix must NOT add it).
  cat > "$WSK_STUB_BIN/codegraph" <<'STUB'
#!/usr/bin/env bash
echo "codegraph $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/codegraph"

  # rtk stub present.
  cat > "$WSK_STUB_BIN/rtk" <<'STUB'
#!/usr/bin/env bash
echo "rtk $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/rtk"

  # claude stub.
  cat > "$WSK_STUB_BIN/claude" <<'STUB'
#!/usr/bin/env bash
echo "claude $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/claude"

  # gum: confirm → YES.
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

  unset -f gum brew 2>/dev/null || true
  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_STUB_BIN='$WSK_STUB_BIN'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    export WSK_AI_RECONFIGURE=1

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    source '${WSK_DIR}/lib/accounts.sh'
    source '${WSK_DIR}/lib/frameworks.sh'

    install_ai_framework 'work' 2>&1 || true
  " 2>&1

  # codegraph must NOT have been registered (it was not present before uninstall).
  local claude_json="$cfg_dir/.claude.json"
  if [[ -f "$claude_json" ]] && grep -q '"codegraph"' "$claude_json" 2>/dev/null; then
    echo "ASSERT FAILED: codegraph was added but account never had it before reconfigure" >&2
    cat "$claude_json" >&2
    return 1
  fi
}

# ===========================================================================
# Scenario 10: reconfigure accepted — caveman NOT re-enabled when it was absent
# ===========================================================================

@test "reconfigure accepted — account without caveman does NOT get caveman added" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_ACCOUNTS_DIR}/work.env"
  local cfg_dir="$HOME/.claude-work"
  mkdir -p "$cfg_dir"

  # settings.json with rtk hook only — no caveman.
  cat > "$cfg_dir/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "rtk hook claude" }] }
    ]
  }
}
JSON

  # gentle-ai stub: uninstall wipes settings.json.
  cat > "$WSK_STUB_BIN/gentle-ai" <<'STUB'
#!/usr/bin/env bash
echo "gentle-ai $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$1" == "uninstall" ]]; then
  rm -f "$HOME/.claude-work/settings.json"
fi
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/gentle-ai"

  # rtk stub present.
  cat > "$WSK_STUB_BIN/rtk" <<'STUB'
#!/usr/bin/env bash
echo "rtk $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$WSK_STUB_BIN/rtk"

  # gum: confirm → YES.
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

  unset -f gum brew 2>/dev/null || true
  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_STUB_BIN='$WSK_STUB_BIN'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    export WSK_AI_RECONFIGURE=1

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    source '${WSK_DIR}/lib/accounts.sh'
    source '${WSK_DIR}/lib/frameworks.sh'

    install_ai_framework 'work' 2>&1 || true
  " 2>&1

  # caveman must NOT appear in the resulting settings.json.
  local settings="$cfg_dir/settings.json"
  if [[ -f "$settings" ]] && grep -q '"caveman@caveman"' "$settings" 2>/dev/null; then
    echo "ASSERT FAILED: caveman was added but account never had it before reconfigure" >&2
    cat "$settings" >&2
    return 1
  fi
}
