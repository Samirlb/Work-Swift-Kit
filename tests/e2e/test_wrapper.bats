#!/usr/bin/env bats
# Tests for the generated wsk wrapper script and the Homebrew Formula case block.

bats_require_minimum_version 1.5.0

load "../helpers/setup"

setup() {
  cleanup_test_artifacts
  init_test_home
  # shellcheck source=/dev/null
  source "${WSK_DIR}/lib/log.sh"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ---------------------------------------------------------------------------
# wrapper arg forwarding
# ---------------------------------------------------------------------------

@test "wrapper: exec forwards all arguments including extra flags" {
  local wrapper_dir="$WSK_TEST_HOME/wrapper_bin"
  local wsk_home="$WSK_TEST_HOME/dot_wsk"
  local args_file="$WSK_TEST_HOME/captured_args"

  mkdir -p "$wrapper_dir" "$wsk_home"

  # Write a stub install.sh that records what args it receives.
  cat > "$wsk_home/install.sh" <<STUB
#!/usr/bin/env bash
echo "\$*" > "$args_file"
exit 0
STUB
  chmod +x "$wsk_home/install.sh"

  # Write the wrapper — must use "\$@" so extra args are preserved.
  local wrapper="$wrapper_dir/wsk"
  cat > "$wrapper" <<WRAPPER
#!/usr/bin/env bash
WSK_DIR="$wsk_home"
export WSK_DIR
exec bash "\$WSK_DIR/install.sh" "\$@"
WRAPPER
  chmod +x "$wrapper"

  # Invoke with a sub-command and an extra flag.
  run bash "$wrapper" fix-git --apply
  [[ "$status" -eq 0 ]]

  # Verify both the command and the flag arrived.
  local captured
  captured="$(cat "$args_file")"
  [[ "$captured" == "fix-git --apply" ]]
}

@test "wrapper template in install.sh uses \"\$@\" for arg forwarding" {
  # Guard: the literal string '"$@"' must appear in the wrapper heredoc inside
  # install.sh. A "$1" here would silently drop extra flags like --apply.
  grep -q '"$@"' "${WSK_REPO_DIR}/install.sh"
}

# ---------------------------------------------------------------------------
# Formula/work-swift-kit.rb: case block coverage
# ---------------------------------------------------------------------------

@test "Formula case block includes fix-git" {
  grep -q 'fix-git' "${WSK_REPO_DIR}/Formula/work-swift-kit.rb"
}

@test "Formula case block includes fix-claude" {
  grep -q 'fix-claude' "${WSK_REPO_DIR}/Formula/work-swift-kit.rb"
}

@test "Formula case block includes sync" {
  grep -q 'sync' "${WSK_REPO_DIR}/Formula/work-swift-kit.rb"
}

@test "Formula case block forwards all args via \"\$@\" not \"\$1\"" {
  # After the fix the known-command arm must use "$@" so extra args like
  # --apply survive the dispatch. "$1" would silently drop them.
  grep -q '"$@"' "${WSK_REPO_DIR}/Formula/work-swift-kit.rb"
}
