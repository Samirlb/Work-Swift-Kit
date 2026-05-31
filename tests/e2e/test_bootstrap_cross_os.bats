#!/usr/bin/env bats

load "../helpers/setup"

setup() {
  cleanup_test_artifacts
  init_test_home

  # Unset exported stub functions so PATH shims take priority for command -v
  unset -f brew 2>/dev/null || true
  unset -f gum  2>/dev/null || true

  source "${WSK_DIR}/lib/log.sh"
  source "${WSK_DIR}/lib/ui.sh"
  source "${WSK_DIR}/lib/os.sh"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ---------------------------------------------------------------------------
# bootstrap cross-OS tests
# ---------------------------------------------------------------------------

@test "bootstrap: macOS path — proceeds without hard-exit (no Darwin guard)" {
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
echo "Darwin"
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

  unset MSYSTEM WSK_OS WSK_PKG_MGR
  source "${WSK_DIR}/lib/bootstrap.sh"
  run bootstrap
  # Must not exit 1 (old Darwin guard is gone)
  [[ "$status" -eq 0 ]]
}

@test "bootstrap: macOS path — detect_os called; WSK_OS=macos exported after bootstrap" {
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
echo "Darwin"
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

  unset MSYSTEM WSK_OS WSK_PKG_MGR
  source "${WSK_DIR}/lib/bootstrap.sh"
  bootstrap
  [[ "${WSK_OS:-}" == "macos" ]]
}

@test "bootstrap: Linux path — WSK_OS=linux set; no hard-exit; exit 0" {
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
echo "Linux"
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

  # Remove brew so apt-get is the detected manager
  stub_absent brew

  unset MSYSTEM WSK_OS WSK_PKG_MGR
  source "${WSK_DIR}/lib/bootstrap.sh"
  run bootstrap
  [[ "$status" -eq 0 ]]
}

@test "bootstrap: Linux path — WSK_OS set to linux after bootstrap runs" {
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
echo "Linux"
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

  stub_absent brew

  unset MSYSTEM WSK_OS WSK_PKG_MGR
  source "${WSK_DIR}/lib/bootstrap.sh"
  bootstrap
  [[ "${WSK_OS:-}" == "linux" ]]
}

@test "bootstrap: Linux path — pkg_install routes through apt when apt-get is the manager" {
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
echo "Linux"
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

  cat > "$WSK_STUB_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
echo "sudo $*" >> "${WSK_STUB_LOG:-/dev/null}"
"$@"
SHIM
  chmod +x "$WSK_STUB_BIN/sudo"

  # Remove brew so apt-get is detected
  stub_absent brew
  # Remove a synthetic absent package to verify apt-get routing via pkg_install directly
  # We test routing by calling pkg_install directly with apt manager set
  WSK_OS="linux"
  WSK_PKG_MGR="apt"
  export WSK_OS WSK_PKG_MGR

  stub_absent wsk-test-prereq-zz9

  run pkg_install wsk-test-prereq-zz9
  assert_stub_called "apt-get install -y wsk-test-prereq-zz9"
}

@test "bootstrap: Windows path — WSK_OS=windows; instructions printed; exit 0" {
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
echo "Linux"
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

  cat > "$WSK_STUB_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
echo "sudo $*" >> "${WSK_STUB_LOG:-/dev/null}"
"$@"
SHIM
  chmod +x "$WSK_STUB_BIN/sudo"

  MSYSTEM="MINGW64"
  export MSYSTEM
  unset WSK_OS WSK_PKG_MGR

  source "${WSK_DIR}/lib/bootstrap.sh"
  run bootstrap
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qi "install"
  assert_stub_not_called "brew install"
  assert_stub_not_called "apt-get install"
  unset MSYSTEM
}

# ---------------------------------------------------------------------------
# packages.sh cross-OS tests
# ---------------------------------------------------------------------------

@test "packages.sh: Linux with WSK_PKG_MGR=apt routes packages through apt-get, not brew" {
  cat > "$WSK_STUB_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
echo "sudo $*" >> "${WSK_STUB_LOG:-/dev/null}"
"$@"
SHIM
  chmod +x "$WSK_STUB_BIN/sudo"

  WSK_OS="linux"
  WSK_PKG_MGR="apt"
  export WSK_OS WSK_PKG_MGR

  # Remove all package shims so pkg_install calls apt-get
  for pkg in git gh fzf rg bat eza fd sd starship zoxide jq tree; do
    stub_absent "$pkg"
  done

  source "${WSK_DIR}/lib/packages.sh"
  run install_packages
  [[ "$status" -eq 0 ]]
  assert_stub_called "apt-get install -y"
  assert_stub_not_called "brew install"
}

# ---------------------------------------------------------------------------
# terminals.sh cross-OS tests
# ---------------------------------------------------------------------------

@test "terminals.sh: macOS — alacritty installed as cask via brew install --cask" {
  WSK_OS="macos"
  WSK_PKG_MGR="brew"
  export WSK_OS WSK_PKG_MGR

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

  # Stub ui_multiselect to return Alacritty only
  ui_multiselect() { echo "Alacritty"; }
  export -f ui_multiselect

  source "${WSK_DIR}/lib/terminals.sh"
  run install_terminals
  [[ "$status" -eq 0 ]]
  assert_stub_called "brew install --cask alacritty"
}

@test "terminals.sh: Linux with apt — alacritty and kitty installed via apt-get (not cask)" {
  cat > "$WSK_STUB_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
echo "sudo $*" >> "${WSK_STUB_LOG:-/dev/null}"
"$@"
SHIM
  chmod +x "$WSK_STUB_BIN/sudo"

  WSK_OS="linux"
  WSK_PKG_MGR="apt"
  export WSK_OS WSK_PKG_MGR

  # Remove terminal shims so pkg_install sees them absent
  stub_absent alacritty
  stub_absent kitty

  # ui_multiselect returns linux-available terminals
  ui_multiselect() { printf 'Alacritty\nKitty\n'; }
  export -f ui_multiselect

  source "${WSK_DIR}/lib/terminals.sh"
  run install_terminals
  [[ "$status" -eq 0 ]]
  assert_stub_called "apt-get install -y alacritty"
  assert_stub_called "apt-get install -y kitty"
  assert_stub_not_called "brew install --cask"
}

@test "terminals.sh: Linux — Warp and iTerm2 are macOS-only; check_warn emitted, no install" {
  WSK_OS="linux"
  WSK_PKG_MGR="apt"
  export WSK_OS WSK_PKG_MGR

  # ui_multiselect returns macOS-only terminals
  ui_multiselect() { printf 'Warp\niTerm2\n'; }
  export -f ui_multiselect

  source "${WSK_DIR}/lib/terminals.sh"
  run install_terminals
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qi "not available on Linux"
  assert_stub_not_called "brew install --cask warp"
  assert_stub_not_called "brew install --cask iterm2"
  assert_stub_not_called "apt-get install"
}

@test "terminals.sh: Windows — all terminals emit install-manually warning, no package manager called" {
  WSK_OS="windows"
  WSK_PKG_MGR=""
  export WSK_OS WSK_PKG_MGR

  ui_multiselect() { printf 'Warp\nAlacritty\nNeovim\n'; }
  export -f ui_multiselect

  source "${WSK_DIR}/lib/terminals.sh"
  run install_terminals
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qi "install"
  assert_stub_not_called "brew install"
  assert_stub_not_called "apt-get install"
}
