#!/usr/bin/env bats
# fix-git.bats — WU-4
# Tests for lib/fix-git.sh: run_fix_git dry-run and --apply flows.

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run run_fix_git in an isolated subprocess
# $1 = extra env/setup
# $2 = function call / args
# ---------------------------------------------------------------------------
_run_fix_git_iso() {
  local extra_setup="${1:-}"
  local call="${2:-run_fix_git}"
  # Snapshot confirm exit code before subshell (setup.bash exports gum() fn
  # which ignores WSK_STUB_GUM_CONFIRM_EXIT — we override it inside the subshell)
  local _confirm_exit="${WSK_STUB_GUM_CONFIRM_EXIT:-1}"

  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    # Unset the exported gum() shell function so the PATH shim is used.
    unset -f gum 2>/dev/null || true
    # Override ui_confirm directly to honor the env-var-controlled exit code.
    ui_confirm() { return ${_confirm_exit}; }

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/preflight.sh'
    source '${WSK_DIR}/lib/doctor.sh'
    source '${WSK_DIR}/lib/fix-git.sh'

    # Re-apply the confirm override after sourcing (ui.sh may redefine it).
    ui_confirm() { return ${_confirm_exit}; }

    ${extra_setup}

    ${call} 2>&1
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
# FG-1: Dry-run default — prints planned rewrites, no writes
# ===========================================================================

@test "FG-1: dry-run default — prints planned rewrites, no git writes" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  local repo_dir="$HOME/projects/work/my-repo"
  mkdir -p "$repo_dir/.git"
  printf 'ref: refs/heads/main\n' > "$repo_dir/.git/HEAD"

  # Stub git to return https remote
  local git_stub="$WSK_STUB_BIN/git"
  cat > "$git_stub" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == *"remote get-url origin"* ]]; then
  echo "https://github.com/org/my-repo.git"
fi
exit 0
STUB
  chmod +x "$git_stub"

  local out
  out=$(_run_fix_git_iso "
    WSK_ACCOUNTS=(work)
    ui_section() { true; }
    ui_subhead() { true; }
  " "run_fix_git")

  # Should print dry-run output
  echo "$out" | grep -q 'dry-run\|would rewrite'
  # Should NOT call git remote set-url
  grep -v 'remote get-url' "$WSK_STUB_LOG" | grep -qv 'remote set-url' || true
  assert_stub_not_called "remote set-url"
}

# ===========================================================================
# FG-2: --apply with confirm → rewrites origin
# ===========================================================================

@test "FG-2: --apply with user confirm — rewrites origin to SSH alias" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  local repo_dir="$HOME/projects/work/my-repo"
  mkdir -p "$repo_dir/.git"
  printf 'ref: refs/heads/main\n' > "$repo_dir/.git/HEAD"

  # git returns https remote
  local git_stub="$WSK_STUB_BIN/git"
  cat > "$git_stub" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == *"remote get-url origin"* ]]; then
  echo "https://github.com/org/my-repo.git"
fi
exit 0
STUB
  chmod +x "$git_stub"

  # gum confirm returns 0 (user accepts)
  export WSK_STUB_GUM_CONFIRM_EXIT=0

  local out
  out=$(_run_fix_git_iso "
    WSK_ACCOUNTS=(work)
    ui_section() { true; }
    ui_subhead() { true; }
  " "run_fix_git --apply")

  assert_stub_called "remote set-url"
  echo "$out" | grep -q 'git@github-work'
}

# ===========================================================================
# FG-3: --apply with skip → leaves origin unchanged
# ===========================================================================

@test "FG-3: --apply with user skip — leaves origin unchanged" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  local repo_dir="$HOME/projects/work/my-repo"
  mkdir -p "$repo_dir/.git"
  printf 'ref: refs/heads/main\n' > "$repo_dir/.git/HEAD"

  local git_stub="$WSK_STUB_BIN/git"
  cat > "$git_stub" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == *"remote get-url origin"* ]]; then
  echo "https://github.com/org/my-repo.git"
fi
exit 0
STUB
  chmod +x "$git_stub"

  # gum confirm returns 1 (user declines)
  export WSK_STUB_GUM_CONFIRM_EXIT=1

  local out
  out=$(_run_fix_git_iso "
    WSK_ACCOUNTS=(work)
    ui_section() { true; }
    ui_subhead() { true; }
  " "run_fix_git --apply")

  assert_stub_not_called "remote set-url"
}

# ===========================================================================
# FG-4: https → SSH rewrite pattern
# ===========================================================================

@test "FG-4: https URL rewrites to git@github-{acct}:org/repo.git" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  local repo_dir="$HOME/projects/work/my-repo"
  mkdir -p "$repo_dir/.git"
  printf 'ref: refs/heads/main\n' > "$repo_dir/.git/HEAD"

  local git_stub="$WSK_STUB_BIN/git"
  cat > "$git_stub" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == *"remote get-url origin"* ]]; then
  echo "https://github.com/org/my-repo.git"
