# Work-Swift-Kit

[![CI](https://github.com/Samirlb/Work-Swift-Kit/actions/workflows/ci.yml/badge.svg)](https://github.com/Samirlb/Work-Swift-Kit/actions/workflows/ci.yml)

Interactive dev environment setup for multi-account workflows (work, personal, and more). Configures git, SSH, zsh, Claude Code, and AI dev tools per account using GNU Stow.

Supported platforms: **macOS** and **Linux**. Windows prints setup instructions without crashing (no silent exit).

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

| Command         | What it does                                                                        |
| --------------- | ----------------------------------------------------------------------------------- |
| `wsk`           | Open the interactive menu                                                           |
| `wsk setup`     | Full setup: accounts, packages, terminals, AI dev tools, gh auth, dotfiles          |
| `wsk accounts`  | Configure accounts and authentication only                                          |
| `wsk terminals` | Install terminals/editors only                                                      |
| `wsk ai`        | Install Claude Code, AI framework, codegraph, and curated skills per account        |
| `wsk doctor`    | Check configuration — read-only health check of tools, links, accounts, AI setup   |
| `wsk update`    | Update the kit, upgrade CLI tools, optionally refresh dotfiles                      |
| `wsk relink`    | Re-render and re-link dotfiles without re-collecting accounts                       |
| `wsk --help`    | Show command reference                                                              |

> `wsk install` still works as an alias for `wsk setup` (back-compat).

### The menu

```
  Full setup           Install everything and configure all tools
  Accounts only        Configure accounts and authentication
  Terminals only       Setup shells, aliases and terminal tools
  AI dev tools         Install Claude Code, framework, codegraph and skills per account
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
- Claude Code installed globally via the official installer
- Per-account AI framework: choose from `gentle-ai`, `gsd`, or `superpowers`
- `codegraph` MCP server wired into `~/.claude-{account}/.mcp.json` (optional, per account)
- Curated Claude skills cloned into `~/.claude-{account}/skills/` (for gsd/superpowers accounts)

## AI Dev Layer (`wsk ai`)

`wsk ai` sets up the full AI development layer, independent of the rest of the setup flow. It can be run standalone at any time.

### What it does

1. Detects OS and package manager
2. Installs **Node.js** and **pnpm** (required for several AI tools)
3. Installs **Claude Code** globally via `curl https://claude.ai/install.sh`
4. For each account in your config, prompts to:
   - Choose an **AI framework**: `gentle-ai`, `gsd`, or `superpowers`
   - Optionally install **codegraph** (`npm i -g @colbymchenry/codegraph`) and wire its MCP config
   - Install **curated Claude skills** into `~/.claude-{account}/skills/`

### Framework choices

| Framework | Description |
|-----------|-------------|
| `gentle-ai` | Homebrew tap (`Gentleman-Programming/homebrew-tap`); runs `gentle-ai install --agent claude-code` with per-account `CLAUDE_CONFIG_DIR`. Curated skills are bundled — no separate clone needed. |
| `gsd` | Installed via `npx get-shit-done-cc --global`; falls back to git clone if npx fails. |
| `superpowers` | Cloned from `https://github.com/obra/superpowers` into `~/.claude-{account}/superpowers`; activate with `/plugin install` inside Claude. |

### Per-account isolation

Every AI framework call exports `CLAUDE_CONFIG_DIR=~/.claude-{account}` so each account has its own Claude configuration, skills, and MCP servers. The default `~/.claude/` directory is never written.

Re-running `wsk ai` is idempotent: if `AI_FRAMEWORK` is already set in the account env file, the framework prompt is skipped.

### Curated skills

For `gsd` and `superpowers` accounts, WSK clones 6 curated skills from the `Gentleman-Programming/gentle-ai` repo:
`branch-pr`, `chained-pr`, `work-unit-commits`, `comment-writer`, `issue-creation`, `judgment-day`.

Each skill directory is individually idempotent — already-present skills are skipped.

## Dependencies

### Bootstrap (installed automatically)

| Tool | Purpose |
|------|---------|
| `gum` | Interactive TUI (menus, spinners, prompts) |
| `stow` | Dotfile symlinking |
| `fzf` | Fuzzy picker |
| `gettext` | Template rendering (`envsubst`) |

### Base packages (installed via `wsk setup`)

`git`, `gh`, `fzf`, `ripgrep`, `bat`, `eza`, `fd`, `sd`, `starship`, `zoxide`, `jq`, `tree`

### AI dev layer (`wsk ai`)

| Tool | Purpose | Installed by |
|------|---------|-------------|
| `node` | JavaScript runtime (required for pnpm, gsd, codegraph) | `wsk ai` via pkg manager |
| `pnpm` | Package manager (macOS: brew; Linux: corepack or curl) | `wsk ai` |
| `claude` | Claude Code CLI | `wsk ai` via official installer |
| `codegraph` | Codebase MCP server for Claude | `wsk ai` (optional, per account) |

> Note: Claude Code and codegraph are installed at runtime by `wsk ai`, not as Homebrew Formula dependencies. Node and pnpm follow the same pattern.

## Cross-OS notes

- **macOS**: full support — all features available
- **Linux**: full support — package installs route through `apt`, `dnf`, or `pacman` automatically
- **Windows** (Git Bash / WSL): WSK detects Windows and prints manual setup instructions for each step without crashing; no silent exits

## Walkthrough

1. Run `wsk` and choose **Full setup**
2. Bootstrap installs: gum, stow, fzf, gettext (if missing)
3. Enter details for each account: name, email, GitHub user, projects dir, SSH key
4. Choose terminals/editors: Warp, iTerm2, Alacritty, WezTerm, Kitty, Neovim
5. Base packages installed: git gh fzf ripgrep bat eza fd sd starship zoxide jq tree
6. AI dev layer: Node, pnpm, Claude Code; per-account framework, codegraph (optional), curated skills
7. Dotfiles rendered and symlinked via GNU Stow

## `wsk doctor` — Health check

`wsk doctor` now reports on:

- **OS / Package manager**: detected OS and active package manager
- **Node / pnpm**: installed status
- **Claude Code**: installed status with `wsk ai` hint if missing
- **AI frameworks** (per account): framework installed and on PATH
- **Codegraph**: global install status
- **Skills** (per account): presence of each curated skill directory

## Re-running

Idempotent — existing files are backed up as `{file}.bak.YYYYMMDD-HHMMSS` before stow restows.

## Development

```bash
brew install bats-core shellcheck
bats tests/e2e/
shellcheck lib/*.sh templates/*.sh install.sh
```

CI runs on both `macos-latest` and `ubuntu-latest`. The bats test suite uses PATH shims for external tools (gum, brew, node, npm, etc.) so no real installs occur on CI runners.
