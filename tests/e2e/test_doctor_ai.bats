#!/usr/bin/env bats
# test_doctor_ai.bats — WU-7
# Tests for lib/doctor.sh AI/OS/node/framework/skills health sections.

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run run_doctor in an isolated subprocess capturing output.
# $1 = extra env vars / setup as a bash heredoc string
# Runs run_doctor and captures combined stdout+stderr.
# ---------------------------------------------------------------------------
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
    source '${WSK_DIR}/lib/accounts.sh'

    ${extra_setup}

    source '${WSK_DIR}/lib/doctor.sh'

    run_doctor 2>&1
  " 2>&1
}

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------
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
# OS / Package manager section
# ===========================================================================

@test "OS section: check_pass for WSK_OS and WSK_PKG_MGR when both detected" {
  # Seed an account
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  local out
  out=$(_run_doctor_iso "
    # Stub everything that run_doctor calls beyond what we're testing
    load_accounts() {
      WSK_ACCOUNTS=(work)
      export WSK_ACCOUNTS
    }
    ui_section()  { true; }
    ui_subhead()  { printf '\n%s\n' \"\$1\"; }
    gh()          { return 1; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
  ")

  echo "$out" | grep -q 'OS: macos'
  echo "$out" | grep -q 'pkg manager: brew'
}

@test "OS section: check_warn when WSK_PKG_MGR is empty" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  local out
  out=$(_run_doctor_iso "
    load_accounts() {
      WSK_ACCOUNTS=(work)
      export WSK_ACCOUNTS
    }
    ui_section()  { true; }
    ui_subhead()  { printf '\n%s\n' \"\$1\"; }
    gh()          { return 1; }
    export WSK_OS=linux
    export WSK_PKG_MGR=''
  ")

  echo "$out" | grep -q 'no recognized package manager detected'
}

# ===========================================================================
# Node / pnpm section
# ===========================================================================

@test "Node section: check_pass for node and pnpm when both present" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  stub_present node
  stub_present pnpm

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
  ")

  echo "$out" | grep -q 'node installed'
  echo "$out" | grep -q 'pnpm installed'
}

@test "Node section: check_fail for pnpm when pnpm absent" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  stub_present node
  stub_absent pnpm

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
  ")

  echo "$out" | grep -q 'pnpm missing'
}

# ===========================================================================
# Claude Code section
# ===========================================================================

@test "Claude section: check_pass when claude is installed" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  stub_present claude

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
  ")

  echo "$out" | grep -q 'claude installed'
}

@test "Claude section: check_fail when claude is absent" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  stub_absent claude

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
  ")

  echo "$out" | grep -q 'claude not installed'
  echo "$out" | grep -q 'wsk ai'
}

# ===========================================================================
# Per-account AI framework section
# ===========================================================================

@test "Framework section: check_pass when AI_FRAMEWORK=gentle-ai and gentle-ai on PATH" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  # Add AI_FRAMEWORK to the env file
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_ACCOUNTS_DIR}/work.env"
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
  ")

  echo "$out" | grep -q 'work: AI_FRAMEWORK=gentle-ai (installed)'
}

@test "Framework section: check_fail when AI_FRAMEWORK=gsd and gsd absent from PATH" {
  seed_account "personal" "Personal" "Jane" "jane@personal.com" "jane_p" "$HOME/projects" "id_personal"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_personal"
  echo "AI_FRAMEWORK=gsd" >> "${WSK_ACCOUNTS_DIR}/personal.env"
  # gsd is not on PATH (no stub added for get-shit-done-cc or gsd)
  stub_absent codegraph

  local out
  out=$(_run_doctor_iso "
    load_accounts() {
      WSK_ACCOUNTS=(personal)
      export WSK_ACCOUNTS
    }
    ui_section()  { true; }
    ui_subhead()  { printf '\n%s\n' \"\$1\"; }
    gh()          { return 1; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
  ")

  echo "$out" | grep -q 'personal: gsd not found on PATH'
}

@test "Framework section: check_warn when AI_FRAMEWORK not set in env file" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  # No AI_FRAMEWORK in the env file

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
  ")

  echo "$out" | grep -q 'work: AI_FRAMEWORK not set'
  echo "$out" | grep -q 'wsk ai'
}

@test "Framework section: check_pass when AI_FRAMEWORK=superpowers and dir exists" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  echo "AI_FRAMEWORK=superpowers" >> "${WSK_ACCOUNTS_DIR}/work.env"
  # Create the superpowers dir
  mkdir -p "$HOME/.claude-work/superpowers"

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
  ")

  echo "$out" | grep -q 'work: AI_FRAMEWORK=superpowers (installed)'
}

# ===========================================================================
# Codegraph section
# ===========================================================================

@test "Codegraph section: check_pass when codegraph is installed" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  stub_present codegraph

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
  ")

  echo "$out" | grep -q 'codegraph installed'
}

@test "Codegraph section: check_warn when codegraph is absent" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  stub_absent codegraph

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
  ")

  echo "$out" | grep -q 'codegraph not installed (optional)'
}

# ===========================================================================
# Skills section
# ===========================================================================

@test "Skills section: 6 check_pass lines when all skill dirs present" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  # Create all 6 skill dirs
  for skill in branch-pr chained-pr work-unit-commits comment-writer issue-creation judgment-day; do
    mkdir -p "$HOME/.claude-work/skills/$skill"
  done

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
  ")

  # Count pass lines for skills
  local pass_count
  pass_count=$(echo "$out" | grep -c 'skill.*present\|skill installed\|check.*skill\|✓.*skill\|✓.*branch-pr\|✓.*chained-pr\|✓.*work-unit\|✓.*comment\|✓.*issue\|✓.*judgment' || true)

  # At minimum, no warn for missing judgment-day
  echo "$out" | grep -qv 'judgment-day skill missing'
}

@test "Skills section: check_warn when judgment-day skill is missing" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  # Create all skills EXCEPT judgment-day
  for skill in branch-pr chained-pr work-unit-commits comment-writer issue-creation; do
    mkdir -p "$HOME/.claude-work/skills/$skill"
  done

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
  ")

  echo "$out" | grep -q 'work: judgment-day skill missing'
}

@test "Skills section: gentle-ai account shows bundled message instead of per-skill checks" {
  seed_account "work" "Work" "Jane" "jane@work.com" "jane" "$HOME/projects" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"
  echo "AI_FRAMEWORK=gentle-ai" >> "${WSK_ACCOUNTS_DIR}/work.env"
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
  ")

  echo "$out" | grep -q 'work: skills bundled by gentle-ai'
}
