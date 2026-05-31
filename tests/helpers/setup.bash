#!/usr/bin/env bash
# shellcheck shell=bash

WSK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export WSK_DIR

# ---------------------------------------------------------------------------
# PATH-shim infrastructure
# ---------------------------------------------------------------------------
# init_test_home sets up:
#   $WSK_TEST_HOME — isolated $HOME
#   $WSK_STUB_BIN  — executable shim dir prepended to PATH
#   $WSK_STUB_LOG  — invocation log for assert_stub_called

init_test_home() {
  WSK_TEST_HOME="$(mktemp -d)"
  export WSK_TEST_HOME
  export HOME="$WSK_TEST_HOME"
  mkdir -p "$HOME/.ssh"

  # Stub bin dir
  WSK_STUB_BIN="$WSK_TEST_HOME/bin"
  export WSK_STUB_BIN
  mkdir -p "$WSK_STUB_BIN"
  PATH="$WSK_STUB_BIN:$PATH"
  export PATH

  # Invocation log
  WSK_STUB_LOG="$WSK_TEST_HOME/stub-calls.log"
  export WSK_STUB_LOG
  : > "$WSK_STUB_LOG"

  # Install all default shims
  _install_all_default_shims
}

# stub_present <name>
# Places an executable shim at $WSK_STUB_BIN/<name>.
# The shim records its invocation and returns 0 by default.
# Reads WSK_STUB_<NAME>_EXIT to override exit code (uppercase, hyphens→underscores).
# Reads WSK_STUB_<NAME>_OUTPUT to echo custom output.
stub_present() {
  local name="$1"
  local upper
  upper="$(echo "$name" | tr '[:lower:]-' '[:upper:]_')"
  _write_shim "$name" "$upper"
}

# stub_absent <name>
# Removes $WSK_STUB_BIN/<name> so command -v fails.
stub_absent() {
  local name="$1"
  rm -f "$WSK_STUB_BIN/$name"
}

# assert_stub_called <pattern>
# Fails if pattern not found in $WSK_STUB_LOG.
assert_stub_called() {
  local pattern="$1"
  if ! grep -q "$pattern" "$WSK_STUB_LOG"; then
    echo "ASSERT FAILED: expected stub call matching: $pattern" >&2
    echo "--- stub log ---" >&2
    cat "$WSK_STUB_LOG" >&2
    echo "--- end stub log ---" >&2
    return 1
  fi
}

# assert_stub_not_called <pattern>
# Fails if pattern IS found in $WSK_STUB_LOG.
assert_stub_not_called() {
  local pattern="$1"
  if grep -q "$pattern" "$WSK_STUB_LOG"; then
    echo "ASSERT FAILED: unexpected stub call matching: $pattern" >&2
    echo "--- stub log ---" >&2
    cat "$WSK_STUB_LOG" >&2
    echo "--- end stub log ---" >&2
    return 1
  fi
}

# stub_log
# Prints the stub invocation log (for debugging).
stub_log() {
  cat "$WSK_STUB_LOG"
}

# ---------------------------------------------------------------------------
# Internal shim writer
# ---------------------------------------------------------------------------
_write_shim() {
  local name="$1" upper="$2"
  local shim="$WSK_STUB_BIN/$name"
  cat > "$shim" <<SHIM
#!/usr/bin/env bash
upper="${upper}"
log_file="\${WSK_STUB_LOG:-/dev/null}"
echo "${name} \$*" >> "\$log_file"
exit_var="WSK_STUB_\${upper}_EXIT"
out_var="WSK_STUB_\${upper}_OUTPUT"
if [[ -n "\${!out_var:-}" ]]; then
  echo "\${!out_var}"
fi
exit "\${!exit_var:-0}"
SHIM
  chmod +x "$shim"
}

# ---------------------------------------------------------------------------
# Special-behaviour shim writers
# ---------------------------------------------------------------------------

_write_node_shim() {
  local shim="$WSK_STUB_BIN/node"
  cat > "$shim" <<'SHIM'
#!/usr/bin/env bash
echo "node $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit_var="WSK_STUB_NODE_EXIT"
if [[ "$1" == "--version" ]]; then
  out_var="WSK_STUB_NODE_OUTPUT"
  echo "${!out_var:-v20.0.0}"
fi
exit "${!exit_var:-0}"
SHIM
  chmod +x "$shim"
}

