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

@test "render_all creates .gitconfig" {
  source "${WSK_DIR}/lib/render.sh"
  render_all
  [ -f "${WSK_DIR}/stow/.gitconfig" ]
}

@test ".gitconfig contains first account name" {
  source "${WSK_DIR}/lib/render.sh"
  render_all
  grep -q "Alice Work" "${WSK_DIR}/stow/.gitconfig"
}

@test "render_all creates per-account gitconfig files" {
  source "${WSK_DIR}/lib/render.sh"
  render_all
  [ -f "${WSK_DIR}/stow/.gitconfig-work" ]
  [ -f "${WSK_DIR}/stow/.gitconfig-personal" ]
}

@test "render_all creates .gitignore_global" {
  source "${WSK_DIR}/lib/render.sh"
  render_all
  [ -f "${WSK_DIR}/stow/.gitignore_global" ]
}

@test "render_all creates .ssh/config" {
  source "${WSK_DIR}/lib/render.sh"
  render_all
  [ -f "${WSK_DIR}/stow/.ssh/config" ]
}

@test "render_all creates the zsh fragment" {
  source "${WSK_DIR}/lib/render.sh"
  render_all
  [ -f "${WSK_DIR}/.rendered/wsk-zshrc" ]
}

@test "render_all creates CLAUDE.md per account" {
  source "${WSK_DIR}/lib/render.sh"
  render_all
  [ -f "${WSK_DIR}/stow/.claude-work/CLAUDE.md" ]
  [ -f "${WSK_DIR}/stow/.claude-personal/CLAUDE.md" ]
}

@test "link_dotfiles creates symlinks in HOME" {
  source "${WSK_DIR}/lib/render.sh"
  source "${WSK_DIR}/lib/stow.sh"
  render_all
  link_dotfiles
  [ -L "$HOME/.gitconfig" ]
  [ -L "$HOME/.gitignore_global" ]
  # ~/.zshrc is no longer symlinked: a managed block is spliced into the real file.
  [ -f "$HOME/.zshrc" ]
  grep -qF '# >>> work-swift-kit >>>' "$HOME/.zshrc"
}
