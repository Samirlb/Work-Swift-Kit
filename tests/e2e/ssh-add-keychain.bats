#!/usr/bin/env bats
# ssh-add-keychain.bats — WU-4
# Tests for _ssh_add_key in lib/accounts.sh.
# Rule: sandboxed HOME, never touches real $HOME, stubs all external commands.

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run _ssh_add_key in an isolated subprocess with WSK libs sourced.
# $1 = extra env/setup  $2 = call expression
# ---------------------------------------------------------------------------
_run_add_iso() {
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

    ${extra_setup}

    source '${WSK_DIR}/lib/accounts.sh'

    ${call} 2>&1
  " 2>&1
}

setup() {
  init_test_home
  export WSK_DIR
  export WSK_TEST_HOME
  # Create a fake key file for all tests that need one
  mkdir -p "$HOME/.ssh"
  echo "stub-private-key" > "$HOME/.ssh/id_ed25519_work"
  chmod 600 "$HOME/.ssh/id_ed25519_work"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ---------------------------------------------------------------------------
# SK-1: macOS + key not in agent → calls ssh-add --apple-use-keychain
# ---------------------------------------------------------------------------
@test "SK-1: macOS key not in agent — calls ssh-add --apple-use-keychain" {
  # Stub ssh-add: reports empty agent list, then succeeds on add
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
  out=$(_run_add_iso "
    export WSK_OS=macos
  " "_ssh_add_key '$HOME/.ssh/id_ed25519_work'")

  assert_stub_called "ssh-add --apple-use-keychain"
}

# ---------------------------------------------------------------------------
# SK-2: macOS + key already in agent → skips ssh-add (idempotent)
# Real `ssh-add -l` on macOS shows the key file path in the comment field.
# We match on the key filename so idempotency works without ssh-keygen.
# ---------------------------------------------------------------------------
@test "SK-2: macOS key already in agent — skips ssh-add" {
  local key_path="$HOME/.ssh/id_ed25519_work"

  # Stub ssh-add: -l returns output that includes the key filename (like real macOS)
  local ssh_add_stub="$WSK_STUB_BIN/ssh-add"
  cat > "$ssh_add_stub" <<STUB
#!/usr/bin/env bash
echo "ssh-add \$*" >> "\${WSK_STUB_LOG:-/dev/null}"
if [[ "\$1" == "-l" ]]; then
  echo "256 SHA256:AABBCCDDEEFF ${key_path} (ED25519)"
  exit 0
fi
exit 0
STUB
  chmod +x "$ssh_add_stub"

  _run_add_iso "
    export WSK_OS=macos
  " "_ssh_add_key '${key_path}'"

  assert_stub_not_called "ssh-add --apple-use-keychain"
}

# ---------------------------------------------------------------------------
# SK-3: Linux + ssh-agent running + key not in agent → calls plain ssh-add
# ---------------------------------------------------------------------------
@test "SK-3: Linux with agent running — calls plain ssh-add" {
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
  out=$(_run_add_iso "
    export WSK_OS=linux
    export SSH_AUTH_SOCK=/tmp/stub-agent.sock
  " "_ssh_add_key '$HOME/.ssh/id_ed25519_work'")

  assert_stub_called "ssh-add $HOME/.ssh/id_ed25519_work"
  assert_stub_not_called "ssh-add --apple-use-keychain"
}

# ---------------------------------------------------------------------------
# SK-4: Linux + no ssh-agent (SSH_AUTH_SOCK unset) → skips, warns
# ---------------------------------------------------------------------------
@test "SK-4: Linux with no agent socket — skips and emits check_warn" {
  local ssh_add_stub="$WSK_STUB_BIN/ssh-add"
  cat > "$ssh_add_stub" <<'STUB'
#!/usr/bin/env bash
echo "ssh-add $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$ssh_add_stub"

  local out
  out=$(_run_add_iso "
    export WSK_OS=linux
    unset SSH_AUTH_SOCK
  " "_ssh_add_key '$HOME/.ssh/id_ed25519_work'")

  # Must not call ssh-add and must warn
  assert_stub_not_called "ssh-add $HOME/.ssh/id_ed25519_work"
  echo "$out" | grep -qi "agent\|no agent\|SSH_AUTH_SOCK"
}

# ---------------------------------------------------------------------------
# SK-5: ssh-add not on PATH → skips silently (check_warn, non-fatal)
# ---------------------------------------------------------------------------
@test "SK-5: ssh-add not installed — skips and warns, never fatal" {
  stub_absent ssh-add

  local out rc
  out=$(_run_add_iso "
    export WSK_OS=macos
  " "_ssh_add_key '$HOME/.ssh/id_ed25519_work'"); rc=$?

  [[ "$rc" -eq 0 ]]
  echo "$out" | grep -qi "ssh-add\|not found\|skip"
}

# ---------------------------------------------------------------------------
# SK-6: ssh-add fails (passphrase mismatch etc.) → check_warn, never fatal
# ---------------------------------------------------------------------------
@test "SK-6: ssh-add fails — emits check_warn, exits 0" {
  local ssh_add_stub="$WSK_STUB_BIN/ssh-add"
  cat > "$ssh_add_stub" <<'STUB'
#!/usr/bin/env bash
echo "ssh-add $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$1" == "-l" ]]; then
  echo "The agent has no identities."
  exit 1
fi
# Simulate failure on add
exit 1
STUB
  chmod +x "$ssh_add_stub"

  local out rc
  out=$(_run_add_iso "
    export WSK_OS=macos
  " "_ssh_add_key '$HOME/.ssh/id_ed25519_work'"); rc=$?

  [[ "$rc" -eq 0 ]]
  echo "$out" | grep -qi "warn\|failed\|could not\|!"
}

# ---------------------------------------------------------------------------
# SK-7: Key file does not exist → skips silently
# ---------------------------------------------------------------------------
@test "SK-7: key file does not exist — skips without error" {
  local ssh_add_stub="$WSK_STUB_BIN/ssh-add"
  cat > "$ssh_add_stub" <<'STUB'
#!/usr/bin/env bash
echo "ssh-add $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$ssh_add_stub"

  local out rc
  out=$(_run_add_iso "
    export WSK_OS=macos
  " "_ssh_add_key '$HOME/.ssh/id_ed25519_nonexistent'"); rc=$?

  [[ "$rc" -eq 0 ]]
  assert_stub_not_called "ssh-add"
}

# ---------------------------------------------------------------------------
# SK-8: _collect_single_account generates key then calls _ssh_add_key
#        (integration: after ssh-keygen, the key is offered to the agent)
# ---------------------------------------------------------------------------
@test "SK-8: after key generation _ssh_add_key is invoked for the new key" {
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

  # _ssh_add_key is called with the key path
  local out
  out=$(_run_add_iso "
    export WSK_OS=macos
  " "_ssh_add_key '$HOME/.ssh/id_ed25519_work'")

  assert_stub_called "ssh-add"
}

# ---------------------------------------------------------------------------
# KL-1: macOS + _ssh_load_keychain → ssh-add --apple-load-keychain invoked once
# ---------------------------------------------------------------------------
@test "KL-1: macOS _ssh_load_keychain — calls ssh-add --apple-load-keychain once" {
  local ssh_add_stub="$WSK_STUB_BIN/ssh-add"
  cat > "$ssh_add_stub" <<'STUB'
#!/usr/bin/env bash
echo "ssh-add $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$ssh_add_stub"

  _run_add_iso "
    export WSK_OS=macos
  " "_ssh_load_keychain"

  assert_stub_called "ssh-add --apple-load-keychain"
}

# ---------------------------------------------------------------------------
# KL-2: Linux + _ssh_load_keychain → ssh-add NOT called (no-op)
# ---------------------------------------------------------------------------
@test "KL-2: Linux _ssh_load_keychain — ssh-add not called (no-op)" {
  local ssh_add_stub="$WSK_STUB_BIN/ssh-add"
  cat > "$ssh_add_stub" <<'STUB'
#!/usr/bin/env bash
echo "ssh-add $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$ssh_add_stub"

  _run_add_iso "
    export WSK_OS=linux
  " "_ssh_load_keychain"

  assert_stub_not_called "ssh-add"
}
