#!/usr/bin/env bash
# preflight.sh — Shared state/dependency validation for WSK flows.
# Prevents set -u crashes on empty arrays and missing optional binaries.
# Requires: lib/log.sh (check_warn, check_pass) to be sourced before this file.
set -euo pipefail

# ---------------------------------------------------------------------------
# require_state <flag>...
# Validates one or more state flags before a flow runs. Supported flags:
#   accounts — WSK_ACCOUNTS is non-empty
#   rendered — ${WSK_DIR}/.rendered/ directory exists and is non-empty
#   linked   — stow/.gitconfig symlink target exists in $HOME
# Emits check_warn + remediation hint for each unmet condition.
# Returns 0 if ALL conditions pass; non-zero on first failure.
# ---------------------------------------------------------------------------
require_state() {
  local flag
  for flag in "$@"; do
    case "$flag" in
      accounts)
        local _count=0
        if [[ -n "${WSK_ACCOUNTS+x}" ]]; then _count="${#WSK_ACCOUNTS[@]}"; fi
        if [[ "$_count" -eq 0 ]]; then
          check_warn "No accounts configured — run: wsk accounts"
          return 1
        fi
        ;;
      rendered)
        local rendered_dir="${WSK_DIR}/.rendered"
        if [[ ! -d "$rendered_dir" ]] || [[ -z "$(ls -A "$rendered_dir" 2>/dev/null)" ]]; then
          check_warn "Dotfiles not yet rendered — run: wsk relink"
          return 1
        fi
        ;;
      linked)
        if [[ ! -f "$HOME/.gitconfig" ]] && [[ ! -L "$HOME/.gitconfig" ]]; then
          check_warn "Dotfiles not linked — run: wsk relink"
          return 1
        fi
        ;;
      *)
        check_warn "require_state: unknown flag '${flag}'"
        return 1
        ;;
    esac
  done
  return 0
}

# ---------------------------------------------------------------------------
# preflight_accounts [--allow-empty]
# Backwards-compatible wrapper around require_state accounts.
# Validates that WSK_ACCOUNTS is non-empty before any flow that reads account
# data. Returns non-zero with a check_warn when accounts are missing.
# Pass --allow-empty to skip the check (e.g. during initial setup flows).
# ---------------------------------------------------------------------------
preflight_accounts() {
  local allow_empty=0
  if [[ "${1:-}" == "--allow-empty" ]]; then
    allow_empty=1
  fi

  if [[ "$allow_empty" -eq 1 ]]; then
    return 0
  fi

  require_state accounts
}

# ---------------------------------------------------------------------------
# _check_optional_dep <cmd> <hint>
# Checks whether <cmd> is available on PATH. If absent, emits check_warn with
# the hint and returns 0 (non-fatal — caller may continue in degraded mode).
# ---------------------------------------------------------------------------
_check_optional_dep() {
  local cmd="$1" hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    check_warn "${cmd} not found — ${hint}"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# preflight_deps
# Checks all optional dependencies used in non-critical paths.
# Emits check_warn for each missing binary and returns 0 always.
# ---------------------------------------------------------------------------
preflight_deps() {
  _check_optional_dep sd "key-value persistence will use fallback"
  _check_optional_dep rg "update progress display skipped"
  _check_optional_dep python3 "claude-md patching will be skipped"
  return 0
}
