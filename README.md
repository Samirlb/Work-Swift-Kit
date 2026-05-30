# Work-Swift-Kit

[![CI](https://github.com/Samirlb/Work-Swift-Kit/actions/workflows/ci.yml/badge.svg)](https://github.com/Samirlb/Work-Swift-Kit/actions/workflows/ci.yml)

Interactive macOS dev environment setup for multi-account workflows (work, personal, and more). Configures git, SSH, zsh, and Claude per account using GNU Stow.

## Install via Homebrew

```bash
brew tap Samirlb/work-swift-kit https://github.com/Samirlb/Work-Swift-Kit
brew install Samirlb/work-swift-kit/work-swift-kit
wsk
```

## Install via curl

```bash
curl -fsSL https://raw.githubusercontent.com/Samirlb/Work-Swift-Kit/main/install.sh | bash
```

## What it sets up

- `.gitconfig` with per-account `includeIf` blocks
- `.gitconfig-{account}` per account (name, email, GitHub user, SSH command)
- `.ssh/config` with `Host github-{account}` per account
- `.zshrc` with PATH, compinit, starship, zoxide, and `claude-{account}()` functions
- `.gitignore_global` covering macOS, Node, Flutter, Android, iOS, Expo, secrets, editors, Claude
- `.claude-{account}/CLAUDE.md` starter config per account

## Walkthrough

1. Run `wsk` (or `./install.sh` from the repo)
2. Choose from the menu: Full setup · Accounts only · Terminals only · Re-link configs
3. Bootstrap installs: Homebrew, gum, stow, fzf, gettext (if missing)
4. Enter details for each account: name, email, GitHub user, projects dir, SSH key
5. Choose terminals/editors to install: Warp, iTerm2, Alacritty, WezTerm, Kitty, Neovim
6. Base packages installed: git gh fzf ripgrep bat eza fd sd starship zoxide jq tree
7. Dotfiles rendered and symlinked via GNU Stow

## Re-running

Idempotent — existing files are backed up as `{file}.bak.YYYYMMDD-HHMMSS` before stow restows.

## Development

```bash
brew install bats-core shellcheck
bats tests/e2e/       # run E2E tests
shellcheck lib/*.sh templates/*.sh install.sh   # lint
```