_write_git_shim() {
  local shim="$WSK_STUB_BIN/git"
  cat > "$shim" <<'SHIM'
#!/usr/bin/env bash
echo "git $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit_var="WSK_STUB_GIT_EXIT"
if [[ "${!exit_var:-0}" != "0" ]]; then
  exit "${!exit_var}"
fi
# git clone <remote> <dest> — create the destination so [[ -d ]] checks pass
if [[ "$1" == "clone" ]]; then
  dest="${*: -1}"
  if [[ -n "$dest" && "$dest" != "$1" ]]; then
    mkdir -p "$dest"
    touch "$dest/.stub-cloned"
  fi
fi
exit 0
SHIM
  chmod +x "$shim"
}

_write_jq_shim() {
  # Delegate to real jq so JSON merge tests work correctly.
  local shim="$WSK_STUB_BIN/jq"
  local real_jq
  # Find real jq outside the stub bin
  real_jq="$(PATH="${PATH//$WSK_STUB_BIN:/}" command -v jq 2>/dev/null || true)"
  if [[ -n "$real_jq" ]]; then
    cat > "$shim" <<SHIM
#!/usr/bin/env bash
echo "jq \$*" >> "\${WSK_STUB_LOG:-/dev/null}"
exec "$real_jq" "\$@"
SHIM
  else
    cat > "$shim" <<'SHIM'
#!/usr/bin/env bash
echo "jq $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit "${WSK_STUB_JQ_EXIT:-0}"
SHIM
  fi
  chmod +x "$shim"
}

_write_sd_shim() {
  # Delegate to real sd for in-place file editing.
  local shim="$WSK_STUB_BIN/sd"
  local real_sd
  real_sd="$(PATH="${PATH//$WSK_STUB_BIN:/}" command -v sd 2>/dev/null || true)"
  if [[ -n "$real_sd" ]]; then
    cat > "$shim" <<SHIM
#!/usr/bin/env bash
echo "sd \$*" >> "\${WSK_STUB_LOG:-/dev/null}"
exec "$real_sd" "\$@"
SHIM
  else
    cat > "$shim" <<'SHIM'
#!/usr/bin/env bash
echo "sd $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit "${WSK_STUB_SD_EXIT:-0}"
SHIM
  fi
  chmod +x "$shim"
}

_write_gum_shim() {
  # gum spin -- <cmd...> executes the command (same as the exported-function stub).
  # Other subcommands are recorded and return 0.
  local shim="$WSK_STUB_BIN/gum"
  cat > "$shim" <<'SHIM'
#!/usr/bin/env bash
echo "gum $*" >> "${WSK_STUB_LOG:-/dev/null}"
cmd="$1"
shift
case "$cmd" in
  input)
    echo ""
    ;;
  confirm)
    exit "${WSK_STUB_GUM_CONFIRM_EXIT:-1}"
    ;;
  choose)
    echo "${WSK_STUB_GUM_CHOOSE_OUTPUT:-$1}"
    ;;
  spin)
    while [[ "$1" != "--" && $# -gt 0 ]]; do shift; done
    [[ "$1" == "--" ]] && shift
    "$@"
    ;;
  *)
    exit "${WSK_STUB_GUM_EXIT:-0}"
    ;;
esac
SHIM
  chmod +x "$shim"
}

_write_npx_shim() {
  local shim="$WSK_STUB_BIN/npx"
  cat > "$shim" <<'SHIM'
#!/usr/bin/env bash
echo "npx $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit_var="WSK_STUB_NPX_EXIT"
out_var="WSK_STUB_NPX_OUTPUT"
if [[ -n "${!out_var:-}" ]]; then
  echo "${!out_var}"
fi
exit "${!exit_var:-0}"
SHIM
  chmod +x "$shim"
}

_write_curl_shim() {
  local shim="$WSK_STUB_BIN/curl"
  cat > "$shim" <<'SHIM'
#!/usr/bin/env bash
echo "curl $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit_var="WSK_STUB_CURL_EXIT"
out_var="WSK_STUB_CURL_OUTPUT"
if [[ -n "${!out_var:-}" ]]; then
  echo "${!out_var}"
fi
exit "${!exit_var:-0}"
SHIM
  chmod +x "$shim"
}

