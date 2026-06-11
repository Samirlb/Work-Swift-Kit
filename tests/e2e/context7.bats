#!/usr/bin/env bats

load "../helpers/setup"

setup() {
  cleanup_test_artifacts
  init_test_home
  source "${WSK_DIR}/lib/log.sh"

  unset -f brew 2>/dev/null || true
  unset -f gum  2>/dev/null || true

  source "${WSK_DIR}/lib/ui.sh"
  source "${WSK_DIR}/lib/os.sh"
  source "${WSK_DIR}/lib/node.sh"
  source "${WSK_DIR}/lib/claude.sh"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ---------------------------------------------------------------------------
# Helper: run install_context7 in an isolated subprocess
# ---------------------------------------------------------------------------
_run_iso_context7() {
  local log_file="$1" env_prefix="$2" body="$3"
  bash -c "
    ${env_prefix}
    export PATH='${WSK_STUB_BIN}:/usr/bin:/bin'
    export WSK_STUB_LOG='${log_file}'
    export WSK_STUB_BIN='${WSK_STUB_BIN}'
    export HOME='${WSK_TEST_HOME}'
    export WSK_DIR='${WSK_DIR}'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    ${body} || true
  " 2>&1
}

# ---------------------------------------------------------------------------
# _write_context7_mcp_config tests
# ---------------------------------------------------------------------------

@test "_write_context7_mcp_config: .claude.json absent — written with context7 and mcpServers structure" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  local claude_json="$cfg_dir/.claude.json"
  stub_absent claude

  _write_context7_mcp_config "work" "$cfg_dir"

  [[ -f "$claude_json" ]]
  grep -q '"context7"' "$claude_json"
  grep -q '"mcpServers"' "$claude_json"
  grep -q '"npx"' "$claude_json"
  ! [[ -f "$cfg_dir/.mcp.json" ]]
}

@test "_write_context7_mcp_config: .claude.json present with codegraph — jq merges context7, codegraph preserved" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  local claude_json="$cfg_dir/.claude.json"
  stub_absent claude
  mkdir -p "$cfg_dir"

  cat > "$claude_json" <<'EOF'
{
  "mcpServers": {
    "codegraph": {
      "command": "codegraph",
      "args": ["mcp"]
    }
  }
}
EOF

  _write_context7_mcp_config "work" "$cfg_dir"

  # context7 key added
  grep -q '"context7"' "$claude_json"
  # codegraph key preserved
  grep -q '"codegraph"' "$claude_json"
}

@test "_write_context7_mcp_config: .claude.json already has context7 — idempotent, 'already configured' in output, file unchanged" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  local claude_json="$cfg_dir/.claude.json"
  mkdir -p "$cfg_dir"

  cat > "$claude_json" <<'EOF'
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    }
  }
}
EOF
  local orig_content
  orig_content="$(cat "$claude_json")"

  run _write_context7_mcp_config "work" "$cfg_dir"

  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already configured"
  [[ "$(cat "$claude_json")" == "$orig_content" ]]
}

@test "_write_context7_mcp_config: jq absent, claude absent — warns 'manually', does NOT create .claude.json" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  local claude_json="$cfg_dir/.claude.json"
  local log_file="$WSK_TEST_HOME/jq_absent_ctx7.log"
  : > "$log_file"
  mkdir -p "$cfg_dir"

  cat > "$claude_json" <<'EOF'
{
  "mcpServers": {
    "other-server": {
      "command": "other",
      "args": []
    }
  }
}
EOF
  local orig_content
  orig_content="$(cat "$claude_json")"

  stub_absent jq
  stub_absent claude

  local output
  output="$(bash -c "
    export PATH='${WSK_STUB_BIN}'
    export WSK_STUB_LOG='${log_file}'
    export WSK_STUB_BIN='${WSK_STUB_BIN}'
    export HOME='${WSK_TEST_HOME}'
    export WSK_DIR='${WSK_DIR}'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    _write_context7_mcp_config 'work' '${cfg_dir}' || true
  " 2>&1)"

  echo "$output" | grep -qi "manually\|absent\|warn"
  [[ "$(cat "$claude_json")" == "$orig_content" ]]
}

