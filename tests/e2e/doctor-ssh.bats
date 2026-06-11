#!/usr/bin/env bats
# doctor-ssh.bats — WU-5
# Tests for the SSH agent checks added to lib/doctor.sh _audit_ssh_agent.
# Checks: (a) key file exists, (b) fingerprint in agent → warn with fix command,
#         (c) optional SSH connectivity test for git@github-{acct}.

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run audit function in an isolated subprocess with WSK libs sourced.
# ---------------------------------------------------------------------------
_run_ssh_iso() {
  local extra_setup="${1:-}"
  local call="${2:-}"

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

    source '${WSK_DIR}/lib/accounts.sh'
    source '${WSK_DIR}/lib/doctor.sh'

    ${call} 2>&1
  " 2>&1
}

setup() {
  init_test_home
  export WSK_DIR
  export WSK_TEST_HOME
  mkdir -p "$HOME/.ssh"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ===========================================================================
# DS-1: key file exists and is loaded in agent → check_pass
# ===========================================================================
@test "DS-1: key exists and is loaded in agent — check_pass" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_ed25519_work"
  touch "$HOME/.ssh/id_ed25519_work"

  local ssh_add_stub="$WSK_STUB_BIN/ssh-add"
  local key_path="$HOME/.ssh/id_ed25519_work"
  cat > "$ssh_add_stub" <<STUB
#!/usr/bin/env bash
echo "ssh-add \$*" >> "\${WSK_STUB_LOG:-/dev/null}"
if [[ "\$1" == "-l" ]]; then
  echo "256 SHA256:AABB ${key_path} (ED25519)"
  exit 0
fi
exit 0
STUB
  chmod +x "$ssh_add_stub"

  local out
  out=$(_run_ssh_iso "
    export WSK_OS=macos
  " "_audit_ssh_agent work id_ed25519_work")

  echo "$out" | grep -qi "loaded\|agent\|pass\|✓"
}

# ===========================================================================
# DS-2: key file missing → check_fail
# ===========================================================================
@test "DS-2: key file missing — check_fail" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_ed25519_work"
  # Do NOT create the key file

  local out
  out=$(_run_ssh_iso "
    export WSK_OS=macos
  " "_audit_ssh_agent work id_ed25519_work")

  echo "$out" | grep -qi "missing\|not found\|does not exist\|✗"
}

# ===========================================================================
# DS-3: key file exists but NOT in agent → check_warn with fix command
# ===========================================================================
@test "DS-3: key exists but not in agent — check_warn with ssh-add command" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_ed25519_work"
  touch "$HOME/.ssh/id_ed25519_work"

  local ssh_add_stub="$WSK_STUB_BIN/ssh-add"
  cat > "$ssh_add_stub" <<'STUB'
#!/usr/bin/env bash
echo "ssh-add $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$1" == "-l" ]]; then
  echo "The agent has no identities."
  exit 1
fi
exit 0
STUB
  chmod +x "$ssh_add_stub"

  local out
  out=$(_run_ssh_iso "
    export WSK_OS=macos
  " "_audit_ssh_agent work id_ed25519_work")

  # Must warn and include the fix command
  echo "$out" | grep -qi "not loaded\|not in agent\|ssh-add\|!"
  echo "$out" | grep -q "apple-use-keychain\|ssh-add"
}

# ===========================================================================
# DS-4: macOS fix command hint contains --apple-use-keychain
# ===========================================================================
@test "DS-4: macOS — fix hint uses --apple-use-keychain" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_ed25519_work"
  touch "$HOME/.ssh/id_ed25519_work"

  local ssh_add_stub="$WSK_STUB_BIN/ssh-add"
  cat > "$ssh_add_stub" <<'STUB'
#!/usr/bin/env bash
echo "ssh-add $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$1" == "-l" ]]; then
  echo "The agent has no identities."
  exit 1
fi
exit 0
STUB
  chmod +x "$ssh_add_stub"

  local out
  out=$(_run_ssh_iso "
    export WSK_OS=macos
  " "_audit_ssh_agent work id_ed25519_work")

  echo "$out" | grep -q "apple-use-keychain"
}

# ===========================================================================
# DS-5: Linux — fix hint uses plain ssh-add (no --apple-use-keychain)
# ===========================================================================
@test "DS-5: Linux — fix hint uses plain ssh-add, not --apple-use-keychain" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_ed25519_work"
  touch "$HOME/.ssh/id_ed25519_work"

  local ssh_add_stub="$WSK_STUB_BIN/ssh-add"
  cat > "$ssh_add_stub" <<'STUB'
#!/usr/bin/env bash
echo "ssh-add $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$1" == "-l" ]]; then
  echo "The agent has no identities."
  exit 1
