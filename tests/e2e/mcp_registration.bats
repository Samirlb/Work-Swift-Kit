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
# Helper: run function in isolated subprocess with controlled PATH
# ---------------------------------------------------------------------------
_run_iso_mcp() {
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
# _write_codegraph_mcp_config — fallback path (jq, no claude CLI)
# ---------------------------------------------------------------------------

@test "_write_codegraph_mcp_config: .claude.json absent, jq present, claude absent — creates .claude.json with codegraph" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  local log_file="$WSK_TEST_HOME/cg_fresh.log"
  : > "$log_file"
  stub_absent claude

  local output
  output="$(_run_iso_mcp "$log_file" "" "_write_codegraph_mcp_config work '$cfg_dir'")"

  [[ -f "${cfg_dir}/.claude.json" ]]
  grep -q '"codegraph"' "${cfg_dir}/.claude.json"
  grep -q '"mcpServers"' "${cfg_dir}/.claude.json"
  ! [[ -f "${cfg_dir}/.mcp.json" ]]
}

@test "_write_codegraph_mcp_config: .claude.json already has codegraph — idempotent, 'already configured' in output" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  mkdir -p "$cfg_dir"
  cat > "${cfg_dir}/.claude.json" <<'EOF'
{"mcpServers":{"codegraph":{"command":"codegraph","args":["mcp"]}}}
EOF
  local orig
  orig="$(cat "${cfg_dir}/.claude.json")"

  run _write_codegraph_mcp_config "work" "$cfg_dir"

  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already configured"
  [[ "$(cat "${cfg_dir}/.claude.json")" == "$orig" ]]
}

@test "_write_codegraph_mcp_config: jq present, .claude.json has context7 — merges codegraph, context7 preserved" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  local log_file="$WSK_TEST_HOME/cg_merge.log"
  : > "$log_file"
  stub_absent claude
  mkdir -p "$cfg_dir"
  cat > "${cfg_dir}/.claude.json" <<'EOF'
{"mcpServers":{"context7":{"command":"npx","args":["-y","@upstash/context7-mcp"]}}}
EOF

  _run_iso_mcp "$log_file" "" "_write_codegraph_mcp_config work '$cfg_dir'"

  grep -q '"codegraph"' "${cfg_dir}/.claude.json"
  grep -q '"context7"' "${cfg_dir}/.claude.json"
}

@test "_write_codegraph_mcp_config: primary path — claude CLI present, invoked with correct args" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  local log_file="$WSK_TEST_HOME/cg_primary.log"
  : > "$log_file"
  # claude stub is present by default from init_test_home

  local output
  output="$(_run_iso_mcp "$log_file" "" "_write_codegraph_mcp_config work '$cfg_dir'")"

  # Verify claude was called with mcp add --scope user codegraph
  grep -q 'claude mcp add --scope user codegraph' "$log_file"
}

@test "_write_codegraph_mcp_config: no claude, no jq — check_warn emitted" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  local log_file="$WSK_TEST_HOME/cg_nowarn.log"
  : > "$log_file"
  stub_absent claude
  stub_absent jq

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
    _write_codegraph_mcp_config work '${cfg_dir}' || true
  " 2>&1)"

  echo "$output" | grep -qi "manually\|absent\|warn"
}

# ---------------------------------------------------------------------------
# _write_context7_mcp_config — fallback path (jq, no claude CLI)
# ---------------------------------------------------------------------------

@test "_write_context7_mcp_config: .claude.json absent, jq present, claude absent — creates .claude.json with context7" {
  local cfg_dir="$WSK_TEST_HOME/.claude-ctx"
  local log_file="$WSK_TEST_HOME/ctx7_fresh.log"
  : > "$log_file"
  stub_absent claude

  _run_iso_mcp "$log_file" "" "_write_context7_mcp_config ctx '$cfg_dir'"

  [[ -f "${cfg_dir}/.claude.json" ]]
  grep -q '"context7"' "${cfg_dir}/.claude.json"
  grep -q '"npx"' "${cfg_dir}/.claude.json"
  ! [[ -f "${cfg_dir}/.mcp.json" ]]
}

@test "_write_context7_mcp_config: .claude.json already has context7 — idempotent, 'already configured' in output" {
  local cfg_dir="$WSK_TEST_HOME/.claude-ctx"
  mkdir -p "$cfg_dir"
  cat > "${cfg_dir}/.claude.json" <<'EOF'
{"mcpServers":{"context7":{"command":"npx","args":["-y","@upstash/context7-mcp"]}}}
EOF
  local orig
  orig="$(cat "${cfg_dir}/.claude.json")"

  run _write_context7_mcp_config "ctx" "$cfg_dir"

  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already configured"
  [[ "$(cat "${cfg_dir}/.claude.json")" == "$orig" ]]
}

@test "_write_context7_mcp_config: primary path — claude CLI present, invoked with correct args" {
  local cfg_dir="$WSK_TEST_HOME/.claude-ctx"
  local log_file="$WSK_TEST_HOME/ctx7_primary.log"
  : > "$log_file"

  _run_iso_mcp "$log_file" "" "_write_context7_mcp_config ctx '$cfg_dir'"

  grep -q 'claude mcp add --scope user context7' "$log_file"
}

@test "_write_context7_mcp_config: jq present, .claude.json has codegraph — merges context7, codegraph preserved" {
  local cfg_dir="$WSK_TEST_HOME/.claude-ctx"
  local log_file="$WSK_TEST_HOME/ctx7_merge.log"
  : > "$log_file"
  stub_absent claude
  mkdir -p "$cfg_dir"
  cat > "${cfg_dir}/.claude.json" <<'EOF'
{"mcpServers":{"codegraph":{"command":"codegraph","args":["mcp"]}}}
EOF

  _run_iso_mcp "$log_file" "" "_write_context7_mcp_config ctx '$cfg_dir'"

  grep -q '"context7"' "${cfg_dir}/.claude.json"
  grep -q '"codegraph"' "${cfg_dir}/.claude.json"
}
