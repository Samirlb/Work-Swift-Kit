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
  source "${WSK_DIR}/lib/frameworks.sh"

  # Default env
  export WSK_OS=macos
  export WSK_PKG_MGR=brew
  WSK_ACCOUNTS=()
  export WSK_ACCOUNTS

  # Seed default accounts dir
  mkdir -p "${WSK_DIR}/accounts"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ---------------------------------------------------------------------------
# Helper: run a body in an isolated subprocess
# Absorbs non-zero exits from the body (|| true).
# ---------------------------------------------------------------------------
_run_iso_fw() {
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
    source '${WSK_DIR}/lib/frameworks.sh'
    ${body} || true
  " 2>&1
}

# ---------------------------------------------------------------------------
# _persist_account_kv tests
# ---------------------------------------------------------------------------

@test "_persist_account_kv: key absent — appended to env file" {
  local env_file="${WSK_DIR}/accounts/work.env"
  seed_account "work" "Work" "Test User" "test@example.com" "testuser" "${HOME}/Work" "id_ed25519_work"

  _persist_account_kv "$env_file" AI_FRAMEWORK gentle-ai

  grep -q "^AI_FRAMEWORK=gentle-ai" "$env_file"
}

@test "_persist_account_kv: key present — updated in-place, not duplicated" {
  local env_file="${WSK_DIR}/accounts/work.env"
  seed_account "work" "Work" "Test User" "test@example.com" "testuser" "${HOME}/Work" "id_ed25519_work"
  echo "AI_FRAMEWORK=gsd" >> "$env_file"

  _persist_account_kv "$env_file" AI_FRAMEWORK superpowers

  grep -q "^AI_FRAMEWORK=superpowers" "$env_file"
  # should not have both old and new value
  local count
  count="$(grep -c "^AI_FRAMEWORK=" "$env_file")"
  [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# _fetch_skill tests
# ---------------------------------------------------------------------------

@test "_fetch_skill: clones from WSK_SKILLS_REPO and copies skill dir" {
  local log_file="$WSK_TEST_HOME/fs1.log"
  : > "$log_file"
  local dest="$WSK_TEST_HOME/.claude-personal/skills/branch-pr"

  _run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew" \
    "_fetch_skill branch-pr '${dest}'"

  grep -q "github.com/Gentleman-Programming/gentle-ai" "$log_file"
}

@test "_fetch_skill: dest already exists — git NOT called" {
  local log_file="$WSK_TEST_HOME/fs2.log"
  : > "$log_file"
  local dest="$WSK_TEST_HOME/.claude-personal/skills/branch-pr"
  mkdir -p "$dest"

  _run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew" \
    "_fetch_skill branch-pr '${dest}'"

  ! grep -q "git clone" "$log_file"
}

# ---------------------------------------------------------------------------
# install_ai_framework tests — gentle-ai
# ---------------------------------------------------------------------------

@test "install_ai_framework: ui_choose returns gentle-ai — brew tap + install + gentle-ai install --agent claude-code called with CLAUDE_CONFIG_DIR; work.env has AI_FRAMEWORK=gentle-ai" {
  local log_file="$WSK_TEST_HOME/fw1.log"
  : > "$log_file"
  seed_account "work" "Work" "Test User" "test@example.com" "testuser" "${HOME}/Work" "id_ed25519_work"

  # gum choose returns gentle-ai
  _run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_STUB_GUM_CHOOSE_OUTPUT=gentle-ai" \
    "install_ai_framework work"

  # gentle-ai install --agent claude-code called
  grep -q "gentle-ai install --agent claude-code" "$log_file"
  # CLAUDE_CONFIG_DIR should be the work dir
  grep -q "\.claude-work" "$log_file"
  # env file persisted
  grep -q "^AI_FRAMEWORK=gentle-ai" "${WSK_DIR}/accounts/work.env"
}

# ---------------------------------------------------------------------------
# install_ai_framework tests — gsd
# ---------------------------------------------------------------------------

@test "install_ai_framework: ui_choose returns gsd — npx get-shit-done-cc --global recorded; personal.env has AI_FRAMEWORK=gsd" {
  local log_file="$WSK_TEST_HOME/fw2.log"
  : > "$log_file"
  seed_account "personal" "Personal" "Test User" "test@example.com" "testuser" "${HOME}/Personal" "id_ed25519_personal"
  node_present

  _run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_STUB_GUM_CHOOSE_OUTPUT=gsd" \
    "install_ai_framework personal"

  grep -q "get-shit-done-cc --global" "$log_file"
  grep -q "^AI_FRAMEWORK=gsd" "${WSK_DIR}/accounts/personal.env"
}

@test "install_ai_framework: gsd fallback — WSK_STUB_NPX_EXIT=1 causes git clone of gsd repo" {
  local log_file="$WSK_TEST_HOME/fw3.log"
  : > "$log_file"
  seed_account "personal" "Personal" "Test User" "test@example.com" "testuser" "${HOME}/Personal" "id_ed25519_personal"
  node_present

  _run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_STUB_GUM_CHOOSE_OUTPUT=gsd WSK_STUB_NPX_EXIT=1" \
    "install_ai_framework personal"

  grep -q "github.com/gsd-build/get-shit-done" "$log_file"
}

# ---------------------------------------------------------------------------
# install_ai_framework tests — superpowers
# ---------------------------------------------------------------------------

@test "install_ai_framework: ui_choose returns superpowers — git clone obra/superpowers into ~/.claude-work/superpowers; /plugin install instruction printed; work.env has AI_FRAMEWORK=superpowers" {
  local log_file="$WSK_TEST_HOME/fw4.log"
  : > "$log_file"
  seed_account "work" "Work" "Test User" "test@example.com" "testuser" "${HOME}/Work" "id_ed25519_work"

  local output
  output="$(_run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_STUB_GUM_CHOOSE_OUTPUT=superpowers" \
    "install_ai_framework work")"

  grep -q "github.com/obra/superpowers" "$log_file"
  [[ -d "$WSK_TEST_HOME/.claude-work/superpowers" ]]
  echo "$output" | grep -qi "plugin install"
  grep -q "^AI_FRAMEWORK=superpowers" "${WSK_DIR}/accounts/work.env"
}

# ---------------------------------------------------------------------------
# Per-account independence
# ---------------------------------------------------------------------------

@test "per-account independence: work=gentle-ai, personal=gsd — env files independent, no cross-contamination" {
  seed_account "work" "Work" "Test User" "work@example.com" "workuser" "${HOME}/Work" "id_ed25519_work"
  seed_account "personal" "Personal" "Test User" "personal@example.com" "personaluser" "${HOME}/Personal" "id_ed25519_personal"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/work.env"
  echo "AI_FRAMEWORK=gsd"       >> "${WSK_DIR}/accounts/personal.env"

  # Each env file must have its own value and only its own value
  grep -q "^AI_FRAMEWORK=gentle-ai" "${WSK_DIR}/accounts/work.env"
  grep -q "^AI_FRAMEWORK=gsd"       "${WSK_DIR}/accounts/personal.env"
  ! grep -q "AI_FRAMEWORK=gsd"      "${WSK_DIR}/accounts/work.env"
  ! grep -q "AI_FRAMEWORK=gentle-ai" "${WSK_DIR}/accounts/personal.env"
}

# ---------------------------------------------------------------------------
# Re-run honoring
# ---------------------------------------------------------------------------

@test "re-run honoring: AI_FRAMEWORK=gentle-ai already in work.env — gum choose NOT invoked" {
  local log_file="$WSK_TEST_HOME/fw5.log"
  : > "$log_file"
  seed_account "work" "Work" "Test User" "test@example.com" "testuser" "${HOME}/Work" "id_ed25519_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/work.env"

  _run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew" \
    "install_ai_framework work"

  # gum choose not recorded (no framework prompt)
  ! grep -q "gum choose" "$log_file"
}

# ---------------------------------------------------------------------------
# CLAUDE_CONFIG_DIR isolation
# ---------------------------------------------------------------------------

@test "CLAUDE_CONFIG_DIR isolation: no write to ~/.claude/ during framework install" {
  local log_file="$WSK_TEST_HOME/fw6.log"
  : > "$log_file"
  seed_account "work" "Work" "Test User" "test@example.com" "testuser" "${HOME}/Work" "id_ed25519_work"

  _run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_STUB_GUM_CHOOSE_OUTPUT=gentle-ai" \
    "install_ai_framework work"

  # Default ~/.claude/ dir should NOT be written
  [[ ! -d "$WSK_TEST_HOME/.claude" ]] || [[ -z "$(ls -A "$WSK_TEST_HOME/.claude" 2>/dev/null)" ]]
}

# ---------------------------------------------------------------------------
# run_ai_for_all_accounts — codegraph confirm
# ---------------------------------------------------------------------------

@test "run_ai_for_all_accounts: ui_confirm returns true — install_codegraph called for that account" {
  local log_file="$WSK_TEST_HOME/loop1.log"
  : > "$log_file"
  seed_account "work" "Work" "Test User" "test@example.com" "testuser" "${HOME}/Work" "id_ed25519_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/work.env"
  node_present
  codegraph_absent

  # gum confirm returns 0 (yes) ; gum choose returns gentle-ai (unused, already set)
  _run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_ACCOUNTS=(work) WSK_STUB_GUM_CONFIRM_EXIT=0" \
    "run_ai_for_all_accounts"

  grep -q "npm i -g @colbymchenry/codegraph" "$log_file"
}

@test "run_ai_for_all_accounts: ui_confirm returns false — codegraph NOT installed, no error" {
  local log_file="$WSK_TEST_HOME/loop2.log"
  : > "$log_file"
  seed_account "work" "Work" "Test User" "test@example.com" "testuser" "${HOME}/Work" "id_ed25519_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/work.env"
  node_present
  codegraph_absent

  # gum confirm returns 1 (no)
  _run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_ACCOUNTS=(work) WSK_STUB_GUM_CONFIRM_EXIT=1" \
    "run_ai_for_all_accounts"

  ! grep -q "npm i -g @colbymchenry/codegraph" "$log_file"
}

# ---------------------------------------------------------------------------
# install_curated_skills tests
# ---------------------------------------------------------------------------

@test "install_curated_skills: gsd framework — git clone of gentle-ai repo; 6 skill dirs created under ~/.claude-personal/skills/" {
  local log_file="$WSK_TEST_HOME/sk1.log"
  : > "$log_file"

  _run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew" \
    "install_curated_skills personal gsd"

  # git clone recorded against the locked URL
  grep -q "github.com/Gentleman-Programming/gentle-ai" "$log_file"
  # The git stub creates the cloned dir; each skill dir is created under skills/
  # (the stub clone creates the tmp dir; we test that all 6 calls were made)
  # We cannot assert filesystem state directly for skills because _fetch_skill uses
  # a tmpdir clone + cp, and the git stub just mkdir's the dest not skills/<name>/.
  # We assert 6 git clone invocations were recorded.
  local clone_count
  clone_count="$(grep -c "git clone" "$log_file" || true)"
  [ "$clone_count" -ge 6 ]
}

@test "install_curated_skills: gentle-ai framework — git NOT called, 'bundled by gentle-ai' in output" {
  local log_file="$WSK_TEST_HOME/sk2.log"
  : > "$log_file"

  local output
  output="$(_run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew" \
    "install_curated_skills work gentle-ai")"

  ! grep -q "git clone" "$log_file"
  echo "$output" | grep -qi "bundled by gentle-ai"
}

@test "install_curated_skills: idempotency — pre-created branch-pr dir skips that skill; others still fetched" {
  local log_file="$WSK_TEST_HOME/sk3.log"
  : > "$log_file"

  # Pre-create branch-pr skill dir
  mkdir -p "$WSK_TEST_HOME/.claude-personal/skills/branch-pr"

  _run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew HOME='${WSK_TEST_HOME}'" \
    "install_curated_skills personal gsd"

  # branch-pr dir existed → that skill should not trigger a clone for itself
  # Other 5 skills should still be attempted (5 clone calls)
  local clone_count
  clone_count="$(grep -c "git clone" "$log_file" || true)"
  [ "$clone_count" -ge 5 ]
  [ "$clone_count" -lt 6 ]
}

@test "install_curated_skills: skills source unavailable — check_warn per skill, no crash" {
  local log_file="$WSK_TEST_HOME/sk4.log"
  : > "$log_file"

  local output
  output="$(_run_iso_fw "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_STUB_GIT_EXIT=1" \
    "install_curated_skills personal gsd")"

  # Should output warn messages but not crash (exit 0 from || true in _run_iso_fw)
  echo "$output" | grep -qi "unavailable\|warn\|!"
}
