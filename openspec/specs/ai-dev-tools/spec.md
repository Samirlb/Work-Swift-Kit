# AI Dev Tools Specification

## Purpose

Installs Claude Code (once, globally), then per each account in `WSK_ACCOUNTS`: prompts for an exclusive AI framework choice, optionally installs codegraph, and installs curated global skills into that account's Claude config directory.

## Requirements

### Requirement: Claude Code Installation

The system MUST install Claude Code via `curl -fsSL https://claude.ai/install.sh | bash` (official cross-platform installer). Installation MUST be idempotent via `command -v claude`. Claude Code is a single global binary; it MUST NOT be re-installed per account.

#### Scenario: Claude Code absent

- GIVEN `command -v claude` fails
- WHEN `install_claude_code` is called
- THEN the official curl installer is executed
- AND `command -v claude` succeeds afterwards

#### Scenario: Claude Code already installed (idempotent)

- GIVEN `command -v claude` succeeds
- WHEN `install_claude_code` is called
- THEN the curl installer is NOT executed
- AND a "claude already installed" message is printed

#### Scenario: Windows — instruction only

- GIVEN `WSK_OS=windows`
- WHEN `install_claude_code` is called
- THEN "Run in PowerShell: irm https://claude.ai/install.ps1 | iex" is printed
- AND no bash installer is executed

---

### Requirement: Per-Account AI Framework Selection

For each account in `WSK_ACCOUNTS`, the system MUST present an exclusive choice of AI frameworks via `ui_choose`: `gentle-ai`, `gsd`, or `superpowers`. Exactly one framework MAY be selected per account; multiple selections MUST NOT be permitted. The chosen framework MUST be persisted to `accounts/{acct}.env` as `AI_FRAMEWORK=<choice>`.

#### Scenario: User selects gentle-ai for an account

- GIVEN account `work` is being configured
- WHEN `ui_choose` returns `gentle-ai`
- THEN `gentle-ai` is installed via brew tap `Gentleman-Programming/homebrew-tap` + `brew install gentle-ai`
- AND `gentle-ai install --agent claude-code` is run with `CLAUDE_CONFIG_DIR=~/.claude-work`
- AND `accounts/work.env` contains `AI_FRAMEWORK=gentle-ai`

#### Scenario: User selects gsd for an account

- GIVEN account `personal` is being configured
- WHEN `ui_choose` returns `gsd`
- THEN gsd is installed via its documented installer (primary: npm package `get-shit-done-cc`; fallback: git clone if npm package is unavailable)
- AND `accounts/personal.env` contains `AI_FRAMEWORK=gsd`

#### Scenario: User selects superpowers for an account

- GIVEN account `work` is being configured
- WHEN `ui_choose` returns `superpowers`
- THEN `obra/superpowers` is git-cloned into `~/.claude-work/`
- AND the message "Open Claude and run: /plugin install" is printed to the user
- AND `accounts/work.env` contains `AI_FRAMEWORK=superpowers`

#### Scenario: Framework choice differs per account

- GIVEN accounts `work` and `personal` both in `WSK_ACCOUNTS`
- WHEN the framework install loop runs and the user picks different frameworks for each
- THEN `accounts/work.env` and `accounts/personal.env` each contain their own `AI_FRAMEWORK=` value
- AND each account's `~/.claude-{acct}/` is configured independently

#### Scenario: Existing framework choice honored on re-run

- GIVEN `accounts/work.env` already contains `AI_FRAMEWORK=gentle-ai`
- WHEN the AI dev tools install runs for account `work`
- THEN `ui_choose` is NOT shown for that account
- AND the existing framework is used without re-prompting

---

### Requirement: CLAUDE_CONFIG_DIR Per-Account Isolation

Every framework install and Claude-adjacent write for account `{acct}` MUST set `CLAUDE_CONFIG_DIR=~/.claude-{acct}` before invoking any Claude-related tool. This matches the per-account `CLAUDE_CONFIG_DIR` set in `templates/zshrc.sh`.

