#!/usr/bin/env bash

WSK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export WSK_DIR

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

init_test_home() {
  WSK_TEST_HOME="$(mktemp -d)"
  export WSK_TEST_HOME
  export HOME="$WSK_TEST_HOME"
  mkdir -p "$HOME/.ssh"
}

cleanup_test_artifacts() {
  rm -rf "${WSK_DIR}/stow" "${WSK_DIR}/accounts"
}

cleanup_test_home() {
  if [[ -n "${WSK_TEST_HOME:-}" && "$WSK_TEST_HOME" != "/" ]]; then
    rm -rf "$WSK_TEST_HOME"
  fi
}
