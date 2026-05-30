#!/usr/bin/env bats

load "../helpers/setup"

setup() {
  cleanup_test_artifacts
  init_test_home
  source "${WSK_DIR}/lib/log.sh"
  source "${WSK_DIR}/lib/ui.sh"
  source "${WSK_DIR}/lib/os.sh"

  # Remove git shim so idempotency tests can control its presence
  stub_absent git
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ---------------------------------------------------------------------------
# pkg_install routing tests
# ---------------------------------------------------------------------------

@test "WSK_PKG_MGR=brew: pkg_install git records brew install git" {
  WSK_PKG_MGR="brew"
  WSK_OS="macos"
  export WSK_PKG_MGR WSK_OS

  # git absent so install is attempted
  stub_absent git
  run pkg_install git
  assert_stub_called "brew install git"
}

@test "WSK_PKG_MGR=apt: pkg_install git records apt-get install -y git" {
  WSK_PKG_MGR="apt"
  WSK_OS="linux"
  export WSK_PKG_MGR WSK_OS

  stub_absent git
  # apt-get install needs sudo — provide sudo shim
  cat > "$WSK_STUB_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
echo "sudo $*" >> "${WSK_STUB_LOG:-/dev/null}"
# Execute the rest of the args to allow apt-get to be called
"$@"
SHIM
  chmod +x "$WSK_STUB_BIN/sudo"

  run pkg_install git
  assert_stub_called "apt-get install -y git"
}

@test "WSK_PKG_MGR=dnf: pkg_install git records dnf install -y git" {
  WSK_PKG_MGR="dnf"
  WSK_OS="linux"
  export WSK_PKG_MGR WSK_OS

  stub_absent git
  cat > "$WSK_STUB_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
echo "sudo $*" >> "${WSK_STUB_LOG:-/dev/null}"
"$@"
SHIM
  chmod +x "$WSK_STUB_BIN/sudo"

  run pkg_install git
  assert_stub_called "dnf install -y git"
}

@test "WSK_PKG_MGR=pacman: pkg_install git records pacman -S --noconfirm git" {
  WSK_PKG_MGR="pacman"
  WSK_OS="linux"
  export WSK_PKG_MGR WSK_OS

  stub_absent git
  cat > "$WSK_STUB_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
echo "sudo $*" >> "${WSK_STUB_LOG:-/dev/null}"
"$@"
SHIM
  chmod +x "$WSK_STUB_BIN/sudo"

  run pkg_install git
  assert_stub_called "pacman -S --noconfirm git"
}

@test "WSK_OS=windows: pkg_install git prints instruction and no manager is called" {
  WSK_OS="windows"
  WSK_PKG_MGR=""
  export WSK_OS WSK_PKG_MGR

  stub_absent git
  run pkg_install git
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qi "install"
  assert_stub_not_called "brew install git"
  assert_stub_not_called "apt-get install"
  assert_stub_not_called "winget install"
}

@test "idempotency: git present so no manager is called and already installed is printed" {
  WSK_PKG_MGR="brew"
  WSK_OS="macos"
  export WSK_PKG_MGR WSK_OS

  # git present on PATH via shim
  stub_present git
  run pkg_install git
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qi "already installed"
  assert_stub_not_called "brew install git"
}

@test "--cask flag with WSK_PKG_MGR=brew records brew install --cask <pkg>" {
  WSK_PKG_MGR="brew"
  WSK_OS="macos"
  export WSK_PKG_MGR WSK_OS

  run pkg_install warp --cask
  assert_stub_called "brew install --cask warp"
}

@test "--cask idempotency: brew list --cask returns 0 so no install is run" {
  WSK_PKG_MGR="brew"
  WSK_OS="macos"
  export WSK_PKG_MGR WSK_OS

  # Make brew list --cask succeed (exit 0) by leaving default brew shim
  # which returns 0 for all subcommands
  run pkg_install warp --cask
  # Since brew list --cask warp returns 0 (already installed), should skip
  [[ "$status" -eq 0 ]]
  # The brew install --cask should NOT be recorded because idempotency guard fired
  assert_stub_not_called "brew install --cask warp"
}
