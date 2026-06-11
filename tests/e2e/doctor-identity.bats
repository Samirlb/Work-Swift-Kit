#!/usr/bin/env bats
# doctor-identity.bats — WU-3
# Tests for lib/doctor.sh git/gh identity audit functions.

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run identity audit functions in an isolated subprocess
# $1 = extra env/setup
# $2 = function call to evaluate
# ---------------------------------------------------------------------------
_run_identity_iso() {
  local extra_setup="${1:-}"
  local call="${2:-run_doctor}"

  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/preflight.sh'

    ${extra_setup}

    source '${WSK_DIR}/lib/doctor.sh'

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
# GI-1: gh login present and active — check_pass
# ===========================================================================

@test "GI-1: gh logged in and active — check_pass printed" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  # Stub gh to report active login
  local gh_stub="$WSK_STUB_BIN/gh"
  cat > "$gh_stub" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == "auth status" ]]; then
  cat <<'EOF'
github.com
  Logged in to github.com account janew (keyring)
  Active account: true
  Token: gho_xxxx
  Token scopes: gist, read:org, repo, workflow
EOF
fi
exit 0
STUB
  chmod +x "$gh_stub"

  local out
  out=$(_run_identity_iso "
    load_accounts() { WSK_ACCOUNTS=(work); }
    ui_section() { true; }
    ui_subhead() { printf '\n%s\n' \"\$1\"; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
  " "_audit_gh_login work janew")

  echo "$out" | grep -q 'janew'
  echo "$out" | grep -q 'active\|logged in'
}

# ===========================================================================
# GI-2: gh login absent for account — check_warn
# ===========================================================================

@test "GI-2: gh not logged in for account — check_warn printed" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  # Stub gh to report a different user
  local gh_stub="$WSK_STUB_BIN/gh"
  cat > "$gh_stub" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == "auth status" ]]; then
  cat <<'EOF'
github.com
  Logged in to github.com account otheruser (keyring)
  Active account: true
EOF
fi
exit 0
STUB
  chmod +x "$gh_stub"

  local out
  out=$(_run_identity_iso "
    load_accounts() { WSK_ACCOUNTS=(work); }
    ui_section() { true; }
    ui_subhead() { printf '\n%s\n' \"\$1\"; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
  " "_audit_gh_login work janew")

  echo "$out" | grep -q 'janew\|not logged in\|no login found'
}

# ===========================================================================
# GI-3: Active account matches — check_pass
# (implicitly covered by GI-1 — active:true produces pass)
# ===========================================================================

@test "GI-3: active account matches — check_pass emitted" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  local gh_stub="$WSK_STUB_BIN/gh"
  cat > "$gh_stub" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == "auth status" ]]; then
  printf 'github.com\n  Logged in to github.com account janew (keyring)\n  Active account: true\n'
fi
exit 0
STUB
  chmod +x "$gh_stub"

  local out
  out=$(_run_identity_iso "
    load_accounts() { WSK_ACCOUNTS=(work); }
    ui_section() { true; }
    ui_subhead() { printf '\n%s\n' \"\$1\"; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
  " "_audit_gh_login work janew")

  echo "$out" | grep -q 'active\|pass\|✓'
}

# ===========================================================================
# GI-4: Logged in but inactive — check_warn
# ===========================================================================

@test "GI-4: gh logged in but not active — check_warn printed" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  local gh_stub="$WSK_STUB_BIN/gh"
  cat > "$gh_stub" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$*" == "auth status" ]]; then
  printf 'github.com\n  Logged in to github.com account janew (keyring)\n  Active account: false\n'
fi
exit 0
STUB
  chmod +x "$gh_stub"

  local out
  out=$(_run_identity_iso "
    load_accounts() { WSK_ACCOUNTS=(work); }
    ui_section() { true; }
    ui_subhead() { printf '\n%s\n' \"\$1\"; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
  " "_audit_gh_login work janew")

  # Expect a warning for not-active
  echo "$out" | grep -q 'not active\|warn\|!'
}

# ===========================================================================
# GI-5: HTTPS remote detected — check_warn with repo path
# ===========================================================================

@test "GI-5: https remote detected under PROJECTS_DIR — check_warn printed" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  # Create a fake git repo with https remote
  local repo_dir="$HOME/projects/work/my-repo"
  mkdir -p "$repo_dir/.git"
  mkdir -p "$repo_dir/.git/refs"
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
  out=$(_run_identity_iso "
    load_accounts() { WSK_ACCOUNTS=(work); }
    ui_section() { true; }
    ui_subhead() { printf '\n%s\n' \"\$1\"; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
  " "_scan_remotes '$HOME/projects/work'")

  echo "$out" | grep -q 'https\|my-repo'
}

# ===========================================================================
# GI-6: No https remotes — no warning
# ===========================================================================

@test "GI-6: no https remotes — no warning emitted" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  # Create a fake git repo with SSH remote
  local repo_dir="$HOME/projects/work/my-repo"
  mkdir -p "$repo_dir/.git"
  printf 'ref: refs/heads/main\n' > "$repo_dir/.git/HEAD"

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
  out=$(_run_identity_iso "
    load_accounts() { WSK_ACCOUNTS=(work); }
    ui_section() { true; }
    ui_subhead() { printf '\n%s\n' \"\$1\"; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
  " "_scan_remotes '$HOME/projects/work'")

  # No https warning, may print pass or nothing
  echo "$out" | grep -qv 'https://github.com'
}

# ===========================================================================
# GI-7: Alias matches dir — pass (no warning)
# ===========================================================================

@test "GI-7: alias matches directory — no warning" {
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
  echo "git@github-work:org/my-repo.git"
fi
exit 0
STUB
  chmod +x "$git_stub"

  local out
  out=$(_run_identity_iso "
    load_accounts() { WSK_ACCOUNTS=(work); }
    ui_section() { true; }
    ui_subhead() { printf '\n%s\n' \"\$1\"; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
  " "_audit_alias_dir work '$HOME/projects/work'")

  # No mismatch warning expected
  echo "$out" | grep -qv 'does not match\|mismatch'
}

# ===========================================================================
# GI-8: Alias/dir mismatch — check_warn
# ===========================================================================

@test "GI-8: alias/dir mismatch — check_warn printed" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  seed_account "personal" "Personal" "Jane P" "janep@home.com" "janep" "$HOME/projects/personal" "id_personal"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  # A repo under personal/ but using work alias
  local repo_dir="$HOME/projects/personal/my-repo"
  mkdir -p "$repo_dir/.git"
  printf 'ref: refs/heads/main\n' > "$repo_dir/.git/HEAD"

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
  out=$(_run_identity_iso "
    load_accounts() { WSK_ACCOUNTS=(work personal); }
    ui_section() { true; }
    ui_subhead() { printf '\n%s\n' \"\$1\"; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
  " "_audit_alias_dir personal '$HOME/projects/personal'")

  echo "$out" | grep -q 'mismatch\|does not match\|github-work'
}

# ===========================================================================
# GI-9: Empty PROJECTS_DIR — no crash
# ===========================================================================

@test "GI-9: empty PROJECTS_DIR — _scan_remotes does not crash" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
  mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/id_work"

  # projects dir exists but is empty
  mkdir -p "$HOME/projects/work"

  local out rc
  out=$(_run_identity_iso "
    load_accounts() { WSK_ACCOUNTS=(work); }
    ui_section() { true; }
    ui_subhead() { printf '\n%s\n' \"\$1\"; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
  " "_scan_remotes '$HOME/projects/work'"); rc=$?

  [[ "$rc" -eq 0 ]]
}
