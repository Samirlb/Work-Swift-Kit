#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

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

# Helper: build an isolated bin dir with only the named manager binary present.
# Returns the dir path.
_make_iso_bin() {
  local manager="$1"
  local iso_bin
  iso_bin="$(mktemp -d)"
  if [[ -n "$manager" ]]; then
    printf '#!/usr/bin/env bash\nexit 0\n' > "$iso_bin/$manager"
    chmod +x "$iso_bin/$manager"
  fi
  echo "$iso_bin"
}

@test "detect_pkg_mgr sets WSK_PKG_MGR=brew when brew shim present, others absent" {
  local iso_bin result_file="$WSK_TEST_HOME/result.txt"
  iso_bin="$(_make_iso_bin brew)"
  bash -c "
    export PATH='$iso_bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/os.sh'
    detect_pkg_mgr
    echo \"\$WSK_PKG_MGR\" > '$result_file'
  "
  [[ "$(cat "$result_file")" == "brew" ]]
  rm -rf "$iso_bin"
}

@test "detect_pkg_mgr sets WSK_PKG_MGR=apt when apt-get present, brew absent" {
  local iso_bin result_file="$WSK_TEST_HOME/result.txt"
  iso_bin="$(_make_iso_bin apt-get)"
  bash -c "
    export PATH='$iso_bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/os.sh'
    detect_pkg_mgr
    echo \"\$WSK_PKG_MGR\" > '$result_file'
  "
  [[ "$(cat "$result_file")" == "apt" ]]
  rm -rf "$iso_bin"
}

@test "detect_pkg_mgr sets WSK_PKG_MGR=dnf when dnf present, brew and apt absent" {
  local iso_bin result_file="$WSK_TEST_HOME/result.txt"
  iso_bin="$(_make_iso_bin dnf)"
  bash -c "
    export PATH='$iso_bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/os.sh'
    detect_pkg_mgr
    echo \"\$WSK_PKG_MGR\" > '$result_file'
  "
  [[ "$(cat "$result_file")" == "dnf" ]]
  rm -rf "$iso_bin"
}

@test "detect_pkg_mgr sets WSK_PKG_MGR=pacman when pacman present, higher-priority absent" {
  local iso_bin result_file="$WSK_TEST_HOME/result.txt"
  iso_bin="$(_make_iso_bin pacman)"
  bash -c "
    export PATH='$iso_bin'
    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/os.sh'
    detect_pkg_mgr
    echo \"\$WSK_PKG_MGR\" > '$result_file'
  "
  [[ "$(cat "$result_file")" == "pacman" ]]
  rm -rf "$iso_bin"
}

@test "detect_pkg_mgr returns non-zero and prints warning when no manager present" {
  local iso_bin
  iso_bin="$(_make_iso_bin "")"

  # Run in a fresh bash process; capture stderr into $stderr via --separate-stderr
  run --separate-stderr bash -c "
    export PATH=\"${iso_bin}\"
    source \"${WSK_DIR}/lib/log.sh\"
    source \"${WSK_DIR}/lib/os.sh\"
    detect_pkg_mgr
  "
  [[ "$status" -ne 0 ]]
  # stderr contains the WARN line from log_warn; output may be empty
  [[ "${stderr:-}" =~ [Nn]o\ recognized\ package\ manager ]] || \
    [[ "${output:-}" =~ [Nn]o\ recognized\ package\ manager ]]
  rm -rf "$iso_bin"
}
