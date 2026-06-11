# Proposal: Flows & Git Identity Hardening

## Intent

WSK flows assume state that only full setup creates: standalone runs crash (`relink` on clean machine, EC-3), re-runs destroy external config (gh credential blocks wiped on every re-render, EC-1), and adding accounts leaves the machine silently half-configured (EC-5). Separately, git identity is unreliable per account: doctor never validates transport (https remotes bypass the per-account SSH design and follow the ACTIVE gh account), and `claude()`/`claude-{acct}()` never switch the gh account — so pushes 403 with the wrong identity. Goal: every flow safe standalone, idempotent on re-run, and git identity (ssh key, gh account, transport) always correct for the repo's owning account.

## Scope

### In Scope
- Flow preflight helper: state/dependency validation before each flow (accounts loaded, empty-array guards under `set -u` bash 3.2, `sd`/`python3`/`rg` guards) — EC-3, EC-6, EC-7, EC-22
- Render-preserving gitconfig strategy: keep externally-added blocks (credential helper) across re-renders — EC-1
- Auto re-render/re-link (or explicit warning) after add/edit account — EC-5
- Stale `.rendered/wsk-zshrc` regeneration on update — EC-2, EC-8
- Doctor: per-account gh login check (robust, not substring-grep), remote transport detection (https bypass), remote alias vs containing-directory mismatch — gaps 3.1–3.3, 3.5
- Fix command(s) to convert https remotes to per-account SSH aliases and align gh active account
- `gh auth switch` integration in `claude()`/`claude-{acct}()` zshrc wrappers — gap 3.4
- Stop swallowing gentle-ai install failures before persisting `AI_FRAMEWORK` — EC-4

### Out of Scope
- TUI redesign (harden existing flows only)
- gentle-ai internals (only WSK's wrapping/patching)
- MEDIUM/LOW edge cases not listed above (EC-9–EC-23) — defer unless trivially co-located
- N-account gh login ordering redesign (EC-10)

## Capabilities

### New Capabilities
- `flow-preflight`: standalone-safe flows — state validation, dependency guards, empty-array safety
- `gitconfig-preservation`: re-renders preserve external gitconfig blocks; idempotent re-runs
- `git-identity-validation`: doctor checks transport, per-account gh login, remote/directory identity match
- `git-identity-fix`: auto-fix for https remotes and gh account alignment
- `gh-session-switching`: zsh wrappers switch gh active account with the session account

### Modified Capabilities
- None (no prior specs exist)

## Approach

1. Add a shared `preflight` lib function flows call first: load accounts, guard arrays, check optional binaries with graceful degradation.
2. Change `render_gitconfig` to a marker-delimited managed section (like the zshrc block splice WSK already uses) so external blocks survive.
3. Extend `run_doctor` with a git/gh section: per-account `gh auth status` parsing, remote URL scan under each `PROJECTS_DIR`, alias-vs-directory check.
4. Add `wsk fix-git` (doctor-driven): rewrite https github remotes to `git@github-{acct}:`, offer `gh auth switch`.
5. Patch `templates/zshrc.sh` wrappers to call `gh auth switch` for the resolved account; regenerate rendered zshrc on update.
6. TDD: bats-core e2e per capability; shellcheck on new `.sh` files.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/preflight.sh` | New | Shared state/dependency preflight |
| `templates/gitconfig.sh`, `stow/.gitconfig` | Modified | Managed-section rendering |
| `lib/doctor.sh` | Modified | git/gh transport+identity checks |
| `lib/fix-git.sh` (or doctor ext.) | New | `wsk fix-git` command |
| `templates/zshrc.sh` | Modified | gh-switch in wrappers |
| `lib/accounts.sh`, `lib/frameworks.sh`, `lib/update.sh`, `install.sh` | Modified | Re-render on add, guards, dispatch |
| `tests/e2e/` | New | bats coverage per capability |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Managed-section migration breaks existing `~/.gitconfig` | Med | Detect legacy file, migrate once, back up before write |
| Auto remote rewrite touches repos user wants on https | Med | `fix-git` is opt-in, per-repo confirm, dry-run default |
| `gh auth switch` in wrappers slows shell / fails offline | Low | Guard with `command -v gh` + non-fatal failure |
| Bash 3.2 regressions from new helpers | Med | bats e2e + shellcheck gate |

## Rollback Plan

Single PR (`size:exception`, user-approved): revert the PR. Backups taken before gitconfig migration allow restoring user files; rendered zshrc regenerates from templates via `wsk relink`.

## Dependencies

- bats-core and shellcheck available locally (already project standard)

## Success Criteria

- [ ] `wsk relink`/`doctor`/`ai`/`sync` run safely on a clean machine (no `set -u` crash)
- [ ] Re-running relink/accounts/update preserves gh credential blocks in `~/.gitconfig`
- [ ] Adding an account leaves zsh functions, includeIf, and SSH alias configured (or warns explicitly)
- [ ] Doctor flags https github remotes, wrong active gh account, and alias/directory mismatch
- [ ] `wsk fix-git` converts flagged remotes and aligns gh account
- [ ] `claude-{acct}()` sessions push with the correct identity
- [ ] All new bats e2e tests and shellcheck pass
