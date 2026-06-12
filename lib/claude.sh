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
# Registers the codegraph MCP server for the given account.
# Target file: $cfg_dir/.claude.json (user-scope MCP, NOT .mcp.json).
# Claude Code reads MCP servers from .claude.json under mcpServers; .mcp.json
# is project-scope only (repo root) and is never read from a config dir.
#
# Primary path: CLAUDE_CONFIG_DIR="$cfg_dir" claude mcp add --scope user codegraph
#   (requires claude CLI on PATH; writes to .claude.json automatically).
# Fallback:     jq-merge entry into .claude.json (creates file if absent).
# Idempotent:   skips if "codegraph" key already present in .claude.json.
# ---------------------------------------------------------------------------
_write_codegraph_mcp_config() {
  local acct="$1" cfg_dir="$2"
  local claude_json="${cfg_dir}/.claude.json"

  mkdir -p "$cfg_dir"

  # Idempotency: already registered in .claude.json?
  if [[ -f "$claude_json" ]] && grep -q '"codegraph"' "$claude_json" 2>/dev/null; then
    check_pass "${acct}: codegraph MCP already configured"
    return 0
  fi

  local codegraph_entry
  codegraph_entry='{"command":"codegraph","args":["serve","--mcp"]}'

  # Primary path: use claude CLI with CLAUDE_CONFIG_DIR
  if command -v claude &>/dev/null; then
    CLAUDE_CONFIG_DIR="$cfg_dir" claude mcp add --scope user codegraph -- codegraph serve --mcp
    check_pass "${acct}: codegraph MCP registered (claude mcp add)"
    return 0
  fi

  # Fallback: jq-merge into .claude.json
  if command -v jq &>/dev/null; then
    if [[ ! -f "$claude_json" ]]; then
      printf '{"mcpServers":{}}\n' > "$claude_json"
    fi
    local tmp
    tmp="$(mktemp)"
    jq --argjson entry "$codegraph_entry" \
       '.mcpServers.codegraph = $entry' \
       "$claude_json" > "$tmp" && mv "$tmp" "$claude_json"
    check_pass "${acct}: codegraph MCP config written (.claude.json)"
    return 0
  fi

  check_warn "${acct}: claude CLI and jq both absent — add codegraph MCP server manually"
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
    # Fall through to cache check even when settings already enabled.
  else
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
  fi

  # ---------------------------------------------------------------------------
  # Plugin cache verification
  # After enabling (or confirming already-enabled), check that the plugin cache
  # dir exists.  gentle-ai reconfigure wipe removes it, causing Claude Code to
  # error "Plugin directory does not exist … run /plugin to reinstall".
  #
  # Strategy:
  #   1. Cache dir present  → nothing to do.
  #   2. Cache dir missing, sibling ~/.claude-*/plugins/cache/caveman found
  #                         → copy it with cp -r.
  #   3. Cache dir missing, no sibling → emit check_warn with /plugin hint.
  # ---------------------------------------------------------------------------
  local cache_dir="${cfg_dir}/plugins/cache/caveman"
  if [[ -d "$cache_dir" ]]; then
    return 0
  fi

  # Search sibling account dirs for a copy of the cache.
  local sibling_cache=""
  local _sib
  for _sib in "${HOME}"/.claude-*/plugins/cache/caveman; do
    # Skip the current account's own (missing) dir and glob non-matches.
    [[ -d "$_sib" ]] || continue
    [[ "$_sib" == "$cache_dir" ]] && continue
    sibling_cache="$_sib"
    break
  done

  if [[ -n "$sibling_cache" ]]; then
    mkdir -p "${cfg_dir}/plugins/cache"
    cp -r "$sibling_cache" "${cfg_dir}/plugins/cache/caveman"
    check_pass "${acct}: caveman plugin cache restored from sibling account"
  else
    check_warn "${acct}: caveman plugin cache missing — open a Claude session in that profile and run /plugin to reinstall caveman"
  fi
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
# _apply_claude_permissions <account>
# Deep-merges the gentle-ai bypass permissions overlay into
# ~/.claude-{acct}/settings.json. Creates the file as {} if absent.
# Pre-existing settings keys not in the overlay are preserved; overlay wins
# on conflict. Idempotent — merging twice yields an identical file.
# Overlay path: ${WSK_DIR}/templates/claude-permissions-overlay.json
# ---------------------------------------------------------------------------
_apply_claude_permissions() {
  local acct="$1"
  local cfg_dir="${HOME}/.claude-${acct}"
  local settings="${cfg_dir}/settings.json"
  local overlay="${WSK_DIR}/templates/claude-permissions-overlay.json"

  mkdir -p "$cfg_dir"

  if [[ ! -f "$overlay" ]]; then
    check_warn "${acct}: permissions overlay not found at ${overlay} — skipping"
    return 0
  fi

  if ! command -v jq &>/dev/null; then
    check_warn "${acct}: jq not available — apply gentle-ai bypass permissions manually"
    return 0
  fi

  log_info "${acct}: applying gentle-ai bypass permissions (defaultMode=bypassPermissions + deny guardrails)"

  [[ -f "$settings" ]] || printf '{}\n' > "$settings"

  local tmp
  tmp="$(mktemp)"
  # Deep-merge: overlay wins on conflict; existing keys not in overlay are kept.
  jq -s '.[0] * .[1]' "$settings" "$overlay" > "$tmp" && mv "$tmp" "$settings"
  check_pass "${acct}: gentle-ai bypass permissions applied"
}

# ---------------------------------------------------------------------------
# install_codegraph <account>
# Installs the codegraph npm global package for the given account and
# registers the per-account MCP config in ~/.claude-{acct}/.claude.json.
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
# Registers the context7 MCP server for the given account.
# Target file: $cfg_dir/.claude.json (user-scope MCP, NOT .mcp.json).
# Claude Code reads MCP servers from .claude.json under mcpServers; .mcp.json
# is project-scope only (repo root) and is never read from a config dir.
#
# Primary path: CLAUDE_CONFIG_DIR="$cfg_dir" claude mcp add --scope user context7
#   (requires claude CLI on PATH; writes to .claude.json automatically).
# Fallback:     jq-merge entry into .claude.json (creates file if absent).
# Idempotent:   skips if "context7" key already present in .claude.json.
# ---------------------------------------------------------------------------
_write_context7_mcp_config() {
  local acct="$1" cfg_dir="$2"
  local claude_json="${cfg_dir}/.claude.json"

  mkdir -p "$cfg_dir"

  # Idempotency: already registered in .claude.json?
  if [[ -f "$claude_json" ]] && grep -q '"context7"' "$claude_json" 2>/dev/null; then
    check_pass "${acct}: context7 MCP already configured"
    return 0
  fi

  local context7_entry
  context7_entry='{"command":"npx","args":["-y","@upstash/context7-mcp"]}'

  # Primary path: use claude CLI with CLAUDE_CONFIG_DIR
  if command -v claude &>/dev/null; then
    CLAUDE_CONFIG_DIR="$cfg_dir" claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp
    check_pass "${acct}: context7 MCP registered (claude mcp add)"
    return 0
  fi

  # Fallback: jq-merge into .claude.json
  if command -v jq &>/dev/null; then
    if [[ ! -f "$claude_json" ]]; then
      printf '{"mcpServers":{}}\n' > "$claude_json"
    fi
    local tmp
    tmp="$(mktemp)"
    jq --argjson entry "$context7_entry" \
       '.mcpServers.context7 = $entry' \
       "$claude_json" > "$tmp" && mv "$tmp" "$claude_json"
    check_pass "${acct}: context7 MCP config written (.claude.json)"
    return 0
  fi

  check_warn "${acct}: claude CLI and jq both absent — add context7 MCP server manually"
}

# ---------------------------------------------------------------------------
# install_context7 <account>
# Verifies npx is available and registers the per-account context7 MCP config
# in ~/.claude-{acct}/.claude.json. No binary install required — context7 runs
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
