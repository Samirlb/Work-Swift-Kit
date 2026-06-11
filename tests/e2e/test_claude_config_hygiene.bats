#!/usr/bin/env bats
# test_claude_config_hygiene.bats
# Tests for:
#   1. _gentle_ai_scoped restore-step cleanup (no ~/.claude symlink left behind)
#   2. _patch_gentle_ai_claude_md idempotency
#   3. run_fix_claude — symlink case, real-dir backup case, absent case
#   4. Doctor checks: ancestor-traversal, missing RTK.md, missing minimalism block

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run a code body in an isolated subprocess with WSK libs sourced.
# Captures combined stdout+stderr.
# ---------------------------------------------------------------------------
_run_iso() {
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

# Helper: run run_doctor in an isolated subprocess.
_run_doctor_iso() {
  local extra_setup="$1"
  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'

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
  source "${WSK_DIR}/lib/frameworks.sh"

  export WSK_OS=macos
  export WSK_PKG_MGR=brew
  WSK_ACCOUNTS=()
  export WSK_ACCOUNTS

  mkdir -p "${WSK_DIR}/accounts"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ===========================================================================
# _gentle_ai_scoped: restore step must NOT leave ~/.claude as a symlink
# ===========================================================================

@test "_gentle_ai_scoped: pre-swap symlink is removed after run (no ancestor-traversal leftover)" {
  local log_file="$WSK_TEST_HOME/scope1.log"
  : > "$log_file"

  # Create a fake account dir and a pre-existing ~/.claude symlink pointing to it.
  mkdir -p "$WSK_TEST_HOME/.claude-work"
  ln -sfn "$WSK_TEST_HOME/.claude-work" "$WSK_TEST_HOME/.claude"

  _run_iso "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew" \
    "_gentle_ai_scoped '${WSK_TEST_HOME}/.claude-work' --version"

  # ~/.claude must NOT exist as symlink after the call
  [[ ! -L "$WSK_TEST_HOME/.claude" ]]
}

@test "_gentle_ai_scoped: ~/.claude absent before run — stays absent after run" {
  local log_file="$WSK_TEST_HOME/scope2.log"
  : > "$log_file"

  mkdir -p "$WSK_TEST_HOME/.claude-work"
  # Ensure ~/.claude does not exist
  rm -rf "$WSK_TEST_HOME/.claude"

  _run_iso "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew" \
    "_gentle_ai_scoped '${WSK_TEST_HOME}/.claude-work' --version"

  [[ ! -e "$WSK_TEST_HOME/.claude" ]]
  [[ ! -L "$WSK_TEST_HOME/.claude" ]]
}

@test "_gentle_ai_scoped: pre-swap real directory (non-WSK) is restored intact after run" {
  local log_file="$WSK_TEST_HOME/scope3.log"
  : > "$log_file"

  mkdir -p "$WSK_TEST_HOME/.claude-work"
  # A real non-WSK ~/.claude directory with a sentinel file
  mkdir -p "$WSK_TEST_HOME/.claude"
  echo "user-data" > "$WSK_TEST_HOME/.claude/sentinel.txt"

  _run_iso "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew" \
    "_gentle_ai_scoped '${WSK_TEST_HOME}/.claude-work' --version"

  # The real directory must be restored with its content
  [[ -f "$WSK_TEST_HOME/.claude/sentinel.txt" ]]
  grep -q "user-data" "$WSK_TEST_HOME/.claude/sentinel.txt"
}

# ===========================================================================
# _patch_gentle_ai_claude_md: idempotency
# ===========================================================================

@test "_patch_gentle_ai_claude_md: appends minimalism block when absent" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  mkdir -p "$cfg_dir"
  echo "# base content" > "$cfg_dir/CLAUDE.md"

  _patch_gentle_ai_claude_md "$cfg_dir"

  grep -qF '<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:BEGIN -->' "$cfg_dir/CLAUDE.md"
  grep -qF '<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:END -->' "$cfg_dir/CLAUDE.md"
}

@test "_patch_gentle_ai_claude_md: running twice produces exactly one minimalism block" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  mkdir -p "$cfg_dir"
  echo "# base content" > "$cfg_dir/CLAUDE.md"

  _patch_gentle_ai_claude_md "$cfg_dir"
  _patch_gentle_ai_claude_md "$cfg_dir"

  local begin_count
  begin_count="$(grep -cF '<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:BEGIN -->' "$cfg_dir/CLAUDE.md" || true)"
  [ "$begin_count" -eq 1 ]

  local end_count
  end_count="$(grep -cF '<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:END -->' "$cfg_dir/CLAUDE.md" || true)"
  [ "$end_count" -eq 1 ]
}