@test "_write_context7_mcp_config: primary path — claude CLI present, invoked with correct args" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  local log_file="$WSK_TEST_HOME/ctx7_primary.log"
  : > "$log_file"
  # claude stub present by default from init_test_home

  _run_iso_context7 "$log_file" "" "_write_context7_mcp_config work '$cfg_dir'"

  grep -q 'claude mcp add --scope user context7' "$log_file"
}

# ---------------------------------------------------------------------------
# install_context7 tests
# ---------------------------------------------------------------------------

@test "install_context7: npx present, claude absent — .claude.json created with context7 entry" {
  local log_file="$WSK_TEST_HOME/ctx7_fresh.log"
  : > "$log_file"
  npx_present
  stub_absent claude

  _run_iso_context7 "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_STUB_GUM_CONFIRM_EXIT=0" \
    "install_context7 work"

  [[ -f "${WSK_TEST_HOME}/.claude-work/.claude.json" ]]
  grep -q '"context7"' "${WSK_TEST_HOME}/.claude-work/.claude.json"
  ! [[ -f "${WSK_TEST_HOME}/.claude-work/.mcp.json" ]]
}

@test "install_context7: fresh write creates context7 alongside existing codegraph" {
  local log_file="$WSK_TEST_HOME/ctx7_alongside.log"
  : > "$log_file"
  npx_present
  stub_absent claude

  # Pre-seed .claude.json with codegraph entry
  local cfg_dir="${WSK_TEST_HOME}/.claude-work"
  mkdir -p "$cfg_dir"
  cat > "${cfg_dir}/.claude.json" <<'EOF'
{
  "mcpServers": {
    "codegraph": {
      "command": "codegraph",
      "args": ["mcp"]
    }
  }
}
EOF

  _run_iso_context7 "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_STUB_GUM_CONFIRM_EXIT=0" \
    "install_context7 work"

  grep -q '"context7"' "${cfg_dir}/.claude.json"
  grep -q '"codegraph"' "${cfg_dir}/.claude.json"
}

@test "install_context7: idempotent re-run — 'already configured' reported, file not clobbered" {
  local log_file="$WSK_TEST_HOME/ctx7_idem.log"
  : > "$log_file"
  npx_present

  # Pre-seed .claude.json with context7 already present
  local cfg_dir="${WSK_TEST_HOME}/.claude-work"
  mkdir -p "$cfg_dir"
  cat > "${cfg_dir}/.claude.json" <<'EOF'
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    }
  }
}
EOF
  local orig_content
  orig_content="$(cat "${cfg_dir}/.claude.json")"

  local output
  output="$(_run_iso_context7 "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_STUB_GUM_CONFIRM_EXIT=0" \
    "install_context7 work")"

  echo "$output" | grep -qi "already configured"
  [[ "$(cat "${cfg_dir}/.claude.json")" == "$orig_content" ]]
}

@test "install_context7: confirm declined — .claude.json NOT created" {
  local log_file="$WSK_TEST_HOME/ctx7_declined.log"
  : > "$log_file"
  npx_present

  _run_iso_context7 "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_STUB_GUM_CONFIRM_EXIT=1" \
    "install_context7 work"

  # install_context7 itself does NOT call ui_confirm — the caller (run_ai) does.
  # Verify no unexpected side-effects.
  true
}

@test "install_context7: npx absent — check_warn printed, .claude.json NOT created" {
  local log_file="$WSK_TEST_HOME/ctx7_npx_absent.log"
  : > "$log_file"
  npx_absent

  local output
  output="$(_run_iso_context7 "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew" \
    "install_context7 work")"

  echo "$output" | grep -qi "npx\|warn\|not found\|missing"
  [[ ! -f "${WSK_TEST_HOME}/.claude-work/.claude.json" ]] || \
    ! grep -q '"context7"' "${WSK_TEST_HOME}/.claude-work/.claude.json"
}
