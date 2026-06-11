# gh Session Switching Specification

## Purpose

`claude()` and `claude-{acct}()` zsh wrappers in `templates/zshrc.sh` do not switch the active gh account when entering an account-scoped session. This causes pushes to 403 when the active gh account does not match the repo's owning account. This spec defines the required `gh auth switch` call in those wrappers and the constraints on failure handling.

## Requirements

### Requirement: gh Account Switch in claude-{acct}() Wrappers

Each `claude-{acct}()` zsh function MUST call `gh auth switch --user {GIT_GITHUB_USER}` before launching Claude Code. The switch MUST be non-fatal: if `gh` is absent or the switch fails (e.g. offline), a warning is printed and Claude Code still launches.

**Side-effect disclosure**: `gh auth switch` changes the GLOBAL gh active account for the entire machine session, not only the current terminal. This behavior MUST be documented in the generated function via an inline comment.

#### Scenario: Successful gh switch before Claude launch

- GIVEN `command -v gh` succeeds and `GIT_GITHUB_USER=acme-work-user` is set for the `work` account
- WHEN `claude-work` is invoked
- THEN `gh auth switch --user acme-work-user` is called
- AND `claude` is subsequently launched
- AND the active gh account is now `acme-work-user` globally

#### Scenario: gh not installed — non-fatal

- GIVEN `command -v gh` fails
- WHEN `claude-work` is invoked
- THEN a warning is printed: `"gh not found — skipping account switch"`
- AND `claude` is launched without the switch

#### Scenario: gh switch fails (offline / no account)

- GIVEN `gh auth switch` exits non-zero
- WHEN `claude-work` is invoked
- THEN a warning is printed: `"gh auth switch failed — Claude will use current active gh account"`
- AND `claude` is launched

---

### Requirement: gh Account Switch in claude() Auto-Detect Wrapper

The generic `claude()` wrapper MUST also attempt `gh auth switch` using the account resolved by its auto-detection logic (directory matching against `PROJECTS_DIR`). The same non-fatal failure handling applies.

#### Scenario: Directory matches personal account

- GIVEN cwd is under the `personal` `PROJECTS_DIR`
- WHEN `claude` is invoked
- THEN `gh auth switch --user {GIT_GITHUB_USER_personal}` is called before launching Claude Code

#### Scenario: Directory matches no known account

- GIVEN cwd does not match any account's `PROJECTS_DIR`
- WHEN `claude` is invoked
- THEN no `gh auth switch` is called
- AND Claude Code is launched with the currently active gh account

---

### Requirement: Failed gentle-ai Install Must Not Persist AI_FRAMEWORK

When `_gentle_ai_scoped install` exits non-zero, the calling code MUST NOT call `_persist_account_kv AI_FRAMEWORK gentle-ai`. The error MUST be surfaced to the user before returning.

#### Scenario: gentle-ai install fails

- GIVEN `_gentle_ai_scoped install` exits 1
- WHEN the AI setup flow processes the result
- THEN `AI_FRAMEWORK` is NOT written to `accounts/{acct}.env`
- AND an error is printed: `"gentle-ai install failed for {acct} — AI_FRAMEWORK not saved"`
- AND the flow returns non-zero

#### Scenario: gentle-ai install succeeds

- GIVEN `_gentle_ai_scoped install` exits 0
- WHEN the AI setup flow processes the result
- THEN `_persist_account_kv AI_FRAMEWORK gentle-ai` is called
- AND `accounts/{acct}.env` is updated with `AI_FRAMEWORK=gentle-ai`

---

### Requirement: Rendered zshrc Regenerated on Update

`wsk update` MUST regenerate `.rendered/wsk-zshrc` by calling `render_zshrc` (or equivalent) after pulling the latest WSK source, so that new interceptors or wrappers added in the update are reflected immediately without requiring a manual `wsk relink`.

#### Scenario: Update regenerates rendered zshrc

- GIVEN `.rendered/wsk-zshrc` exists with stale content missing a wrapper introduced in the new version
- WHEN `wsk update` completes
- THEN `.rendered/wsk-zshrc` is overwritten with freshly rendered content from `templates/zshrc.sh`
- AND `inject_zshrc_block` is called to splice the updated block into `~/.zshrc`
