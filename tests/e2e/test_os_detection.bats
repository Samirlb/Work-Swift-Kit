#!/usr/bin/env bats

load "../helpers/setup"

setup() {
  cleanup_test_artifacts
  init_test_home
  source "${WSK_DIR}/lib/log.sh"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ---------------------------------------------------------------------------
# detect_os tests
# ---------------------------------------------------------------------------

@test "detect_os sets WSK_OS=macos when uname returns Darwin" {
  # Provide a uname shim that returns Darwin
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
if [[ "$1" == "-s" ]]; then
  echo "Darwin"
else
  echo "Darwin"
fi
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

  unset MSYSTEM WSK_OS
  source "${WSK_DIR}/lib/os.sh"
  detect_os
  [[ "$WSK_OS" == "macos" ]]
}

@test "detect_os sets WSK_OS=linux when uname returns Linux and MSYSTEM unset" {
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
echo "Linux"
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

  unset MSYSTEM WSK_OS
  # Ensure /proc/version does not contain microsoft (use a fake proc/version or rely on macOS host)
  source "${WSK_DIR}/lib/os.sh"
  detect_os
  [[ "$WSK_OS" == "linux" ]]
}

@test "detect_os sets WSK_OS=windows when MSYSTEM is set" {
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
echo "MINGW64_NT-10.0"
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

  MSYSTEM="MINGW64"
  export MSYSTEM
  unset WSK_OS
  source "${WSK_DIR}/lib/os.sh"
  detect_os
  [[ "$WSK_OS" == "windows" ]]
  unset MSYSTEM
}

@test "detect_os sets WSK_OS=windows when /proc/version contains microsoft" {
  cat > "$WSK_STUB_BIN/uname" <<'SHIM'
#!/usr/bin/env bash
echo "Linux"
SHIM
  chmod +x "$WSK_STUB_BIN/uname"

  unset MSYSTEM WSK_OS
  # Create a fake /proc/version in the test home to simulate WSL
  # We patch detect_os by overriding the grep target via WSK_PROC_VERSION_FILE
  # Since the design reads /proc/version directly we need to intercept grep.
  # Provide a grep shim that detects our signal env var.
  cat > "$WSK_STUB_BIN/grep" <<'SHIM'
#!/usr/bin/env bash
echo "grep $*" >> "${WSK_STUB_LOG:-/dev/null}"
# If checking /proc/version, simulate WSL detection
if [[ "$*" == *"/proc/version"* || "$*" == *"microsoft"* ]]; then
  exit "${WSK_STUB_GREP_PROC_VERSION_EXIT:-1}"
fi
exec /usr/bin/grep "$@"
SHIM
  chmod +x "$WSK_STUB_BIN/grep"
  WSK_STUB_GREP_PROC_VERSION_EXIT=0
  export WSK_STUB_GREP_PROC_VERSION_EXIT

  source "${WSK_DIR}/lib/os.sh"
  detect_os
  [[ "$WSK_OS" == "windows" ]]
}

# ---------------------------------------------------------------------------
# detect_pkg_mgr tests
# ---------------------------------------------------------------------------

@test "detect_pkg_mgr sets WSK_PKG_MGR=brew when brew shim present, others absent" {
  stub_present brew
  stub_absent apt-get
  stub_absent dnf
  stub_absent pacman
  stub_absent winget

  unset WSK_PKG_MGR
  source "${WSK_DIR}/lib/os.sh"
  detect_pkg_mgr
  [[ "$WSK_PKG_MGR" == "brew" ]]
}

@test "detect_pkg_mgr sets WSK_PKG_MGR=apt when apt-get present, brew absent" {
  stub_absent brew
  stub_present apt-get
  stub_absent dnf
  stub_absent pacman
  stub_absent winget

  unset WSK_PKG_MGR
  source "${WSK_DIR}/lib/os.sh"
  detect_pkg_mgr
  [[ "$WSK_PKG_MGR" == "apt" ]]
}

@test "detect_pkg_mgr sets WSK_PKG_MGR=dnf when dnf present, brew and apt absent" {
  stub_absent brew
  stub_absent apt-get
  stub_present dnf
  stub_absent pacman
  stub_absent winget

  unset WSK_PKG_MGR
  source "${WSK_DIR}/lib/os.sh"
  detect_pkg_mgr
  [[ "$WSK_PKG_MGR" == "dnf" ]]
}

@test "detect_pkg_mgr sets WSK_PKG_MGR=pacman when pacman present, higher-priority absent" {
  stub_absent brew
  stub_absent apt-get
  stub_absent dnf
  stub_present pacman
  stub_absent winget

  unset WSK_PKG_MGR
  source "${WSK_DIR}/lib/os.sh"
  detect_pkg_mgr
  [[ "$WSK_PKG_MGR" == "pacman" ]]
}

@test "detect_pkg_mgr returns non-zero and prints warning when no manager present" {
  stub_absent brew
  stub_absent apt-get
  stub_absent dnf
  stub_absent pacman
  stub_absent winget

  unset WSK_PKG_MGR
  source "${WSK_DIR}/lib/os.sh"
  run detect_pkg_mgr
  [[ "$status" -ne 0 ]]
  echo "$output" | grep -qi "no recognized package manager"
}
