#!/usr/bin/env bats

load "../helpers/setup"

setup() {
  cleanup_test_artifacts
  init_test_home
  source "${WSK_DIR}/lib/log.sh"

  # Unset exported stub functions so PATH shims take priority.
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
# Helper: run a body in an isolated subprocess (stripped PATH)
# Non-zero exit from body is absorbed (|| true).
# ---------------------------------------------------------------------------
_run_iso_claude() {
  local log_file="$1" env_prefix="$2" body="$3"
  bash -c "
    ${env_prefix}
    export PATH='${WSK_STUB_BIN}:/usr/bin:/bin'
    export WSK_STUB_LOG='${log_file}'
    export WSK_STUB_BIN='${WSK_STUB_BIN}'
    export HOME='${WSK_TEST_HOME}'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    ${body} || true
  " 2>&1
}

# ---------------------------------------------------------------------------
# install_claude_code tests
# ---------------------------------------------------------------------------

@test "install_claude_code: claude absent, WSK_OS=macos — curl claude.ai/install.sh in log, no brew call" {
  local log_file="$WSK_TEST_HOME/c1.log"
  : > "$log_file"
  claude_absent

  # sh shim to absorb piped curl output without running the real installer
  cat > "$WSK_STUB_BIN/sh" <<'SHIM'
#!/usr/bin/env bash
echo "sh $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
SHIM
  chmod +x "$WSK_STUB_BIN/sh"

  _run_iso_claude "$log_file" "export WSK_OS=macos WSK_PKG_MGR=brew" "install_claude_code"

  grep -q "https://claude.ai/install.sh" "$log_file"
  ! grep -q "brew install claude" "$log_file"
}

@test "install_claude_code: claude present — curl NOT called, 'already installed' in output" {
  WSK_OS="macos"
  export WSK_OS

  claude_present

  run install_claude_code
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already installed"
  assert_stub_not_called "https://claude.ai/install.sh"
}

@test "install_claude_code: WSK_OS=windows — PowerShell instruction printed, curl NOT called" {
  local log_file="$WSK_TEST_HOME/c3.log"
  : > "$log_file"
  claude_absent

  local output
  output="$(_run_iso_claude "$log_file" "export WSK_OS=windows WSK_PKG_MGR=''" "install_claude_code")"

  echo "$output" | grep -qi "PowerShell\|install.ps1"
  ! grep -q "https://claude.ai/install.sh" "$log_file"
}

# ---------------------------------------------------------------------------
# install_codegraph tests
# ---------------------------------------------------------------------------

@test "install_codegraph: codegraph absent, node present — npm i -g @colbymchenry/codegraph in log; .mcp.json created" {
  local log_file="$WSK_TEST_HOME/cg1.log"
  : > "$log_file"
  codegraph_absent
  node_present

  _run_iso_claude "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew" \
    "install_codegraph work"

  grep -q "npm i -g @colbymchenry/codegraph" "$log_file"
  [[ -f "${WSK_TEST_HOME}/.claude-work/.mcp.json" ]]
  grep -q "codegraph" "${WSK_TEST_HOME}/.claude-work/.mcp.json"
}

@test "install_codegraph: codegraph present — npm NOT called, 'already installed' in output" {
  WSK_OS="macos"
  export WSK_OS

  node_present
  codegraph_present

  run install_codegraph work
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already installed"
  assert_stub_not_called "npm i -g @colbymchenry/codegraph"
}

@test "install_codegraph: node absent — error 'Node.js is required for codegraph', npm NOT called" {
  local log_file="$WSK_TEST_HOME/cg3.log"
  : > "$log_file"
  codegraph_absent
  stub_absent node

  local output
  output="$(_run_iso_claude "$log_file" "export WSK_OS=macos WSK_PKG_MGR=brew" "install_codegraph work")"

  echo "$output" | grep -qi "Node.js is required"
  ! grep -q "npm i -g" "$log_file"
}

# ---------------------------------------------------------------------------
# _write_codegraph_mcp_config tests
# ---------------------------------------------------------------------------

@test "_write_codegraph_mcp_config: .mcp.json absent — written with correct JSON structure" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  local mcp_file="$cfg_dir/.mcp.json"

  _write_codegraph_mcp_config "work" "$cfg_dir"

  [[ -f "$mcp_file" ]]
  grep -q '"codegraph"' "$mcp_file"
  grep -q '"mcpServers"' "$mcp_file"
}

@test "_write_codegraph_mcp_config: .mcp.json present without codegraph — jq merges codegraph key, existing keys preserved" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  local mcp_file="$cfg_dir/.mcp.json"
  mkdir -p "$cfg_dir"

  # Existing config without codegraph
  cat > "$mcp_file" <<'EOF'
{
  "mcpServers": {
    "other-server": {
      "command": "other",
      "args": [],
      "env": {}
    }
  }
}
EOF

  _write_codegraph_mcp_config "work" "$cfg_dir"

  # codegraph key added
  grep -q '"codegraph"' "$mcp_file"
  # existing key preserved
  grep -q '"other-server"' "$mcp_file"
}

@test "_write_codegraph_mcp_config: .mcp.json present with codegraph already — no overwrite, 'already configured' in output" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  local mcp_file="$cfg_dir/.mcp.json"
  mkdir -p "$cfg_dir"

  cat > "$mcp_file" <<'EOF'
{
  "mcpServers": {
    "codegraph": {
      "command": "codegraph",
      "args": ["mcp"],
      "env": {}
    }
  }
}
EOF
  local orig_content
  orig_content="$(cat "$mcp_file")"

  run _write_codegraph_mcp_config "work" "$cfg_dir"

  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already configured"
  # file unchanged
  [[ "$(cat "$mcp_file")" == "$orig_content" ]]
}

@test "_write_codegraph_mcp_config: jq absent — warns 'add codegraph server manually', does NOT clobber existing file" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  local mcp_file="$cfg_dir/.mcp.json"
  mkdir -p "$cfg_dir"

  cat > "$mcp_file" <<'EOF'
{
  "mcpServers": {
    "other-server": {
      "command": "other",
      "args": [],
      "env": {}
    }
  }
}
EOF
  local orig_content
  orig_content="$(cat "$mcp_file")"

  # Remove jq shim to simulate jq absent
  stub_absent jq

  run _write_codegraph_mcp_config "work" "$cfg_dir"

  echo "$output" | grep -qi "manually\|add codegraph"
  # existing file not clobbered
  [[ "$(cat "$mcp_file")" == "$orig_content" ]]
}
