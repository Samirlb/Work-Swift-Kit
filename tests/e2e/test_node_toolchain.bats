#!/usr/bin/env bats

load "../helpers/setup"

setup() {
  cleanup_test_artifacts
  init_test_home
  source "${WSK_DIR}/lib/log.sh"

  # Unset exported stub functions so PATH shims take priority for command -v and invocation.
  unset -f brew 2>/dev/null || true
  unset -f gum  2>/dev/null || true

  source "${WSK_DIR}/lib/ui.sh"
  source "${WSK_DIR}/lib/os.sh"
  source "${WSK_DIR}/lib/node.sh"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
  rm -f /Users/samir/Documents/Personal/Work-Swift-Kit/tests/e2e/test_debug_node.bats \
         /Users/samir/Documents/Personal/Work-Swift-Kit/tests/e2e/test_debug2.bats 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Runs a bash -c body in an isolated subprocess where PATH contains only
# $WSK_STUB_BIN and minimal system dirs. Logs go to $stub_log_file.
# Non-zero exit from the body does NOT cause bash -c to fail (body ends with `|| true`).
_run_iso_body() {
  local stub_log_file="$1" env_prefix="$2" body="$3"
  bash -c "
    ${env_prefix}
    export PATH='${WSK_STUB_BIN}:/usr/bin:/bin'
    export WSK_STUB_LOG='${stub_log_file}'
    export WSK_STUB_BIN='${WSK_STUB_BIN}'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'
    source '${WSK_DIR}/lib/os.sh'
    source '${WSK_DIR}/lib/node.sh'
    ${body} || true
  " 2>&1
}

# ---------------------------------------------------------------------------
# install_node tests
# ---------------------------------------------------------------------------

@test "install_node: node absent, WSK_OS=macos, WSK_PKG_MGR=brew — brew install node in log" {
  local log_file="$WSK_TEST_HOME/n1.log"
  : > "$log_file"
  stub_absent node

  _run_iso_body "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew" \
    "install_node"

  # gum spin records its full args including the brew subcommand
  grep -q "brew install node" "$log_file"
}

@test "install_node: node absent, WSK_OS=linux, WSK_PKG_MGR=apt — apt-get install -y node in log" {
  local log_file="$WSK_TEST_HOME/n2.log"
  : > "$log_file"
  stub_absent node

  # sudo shim that passes through commands
  cat > "$WSK_STUB_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
echo "sudo $*" >> "${WSK_STUB_LOG:-/dev/null}"
"$@"
SHIM
  chmod +x "$WSK_STUB_BIN/sudo"

  _run_iso_body "$log_file" \
    "export WSK_OS=linux WSK_PKG_MGR=apt" \
    "install_node"

  grep -q "apt-get install -y node" "$log_file"
}

@test "install_node: node already present — no installer called, already installed in output" {
  WSK_OS="macos"
  WSK_PKG_MGR="brew"
  export WSK_OS WSK_PKG_MGR

  node_present
  run install_node
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already installed"
  assert_stub_not_called "brew install node"
}

@test "install_node: WSK_OS=windows — instruction printed, no installer called" {
  local log_file="$WSK_TEST_HOME/n4.log"
  : > "$log_file"
  stub_absent node

  local output
  output="$(_run_iso_body "$log_file" \
    "export WSK_OS=windows WSK_PKG_MGR=''" \
    "install_node")"

  echo "$output" | grep -qi "winget\|install"
  ! grep -q "brew install node" "$log_file"
}

# ---------------------------------------------------------------------------
# install_pnpm tests
# ---------------------------------------------------------------------------

@test "install_pnpm: pnpm absent, WSK_OS=macos — brew install pnpm in log, curl NOT called with pnpm URL" {
  local log_file="$WSK_TEST_HOME/p1.log"
  : > "$log_file"
  stub_absent pnpm

  _run_iso_body "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew" \
    "install_pnpm"

  # gum spin logs its full args including the brew subcommand
  grep -q "brew install pnpm" "$log_file"
  ! grep -q "get.pnpm.io" "$log_file"
}

@test "install_pnpm: pnpm absent, WSK_OS=linux, corepack present — corepack enable pnpm in log" {
  local log_file="$WSK_TEST_HOME/p2.log"
  : > "$log_file"
  stub_absent pnpm
  corepack_present

  _run_iso_body "$log_file" \
    "export WSK_OS=linux WSK_PKG_MGR=apt" \
    "install_pnpm"

  grep -q "corepack enable pnpm" "$log_file"
}

@test "install_pnpm: pnpm absent, WSK_OS=linux, no corepack — curl https://get.pnpm.io/install.sh in log" {
  local log_file="$WSK_TEST_HOME/p3.log"
  : > "$log_file"
  stub_absent pnpm
  corepack_absent

  # sh shim that records stdin invocation without running the actual installer
  cat > "$WSK_STUB_BIN/sh" <<'SHIM'
#!/usr/bin/env bash
echo "sh $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit 0
SHIM
  chmod +x "$WSK_STUB_BIN/sh"

  _run_iso_body "$log_file" \
    "export WSK_OS=linux WSK_PKG_MGR=apt" \
    "install_pnpm"

  grep -q "https://get.pnpm.io/install.sh" "$log_file"
}

@test "install_pnpm: pnpm already present — no installer called" {
  WSK_OS="macos"
  WSK_PKG_MGR="brew"
  export WSK_OS WSK_PKG_MGR

  node_present
  pnpm_present

  run install_pnpm
  [ "$status" -eq 0 ]
  assert_stub_not_called "brew install pnpm"
  assert_stub_not_called "corepack enable pnpm"
  assert_stub_not_called "get.pnpm.io"
}

@test "install_pnpm: node absent — error message printed, pnpm NOT attempted" {
  local log_file="$WSK_TEST_HOME/p5.log"
  : > "$log_file"
  stub_absent node
  stub_absent pnpm

  local output
  output="$(_run_iso_body "$log_file" \
    "export WSK_OS=macos WSK_PKG_MGR=brew" \
    "install_pnpm")"

  echo "$output" | grep -qi "Node.js is required"
  ! grep -q "brew install pnpm" "$log_file"
}

@test "install_pnpm: WSK_OS=windows — instruction printed, no installer called" {
  local log_file="$WSK_TEST_HOME/p6.log"
  : > "$log_file"
  stub_absent pnpm

  local output
  output="$(_run_iso_body "$log_file" \
    "export WSK_OS=windows WSK_PKG_MGR=''" \
    "install_pnpm")"

  echo "$output" | grep -qi "winget\|install"
  ! grep -q "brew install pnpm" "$log_file"
  ! grep -q "corepack enable pnpm" "$log_file"
}
