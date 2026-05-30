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
}

# ---------------------------------------------------------------------------
# install_node tests
# ---------------------------------------------------------------------------

@test "install_node: node absent, WSK_OS=macos, WSK_PKG_MGR=brew — brew install node recorded" {
  WSK_OS="macos"
  WSK_PKG_MGR="brew"
  export WSK_OS WSK_PKG_MGR

  node_absent
  run install_node
  [ "$status" -eq 0 ]
  assert_stub_called "brew install node"
}

@test "install_node: node absent, WSK_OS=linux, WSK_PKG_MGR=apt — apt-get install -y node recorded" {
  WSK_OS="linux"
  WSK_PKG_MGR="apt"
  export WSK_OS WSK_PKG_MGR

  node_absent
  # Need sudo shim to execute apt-get
  cat > "$WSK_STUB_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
echo "sudo $*" >> "${WSK_STUB_LOG:-/dev/null}"
"$@"
SHIM
  chmod +x "$WSK_STUB_BIN/sudo"

  run install_node
  [ "$status" -eq 0 ]
  assert_stub_called "apt-get install -y node"
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
  WSK_OS="windows"
  WSK_PKG_MGR=""
  export WSK_OS WSK_PKG_MGR

  node_absent
  run install_node
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "winget\|install"
  assert_stub_not_called "brew install node"
  assert_stub_not_called "apt-get install"
}

# ---------------------------------------------------------------------------
# install_pnpm tests
# ---------------------------------------------------------------------------

@test "install_pnpm: pnpm absent, WSK_OS=macos — brew install pnpm recorded, curl NOT called with pnpm URL" {
  WSK_OS="macos"
  WSK_PKG_MGR="brew"
  export WSK_OS WSK_PKG_MGR

  node_present
  pnpm_absent

  run install_pnpm
  [ "$status" -eq 0 ]
  assert_stub_called "brew install pnpm"
  assert_stub_not_called "get.pnpm.io"
}

@test "install_pnpm: pnpm absent, WSK_OS=linux, corepack present — corepack enable pnpm recorded" {
  WSK_OS="linux"
  WSK_PKG_MGR="apt"
  export WSK_OS WSK_PKG_MGR

  node_present
  pnpm_absent
  corepack_present

  run install_pnpm
  [ "$status" -eq 0 ]
  assert_stub_called "corepack enable pnpm"
}

@test "install_pnpm: pnpm absent, WSK_OS=linux, no corepack — curl get.pnpm.io recorded" {
  WSK_OS="linux"
  WSK_PKG_MGR="apt"
  export WSK_OS WSK_PKG_MGR

  node_present
  pnpm_absent
  corepack_absent

  # curl shim pipes to sh; sh is real — just record the curl call
  run install_pnpm
  [ "$status" -eq 0 ]
  assert_stub_called "https://get.pnpm.io/install.sh"
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

@test "install_pnpm: node absent — error printed, non-zero exit, pnpm NOT attempted" {
  WSK_OS="macos"
  WSK_PKG_MGR="brew"
  export WSK_OS WSK_PKG_MGR

  node_absent
  pnpm_absent

  run install_pnpm
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "Node.js is required"
  assert_stub_not_called "brew install pnpm"
}

@test "install_pnpm: WSK_OS=windows — instruction printed, no installer called" {
  WSK_OS="windows"
  WSK_PKG_MGR=""
  export WSK_OS WSK_PKG_MGR

  node_present
  pnpm_absent

  run install_pnpm
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "winget\|install"
  assert_stub_not_called "brew install pnpm"
  assert_stub_not_called "corepack enable pnpm"
}
