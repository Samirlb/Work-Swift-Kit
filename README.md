# Work-Swift-Kit

[![CI](https://github.com/Samirlb/Work-Swift-Kit/actions/workflows/ci.yml/badge.svg)](https://github.com/Samirlb/Work-Swift-Kit/actions/workflows/ci.yml)

Interactive macOS dev environment setup for multi-account workflows (work, personal, and more). Configures git, SSH, zsh, and Claude per account using GNU Stow.

## Install via Homebrew

```bash
brew tap Samirlb/work-swift-kit https://github.com/Samirlb/Work-Swift-Kit
brew install work-swift-kit
```

## Install via curl

```bash
curl -fsSL https://raw.githubusercontent.com/Samirlb/Work-Swift-Kit/main/install.sh | bash
```

## Usage

Run `wsk` with no arguments to open the interactive menu:

```bash
wsk
```

Or call any action directly:

| Command         | What it does                                                       |
| --------------- | ------------------------------------------------------------------ |
| `wsk`           | Open the interactive menu                                          |
| `wsk setup`     | Full setup: accounts, packages, terminals, gh auth, dotfiles       |
| `wsk accounts`  | Configure accounts and authentication only                         |
| `wsk terminals` | Install terminals/editors only                                     |
| `wsk doctor`    | Check configuration — read-only health check of tools, links, accounts |
| `wsk update`    | Update the kit, upgrade CLI tools, optionally refresh dotfiles     |
| `wsk relink`    | Re-render and re-link dotfiles without re-collecting accounts      |
| `wsk --help`    | Show command reference                                             |

> `wsk install` still works as an alias for `wsk setup` (back-compat).

### The menu

```
  Full setup           Install everything and configure all tools
  Accounts only        Configure accounts and authentication
  Terminals only       Setup shells, aliases and terminal tools
  Check configuration  Verify installed tools, links and accounts
  Update               Pull latest kit and upgrade packages
  Re-link configs      Re-symlink existing configuration files
  Quit                 Exit the installer
```

## What it sets up

- `.gitconfig` with per-account `includeIf` blocks
- `.gitconfig-{account}` per account (name, email, GitHub user, SSH command)
- `.ssh/config` with `Host github-{account}` per account
- `.zshrc` with PATH, compinit, starship, zoxide, and `claude-{account}()` functions
- `.gitignore_global` covering macOS, Node, Flutter, Android, iOS, Expo, secrets, editors, Claude
- `.claude-{account}/CLAUDE.md` starter config per account

## Walkthrough

1. Run `wsk` and choose **Full setup**
2. Bootstrap installs: gum, stow, fzf, gettext (if missing)
3. Enter details for each account: name, email, GitHub user, projects dir, SSH key
4. Choose terminals/editors: Warp, iTerm2, Alacritty, WezTerm, Kitty, Neovim
5. Base packages installed: git gh fzf ripgrep bat eza fd sd starship zoxide jq tree
6. Dotfiles rendered and symlinked via GNU Stow

## Re-running

Idempotent — existing files are backed up as `{file}.bak.YYYYMMDD-HHMMSS` before stow restows.

## Development

```bash
brew install bats-core shellcheck
bats tests/e2e/
shellcheck lib/*.sh templates/*.sh install.sh
```