@test "_patch_gentle_ai_claude_md: replaces existing block content on second run" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  mkdir -p "$cfg_dir"
  # Pre-seed with a stale minimalism block containing old text
  cat > "$cfg_dir/CLAUDE.md" <<'EOF'
# header
<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:BEGIN -->
OLD STALE CONTENT
<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:END -->
EOF

  _patch_gentle_ai_claude_md "$cfg_dir"

  # Old text must be gone
  ! grep -q 'OLD STALE CONTENT' "$cfg_dir/CLAUDE.md"
  # Current content must be present
  grep -qF 'Sub-Agent Context Minimalism' "$cfg_dir/CLAUDE.md"
}

@test "_patch_gentle_ai_claude_md: appends @RTK.md when RTK.md present and import absent" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  mkdir -p "$cfg_dir"
  echo "# base content" > "$cfg_dir/CLAUDE.md"
  echo "rtk content" > "$cfg_dir/RTK.md"

  _patch_gentle_ai_claude_md "$cfg_dir"

  grep -qF '@RTK.md' "$cfg_dir/CLAUDE.md"
}

@test "_patch_gentle_ai_claude_md: @RTK.md not duplicated on second run" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  mkdir -p "$cfg_dir"
  echo "# base content" > "$cfg_dir/CLAUDE.md"
  echo "rtk content" > "$cfg_dir/RTK.md"

  _patch_gentle_ai_claude_md "$cfg_dir"
  _patch_gentle_ai_claude_md "$cfg_dir"

  local rtk_count
  rtk_count="$(grep -cF '@RTK.md' "$cfg_dir/CLAUDE.md" || true)"
  [ "$rtk_count" -eq 1 ]
}

@test "_patch_gentle_ai_claude_md: no @RTK.md appended when RTK.md missing from cfg_dir" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  mkdir -p "$cfg_dir"
  echo "# base content" > "$cfg_dir/CLAUDE.md"
  # RTK.md intentionally absent

  _patch_gentle_ai_claude_md "$cfg_dir"

  ! grep -qF '@RTK.md' "$cfg_dir/CLAUDE.md"
}

@test "_patch_gentle_ai_claude_md: no-op when CLAUDE.md absent" {
  local cfg_dir="$WSK_TEST_HOME/.claude-work"
  mkdir -p "$cfg_dir"
  # No CLAUDE.md

  # Should not error
  _patch_gentle_ai_claude_md "$cfg_dir"
  [[ ! -f "$cfg_dir/CLAUDE.md" ]]
}

# ===========================================================================
# run_fix_claude
# ===========================================================================

@test "run_fix_claude: symlink case — removes ~/.claude symlink, prints what it pointed to" {
  local log_file="$WSK_TEST_HOME/fix1.log"
  : > "$log_file"
  seed_account "work" "Work" "Test" "t@t.com" "t" "$WSK_TEST_HOME/Work" "id_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$WSK_TEST_HOME/.claude-work"
  echo "# CLAUDE" > "$WSK_TEST_HOME/.claude-work/CLAUDE.md"
  ln -sfn "$WSK_TEST_HOME/.claude-work" "$WSK_TEST_HOME/.claude"

  local output
  output="$(_run_iso "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_ACCOUNTS=(work)" \
    "run_fix_claude")"

  # Symlink must be gone
  [[ ! -L "$WSK_TEST_HOME/.claude" ]]
  # Output must mention the removal
  echo "$output" | grep -qi "removed symlink\|\.claude"
}

