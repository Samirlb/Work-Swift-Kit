#!/usr/bin/env bats

load "../helpers/setup"

setup() {
  cleanup_test_artifacts
  init_test_home
  mkdir -p "${WSK_DIR}/stow" "${WSK_ACCOUNTS_DIR}" "$HOME/.ssh"

  WSK_ACCOUNTS=()
  export WSK_ACCOUNTS

  source "${WSK_DIR}/lib/log.sh"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

@test "ssh-keygen stub creates private key file" {
  local key_path="$HOME/.ssh/id_ed25519_test"
  ssh-keygen -t ed25519 -C "test@test.com" -f "$key_path" -N ""
  [ -f "$key_path" ]
}

@test "ssh-keygen stub creates public key file" {
  local key_path="$HOME/.ssh/id_ed25519_test"
  ssh-keygen -t ed25519 -C "test@test.com" -f "$key_path" -N ""
  [ -f "${key_path}.pub" ]
}

@test "ssh config contains correct IdentityFile for generated key" {
  seed_account "work" "Work" "Alice" "alice@work.com" "alicework" "$HOME/Documents/Work" "id_ed25519_work"
  WSK_ACCOUNTS=(work)

  source "${WSK_DIR}/lib/render.sh"
  render_all

  grep -q "IdentityFile ~/.ssh/id_ed25519_work" "${WSK_DIR}/stow/.ssh/config"
}

@test "ssh config Host block uses account name" {
  seed_account "work" "Work" "Alice" "alice@work.com" "alicework" "$HOME/Documents/Work" "id_ed25519_work"
  WSK_ACCOUNTS=(work)

  source "${WSK_DIR}/lib/render.sh"
  render_all

  grep -q "^Host github-work" "${WSK_DIR}/stow/.ssh/config"
}