#### Scenario: Framework installed into correct account dir

- GIVEN account `work`
- WHEN any framework installer is invoked
- THEN `CLAUDE_CONFIG_DIR` is set to `~/.claude-work` for the duration of that call
- AND no writes occur to `~/.claude/` (default Claude dir)

---

### Requirement: Codegraph Installation

After framework selection for each account, the system MUST offer codegraph via `ui_confirm`. If confirmed, codegraph MUST be installed via `npm i -g @colbymchenry/codegraph`. Node MUST be present before codegraph is attempted. Codegraph is additive and orthogonal to framework choice. Installation MUST be idempotent via `command -v codegraph`.

#### Scenario: User confirms codegraph for an account

- GIVEN `ui_confirm "Install codegraph?"` returns true and `command -v node` succeeds
- WHEN codegraph install runs for account `work`
- THEN `npm i -g @colbymchenry/codegraph` is executed
- AND codegraph MCP config is written into `~/.claude-work/`

#### Scenario: User declines codegraph

- GIVEN `ui_confirm "Install codegraph?"` returns false
- WHEN the install loop continues
- THEN codegraph is not installed for that account
- AND no error is raised

#### Scenario: Codegraph install blocked when Node absent

- GIVEN `command -v node` fails
- WHEN codegraph install is attempted
- THEN an error "Node.js is required for codegraph" is printed
- AND codegraph install is skipped

#### Scenario: Codegraph already installed (idempotent)

- GIVEN `command -v codegraph` succeeds
- WHEN codegraph install runs
- THEN `npm i -g` is NOT executed again

---

### Requirement: Curated Global Skills Installation

For each account, the system MUST install the following curated skills into `~/.claude-{acct}/skills/{name}/`: `branch-pr`, `chained-pr`, `work-unit-commits`, `comment-writer`, `issue-creation`, `judgment-day`. Skills MUST be fetched via `git clone` or `curl` from their canonical source. If `gentle-ai` is the chosen framework, gentle-ai bundles equivalent skills; the explicit curated install step MAY be skipped for gentle-ai accounts to avoid duplication. Skills install MUST be idempotent: if `~/.claude-{acct}/skills/{name}/` already exists, the skill is skipped.

#### Scenario: Skills installed for a gsd account

- GIVEN account `personal` has `AI_FRAMEWORK=gsd`
- WHEN curated skills install runs
- THEN each of the 6 skills is cloned/fetched into `~/.claude-personal/skills/{name}/`

#### Scenario: Skills install skipped for gentle-ai account

- GIVEN account `work` has `AI_FRAMEWORK=gentle-ai`
- WHEN curated skills install runs
- THEN the explicit skill clone step is skipped (gentle-ai bundles them)

#### Scenario: Idempotent skill install

- GIVEN `~/.claude-work/skills/branch-pr/` already exists
- WHEN curated skills install runs for account `work`
- THEN the branch-pr directory is not re-cloned
- AND no error is raised

---

### Requirement: Standalone AI Dev Tools Menu Entry and Dispatch

The system MUST expose an "AI dev tools" entry in the `ui_menu` interactive menu AND a `wsk ai` CLI dispatch. Both MUST invoke the same shared functions as `run_full_setup` uses. Running `wsk ai` standalone MUST load accounts first (`load_accounts`) before entering the per-account install loop.

#### Scenario: wsk ai dispatch

- GIVEN accounts `work` and `personal` exist in `WSK_DIR/accounts/`
- WHEN `wsk ai` is run
- THEN `load_accounts` is called
- AND the AI dev tools install loop runs for each account

#### Scenario: Menu entry triggers same flow

- GIVEN the interactive menu is open
- WHEN the user selects "AI dev tools"
- THEN the same function invoked by `wsk ai` is called