@test "run_fix_claude: real-dir case — moves ~/.claude to timestamped backup" {
  local log_file="$WSK_TEST_HOME/fix2.log"
  : > "$log_file"
  seed_account "work" "Work" "Test" "t@t.com" "t" "$WSK_TEST_HOME/Work" "id_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$WSK_TEST_HOME/.claude-work"
  echo "# CLAUDE" > "$WSK_TEST_HOME/.claude-work/CLAUDE.md"
  # Real directory (not a symlink)
  mkdir -p "$WSK_TEST_HOME/.claude"
  echo "old-data" > "$WSK_TEST_HOME/.claude/old.txt"

  local output
  output="$(_run_iso "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_ACCOUNTS=(work)" \
    "run_fix_claude")"

  # Real dir must be gone from its original location (strict: path must not exist at all)
  [[ ! -d "$WSK_TEST_HOME/.claude" ]]
  # A backup directory must exist and contain the original file
  local backup_dir
  backup_dir="$(find "$WSK_TEST_HOME" -maxdepth 1 -name '.claude.wsk-backup-*' -type d | head -1)"
  [[ -n "$backup_dir" ]]
  [[ -f "$backup_dir/old.txt" ]]
  # A backup must exist
  local backup_count
  backup_count="$(find "$WSK_TEST_HOME" -maxdepth 1 -name '.claude.wsk-backup-*' -type d | wc -l | tr -d ' ')"
  [ "$backup_count" -ge 1 ]
  # Output must mention the backup path
  echo "$output" | grep -qi "wsk-backup\|moved"
}

@test "run_fix_claude: absent case — reports already clean" {
  local log_file="$WSK_TEST_HOME/fix3.log"
  : > "$log_file"
  seed_account "work" "Work" "Test" "t@t.com" "t" "$WSK_TEST_HOME/Work" "id_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$WSK_TEST_HOME/.claude-work"
  echo "# CLAUDE" > "$WSK_TEST_HOME/.claude-work/CLAUDE.md"
  # ~/.claude intentionally absent

  local output
  output="$(_run_iso "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_ACCOUNTS=(work)" \
    "run_fix_claude")"

  echo "$output" | grep -qi "already absent\|nothing to do\|already clean"
}

@test "run_fix_claude: idempotent — second run is safe when ~/.claude already absent" {
  local log_file="$WSK_TEST_HOME/fix4.log"
  : > "$log_file"
  seed_account "work" "Work" "Test" "t@t.com" "t" "$WSK_TEST_HOME/Work" "id_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$WSK_TEST_HOME/.claude-work"
  echo "# CLAUDE" > "$WSK_TEST_HOME/.claude-work/CLAUDE.md"

  # First run (nothing to remove)
  _run_iso "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_ACCOUNTS=(work)" \
    "run_fix_claude" >/dev/null

  # Second run must also exit cleanly
  local rc=0
  _run_iso "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_ACCOUNTS=(work)" \
    "run_fix_claude" >/dev/null || rc=$?

  [ "$rc" -eq 0 ]
}

@test "run_fix_claude: copies RTK.md from one account dir to another that lacks it" {
  local log_file="$WSK_TEST_HOME/fix5.log"
  : > "$log_file"
  seed_account "work" "Work" "Test" "t@t.com" "t" "$WSK_TEST_HOME/Work" "id_work"
  seed_account "personal" "Personal" "Test" "t@p.com" "tp" "$WSK_TEST_HOME/Personal" "id_personal"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/work.env"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/personal.env"

  mkdir -p "$WSK_TEST_HOME/.claude-work"
  echo "# CLAUDE" > "$WSK_TEST_HOME/.claude-work/CLAUDE.md"
  echo "rtk content" > "$WSK_TEST_HOME/.claude-work/RTK.md"

  mkdir -p "$WSK_TEST_HOME/.claude-personal"
  echo "# CLAUDE" > "$WSK_TEST_HOME/.claude-personal/CLAUDE.md"
  # personal has no RTK.md initially

  _run_iso "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_ACCOUNTS=(work personal)" \
    "run_fix_claude" >/dev/null

  [[ -f "$WSK_TEST_HOME/.claude-personal/RTK.md" ]]
}

@test "run_fix_claude: patches CLAUDE.md with minimalism block for each gentle-ai account" {
  local log_file="$WSK_TEST_HOME/fix6.log"
  : > "$log_file"
  seed_account "work" "Work" "Test" "t@t.com" "t" "$WSK_TEST_HOME/Work" "id_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$WSK_TEST_HOME/.claude-work"
  echo "# CLAUDE" > "$WSK_TEST_HOME/.claude-work/CLAUDE.md"

  _run_iso "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew WSK_ACCOUNTS=(work)" \
    "run_fix_claude" >/dev/null

  grep -qF '<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:BEGIN -->' "$WSK_TEST_HOME/.claude-work/CLAUDE.md"
}

