# Proposal: quick-dev-setup

## Intent

Work-Swift-Kit configures multi-account git/ssh/zsh/dotfiles + base CLI + terminals, but its
core promise — *start developing fast* — is missing. This change installs the AI dev layer
(Claude Code, ONE AI framework, codegraph, curated global skills) plus Node/pnpm, cross-OS
(macOS + Linux now, Windows foundations), all **per account**, all surfaced in `Check configuration`.

## Scope

### In Scope
- `lib/os.sh`: OS + package-manager detection; `pkg_install` router (brew/apt/dnf/pacman/winget).
- Cross-OS refactor of `bootstrap.sh`, `packages.sh`, `terminals.sh` to drop the Darwin guard and use `pkg_install`.
- `lib/node.sh`: Node + pnpm per OS (brew on mac; corepack/curl on linux; winget on Windows).
- `lib/claude.sh`: idempotent Claude Code install (curl native); codegraph install + per-account MCP config.
- `lib/frameworks.sh`: exclusive AI framework choice (gentle-ai / gsd / superpowers) **per account**, persisted; superpowers git-clone fallback; codegraph `ui_confirm`; curated global skills install per account.
- AI steps run inside `Full setup` AND a standalone top-level **AI dev tools** menu entry + `wsk ai` dispatch (shared functions).
- `doctor.sh`: new sub-sections (OS/pkg-mgr, Node+pnpm, Claude Code, per-account framework, codegraph, skills).
- bats stubs in `tests/helpers/setup.bash` for npm/node/pnpm/claude/gentle-ai/codegraph/git.

### Out of Scope
- Full Windows support (this change only detects OS + prints instructions; no winget execution path tested).
- Installing more than one framework per account; per-project codegraph init; team/CI skill sync.

## Capabilities

### New Capabilities
- `os-abstraction`: cross-OS detection and `pkg_install` routing.
- `ai-dev-tools`: per-account install of Claude Code, AI framework, codegraph, curated skills + menu/dispatch.
- `node-toolchain`: Node + pnpm install per OS.

### Modified Capabilities
- `bootstrap`: remove Darwin-only guard; source os-abstraction.
- `doctor`: add AI/Node/OS health sub-sections.

## Approach

Locked decisions (honored): (1) AI steps in Full setup **and** a standalone "AI dev tools" entry, same functions.
(2) ONE framework via `ui_choose`, mutually exclusive. (3) superpowers = git clone `obra/superpowers` into the
account Claude dir + print `/plugin install` instruction. (4) codegraph always offered after framework via
`ui_confirm`. (5) curated GLOBAL skills installed into each account's `skills/`. (6) macOS + Linux now, Windows
instructions-only. (7) **PER-ACCOUNT** — everything installs into each account's `CLAUDE_CONFIG_DIR=~/.claude-{acct}`
(see `templates/zshrc.sh`); framework choice may differ per account, persisted to `accounts/{acct}.env`
(`AI_FRAMEWORK=`) so doctor verifies per account.

**Per-account model**: loop `WSK_ACCOUNTS`; for each, set `CLAUDE_CONFIG_DIR=~/.claude-{acct}` and install framework
(`gentle-ai install --agent claude-code`, `npx get-shit-done-cc`, or superpowers clone), codegraph MCP config, and
curated skills into `~/.claude-{acct}/skills/`. Claude Code, Node, pnpm install once (global binaries).

**Curated starter skills** (drawn from the user's real global set): `branch-pr`, `work-unit-commits`,
`comment-writer`, `issue-creation`, `judgment-day`. Fetched via git/curl into each account's `skills/{name}/`.
Exact final list = spec open question.

**Test strategy** (strict TDD on): mock ALL external installers as stubs in `tests/helpers/setup.bash`
(npm/node/pnpm/claude/gentle-ai/codegraph/git); bats e2e asserts per-account dirs, persisted `AI_FRAMEWORK`,
idempotency, and doctor output; shellcheck gates every new `.sh`.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/os.sh` | New | OS + pkg-mgr detection, `pkg_install` router |
| `lib/node.sh` | New | Node + pnpm per OS |
| `lib/claude.sh` | New | Claude Code + codegraph install |
| `lib/frameworks.sh` | New | Per-account framework + skills install |
| `lib/bootstrap.sh` | Modified | Drop Darwin guard; use `pkg_install` |
| `lib/packages.sh`, `lib/terminals.sh` | Modified | Use `pkg_install` |
| `lib/doctor.sh` | Modified | New AI/Node/OS sub-sections |
| `install.sh` | Modified | `run_full_setup` steps; `wsk ai` + menu entry |
| `accounts/{acct}.env` | Modified | `AI_FRAMEWORK=` field per account |
| `tests/helpers/setup.bash` | Modified | New installer stubs |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| superpowers headless install impossible | High | git-clone fallback + printed `/plugin install` instruction |
| gsd npm package ownership uncertain | Med | Confirm canonical source in spec; fallback to git clone |
| Intel Mac pnpm standalone script fails | Med | Force brew path on macOS |
| Per-account loop misconfigures wrong Claude dir | Med | Always derive `~/.claude-{acct}`; assert in bats |
| Linux paths untested (CI is macOS-only) | Med | Open question: add ubuntu CI job |
| Node prereq chain (gsd, codegraph) | Med | Enforce order: Node → pnpm → tools |
| Windows bash gaps (stow/gum/fzf) | Low | Detect + skip + instruct only |

## Rollback Plan

New `lib/*.sh` are additive — delete them and revert the 3 refactored files + `install.sh` to restore macOS-only
behavior. Per-account installs are isolated under `~/.claude-{acct}/`; remove those dirs and the `AI_FRAMEWORK=`
line from `accounts/{acct}.env`. No destructive changes to existing dotfile links.

## Dependencies

- Network access to claude.ai installer, npm registry, the gentle-ai homebrew tap, and `obra/superpowers`.
- Node present before gsd/codegraph (install order enforced).

## Success Criteria

- [ ] `wsk setup` and `wsk ai` install Claude Code + chosen framework + (opt) codegraph + curated skills **per account**.
- [ ] Framework choice differs per account and persists to `accounts/{acct}.env`.
- [ ] Works on macOS and Linux; Windows prints instructions without crashing.
- [ ] `Check configuration` reports OS/pkg-mgr, Node+pnpm, Claude Code, per-account framework, codegraph, skills.
- [ ] All installers idempotent; bats e2e + shellcheck green with mocked installers.

## Open Questions (for spec/design)

1. Canonical gsd source — is `get-shit-done-cc` npm the owner, or git clone?
2. Exact curated global skills list (and per-account vs framework-bundled).
3. Add an ubuntu CI job to exercise Linux `pkg_install` paths?
