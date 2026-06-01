#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load "../helpers/setup"

setup() {
  cleanup_test_artifacts
  init_test_home
  source "${WSK_DIR}/lib/log.sh"

  # Unset exported stub functions so PATH shims take priority for command -v and invocation.
  # PATH shims record to $WSK_STUB_LOG; the exported functions do not.
  unset -f brew 2>/dev/null || true
  unset -f gum  2>/dev/null || true

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

# Helper: write a sudo shim that executes its arguments (for apt/dnf/pacman)
_write_sudo_shim() {
  cat > "$WSK_STUB_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
echo "sudo $*" >> "${WSK_STUB_LOG:-/dev/null}"
"$@"
SHIM
  chmod +x "$WSK_STUB_BIN/sudo"
}

@test "WSK_PKG_MGR=brew: pkg_install records brew install for absent package" {
  WSK_PKG_MGR="brew"
  WSK_OS="macos"
  export WSK_PKG_MGR WSK_OS

  run pkg_install wsk-fake-pkg-zz9
  assert_stub_called "brew install wsk-fake-pkg-zz9"
}

@test "WSK_PKG_MGR=apt: pkg_install records apt-get install -y for absent package" {
  WSK_PKG_MGR="apt"
  WSK_OS="linux"
  export WSK_PKG_MGR WSK_OS

  _write_sudo_shim
  run pkg_install wsk-fake-pkg-zz9
  assert_stub_called "apt-get install -y wsk-fake-pkg-zz9"
}

@test "WSK_PKG_MGR=dnf: pkg_install records dnf install -y for absent package" {
  WSK_PKG_MGR="dnf"
  WSK_OS="linux"
  export WSK_PKG_MGR WSK_OS

  _write_sudo_shim
  run pkg_install wsk-fake-pkg-zz9
  assert_stub_called "dnf install -y wsk-fake-pkg-zz9"
}

@test "WSK_PKG_MGR=pacman: pkg_install records pacman -S --noconfirm for absent package" {
  WSK_PKG_MGR="pacman"
  WSK_OS="linux"
  export WSK_PKG_MGR WSK_OS

  _write_sudo_shim
  run pkg_install wsk-fake-pkg-zz9
  assert_stub_called "pacman -S --noconfirm wsk-fake-pkg-zz9"
}

@test "WSK_OS=windows: pkg_install prints install instruction and no manager is called" {
  WSK_OS="windows"
  WSK_PKG_MGR=""
  export WSK_OS WSK_PKG_MGR

  run pkg_install wsk-fake-pkg-zz9
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qi "install"
  assert_stub_not_called "brew install"
  assert_stub_not_called "apt-get install"
  assert_stub_not_called "winget install"
}

@test "idempotency: package already on PATH so no manager is called" {
  WSK_PKG_MGR="brew"
  WSK_OS="macos"
  export WSK_PKG_MGR WSK_OS

  # Place a fake binary on PATH to simulate an already-installed package
  local fake_pkg="wsk-already-installed-zz9"
  stub_present "$fake_pkg"
  run pkg_install "$fake_pkg"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qi "already installed"
  assert_stub_not_called "brew install $fake_pkg"
}

@test "--cask flag with WSK_PKG_MGR=brew records brew install --cask when not already installed" {
  WSK_PKG_MGR="brew"
  WSK_OS="macos"
  export WSK_PKG_MGR WSK_OS

  # Override brew shim so 'brew list --cask' returns 1 (not installed)
  cat > "$WSK_STUB_BIN/brew" <<'SHIM'
#!/usr/bin/env bash
echo "brew $*" >> "${WSK_STUB_LOG:-/dev/null}"
if [[ "$1" == "list" && "$2" == "--cask" ]]; then
  exit 1
fi
exit 0
SHIM
  chmod +x "$WSK_STUB_BIN/brew"

  run pkg_install wsk-fake-cask-zz9 --cask
  assert_stub_called "brew install --cask wsk-fake-cask-zz9"
}

@test "--cask idempotency: brew list --cask returns 0 so no install is run" {
  WSK_PKG_MGR="brew"
  WSK_OS="macos"
  export WSK_PKG_MGR WSK_OS

  # Default brew shim returns 0 for everything including 'list --cask'
  run pkg_install wsk-fake-cask-zz9 --cask
  [[ "$status" -eq 0 ]]
  assert_stub_not_called "brew install --cask wsk-fake-cask-zz9"
}
