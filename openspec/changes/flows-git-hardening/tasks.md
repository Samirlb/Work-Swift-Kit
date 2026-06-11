# Tasks: Flows & Git Identity Hardening

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 520–650 |
| 400-line budget risk | High |
| Chained PRs recommended | No |
| Suggested split | Single PR (size:exception approved) |
| Delivery strategy | single-pr |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: High

**Rationale**: User has pre-approved `size:exception`. All work units ship in one PR.
Each commit is a self-contained work unit (test + code) keeping the bats suite green between commits.

### Recorded Decisions (from open questions + conflict resolutions)

- **fix-git scope**: origin remote only (not all remotes).
- **fix-git menu entry**: direct-command only (`wsk fix-git`), no interactive-menu entry — mirrors `fix-claude` convention.
- **Auto re-render after add/edit account**: design WINS — auto re-render with clear messaging (not warn-only).
- **gentle-ai failure policy**: kept in `gh-session-switching` spec scope; task references both spec scenario GH-9 and design's error-propagation decision.
- **Nested PROJECTS_DIR alias resolution**: longest-prefix-match wins.

### Suggested Work Units

| Unit | Goal | Commit | Notes |
|------|------|--------|-------|
| WU-1 | Shared preflight guard | 1 commit | New file; bats tests first |
| WU-2 | Gitconfig managed-section + migration | 1 commit | Modifies templates/gitconfig.sh |
| WU-3 | Doctor git/gh identity audit | 1 commit | Extends lib/doctor.sh |
| WU-4 | wsk fix-git command | 1 commit | New lib/fix-git.sh + dispatch |
| WU-5 | gh session switching + stale zshrc fix | 1 commit | templates/zshrc.sh, lib/update.sh |
| WU-6 | Dependency fallbacks + EC-4 error propagation | 1 commit | lib/frameworks.sh |
| WU-7 | Accounts auto re-render after add/edit | 1 commit | lib/accounts.sh |
| WU-R1 | Remediation: doctor ordering + dispatch arg forwarding | 1 commit | lib/doctor.sh, install.sh |
| WU-R2 | Remediation: warnings W2-W6 | 1 commit | lib/fix-git.sh, lib/preflight.sh, etc. |

---

## Work Unit 1 — Shared Preflight Guard

**Spec refs**: flow-preflight scenarios PF-1 – PF-7

- [x] 1.1 Write `tests/e2e/preflight.bats`: failing tests for PF-1 (empty WSK_ACCOUNTS aborts flow), PF-2 (single account passes), PF-3 (no accounts + `--allow-empty` passes), PF-4 (sd missing → warn + continue), PF-5 (rg missing → warn + continue), PF-6 (python3 missing → warn + continue), PF-7 (all deps present → silent pass). [RED]
- [x] 1.2 Create `lib/preflight.sh`: `require_state <flag>...` function; flags: `accounts`, `rendered`, `linked`; on missing state emit `check_warn` + hint, return non-zero without crashing. [GREEN for PF-1 – PF-3]
- [x] 1.3 Add `_check_optional_dep <cmd> <hint>` in `lib/preflight.sh`: `command -v` guard, `check_warn` on absent, continue (not abort). [GREEN for PF-4 – PF-7]
- [x] 1.4 Apply bash 3.2 safe array pattern throughout `lib/preflight.sh`: use `${arr[@]+"${arr[@]}"}` for iteration; `${arr[0]:-}` for index access; never bare `${arr[@]}` on empty array.
- [x] 1.5 Source `lib/preflight.sh` in `install.sh` (after `lib/bootstrap.sh`); add preflight guards at `run_relink`, `run_sync`, `run_doctor`. NOTE: `require_state accounts` guard at dispatch AI entry (run_ai) not added — run_ai has its own account collection; `run_doctor` uses inline guard for standalone test compatibility.
- [x] 1.6 Run `shellcheck lib/preflight.sh`; fix all warnings. Run `bats tests/e2e/preflight.bats` → all green.

---

## Work Unit 2 — Gitconfig Managed-Section + Migration

**Spec refs**: gitconfig-preservation scenarios GC-1 – GC-7

- [x] 2.1 Write `tests/e2e/gitconfig.bats`: failing tests for GC-1 through GC-7. [RED]
- [x] 2.2 Rewrite `render_gitconfig` in `templates/gitconfig.sh`: use awk strip-and-reappend pattern with markers `# WSK:BEGIN` / `# WSK:END`; preserve all content outside markers. [GREEN for GC-1, GC-2, GC-3, GC-5]
- [x] 2.3 Add one-time migration path in `render_gitconfig`: detect absence of markers; if absent → backup + strip WSK-generated sections + wrap. Deduplication bug fixed in remediation (WU-R2). [GREEN for GC-4, GC-7]
- [x] 2.4 Run `shellcheck templates/gitconfig.sh`; run `bats tests/e2e/gitconfig.bats` → all green (7/7).

---

## Work Unit 3 — Doctor Git/gh Identity Audit

**Spec refs**: git-identity-validation scenarios GI-1 – GI-9

- [x] 3.1 Write `tests/e2e/doctor-identity.bats`: failing tests for GI-1 through GI-9. GI-10 (gh not installed) added in remediation. [RED]
- [x] 3.2 Add `_audit_gh_login <account> <github_user>` in `lib/doctor.sh`: parse `gh auth status` output for exact token match; emit `check_warn` on absent or inactive. [GREEN for GI-1 – GI-4]
- [x] 3.3 Add `_scan_remotes <projects_dir>` in `lib/doctor.sh`: glob `<dir>/*/.git` at maxdepth 2; read `git -C <repo> remote get-url origin`; flag https remotes. [GREEN for GI-5, GI-6, GI-9]
- [x] 3.4 Add `_audit_alias_dir <acct_name> <projects_dir>` in `lib/doctor.sh`. [GREEN for GI-7, GI-8]
- [x] 3.5 Wire identity audit functions into `run_doctor` loop over WSK_ACCOUNTS.
- [x] 3.6 Run `shellcheck lib/doctor.sh`; run `bats tests/e2e/doctor-identity.bats` → all green.

