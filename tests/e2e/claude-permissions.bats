#!/usr/bin/env bats
# claude-permissions.bats — Tests for _apply_claude_permissions and doctor checks.
# Covers: fresh apply, idempotency, key preservation, jq-absent warn, doctor pass/warn.

bats_require_minimum_version 1.5.0

load "../helpers/setup"

# ---------------------------------------------------------------------------
# Helper: run _apply_claude_permissions in an isolated subprocess.
# $1 = account name
# $2 = extra env/setup fragment (injected before sourcing libs)
# ---------------------------------------------------------------------------
_run_iso_perms() {
  local acct="$1" extra_setup="${2:-}"
  bash -c "
    export PATH='${WSK_STUB_BIN}:/usr/bin:/bin'
    export WSK_STUB_LOG='${WSK_STUB_LOG}'
    export WSK_STUB_BIN='${WSK_STUB_BIN}'
    export HOME='${WSK_TEST_HOME}'
    export WSK_DIR='${WSK_DIR}'
    ${extra_setup}
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    _apply_claude_permissions '${acct}' || true
  " 2>&1
}

# ---------------------------------------------------------------------------
# Helper: run run_doctor in an isolated subprocess capturing output.
# $1 = extra env/setup fragment (injected before sourcing doctor.sh)
# ---------------------------------------------------------------------------
_run_doctor_iso() {
  local extra_setup="${1:-}"
  bash -c "
    export WSK_STUB_LOG='${WSK_STUB_LOG}'
    export WSK_TEST_HOME='${WSK_TEST_HOME}'
    export WSK_DIR='${WSK_DIR}'
    export HOME='${WSK_TEST_HOME}'
    export PATH='${WSK_STUB_BIN}:/usr/bin:/bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/accounts.sh'
    ${extra_setup}
    source '${WSK_DIR}/lib/doctor.sh'
    run_doctor 2>&1
  " 2>&1
}

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

# ===========================================================================
# _apply_claude_permissions — fresh apply
# ===========================================================================

@test "_apply_claude_permissions: settings.json absent — creates file with defaultMode=bypassPermissions" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"

  _run_iso_perms "work"

  [[ -f "${cfg_dir}/settings.json" ]]
  grep -q 'bypassPermissions' "${cfg_dir}/settings.json"
  grep -q '"defaultMode"' "${cfg_dir}/settings.json"
}

@test "_apply_claude_permissions: fresh apply includes skipDangerousModePermissionPrompt=true" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"

  _run_iso_perms "work"

  [[ -f "${cfg_dir}/settings.json" ]]
  grep -q 'skipDangerousModePermissionPrompt' "${cfg_dir}/settings.json"
}

@test "_apply_claude_permissions: fresh apply includes deny array with at least one entry" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"

  _run_iso_perms "work"

  [[ -f "${cfg_dir}/settings.json" ]]
  grep -q '"deny"' "${cfg_dir}/settings.json"
  # The overlay has 24 entries; verify at least the .env guard is present.
  grep -q 'Read(.env)' "${cfg_dir}/settings.json"
}

# ===========================================================================
# _apply_claude_permissions — idempotency
# ===========================================================================

@test "_apply_claude_permissions: double-apply produces identical settings.json" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"

  _run_iso_perms "work"
  local first
  first="$(cat "${cfg_dir}/settings.json")"

  _run_iso_perms "work"
  local second
  second="$(cat "${cfg_dir}/settings.json")"

  [[ "$first" == "$second" ]]
}

# ===========================================================================
# _apply_claude_permissions — preserves pre-existing keys
# ===========================================================================

@test "_apply_claude_permissions: preserves pre-existing 'model' key in settings.json" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  mkdir -p "$cfg_dir"
  printf '{"model":"claude-opus-4-5"}\n' > "${cfg_dir}/settings.json"

  _run_iso_perms "work"

  [[ -f "${cfg_dir}/settings.json" ]]
  grep -q '"model"' "${cfg_dir}/settings.json"
  grep -q 'claude-opus-4-5' "${cfg_dir}/settings.json"
  # And permissions overlay is also present
  grep -q 'bypassPermissions' "${cfg_dir}/settings.json"
}

@test "_apply_claude_permissions: preserves pre-existing 'hooks' key in settings.json" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  mkdir -p "$cfg_dir"
  printf '{"hooks":{"PreToolUse":[]}}\n' > "${cfg_dir}/settings.json"

  _run_iso_perms "work"

  [[ -f "${cfg_dir}/settings.json" ]]
  grep -q '"hooks"' "${cfg_dir}/settings.json"
  grep -q 'bypassPermissions' "${cfg_dir}/settings.json"
}

