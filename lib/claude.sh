#!/usr/bin/env bash
set -euo pipefail

# claude.sh — Claude Code and codegraph installers, per-account MCP config writer.
# Depends on: lib/log.sh, lib/ui.sh, lib/os.sh (WSK_OS), lib/node.sh (node prereq).

# Guard against double-source.
if declare -f install_claude_code > /dev/null 2>&1; then
  return 0
fi

# ---------------------------------------------------------------------------
# install_claude_code
# Installs Claude Code via the official cross-platform curl installer.
# Idempotent via command -v claude.
# Windows: prints a PowerShell instruction, no installer run.
# ---------------------------------------------------------------------------
install_claude_code() {
  if command -v claude &>/dev/null; then
    check_pass "claude already installed"
    return 0
  fi

  if [[ "${WSK_OS:-}" == "windows" ]]; then
    log_info "Run in PowerShell: irm https://claude.ai/install.ps1 | iex"
    return 0
  fi

  ui_spin "Installing Claude Code..." bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
}

# ---------------------------------------------------------------------------
# _write_codegraph_mcp_config <account> <cfg_dir>
# Writes the codegraph MCP server entry into $cfg_dir/.mcp.json.
# Idempotent: if the file already contains "codegraph", returns immediately.
# Merge strategy:
#   - File absent      → write full JSON object.
#   - File present, no codegraph, jq available → jq-merge (non-destructive).
#   - File present, no codegraph, jq absent    → check_warn, do NOT clobber.
# ---------------------------------------------------------------------------
_write_codegraph_mcp_config() {
  local acct="$1" cfg_dir="$2"
  local mcp_file="${cfg_dir}/.mcp.json"

  mkdir -p "$cfg_dir"

  # Idempotency: already configured?
  if [[ -f "$mcp_file" ]] && grep -q '"codegraph"' "$mcp_file" 2>/dev/null; then
    check_pass "${acct}: codegraph MCP already configured"
    return 0
  fi

  local codegraph_entry
  codegraph_entry='{"command":"codegraph","args":["mcp"],"env":{}}'

  if [[ ! -f "$mcp_file" ]]; then
    # File absent — write full object
    printf '{\n  "mcpServers": {\n    "codegraph": %s\n  }\n}\n' "$codegraph_entry" > "$mcp_file"
    check_pass "${acct}: codegraph MCP config written"
    return 0
  fi

  # File present, codegraph not yet in it — try jq merge
  if command -v jq &>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    jq --argjson entry "$codegraph_entry" \
       '.mcpServers.codegraph = $entry' \
       "$mcp_file" > "$tmp" && mv "$tmp" "$mcp_file"
    check_pass "${acct}: codegraph MCP config merged"
  else
    check_warn "${acct}: .mcp.json exists — add codegraph server manually (jq not available)"
  fi
}

# ---------------------------------------------------------------------------
# install_codegraph <account>
# Installs the codegraph npm global package for the given account and writes
# the per-account MCP config into ~/.claude-{acct}/.mcp.json.
# Requires Node.js. Idempotent via command -v codegraph.
# ---------------------------------------------------------------------------
install_codegraph() {
  local acct="$1"
  local cfg_dir="${HOME}/.claude-${acct}"

  if ! command -v node &>/dev/null; then
    log_error "Node.js is required for codegraph"
    return 1
  fi

  if ! command -v codegraph &>/dev/null; then
    ui_spin "Installing codegraph..." npm i -g @colbymchenry/codegraph
  else
    check_pass "codegraph already installed"
  fi

  _write_codegraph_mcp_config "$acct" "$cfg_dir"
}
