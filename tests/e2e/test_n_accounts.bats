#!/usr/bin/env bats

load "../helpers/setup"

setup() {
  cleanup_test_artifacts
  init_test_home
  mkdir -p "${WSK_DIR}/stow" "${WSK_DIR}/accounts"

  seed_account "work"     "Work"     "Alice Work"     "alice@work.com"     "alicework"     "$HOME/Documents/Work"     "id_ed25519_work"
  seed_account "personal" "Personal" "Alice Personal" "alice@personal.com" "alicepersonal" "$HOME/Documents/Personal" "id_ed25519_personal"
  seed_account "client"   "Client"   "Alice Client"   "alice@client.com"   "aliceclient"   "$HOME/Documents/Client"   "id_ed25519_client"

  WSK_ACCOUNTS=(work personal client)
  export WSK_ACCOUNTS

  source "${WSK_DIR}/lib/log.sh"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

@test "three gitconfig-{name} files created" {
  source "${WSK_DIR}/lib/render.sh"
  render_all
  [ -f "${WSK_DIR}/stow/.gitconfig-work" ]
  [ -f "${WSK_DIR}/stow/.gitconfig-personal" ]
  [ -f "${WSK_DIR}/stow/.gitconfig-client" ]
}

@test ".gitconfig has three includeIf blocks" {
  source "${WSK_DIR}/lib/render.sh"
  render_all
  local count
  count=$(grep -c 'includeIf' "${WSK_DIR}/stow/.gitconfig")
  [ "$count" -eq 3 ]
}

@test ".ssh/config has three Host blocks" {
  source "${WSK_DIR}/lib/render.sh"
  render_all
  local count
  count=$(grep -c '^Host github-' "${WSK_DIR}/stow/.ssh/config")
  [ "$count" -eq 3 ]
}

@test "three CLAUDE.md files created" {
  source "${WSK_DIR}/lib/render.sh"
  render_all
  [ -f "${WSK_DIR}/stow/.claude-work/CLAUDE.md" ]
  [ -f "${WSK_DIR}/stow/.claude-personal/CLAUDE.md" ]
  [ -f "${WSK_DIR}/stow/.claude-client/CLAUDE.md" ]
}

@test ".zshrc has one claude-profile switch function per account" {
  source "${WSK_DIR}/lib/render.sh"
  render_all
  # Each account renders a `function <acct>()` that calls the shared
  # _wsk_switch_profile helper (which sets CLAUDE_CONFIG_DIR). Count the calls
  # (trailing space excludes the single `_wsk_switch_profile()` definition).
  local count
  count=$(grep -c '_wsk_switch_profile ' "${WSK_DIR}/stow/.zshrc")
  [ "$count" -eq 3 ]
}
