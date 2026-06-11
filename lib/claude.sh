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
    if claude --version &>/dev/null 2>&1; then
      check_pass "claude already installed"
      return 0
    fi
    log_info "claude wrapper found but native binary missing — reinstalling..."
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
# install_rtk
# Installs RTK (Rust Token Killer) via Homebrew and wires the PreToolUse hook
# into EVERY account's Claude settings so Bash commands are auto-compressed.
# NOTE: `rtk init -g` does NOT write the hook itself — it only prints a manual
# snippet — so the kit merges the hook entry directly via jq.
# Idempotent via command -v rtk and per-account hook checks.
# ---------------------------------------------------------------------------
_write_rtk_hook() {
  local acct="$1"
  local cfg_dir="${HOME}/.claude-${acct}"
  local settings="${cfg_dir}/settings.json"

  mkdir -p "$cfg_dir"

  if [[ -f "$settings" ]] && grep -q 'rtk hook claude' "$settings" 2>/dev/null; then
    check_pass "${acct}: rtk hook already configured"
    return 0
  fi

  if ! command -v jq &>/dev/null; then
    check_warn "${acct}: jq not available — add the rtk PreToolUse hook to ${settings} manually"
    return 0
  fi

  [[ -f "$settings" ]] || printf '{}\n' > "$settings"

  local tmp
  tmp="$(mktemp)"
  jq '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{
        matcher: "Bash",
        hooks: [{ type: "command", command: "rtk hook claude" }]
      }])' "$settings" > "$tmp" && mv "$tmp" "$settings"
  check_pass "${acct}: rtk hook configured"
}

install_rtk() {
  if ! command -v rtk &>/dev/null; then
    ui_spin "Installing rtk..." brew install rtk
  else
    check_pass "rtk already installed"
  fi

  command -v rtk &>/dev/null || return 0

  if [[ "${#WSK_ACCOUNTS[@]}" -eq 0 ]]; then
    load_accounts
  fi

  if [[ "${#WSK_ACCOUNTS[@]}" -eq 0 ]]; then
    check_warn "no accounts configured — rtk hook not wired (run accounts setup first)"
    return 0
  fi

  local acct
  for acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    _write_rtk_hook "$acct"
  done
}

# ---------------------------------------------------------------------------
# install_caveman
# Enables the Caveman token-compression plugin for EVERY account via the
# Claude Code plugin system (marketplace entry + enabledPlugins).
# Plugin-based install only — the standalone curl installer is intentionally
# NOT used because it duplicates the plugin's SessionStart/UserPromptSubmit
# hooks (both fire on every prompt).
# Idempotent via per-account settings checks.
# ---------------------------------------------------------------------------
_enable_caveman_plugin() {
  local acct="$1"
  local cfg_dir="${HOME}/.claude-${acct}"
  local settings="${cfg_dir}/settings.json"

  mkdir -p "$cfg_dir"

  if [[ -f "$settings" ]] && grep -q '"caveman@caveman"' "$settings" 2>/dev/null; then
    check_pass "${acct}: caveman plugin already enabled"
    return 0
  fi

  if ! command -v jq &>/dev/null; then
    check_warn "${acct}: jq not available — enable the caveman plugin in ${settings} manually"
    return 0
  fi

  [[ -f "$settings" ]] || printf '{}\n' > "$settings"

  local tmp
  tmp="$(mktemp)"
  jq '.enabledPlugins."caveman@caveman" = true
      | .extraKnownMarketplaces.caveman = {
          source: { source: "github", repo: "JuliusBrussee/caveman" }
        }' "$settings" > "$tmp" && mv "$tmp" "$settings"
  check_pass "${acct}: caveman plugin enabled"
}

install_caveman() {
  if ! command -v node &>/dev/null; then
    check_warn "caveman requires Node ≥18 — skipping"
    return 0
  fi

  if [[ "${#WSK_ACCOUNTS[@]}" -eq 0 ]]; then
    load_accounts
  fi

  if [[ "${#WSK_ACCOUNTS[@]}" -eq 0 ]]; then
    check_warn "no accounts configured — caveman not enabled (run accounts setup first)"
    return 0
  fi

  local acct
  for acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    _enable_caveman_plugin "$acct"
  done
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

# ---------------------------------------------------------------------------
# _write_context7_mcp_config <account> <cfg_dir>
# Writes/merges the context7 MCP server entry into <cfg_dir>/.mcp.json.
# Behaviour mirrors _write_codegraph_mcp_config:
#   - File absent      → write full JSON object.
#   - File present, no context7, jq available → jq-merge (non-destructive).
#   - File present, no context7, jq absent    → check_warn, do NOT clobber.
# ---------------------------------------------------------------------------
_write_context7_mcp_config() {
  local acct="$1" cfg_dir="$2"
  local mcp_file="${cfg_dir}/.mcp.json"

  mkdir -p "$cfg_dir"

  # Idempotency: already configured?
  if [[ -f "$mcp_file" ]] && grep -q '"context7"' "$mcp_file" 2>/dev/null; then
    check_pass "${acct}: context7 MCP already configured"
    return 0
  fi

  local context7_entry
  context7_entry='{"command":"npx","args":["-y","@upstash/context7-mcp"],"env":{}}'

  if [[ ! -f "$mcp_file" ]]; then
    # File absent — write full object
    printf '{\n  "mcpServers": {\n    "context7": %s\n  }\n}\n' "$context7_entry" > "$mcp_file"
    check_pass "${acct}: context7 MCP config written"
    return 0
  fi

  # File present, context7 not yet in it — try jq merge
  if command -v jq &>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    jq --argjson entry "$context7_entry" \
       '.mcpServers.context7 = $entry' \
       "$mcp_file" > "$tmp" && mv "$tmp" "$mcp_file"
    check_pass "${acct}: context7 MCP config merged"
  else
    check_warn "${acct}: .mcp.json exists — add context7 server manually (jq not available)"
  fi
}

# ---------------------------------------------------------------------------
# install_context7 <account>
# Verifies npx is available and writes the per-account context7 MCP config
# into ~/.claude-{acct}/.mcp.json. No binary install required — context7 runs
# via `npx -y @upstash/context7-mcp` at MCP startup. Idempotent.
# ---------------------------------------------------------------------------
install_context7() {
  local acct="$1"
  local cfg_dir="${HOME}/.claude-${acct}"

  if ! command -v npx &>/dev/null; then
    check_warn "npx not found — install Node.js to enable context7 MCP for ${acct}"
    return 0
  fi

  _write_context7_mcp_config "$acct" "$cfg_dir"
}