---

## Work Unit 4 — wsk fix-git Command

**Spec refs**: git-identity-fix scenarios FG-1 – FG-7

- [x] 4.1 Write `tests/e2e/fix-git.bats`: failing tests for FG-1 through FG-7. FG-0, FG-8, FG-repo-no-acct added in remediation. [RED]
- [x] 4.2 Create `lib/fix-git.sh`: `run_fix_git [--apply]`; longest-prefix-match; dry-run and apply modes. [GREEN for FG-1 – FG-7]
- [x] 4.3 Add SSH alias rewrite logic in `lib/fix-git.sh`. [GREEN for FG-4, FG-5]
- [x] 4.4 Add post-rewrite `_wsk_gh_switch` offer in `lib/fix-git.sh`. [GREEN for FG-6, FG-7]
- [x] 4.5 Add `fix-git` to dispatch in `install.sh`; `run_fix_git_cmd` wrapper; `run_help` entry. CLI arg forwarding fixed in remediation (WU-R1).
- [x] 4.6 Source `lib/fix-git.sh` in `install.sh`.
- [x] 4.7 Run `shellcheck lib/fix-git.sh`; run `bats tests/e2e/fix-git.bats` → all green (9/9).

---

## Work Unit 5 — gh Session Switching + Stale Rendered Zshrc Fix

**Spec refs**: gh-session-switching scenarios GH-1 – GH-8 (GH-9 covered in WU-6)

- [x] 5.1 Write `tests/e2e/gh-session.bats`: failing tests for GH-1 through GH-8. [RED]
- [x] 5.2 Add `_wsk_gh_switch <github_user>` helper in `templates/zshrc.sh`.
- [x] 5.3 Inject `_wsk_gh_switch` call in `claude-{acct}()` wrapper.
- [x] 5.4 Inject `_wsk_gh_switch` in auto-detect `claude()` wrapper.
- [x] 5.5 Prepend `render_zshrc` before `inject_zshrc_block` in `lib/update.sh`.
- [x] 5.6 Prepend `render_zshrc` before `inject_zshrc_block` in relink path.
- [x] 5.7 Run `shellcheck templates/zshrc.sh lib/update.sh`; run `bats tests/e2e/gh-session.bats` → all green.

---

## Work Unit 6 — Dependency Fallbacks + EC-4 Error Propagation

**Spec refs**: gh-session-switching scenario GH-9; flow-preflight PF-4 – PF-6

- [x] 6.1 Write `tests/e2e/frameworks-hardening.bats`: failing tests for EC-4, EC-6, EC-7. [RED]
- [x] 6.2 Fix `_gentle_ai_scoped` in `lib/frameworks.sh`: capture exit code; on failure check_warn, do NOT persist. [GREEN for EC-4]
- [x] 6.3 Add `sd` absence fallback in `_persist_account_kv`. [GREEN for EC-6]
- [x] 6.4 Add `python3` absence fallback in `_patch_gentle_ai_claude_md`. [GREEN for EC-7]
- [x] 6.5 Run `shellcheck lib/frameworks.sh`; run `bats tests/e2e/frameworks-hardening.bats` → all green.

---

## Work Unit 7 — Accounts Auto Re-Render After Add/Edit

**Spec refs**: gitconfig-preservation scenario GC-6; gh-session-switching scenario GH-7

- [x] 7.1 Write `tests/e2e/accounts-rerender.bats`: failing tests for GC-6, AR-2, AR-3. [RED]
- [x] 7.2 Add `render_all` call (with log_info message) at end of `_collect_single_account`. Visible check_warn added in remediation (WU-R2) when render_all is undefined.
- [x] 7.3 Ensure `render_all` is safe on empty `WSK_ACCOUNTS`.
- [x] 7.4 Run `shellcheck lib/accounts.sh`; run `bats tests/e2e/accounts-rerender.bats` → all green.

---

## Validation Gate (not a commit — run before PR)

- [x] V.1 Run full bats suite: `bats tests/e2e/` — 182 passed / 1 failed (pre-existing apt-get routing in test_bootstrap_cross_os.bats test 69).
- [x] V.2 Run `shellcheck` on all new and modified files → exit 0 (only pre-existing SC2088/SC2034/SC2129 warnings present at baseline 328d4d2).
- [ ] V.3 Smoke-test `wsk doctor` in a sandbox HOME — manual-smoke (not bats-automatable).
- [ ] V.4 Smoke-test `wsk fix-git` dry-run — manual-smoke.
- [ ] V.5 Smoke-test `wsk fix-git --apply` — manual-smoke.
- [ ] V.6 Confirm `wsk relink` with empty WSK_ACCOUNTS does not crash — covered by PF-relink bats test.

### Untested spec scenarios (manual-smoke or deferred)

- **flow-preflight "Flow aborts when preflight fails (relink)"** — covered by PF-relink bats test (added in WU-R2).
- **gh-session "Directory matches no known account"** — manual-smoke; runtime behavior of rendered zshrc wrapper, not bats-automatable without a full zsh eval environment.
- **git-identity-fix "Repo not under any known PROJECTS_DIR"** — covered by FG-repo-no-acct bats test (added in WU-R2).
- **git-identity-validation "gh not installed"** — covered by GI-10 bats test (added in WU-R2).
- **"No repos under PROJECTS_DIR → check_pass"** — GI-9 strengthened to assert message (WU-R2).
