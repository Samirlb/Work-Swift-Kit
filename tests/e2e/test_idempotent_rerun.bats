#!/usr/bin/env bats

load "../helpers/setup"

setup() {
  cleanup_test_artifacts
  init_test_home
  mkdir -p "${WSK_DIR}/stow" "${WSK_DIR}/accounts"

  seed_account "work" "Work" "Alice Work" "alice@work.com" "alicework" "$HOME/Documents/Work" "id_ed25519_work"
  seed_account "personal" "Personal" "Alice" "alice@personal.com" "alicepersonal" "$HOME/Documents/Personal" "id_ed25519_personal"

  WSK_ACCOUNTS=(work personal)
  export WSK_ACCOUNTS

  source "${WSK_DIR}/lib/log.sh"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

@test "second run creates .bak. file for existing real .gitconfig" {
  source "${WSK_DIR}/lib/render.sh"
  source "${WSK_DIR}/lib/stow.sh"

  render_all
  link_dotfiles

  rm -f "$HOME/.gitconfig"
  echo "real config" > "$HOME/.gitconfig"

  render_all
  link_dotfiles

  local bak_count
  bak_count=$(find "$HOME" -maxdepth 1 -name ".gitconfig.bak.*" | wc -l | tr -d ' ')
  [ "$bak_count" -ge 1 ]
}

@test "second run does not error -- stow restow is idempotent" {
  source "${WSK_DIR}/lib/render.sh"
  source "${WSK_DIR}/lib/stow.sh"

  render_all
  link_dotfiles
  render_all
  link_dotfiles
}

@test "symlinks still valid after second run" {
  source "${WSK_DIR}/lib/render.sh"
  source "${WSK_DIR}/lib/stow.sh"

  render_all
  link_dotfiles
  render_all
  link_dotfiles

  [ -L "$HOME/.gitconfig" ]
  # ~/.zshrc is a managed-block file (not a symlink); the block stays singular.
  [ -f "$HOME/.zshrc" ]
  [ "$(grep -c '# >>> work-swift-kit >>>' "$HOME/.zshrc")" -eq 1 ]
}
