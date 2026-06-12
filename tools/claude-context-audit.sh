#!/usr/bin/env bash
set -euo pipefail

# claude-context-audit.sh — estimate the fixed token floor a Claude Code
# session (and every sub-agent) pays for a given profile.
#
# Usage:
#   tools/claude-context-audit.sh [profile-dir ...]
# With no args, audits every ~/.claude-* profile directory.
#
# Token estimate: chars / 4 (rough English/markdown average). Treat results
# as relative weights, not billing-grade numbers.

_est_tokens() { # <bytes>
  echo $(( $1 / 4 ))
}

_file_size() { # <path> → bytes (0 if missing)
  [[ -f "$1" ]] && wc -c < "$1" | tr -d ' ' || echo 0
}

_section_size() { # <file> <begin-marker> <end-marker> → bytes of the region
  awk -v b="$2" -v e="$3" '
    index($0, b) { on=1 }
    on { n += length($0) + 1 }
    index($0, e) { on=0 }
    END { print n+0 }
  ' "$1" 2>/dev/null
}

_audit_profile() {
  local dir="$1"
  [[ -d "$dir" ]] || { echo "skip: $dir (not a directory)"; return 0; }
  local name="${dir##*/}"
  local total_bytes=0

  printf '\n=== %s ===\n' "$name"

  # --- CLAUDE.md, with per-section breakdown ------------------------------
  local md="$dir/CLAUDE.md"
  local md_bytes; md_bytes=$(_file_size "$md")
  total_bytes=$(( total_bytes + md_bytes ))
  printf 'CLAUDE.md                 %7d bytes  ~%5d tokens\n' "$md_bytes" "$(_est_tokens "$md_bytes")"

  if [[ -f "$md" ]]; then
    local sec
    for sec in persona sdd-orchestrator engram-protocol; do
      local b; b=$(_section_size "$md" "<!-- gentle-ai:${sec} -->" "<!-- /gentle-ai:${sec} -->")
      [[ "$b" -gt 0 ]] && printf '  - gentle-ai:%-14s %7d bytes  ~%5d tokens\n' "$sec" "$b" "$(_est_tokens "$b")"
    done
    for sec in SUBAGENT-CONTEXT-MINIMALISM MULTI-ACCOUNT-GUIDE; do
      local b; b=$(_section_size "$md" "<!-- WSK:${sec}:BEGIN -->" "<!-- WSK:${sec}:END -->")
      [[ "$b" -gt 0 ]] && printf '  - WSK:%-19s %7d bytes  ~%5d tokens\n' "$sec" "$b" "$(_est_tokens "$b")"
    done
    # @imports referenced from CLAUDE.md (e.g. @RTK.md) load too.
    local imp
    while IFS= read -r imp; do
      imp="${imp#@}"
      local p="$dir/$imp"
      local b; b=$(_file_size "$p")
      [[ "$b" -gt 0 ]] && { total_bytes=$(( total_bytes + b )); printf '  - import @%-15s %7d bytes  ~%5d tokens\n' "$imp" "$b" "$(_est_tokens "$b")"; }
    done < <(grep -o '^@[A-Za-z0-9._/-]*' "$md" 2>/dev/null || true)
  fi

  # --- Skills: the listing (name + description) loads every session -------
  if [[ -d "$dir/skills" ]]; then
    local skill_count=0 desc_bytes=0
    local sk
    for sk in "$dir/skills"/*/SKILL.md; do
      [[ -e "$sk" ]] || continue
      skill_count=$(( skill_count + 1 ))
      # description: field from frontmatter is what enters the session listing
      local d; d=$(awk -F': *' '/^description:/ {print $2; exit}' "$sk" 2>/dev/null | wc -c | tr -d ' ')
      desc_bytes=$(( desc_bytes + d + 40 ))   # +40: name/frontmatter overhead per entry
    done
    total_bytes=$(( total_bytes + desc_bytes ))
    printf 'skills listing (%2d)       %7d bytes  ~%5d tokens\n' "$skill_count" "$desc_bytes" "$(_est_tokens "$desc_bytes")"
  fi

  # --- Commands (slash) — only their names list; bodies load on invoke ----
  if [[ -d "$dir/commands" ]]; then
    local cmd_count; cmd_count=$(find "$dir/commands" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    printf 'commands (on-invoke)      %7s        %2d files (bodies load only when used)\n' "-" "$cmd_count"
  fi

  # --- Agents — definitions load when an agent type is launched -----------
  if [[ -d "$dir/agents" ]]; then
    local ag_bytes=0 ag_count=0 ag
    for ag in "$dir/agents"/*.md; do
      [[ -e "$ag" ]] || continue
      ag_count=$(( ag_count + 1 ))
      ag_bytes=$(( ag_bytes + $(_file_size "$ag") ))
    done
    printf 'agents (per-launch)       %7d bytes  ~%5d tokens across %d defs (cost hits the launched agent)\n' "$ag_bytes" "$(_est_tokens "$ag_bytes")" "$ag_count"
  fi

  # --- Plugins -------------------------------------------------------------
  local settings="$dir/settings.json"
  if [[ -f "$settings" ]] && command -v jq >/dev/null 2>&1; then
    local plugins; plugins=$(jq -r '.enabledPlugins // {} | keys | join(", ")' "$settings" 2>/dev/null)
    printf 'plugins enabled           %7s        %s (each adds hooks/instructions at runtime)\n' "-" "${plugins:-none}"
  fi

  # --- MCP servers (user scope) — instructions+tools load server-side -----
  local cj="$dir/.claude.json"
  if [[ -f "$cj" ]] && command -v jq >/dev/null 2>&1; then
    local mcps; mcps=$(jq -r '.mcpServers // {} | keys | join(", ")' "$cj" 2>/dev/null)
    printf 'MCP servers (user)        %7s        %s (instructions size depends on each server)\n' "-" "${mcps:-none}"
  fi

  printf -- '--------------------------------------------\n'
  printf 'measurable fixed floor    %7d bytes  ~%5d tokens per session AND per sub-agent\n' "$total_bytes" "$(_est_tokens "$total_bytes")"
  printf '(plus: system prompt, tool definitions, MCP instructions, plugin hook output — not measurable from disk)\n'
}

if [[ $# -gt 0 ]]; then
  for d in "$@"; do _audit_profile "$d"; done
else
  found=0
  for d in "$HOME"/.claude-*; do
    [[ -d "$d" ]] || continue
    found=1
    _audit_profile "$d"
  done
  [[ "$found" -eq 1 ]] || echo "No ~/.claude-* profile directories found."
fi
