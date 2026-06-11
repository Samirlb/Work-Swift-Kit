#!/usr/bin/env bats
# patch-skills-path.bats — WU-1
# Tests for _patch_gentle_ai_commands skills-path rewrite
# (spec domain gentle-ai-sync-patches).

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run a frameworks.sh body in an isolated subprocess
# ---------------------------------------------------------------------------
_run_fw_iso() {
  local extra_setup="${1:-}"
  local call="${2:-}"

  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_STUB_BIN='$WSK_STUB_BIN'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    source '${WSK_DIR}/lib/claude.sh'
    source '${WSK_DIR}/lib/accounts.sh'
    source '${WSK_DIR}/lib/frameworks.sh'

    ${extra_setup}

    ${call}
  " 2>&1
}

setup() {
  init_test_home
  export WSK_DIR
  export WSK_TEST_HOME
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ===========================================================================
# Scenario 1: commands contain hardcoded path — patch rewrites them
# ===========================================================================

@test "commands contain hardcoded ~/.claude/skills/ path — patch rewrites to account-specific path" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  local cfg_dir="$HOME/.claude-work"
  local commands_dir="$cfg_dir/commands"
  mkdir -p "$commands_dir"

  # Create a fixture command file with hardcoded path
  cat > "$commands_dir/sdd-new.md" <<'EOF'
# SDD New

Load skill from ~/.claude/skills/sdd-new/SKILL.md before starting.
Also see ~/.claude/skills/work-unit-commits/SKILL.md.
EOF

  _run_fw_iso "" "_patch_gentle_ai_commands '$cfg_dir'"

  # After patch: no ~/.claude/skills/ should remain
  ! grep -q '~/.claude/skills/' "$commands_dir/sdd-new.md"
}

# ===========================================================================
# Scenario 2: commands contain no hardcoded path — file unchanged
# ===========================================================================

@test "commands with no hardcoded ~/.claude/skills/ — file left unchanged" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  local cfg_dir="$HOME/.claude-work"
  local commands_dir="$cfg_dir/commands"
  mkdir -p "$commands_dir"

  # File with no hardcoded path
  local original="# Clean command file
Load from the configured skills directory.
No hardcoded paths here."
  printf '%s\n' "$original" > "$commands_dir/clean.md"

  _run_fw_iso "" "_patch_gentle_ai_commands '$cfg_dir'"

  # Content should be identical
  local after
  after="$(cat "$commands_dir/clean.md")"
  [[ "$(printf '%s\n' "$original")" == "$after" ]]
}

# ===========================================================================
# Scenario 3: patch runs after every sync — _patch_gentle_ai_commands called
# ===========================================================================

@test "patch runs after every sync — _patch_gentle_ai_commands is called per account in sync flow" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  # Seed AI_FRAMEWORK=gentle-ai
  printf '\nAI_FRAMEWORK=gentle-ai\n' >> "${WSK_DIR}/accounts/work.env"

  local cfg_dir="$HOME/.claude-work"
  mkdir -p "$cfg_dir/commands"

  # File with a hardcoded path so we can observe the rewrite
  printf 'Load ~/.claude/skills/sdd-new/SKILL.md\n' > "$cfg_dir/commands/sdd-new.md"

  # Stub gentle-ai to just exit 0 (sync is a no-op in the stub)
  # The _patch_gentle_ai_commands call should still happen after sync

  _run_fw_iso "WSK_ACCOUNTS=(work)" "
    sync_gentle_ai_accounts
  "

  # The skills path should have been rewritten
  ! grep -q '~/.claude/skills/' "$cfg_dir/commands/sdd-new.md"
}