fi
exit 0
STUB
  chmod +x "$git_stub"
  export WSK_STUB_GUM_CONFIRM_EXIT=0

  _run_fix_git_iso "
    WSK_ACCOUNTS=(work)
    ui_section() { true; }
    ui_subhead() { true; }
  " "run_fix_git --apply" >/dev/null

  # The set-url call should contain the correct SSH alias
  grep -q "remote set-url origin git@github-work:org/my-repo.git" "$WSK_STUB_LOG"
}

# ===========================================================================
# FG-5: git@github.com normalization
# ===========================================================================

@test "FG-5: git@github.com remote normalized to git@github-{acct}:" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  local repo_dir="$HOME/projects/work/my-repo"
  mkdir -p "$repo_dir/.git"
  printf 'ref: refs/heads/main\n' > "$repo_dir/.git/HEAD"

  local git_stub="$WSK_STUB_BIN/git"
  cat > "$git_stub" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == *"remote get-url origin"* ]]; then
  echo "git@github.com:org/my-repo.git"
fi
exit 0
STUB
  chmod +x "$git_stub"
  export WSK_STUB_GUM_CONFIRM_EXIT=0

  _run_fix_git_iso "
    WSK_ACCOUNTS=(work)
    ui_section() { true; }
    ui_subhead() { true; }
  " "run_fix_git --apply" >/dev/null

  grep -q "remote set-url origin git@github-work:org/my-repo.git" "$WSK_STUB_LOG"
}

# ===========================================================================
# FG-6: Post-rewrite gh auth switch offer, accepted
# ===========================================================================

@test "FG-6: post-rewrite gh switch offer accepted — gh auth switch called" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  local repo_dir="$HOME/projects/work/my-repo"
  mkdir -p "$repo_dir/.git"
  printf 'ref: refs/heads/main\n' > "$repo_dir/.git/HEAD"

  local git_stub="$WSK_STUB_BIN/git"
  cat > "$git_stub" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == *"remote get-url origin"* ]]; then
  echo "https://github.com/org/my-repo.git"
fi
exit 0
STUB
  chmod +x "$git_stub"

  # Add gh stub to the stub bin
  local gh_stub="$WSK_STUB_BIN/gh"
  cat > "$gh_stub" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$gh_stub"

  local out
  out=$(bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    unset -f gum 2>/dev/null || true
    ui_confirm() { return 0; }

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    ui_confirm() { return 0; }
    source '${WSK_DIR}/lib/preflight.sh'
    source '${WSK_DIR}/lib/doctor.sh'
    source '${WSK_DIR}/lib/fix-git.sh'
    ui_confirm() { return 0; }

    WSK_ACCOUNTS=(work)
    ui_section() { true; }
    ui_subhead() { true; }
    run_fix_git --apply 2>&1
  " 2>&1)

  assert_stub_called "auth switch"
}

# ===========================================================================
# FG-7: Post-rewrite gh auth switch offer, skipped
# ===========================================================================

@test "FG-7: post-rewrite gh switch offer declined — no gh auth switch" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  local repo_dir="$HOME/projects/work/my-repo"
  mkdir -p "$repo_dir/.git"
  printf 'ref: refs/heads/main\n' > "$repo_dir/.git/HEAD"

  local git_stub="$WSK_STUB_BIN/git"
  cat > "$git_stub" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == *"remote get-url origin"* ]]; then
  echo "https://github.com/org/my-repo.git"
