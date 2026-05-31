# Exploration — quick-dev-setup

## Goal

Work-Swift-Kit today sets up multi-account git/ssh/zsh/dotfiles + base CLI + terminals + gh.
Its intended main purpose — a **quick dev setup to start development fast** — is missing its core:
install Claude Code, an AI framework, codegraph, skills, and Node/pnpm, across OSes, all reflected
in `Check configuration` (doctor).

## Current state (confirmed)

- `lib/bootstrap.sh` — hard-exits if `uname -s` != Darwin; installs Homebrew, then gum/stow/fzf/gettext.
- `lib/packages.sh` — `install_packages()` installs a fixed list via `brew install` only (idempotent via `brew list`).
- `lib/doctor.sh` — sections: Dependencies / Base packages / Dotfile links / Accounts / GitHub auth. No Node/pnpm/Claude/framework checks.
- `lib/terminals.sh` — `ui_multiselect` + `brew install --cask`.
- `lib/ui.sh` — `ui_menu` (fzf, "Label::Description"), `ui_choose` (gum single), `ui_multiselect`, `ui_spin`, `ui_confirm`, `check_pass/fail/warn`.
- `install.sh` — `run_full_setup` = collect_accounts → install_packages → install_terminals → setup_gh_accounts → render_all → link_dotfiles.
- `tests/helpers/setup.bash` — stubs `brew`, `gum`, `ssh-keygen`. No npm/node/claude stubs.
- CI — shellcheck on ubuntu, bats on macOS only.

## Affected areas

| File | Why |
|------|-----|
| `lib/bootstrap.sh` | Remove Darwin guard; source `lib/os.sh`; detect OS + pkg manager |
| `lib/packages.sh` | Replace direct `brew install` with `pkg_install` |
| `lib/terminals.sh` | OS-conditional cask install |
| `lib/doctor.sh` | New sub-sections: Node/pnpm, Claude Code, AI framework, codegraph, skills, package manager |
| `install.sh` | New steps in `run_full_setup`; `wsk ai` dispatch |
| `tests/helpers/setup.bash` | Stubs: npm, node, pnpm, claude, gentle-ai, codegraph |
| NEW `lib/os.sh` | OS + pkg-manager detection, `pkg_install` wrapper |
| NEW `lib/node.sh` | `install_node()`, `install_pnpm()` per OS |
| NEW `lib/claude.sh` | `install_claude_code()`, `install_codegraph()` |
| NEW `lib/frameworks.sh` | `install_ai_framework()` exclusive sub-menu |

## Confirmed install commands

**Claude Code** — primary: `curl -fsSL https://claude.ai/install.sh | bash` (official, auto-update, mac+linux).
Windows: `irm https://claude.ai/install.ps1 | iex`. Brew cask exists (mac, no auto-update). npm path deprecated. Verify `command -v claude`.

**Node** — mac: `brew install node`. Linux: apt/dnf/pacman or `fnm`. Cross-platform: fnm.

**pnpm** — mac: `brew install pnpm` (standalone script FAILS on Intel darwin-x64). Linux: `curl -fsSL https://get.pnpm.io/install.sh | sh -`. Windows: `winget install pnpm.pnpm`. Any-OS-with-node: `corepack enable pnpm`.

**gentle-ai** — `brew tap Gentleman-Programming/homebrew-tap && brew install gentle-ai` (mac/linux); scoop on Windows. Configure: `gentle-ai install --agent claude-code --preset full-gentleman` (or `--component sdd`). Standalone Go CLI that injects into `~/.claude/`. Verify `command -v gentle-ai`.

**gsd** — `npx get-shit-done-cc --global` (needs Node). Canonical repo ownership = open question.

**superpowers** — `/plugin install superpowers@claude-plugins-official` inside Claude REPL (true plugin, no binary). Headless automation unverified → fallback: git clone `obra/superpowers` into `~/.claude/` + show manual instruction.

**codegraph** — `npm i -g @colbymchenry/codegraph` or curl installer. MCP server, auto-configures Claude MCP. Additive (orthogonal to framework). Needs Node.

**Skills** — live in `~/.claude/skills/{name}/SKILL.md`. Installed via `/plugin`, manual curl/git, or `gentle-ai install`. Exact "necessary skills" list = open question.

## Recommended architecture

1. `lib/os.sh` — `detect_os` (uname + MSYSTEM/WSL), `detect_pkg_mgr`, `pkg_install` router (brew/apt/dnf/pacman/winget). Windows sets `WSK_OS=windows` and installers print instructions.
2. `lib/node.sh` — `install_node`, `install_pnpm` (brew on mac; corepack/curl on linux; winget Windows).
3. `lib/claude.sh` — `install_claude_code` (curl native, idempotent via `command -v claude`), `install_codegraph` (Node prereq check).
4. `lib/frameworks.sh` — `install_ai_framework` via `ui_choose` (exclusive gentle-ai/gsd/superpowers) + `ui_confirm` for codegraph. Persist choice to `accounts/ai-framework.env` so doctor can verify.
5. `install.sh` `run_full_setup`: … → install_node → install_pnpm → install_claude_code → install_ai_framework → install_codegraph → … ; add `wsk ai` dispatch.
6. `lib/doctor.sh`: new sub-sections using `check_pass/fail/warn`.
7. `tests/helpers/setup.bash`: stubs for npm/node/pnpm/claude/gentle-ai/codegraph before any bats tests. Consider an ubuntu CI job.

## Approaches with tradeoffs

- **Claude install**: curl native (official, auto-update, cross-OS) ✅ vs brew cask (mac-only, no auto-update) vs npm (deprecated). → curl native.
- **OS detection**: single `lib/os.sh` + `pkg_install` ✅ vs per-OS scripts (breaks single-entry philosophy). → single os.sh.

## Open questions (for proposal/spec)

1. Which "necessary skills" exactly? (fixed list / framework-dependent / this project's skills)
2. Can superpowers `/plugin install` run non-interactively, or fallback to git clone + manual instruction?
3. Is `get-shit-done-cc` npm the canonical gsd, or use git clone?
4. Windows: foundations only (detect + instruct) — CONFIRMED by user.
5. Menu placement: new top-level "AI tools" entry vs only inside "Full setup"?
6. Persist chosen framework to a state file for doctor? (recommended yes)
7. Add `wsk codegraph-init` per-project, or document manual init?
8. Add an ubuntu CI job for Linux paths?

## Risks

1. Windows bash: stow/gum/fzf unavailable in Git Bash/WSL → detect + skip + instruct.
2. Superpowers headless install unverified.
3. gsd npm package ownership uncertain.
4. Intel Mac pnpm: standalone script fails → brew required on mac.
5. Node prereq chain: gsd + codegraph need Node (install order Node → pnpm → tools).
6. Test isolation: setup.bash needs new stubs or CI bats fails.
7. gentle-ai depends on its homebrew tap staying maintained.
8. Linux paths untested in CI.

## Verdict

Ready for proposal. Cross-OS package-manager abstraction + 4 new lib modules + doctor extensions + framework sub-menu.