_write_brew_shim() {
  local shim="$WSK_STUB_BIN/brew"
  cat > "$shim" <<'SHIM'
#!/usr/bin/env bash
echo "brew $*" >> "${WSK_STUB_LOG:-/dev/null}"
exit_var="WSK_STUB_BREW_EXIT"
out_var="WSK_STUB_BREW_OUTPUT"
if [[ -n "${!out_var:-}" ]]; then
  echo "${!out_var}"
fi
exit "${!exit_var:-0}"
SHIM
  chmod +x "$shim"
}

# ---------------------------------------------------------------------------
# Install all default shims (called by init_test_home)
# ---------------------------------------------------------------------------
_install_all_default_shims() {
  # Special-behaviour shims
  _write_node_shim
  _write_git_shim
  _write_jq_shim
  _write_sd_shim
  _write_gum_shim
  _write_npx_shim
  _write_curl_shim
  _write_brew_shim

  # Generic shims (record + return 0)
  for _stub_name in npm pnpm corepack claude gentle-ai codegraph winget apt-get dnf pacman; do
    _upper="$(echo "$_stub_name" | tr '[:lower:]-' '[:upper:]_')"
    _write_shim "$_stub_name" "$_upper"
  done
  unset _stub_name _upper
}

# ---------------------------------------------------------------------------
# Presence toggle convenience wrappers
# ---------------------------------------------------------------------------
node_present()      { stub_present node; }
node_absent()       { stub_absent node; }
pnpm_present()      { stub_present pnpm; }
pnpm_absent()       { stub_absent pnpm; }
corepack_present()  { stub_present corepack; }
corepack_absent()   { stub_absent corepack; }
claude_present()    { stub_present claude; }
claude_absent()     { stub_absent claude; }
codegraph_present() { stub_present codegraph; }
codegraph_absent()  { stub_absent codegraph; }
npx_present()       { stub_present npx; }
npx_absent()        { stub_absent npx; }
gentle_ai_present() { stub_present gentle-ai; }
gentle_ai_absent()  { stub_absent gentle-ai; }

# ---------------------------------------------------------------------------
# Existing exported-function stubs (kept for backward compat with existing tests)
# Note: PATH shims override these for command -v checks; the exported functions
# remain as fallback for tests that source libs without PATH-shim init.
# ---------------------------------------------------------------------------

# Stub: gum reads pre-seeded account env files rather than prompting interactively.
gum() {
  local cmd="$1"
  shift
  case "$cmd" in
    input)
      echo ""
      ;;
    confirm)
      return 1
      ;;
    choose)
      echo "$1"
      ;;
    spin)
      while [[ "$1" != "--" && $# -gt 0 ]]; do shift; done
      [[ "$1" == "--" ]] && shift
      "$@"
      ;;
    *)
      return 0
      ;;
  esac
}
export -f gum

# Stub: brew no-ops for install calls, returns success for list calls
brew() {
  case "$1" in
    install) return 0 ;;
    list)    return 0 ;;
    *)       return 0 ;;
  esac
}
export -f brew

ssh-keygen() {
  local key_file=""
  local i
  for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "-f" ]]; then
      j=$((i+1))
      key_file="${!j}"
    fi
  done
  if [[ -n "$key_file" ]]; then
    mkdir -p "$(dirname "$key_file")"
    echo "stub-private-key" > "$key_file"
    echo "stub-public-key" > "${key_file}.pub"
  fi
}
export -f ssh-keygen

# ---------------------------------------------------------------------------
# Account helpers
# ---------------------------------------------------------------------------
seed_account() {
  local name="$1" display="$2" git_name="$3" git_email="$4" github_user="$5" projects_dir="$6" ssh_key="$7"
  mkdir -p "${WSK_DIR}/accounts"
  cat > "${WSK_DIR}/accounts/${name}.env" <<EOF
ACCOUNT_NAME=${name}
DISPLAY_NAME=${display}
GIT_NAME=${git_name}
GIT_EMAIL=${git_email}
GIT_GITHUB_USER=${github_user}
PROJECTS_DIR=${projects_dir}
WSK_SSH_KEY=${ssh_key}
EOF
}

cleanup_test_artifacts() {
  rm -rf "${WSK_DIR}/stow" "${WSK_DIR}/accounts"
}

cleanup_test_home() {
  if [[ -n "${WSK_TEST_HOME:-}" && "$WSK_TEST_HOME" != "/" ]]; then
    rm -rf "$WSK_TEST_HOME"
  fi
}
