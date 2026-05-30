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

@test "bootstrap: macOS path — proceeds without hard-exit; detect_os sets macos" {
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
echo "Darwin"
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

  unset MSYSTEM WSK_OS WSK_PKG_MGR
  source "${WSK_DIR}/lib/bootstrap.sh"
  run bootstrap
  [[ "$status" -eq 0 ]]
  assert_stub_called "brew install gum"
}

@test "bootstrap: Linux path — WSK_OS=linux set; prereqs installed via pkg_install (apt)" {
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
echo "Linux"
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

  # Provide a sudo shim that passes through the subcommand
  cat > "$WSK_STUB_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
echo "sudo $*" >> "${WSK_STUB_LOG:-/dev/null}"
"$@"
SHIM
  chmod +x "$WSK_STUB_BIN/sudo"

  # Remove brew so apt-get is the detected manager
  stub_absent brew
  # apt-get shim already installed by init_test_home

  unset MSYSTEM WSK_OS WSK_PKG_MGR
  source "${WSK_DIR}/lib/bootstrap.sh"
  run bootstrap
  [[ "$status" -eq 0 ]]
  # apt-get install calls recorded for core prereqs
  assert_stub_called "apt-get install -y gum"
  assert_stub_called "apt-get install -y stow"
  assert_stub_called "apt-get install -y fzf"
  assert_stub_called "apt-get install -y gettext"
}

@test "bootstrap: Windows path — WSK_OS=windows; instructions printed; exit 0" {
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
echo "Linux"
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

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
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
echo "Darwin"
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

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
  cat > "$WSK_STUB_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
echo "sudo $*" >> "${WSK_STUB_LOG:-/dev/null}"
"$@"
SHIM
  chmod +x "$WSK_STUB_BIN/sudo"

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