# ===========================================================================
# Doctor: ancestor-traversal check
# ===========================================================================

@test "Doctor: check_fail when ~/.claude exists alongside ~/.claude-{acct}" {
  seed_account "work" "Work" "Jane" "j@w.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  mkdir -p "$HOME/.claude-work"
  # Simulate the leftover symlink situation
  ln -sfn "$HOME/.claude-work" "$HOME/.claude"

  local out
  out=$(_run_doctor_iso "
    load_accounts() { WSK_ACCOUNTS=(work); export WSK_ACCOUNTS; }
    ui_section()  { true; }
    ui_subhead()  { printf '\n%s\n' \"\$1\"; }
    gh()          { return 1; }
    export WSK_OS=macos WSK_PKG_MGR=brew
  ")

  echo "$out" | grep -qi "ancestor-traversal\|double-load\|wsk fix-claude"
}

@test "Doctor: check_pass for claude config hygiene when ~/.claude absent" {
  seed_account "work" "Work" "Jane" "j@w.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  mkdir -p "$HOME/.claude-work"
  # No ~/.claude

  local out
  out=$(_run_doctor_iso "
    load_accounts() { WSK_ACCOUNTS=(work); export WSK_ACCOUNTS; }
    ui_section()  { true; }
    ui_subhead()  { printf '\n%s\n' \"\$1\"; }
    gh()          { return 1; }
    export WSK_OS=macos WSK_PKG_MGR=brew
  ")

  echo "$out" | grep -qi "ancestor-traversal risk\|no ancestor"
}

# ===========================================================================
# Doctor: RTK.md reference without file
# ===========================================================================

@test "Doctor: check_warn when CLAUDE.md references @RTK.md but RTK.md absent" {
  seed_account "work" "Work" "Jane" "j@w.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$HOME/.claude-work"
  printf '# CLAUDE\n@RTK.md\n' > "$HOME/.claude-work/CLAUDE.md"
  # RTK.md intentionally absent

  local out
  out=$(_run_doctor_iso "
    load_accounts() { WSK_ACCOUNTS=(work); export WSK_ACCOUNTS; }
    ui_section()  { true; }
    ui_subhead()  { printf '\n%s\n' \"\$1\"; }
    gh()          { return 1; }
    export WSK_OS=macos WSK_PKG_MGR=brew
  ")

  echo "$out" | grep -qi "RTK.md.*missing\|missing.*RTK.md"
}

# ===========================================================================
# Doctor: minimalism block markers missing
# ===========================================================================

@test "Doctor: check_warn when CLAUDE.md missing minimalism block markers" {
  seed_account "work" "Work" "Jane" "j@w.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$HOME/.claude-work"
  # CLAUDE.md without the minimalism markers
  echo "# CLAUDE" > "$HOME/.claude-work/CLAUDE.md"

  local out
  out=$(_run_doctor_iso "
    load_accounts() { WSK_ACCOUNTS=(work); export WSK_ACCOUNTS; }
    ui_section()  { true; }
    ui_subhead()  { printf '\n%s\n' \"\$1\"; }
    gh()          { return 1; }
    export WSK_OS=macos WSK_PKG_MGR=brew
  ")

  echo "$out" | grep -qi "minimalism block\|wsk fix-claude"
}

@test "Doctor: no minimalism-block warn when block present in CLAUDE.md" {
  seed_account "work" "Work" "Jane" "j@w.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_DIR}/accounts/work.env"
  mkdir -p "$HOME/.claude-work"
  cat > "$HOME/.claude-work/CLAUDE.md" <<'EOF'
# CLAUDE
<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:BEGIN -->
## Sub-Agent Context Minimalism (MANDATORY)
content here
<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:END -->
EOF

  local out
  out=$(_run_doctor_iso "
    load_accounts() { WSK_ACCOUNTS=(work); export WSK_ACCOUNTS; }
    ui_section()  { true; }
    ui_subhead()  { printf '\n%s\n' \"\$1\"; }
    gh()          { return 1; }
    export WSK_OS=macos WSK_PKG_MGR=brew
  ")

  # No minimalism warning should be present
  ! echo "$out" | grep -qi "minimalism block.*missing\|missing.*minimalism"
}