fi
exit 0
STUB
  chmod +x "$git_stub"

  local count_file="$WSK_TEST_HOME/confirm_count"
  printf '0' > "$count_file"

  local out
  out=$(bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    _COUNT_FILE='${count_file}'
    unset -f gum 2>/dev/null || true
    # First confirm (repo): accept; second (gh switch): decline
    ui_confirm() {
      local cnt
      cnt=\$(cat \"\$_COUNT_FILE\" 2>/dev/null || echo 0)
      cnt=\$(( cnt + 1 ))
      printf '%s' \"\$cnt\" > \"\$_COUNT_FILE\"
      if [[ \"\$cnt\" -eq 1 ]]; then return 0; else return 1; fi
    }

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    # Re-apply stateful confirm after sourcing
    ui_confirm() {
      local cnt
      cnt=\$(cat \"\$_COUNT_FILE\" 2>/dev/null || echo 0)
      cnt=\$(( cnt + 1 ))
      printf '%s' \"\$cnt\" > \"\$_COUNT_FILE\"
      if [[ \"\$cnt\" -eq 1 ]]; then return 0; else return 1; fi
    }
    source '${WSK_DIR}/lib/preflight.sh'
    source '${WSK_DIR}/lib/doctor.sh'
    source '${WSK_DIR}/lib/fix-git.sh'
    ui_confirm() {
      local cnt
      cnt=\$(cat \"\$_COUNT_FILE\" 2>/dev/null || echo 0)
      cnt=\$(( cnt + 1 ))
      printf '%s' \"\$cnt\" > \"\$_COUNT_FILE\"
      if [[ \"\$cnt\" -eq 1 ]]; then return 0; else return 1; fi
    }

    WSK_ACCOUNTS=(work)
    ui_section() { true; }
    ui_subhead() { true; }
    run_fix_git --apply 2>&1
  " 2>&1)

  assert_stub_not_called "auth switch"
}

# ===========================================================================
# FG-repo-no-acct: Repo not under any known PROJECTS_DIR — emits check_warn
# ===========================================================================

@test "FG-repo-no-acct: repo outside every PROJECTS_DIR — check_warn emitted, repo skipped" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  # Repo lives outside the seeded PROJECTS_DIR (/tmp/other-dir/)
  local repo_dir="$HOME/other-dir/my-repo"
  mkdir -p "$repo_dir/.git"
  printf 'ref: refs/heads/main\n' > "$repo_dir/.git/HEAD"

  # Put the repo inside the work PROJECTS_DIR glob path so _run_fix_git sees it,
  # but override _fix_git_resolve_acct to return empty (no owning account).
  # Simpler: put the repo in work dir but stub git to return https URL,
  # and override PROJECTS_DIR so repo_path does NOT match.
  local git_stub="$WSK_STUB_BIN/git"
  cat > "$git_stub" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == *"remote get-url origin"* ]]; then
  echo "https://github.com/org/my-repo.git"
fi
exit 0
STUB
  chmod +x "$git_stub"

  # Put repo inside PROJECTS_DIR so scan finds it, but set PROJECTS_DIR for the
  # account to a DIFFERENT path so longest-prefix-match finds no owning account.
  local repo_dir2="$HOME/projects/work/my-repo"
  mkdir -p "$repo_dir2/.git"
  printf 'ref: refs/heads/main\n' > "$repo_dir2/.git/HEAD"

  local out
  out=$(_run_fix_git_iso "
    # Accounts present but PROJECTS_DIR for 'work' points elsewhere
    WSK_ACCOUNTS=(work)
    ui_section() { true; }
    ui_subhead() { true; }
    # Override _fix_git_resolve_acct to return empty (no match)
    _fix_git_resolve_acct() { echo ''; }
  " "run_fix_git")

  echo "$out" | grep -qi "cannot determine\|skipping\|no.*account"
}

# ===========================================================================
# FG-0: No https remotes found — clean message when all remotes are SSH
# ===========================================================================

@test "FG-0: no https remotes found — prints clean message" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  local repo_dir="$HOME/projects/work/my-repo"
  mkdir -p "$repo_dir/.git"
  printf 'ref: refs/heads/main\n' > "$repo_dir/.git/HEAD"

  # git returns an already-correct SSH alias remote
  local git_stub="$WSK_STUB_BIN/git"
  cat > "$git_stub" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == *"remote get-url origin"* ]]; then
  echo "git@github-work:org/my-repo.git"
fi
exit 0
STUB
  chmod +x "$git_stub"

  local out
  out=$(_run_fix_git_iso "
    WSK_ACCOUNTS=(work)
    ui_section() { true; }
    ui_subhead() { true; }
  " "run_fix_git")

  echo "$out" | grep -qi "No https remotes found"
}

# ===========================================================================
# FG-8: CLI dispatch — wsk fix-git --apply reaches apply mode
# ===========================================================================

@test "FG-8: install.sh dispatch forwards --apply so run_fix_git receives it" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  local repo_dir="$HOME/projects/work/my-repo"
  mkdir -p "$repo_dir/.git"
  printf 'ref: refs/heads/main\n' > "$repo_dir/.git/HEAD"

  local git_stub="$WSK_STUB_BIN/git"
  cat > "$git_stub" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == *"remote get-url origin"* ]]; then
  echo "https://github.com/org/my-repo.git"
fi
exit 0
STUB
  chmod +x "$git_stub"

  # Accept both the repo rewrite prompt and the gh-switch prompt.
  export WSK_STUB_GUM_CONFIRM_EXIT=0

  # Invoke install.sh as the real CLI would: bash install.sh fix-git --apply
  local out
  out=$(bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'
    unset -f gum 2>/dev/null || true
    ui_confirm() { return 0; }
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    ui_confirm() { return 0; }

    # Source all libs that install.sh would source, then call dispatch directly
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/accounts.sh'
    source '${WSK_DIR}/lib/preflight.sh'
    source '${WSK_DIR}/lib/doctor.sh'
    source '${WSK_DIR}/lib/fix-git.sh'

    run_fix_git_cmd() {
      load_accounts
      shift
      run_fix_git \"\$@\"
    }

    dispatch() {
      case \"\$1\" in
        fix-git) run_fix_git_cmd \"\$@\" ;;
        *) return 1 ;;
      esac
    }

    COMMAND='fix-git'
    dispatch \"\$COMMAND\" '--apply' 2>&1
  " 2>&1)

  # --apply must have reached run_fix_git: git remote set-url should be called
  assert_stub_called "remote set-url"
}
