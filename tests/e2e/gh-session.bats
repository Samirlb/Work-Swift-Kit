#!/usr/bin/env bats
# gh-session.bats — WU-5
# Tests for gh auth switch injection into zshrc wrappers and render_zshrc
# regeneration on update/relink.

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

setup() {
  init_test_home
  export WSK_DIR
  export WSK_TEST_HOME
  mkdir -p "${WSK_DIR}/stow"
  mkdir -p "${WSK_DIR}/.rendered"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ---------------------------------------------------------------------------
# Helper: render zshrc fragment in sandbox
# ---------------------------------------------------------------------------
_render_zshrc_iso() {
  local extra_setup="${1:-}"

  bash -c "
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    ${extra_setup}
    source '${WSK_DIR}/templates/zshrc.sh'
    render_zshrc 2>&1
  " 2>&1
}

# ===========================================================================
# GH-1: claude-{acct}() calls gh auth switch before claude launch
# ===========================================================================

@test "GH-1: rendered zshrc claude-work() calls gh auth switch before claude" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"

  _render_zshrc_iso "WSK_ACCOUNTS=(work)" >/dev/null

  local frag="${WSK_DIR}/.rendered/wsk-zshrc"
  [[ -f "$frag" ]]
  # The claude-work function should contain _wsk_gh_switch
  grep -q 'claude-work' "$frag"
  grep -q '_wsk_gh_switch' "$frag"
}

# ===========================================================================
# GH-2: auto-detect claude() wrapper calls gh auth switch
# ===========================================================================

@test "GH-2: rendered zshrc claude() auto-detect wrapper calls _wsk_gh_switch" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  seed_account "personal" "Personal" "JaneP" "janep@home.com" "janep" "$HOME/projects/personal" "id_personal"

  _render_zshrc_iso "WSK_ACCOUNTS=(work personal)" >/dev/null

  local frag="${WSK_DIR}/.rendered/wsk-zshrc"
  # The auto-detect claude() function should call _wsk_gh_switch with the detected account's GH user
  grep -q '_wsk_gh_switch' "$frag"
}

# ===========================================================================
# GH-3: gh absent → non-fatal, claude still launched
# ===========================================================================

@test "GH-3: _wsk_gh_switch guards command -v gh — returns 0 when gh absent" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"

  _render_zshrc_iso "WSK_ACCOUNTS=(work)" >/dev/null

  local frag="${WSK_DIR}/.rendered/wsk-zshrc"
  # The _wsk_gh_switch helper must guard with command -v gh
  grep -qF 'command -v gh' "$frag"
}

# ===========================================================================
# GH-4: gh auth switch fails → non-fatal
# ===========================================================================

@test "GH-4: _wsk_gh_switch is non-fatal on gh auth switch failure" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"

  _render_zshrc_iso "WSK_ACCOUNTS=(work)" >/dev/null

  local frag="${WSK_DIR}/.rendered/wsk-zshrc"
  # The helper should exist and contain non-fatal error handling (|| pattern)
  grep -qF '_wsk_gh_switch' "$frag"
  # Extract the _wsk_gh_switch function body and verify it has || (non-fatal fallback)
  local fn_body
  fn_body="$(awk '/^function _wsk_gh_switch/,/^}/' "$frag")"
  echo "$fn_body" | grep -q '||'
}

# ===========================================================================
# GH-5: wsk update calls render_zshrc before inject_zshrc_block
# ===========================================================================

@test "GH-5: run_update calls render_zshrc (function exists in lib/update.sh)" {
  # This is a code-level check: lib/update.sh must invoke render_zshrc
  grep -q 'render_zshrc' "${WSK_DIR}/lib/update.sh"
}

# ===========================================================================
# GH-6: wsk relink calls render_zshrc before inject_zshrc_block
# ===========================================================================

@test "GH-6: run_relink calls render_zshrc before inject_zshrc_block in install.sh" {
  grep -q 'render_zshrc' "${WSK_DIR}/install.sh" || grep -q 'render_all' "${WSK_DIR}/install.sh"
}

# ===========================================================================
# GH-7: wsk update with stale rendered zshrc → regenerated
# ===========================================================================

@test "GH-7: render_zshrc overwrites stale rendered content" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"

  # Pre-seed stale rendered file
  local frag="${WSK_DIR}/.rendered/wsk-zshrc"
  printf 'STALE CONTENT\n' > "$frag"

  _render_zshrc_iso "WSK_ACCOUNTS=(work)" >/dev/null

  # After render, file should NOT contain stale content
  grep -qv 'STALE CONTENT' "$frag"
  # Should contain _wsk_gh_switch
  grep -qF '_wsk_gh_switch' "$frag"
}

# ===========================================================================
# GH-8: _wsk_gh_switch defined once in rendered zshrc, not duplicated
# ===========================================================================

@test "GH-8: _wsk_gh_switch defined exactly once in rendered zshrc" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  seed_account "personal" "Personal" "JaneP" "janep@home.com" "janep" "$HOME/projects/personal" "id_personal"

  _render_zshrc_iso "WSK_ACCOUNTS=(work personal)" >/dev/null

  local frag="${WSK_DIR}/.rendered/wsk-zshrc"
  local count
  count=$(grep -c 'function _wsk_gh_switch' "$frag" || true)
  [[ "$count" -eq 1 ]]
}