# ===========================================================================
# _apply_claude_permissions — jq absent path
# ===========================================================================

@test "_apply_claude_permissions: jq absent — emits check_warn, does not crash" {
  # Exclude /usr/bin from PATH so jq (at /usr/bin/jq on macOS) is invisible.
  # Keep /bin so that mkdir, bash, and other POSIX builtins remain accessible.
  # Remove the jq shim from WSK_STUB_BIN for the same reason.
  local output
  output="$(bash -c "
    export PATH='${WSK_STUB_BIN}:/bin'
    export WSK_STUB_LOG='${WSK_STUB_LOG}'
    export WSK_STUB_BIN='${WSK_STUB_BIN}'
    export HOME='${WSK_TEST_HOME}'
    export WSK_DIR='${WSK_DIR}'
    rm -f '${WSK_STUB_BIN}/jq'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    _apply_claude_permissions work || true
  " 2>&1)"

  echo "$output" | grep -qi "manually\|not available\|warn"
}

@test "_apply_claude_permissions: jq absent — bypassPermissions not written to settings.json" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"

  bash -c "
    export PATH='${WSK_STUB_BIN}:/bin'
    export WSK_STUB_LOG='${WSK_STUB_LOG}'
    export WSK_STUB_BIN='${WSK_STUB_BIN}'
    export HOME='${WSK_TEST_HOME}'
    export WSK_DIR='${WSK_DIR}'
    rm -f '${WSK_STUB_BIN}/jq'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    _apply_claude_permissions work || true
  " 2>&1

  # Without jq the settings.json should not contain bypassPermissions.
  if [[ -f "${cfg_dir}/settings.json" ]]; then
    ! grep -q 'bypassPermissions' "${cfg_dir}/settings.json"
  fi
}

# ===========================================================================
# Doctor — bypass permissions pass/warn checks
# ===========================================================================

@test "Doctor: bypass permissions — check_pass when defaultMode=bypassPermissions in settings.json" {
  seed_account "work" "Work" "Dev" "dev@work.com" "devuser" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_ACCOUNTS_DIR}/work.env"
  mkdir -p "$HOME/.claude-work"
  printf '{"permissions":{"defaultMode":"bypassPermissions","deny":[]},"skipDangerousModePermissionPrompt":true}\n' \
    > "$HOME/.claude-work/settings.json"
  stub_present gentle-ai

  local out
  out=$(_run_doctor_iso "
    load_accounts() {
      WSK_ACCOUNTS=(work)
      export WSK_ACCOUNTS
    }
    ui_section()  { true; }
    ui_subhead()  { printf '\n%s\n' \"\$1\"; }
    gh()          { return 1; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
    export WSK_ACCOUNTS_DIR='${WSK_ACCOUNTS_DIR}'
  ")

  echo "$out" | grep -q 'bypass permissions overlay applied'
}

@test "Doctor: bypass permissions — check_warn when settings.json has no defaultMode" {
  seed_account "work" "Work" "Dev" "dev@work.com" "devuser" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_ACCOUNTS_DIR}/work.env"
  mkdir -p "$HOME/.claude-work"
  printf '{"model":"claude-opus-4-5"}\n' > "$HOME/.claude-work/settings.json"
  stub_present gentle-ai

  local out
  out=$(_run_doctor_iso "
    load_accounts() {
      WSK_ACCOUNTS=(work)
      export WSK_ACCOUNTS
    }
    ui_section()  { true; }
    ui_subhead()  { printf '\n%s\n' \"\$1\"; }
    gh()          { return 1; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
    export WSK_ACCOUNTS_DIR='${WSK_ACCOUNTS_DIR}'
  ")

  echo "$out" | grep -q 'bypass permissions overlay missing'
  echo "$out" | grep -q 'wsk fix-claude'
}

@test "Doctor: bypass permissions — no check emitted for non-gentle-ai account" {
  seed_account "work" "Work" "Dev" "dev@work.com" "devuser" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  echo "AI_FRAMEWORK=gsd" >> "${WSK_ACCOUNTS_DIR}/work.env"
  mkdir -p "$HOME/.claude-work"
  printf '{"model":"claude-opus-4-5"}\n' > "$HOME/.claude-work/settings.json"

  local out
  out=$(_run_doctor_iso "
    load_accounts() {
      WSK_ACCOUNTS=(work)
      export WSK_ACCOUNTS
    }
    ui_section()  { true; }
    ui_subhead()  { printf '\n%s\n' \"\$1\"; }
    gh()          { return 1; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
    export WSK_ACCOUNTS_DIR='${WSK_ACCOUNTS_DIR}'
  ")

  ! echo "$out" | grep -q 'bypass permissions overlay'
}