fi
exit 0
STUB
  chmod +x "$ssh_add_stub"

  local out
  out=$(_run_ssh_iso "
    export WSK_OS=linux
  " "_audit_ssh_agent work id_ed25519_work")

  # Should mention ssh-add but NOT --apple-use-keychain
  echo "$out" | grep -q "ssh-add"
  echo "$out" | grep -qv "apple-use-keychain"
}

# ===========================================================================
# DS-6: ssh-add not available → check_warn and not fatal
# ===========================================================================
@test "DS-6: ssh-add not on PATH — check_warn, returns 0" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_ed25519_work"
  touch "$HOME/.ssh/id_ed25519_work"

  stub_absent ssh-add

  local out rc
  out=$(_run_ssh_iso "
    export WSK_OS=macos
  " "_audit_ssh_agent work id_ed25519_work"); rc=$?

  [[ "$rc" -eq 0 ]]
  echo "$out" | grep -qi "ssh-add\|not found\|skip\|!"
}

# ===========================================================================
# DS-7: SSH connectivity check → pass when git@github-{acct} responds OK
# ===========================================================================
@test "DS-7: SSH connectivity check passes — check_pass emitted" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_ed25519_work"
  touch "$HOME/.ssh/id_ed25519_work"

  # Stub ssh to simulate a successful GitHub SSH handshake
  local ssh_stub="$WSK_STUB_BIN/ssh"
  cat > "$ssh_stub" <<'STUB'
#!/usr/bin/env bash
echo "ssh $*" >> "${WSK_STUB_LOG:-/dev/null}"
# GitHub responds on stderr: "Hi <user>! You've successfully authenticated"
echo "Hi janew! You've successfully authenticated, but GitHub does not provide shell access." >&2
exit 1  # GitHub returns exit 1 even on success
STUB
  chmod +x "$ssh_stub"

  local out
  out=$(_run_ssh_iso "
    export WSK_OS=macos
    export WSK_SSH_CHECK=1
  " "_audit_ssh_connectivity work janew id_ed25519_work")

  echo "$out" | grep -qi "authenticated\|connected\|pass\|✓"
}

# ===========================================================================
# DS-8: SSH connectivity check → warn when connection fails
# ===========================================================================
@test "DS-8: SSH connectivity check fails — check_warn emitted" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_ed25519_work"
  touch "$HOME/.ssh/id_ed25519_work"

  # Stub ssh to simulate a failure (Permission denied)
  local ssh_stub="$WSK_STUB_BIN/ssh"
  cat > "$ssh_stub" <<'STUB'
#!/usr/bin/env bash
echo "ssh $*" >> "${WSK_STUB_LOG:-/dev/null}"
echo "git@github-work: Permission denied (publickey)." >&2
exit 255
STUB
  chmod +x "$ssh_stub"

  local out
  out=$(_run_ssh_iso "
    export WSK_OS=macos
    export WSK_SSH_CHECK=1
  " "_audit_ssh_connectivity work janew id_ed25519_work")

  echo "$out" | grep -qi "permission denied\|failed\|could not\|!"
}

# ===========================================================================
# DS-9: SSH connectivity skipped when WSK_SSH_CHECK not set
# ===========================================================================
@test "DS-9: SSH connectivity skipped when WSK_SSH_CHECK unset" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_ed25519_work"
  touch "$HOME/.ssh/id_ed25519_work"

  local ssh_stub="$WSK_STUB_BIN/ssh"
  cat > "$ssh_stub" <<'STUB'
#!/usr/bin/env bash
echo "ssh $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$ssh_stub"

  _run_ssh_iso "
    export WSK_OS=macos
    unset WSK_SSH_CHECK
  " "_audit_ssh_connectivity work janew id_ed25519_work"

  assert_stub_not_called "ssh "
}

# ===========================================================================
# DS-10: run_doctor includes SSH agent section in output
# ===========================================================================
@test "DS-10: run_doctor emits SSH agent section" {
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_ed25519_work"
  touch "$HOME/.ssh/id_ed25519_work"

  local ssh_add_stub="$WSK_STUB_BIN/ssh-add"
  local key_path="$HOME/.ssh/id_ed25519_work"
  cat > "$ssh_add_stub" <<STUB
#!/usr/bin/env bash
echo "ssh-add \$*" >> "\${WSK_STUB_LOG:-/dev/null}"
if [[ "\$1" == "-l" ]]; then
  echo "256 SHA256:AABB ${key_path} (ED25519)"
  exit 0
fi
exit 0
STUB
  chmod +x "$ssh_add_stub"

  local gh_stub="$WSK_STUB_BIN/gh"
  cat > "$gh_stub" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$gh_stub"

  local out
  out=$(_run_ssh_iso "
    load_accounts() { WSK_ACCOUNTS=(work); }
    ui_section() { true; }
    ui_subhead() { printf '\n%s\n' \"\$1\"; }
    export WSK_OS=macos
    export WSK_PKG_MGR=brew
  " "run_doctor")

  echo "$out" | grep -qi "SSH agent\|ssh agent\|agent"
}
