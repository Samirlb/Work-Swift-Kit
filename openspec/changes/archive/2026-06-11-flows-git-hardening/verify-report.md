# Verification Report

**Change**: flows-git-hardening
**Mode**: Strict TDD (bats tests/e2e/)
**Date**: 2026-06-11
**Verdict**: PASS WITH SUGGESTIONS — see Re-verification section (2026-06-11, post-remediation). Original FAIL verdict superseded.

---

## Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 35 (+6 validation gate) |
| Tasks checked off in tasks.md | 0 |
| Tasks implemented per code inspection | 35 |

All checkboxes in `tasks.md` remain `[ ]` despite apply-progress claiming all 7 WUs complete. File state does not match claimed completion (WARNING W-1).

---

## Build & Tests Execution

**Test runner**: `bats tests/e2e/` at HEAD (7a52b91)

**Tests**: 181 total — 162 passed / **19 failed** / 0 skipped (exit != 0)

Failures at HEAD:
- `tests/e2e/test_doctor_ai.bats` — 14 failures (tests 106–117, 119, 120)
- `tests/e2e/test_claude_config_hygiene.bats` — 4 failures (tests 90–93, doctor hygiene checks)
- `tests/e2e/test_bootstrap_cross_os.bats` — 1 failure (test 69, apt-get routing)

**Regression baseline** (git worktree at 328d4d2, the commit before WU-1, same 4 files): 64 tests, **1 failure** (test 69 only).

**Conclusion**: 18 of the 19 failures were INTRODUCED by this change. The apply-progress claim that `test_doctor_ai.bats` failures were "pre-existing" is false. Only the apt-get routing failure (test 69) is genuinely pre-existing.

**shellcheck**: exit 0. Only pre-existing warnings (SC2088 x5 in lib/doctor.sh:267-271 + lib/frameworks.sh:435,450; SC2034 x2 in lib/frameworks.sh:329-330; SC2129 in templates/zshrc.sh:44) — all confirmed present at 328d4d2. No new findings.

**Coverage**: Not available (bats has no coverage tooling configured).

---

## CRITICAL Issues

### C-1: `wsk doctor` is broken in production and 18 tests regressed — root cause `lib/doctor.sh:423-426`

```bash
run_doctor() {
  preflight_accounts || return 0
  _run_doctor_output
}
```

`preflight_accounts` runs BEFORE `load_accounts` (which only happens inside `_run_doctor_output`, lib/doctor.sh:160). The dispatch path (`install.sh:151 doctor|check) run_doctor`) never loads accounts first. Therefore on a real machine with configured accounts, `WSK_ACCOUNTS` is unset at the preflight check, so `wsk doctor` prints only "No accounts configured — run: wsk accounts" and exits 0 without running ANY check. Verified empirically in a sandboxed HOME with a valid accounts/work.env on disk.

Secondary effect: the test harnesses (`_run_doctor_iso` in test_doctor_ai.bats:14-34 and the hygiene equivalents) source log/ui/os/doctor but NOT lib/preflight.sh, so `preflight_accounts` is command-not-found (127), swallowed by `|| return 0` → run_doctor produces zero output → 18 tests fail.

Fix direction: move the guard after `load_accounts` (mirror `run_relink` in install.sh:97-99) or call `load_accounts` inside `run_doctor` before the preflight; doctor should arguably still print its non-account sections when accounts are empty.

### C-2: `wsk fix-git --apply` is unreachable from the real CLI — `install.sh:162` + dispatch

`COMMAND="${1:-menu}"` then `dispatch "$COMMAND"` forwards ONLY the command name. Inside dispatch, `fix-git) run_fix_git_cmd "$@"` expands to `run_fix_git_cmd "fix-git"`, so `run_fix_git` receives `fix-git` as `$1` — never `--apply` (lib/fix-git.sh:70 checks `"${1:-}" == "--apply"`). Reproduced with a minimal shell repro: args forwarded = `[fix-git]`.

Consequence: spec git-identity-fix "Apply flag — rewrites proceed", per-repo confirmation, and the gh alignment offer (FG-2, FG-4, FG-6, FG-7 behaviors) can NEVER trigger via `wsk fix-git --apply`. The command is permanently dry-run in production. Tests pass only because they invoke `run_fix_git` directly.

Fix direction: pass remaining args through, e.g. `dispatch "$@"` with `shift` semantics or `dispatch "$COMMAND" "${@:2}"` and `fix-git) shift; run_fix_git_cmd "$@"`.

---

## WARNING Issues

- **W-1**: `tasks.md` has 0 of 35 checkboxes marked — apply never checked off tasks (openspec audit trail broken for hybrid mode).
- **W-2**: Spec scenario "No https remotes found — nothing to fix" not implemented: `lib/fix-git.sh` prints nothing when no candidates exist (silent exit 0; spec requires the message). Also untested.
- **W-3**: Legacy gitconfig migration (`templates/gitconfig.sh:30-42`) preserves the ENTIRE legacy file outside the new markers, including old WSK-generated `[user]`, `[core]`, `[alias]`, and `[includeIf]` content. Design said to re-insert only external blocks. Result after migration: duplicated config blocks (git last-wins masks `[user]`, but `includeIf`/aliases are applied twice). Spec scenario "External blocks in legacy file are preserved" passes, but with this side effect.
- **W-4**: `lib/accounts.sh:106` guards the auto re-render with `if declare -f render_all ...; then render_all; fi` with NO else branch. If `render_all` is undefined the skip is silent — exactly the silent state mismatch class this change exists to fix (gitconfig-preservation requires render OR a clear warning). Unreachable in normal `wsk` runs (install.sh sources lib/render.sh before dispatch), so WARNING not CRITICAL; add an else `check_warn "Run 'wsk relink' ..."`.
- **W-5**: Untested spec scenarios (code present but no test): flow-preflight "Flow aborts when preflight fails" (relink integration); gh-session "Directory matches no known account"; git-identity-fix "Repo not under any known PROJECTS_DIR"; git-identity-validation "gh not installed" (lib/doctor.sh:13-14 exists, untested); "No repos under PROJECTS_DIR → check_pass" (GI-9 asserts no-crash only, not the check_pass message — implementation does not print it).
- **W-6**: Design/tasks interface deviation: design specified `require_state <flag>...` with `accounts|rendered|linked` flags; implementation shipped only `preflight_accounts` (accounts flag) and never the `rendered`/`linked` states. Task 1.5 also required a guard on the dispatch AI entry — not present (`ai) run_ai` has no preflight; mitigated by run_ai's own account collection).

---

## SUGGESTION Issues

- **S-1**: Marker convention split: gitconfig uses `# WSK:BEGIN/# WSK:END` (per spec) while zshrc uses `# >>> work-swift-kit >>>/# <<< <<<` (per design). Two managed-section conventions now coexist; consider unifying.
- **S-2**: `preflight_accounts` emits the no-accounts message via `check_warn`; spec wording says "prints an error". Cosmetic.
- **S-3**: Clean up pre-existing shellcheck warnings (SC2088/SC2034/SC2129) while files are hot.
- **S-4**: GH-5 ("run_update calls render_zshrc") asserts only that the call text exists in lib/update.sh — strengthen to behavioral assertion.

---

## Verdict (Initial)

**FAIL** — 2 CRITICAL, 6 WARNING, 4 SUGGESTION.

The 45 new tests are green and most spec behavior is implemented, but the change (1) broke `wsk doctor` in production and regressed 18 previously-passing tests — mislabeled as "pre-existing" in apply-progress — and (2) shipped a `wsk fix-git --apply` flag that can never be activated from the CLI. Both must be fixed via sdd-apply remediation before archive.

---

# Re-verification (2026-06-11, post-remediation)

**Remediation commits**: b9b53c2 (fix doctor/dispatch), 8c1e675 (fix W2-W6), fb595f0 (tasks.md checkboxes)
**Method**: full bats suite + sandboxed-HOME CLI repros (read-only on source) + shellcheck + static inspection
**Revised Verdict**: **PASS WITH SUGGESTIONS** — 0 CRITICAL, 0 WARNING, 4 SUGGESTION

## Full Suite

`bats tests/e2e/` at HEAD (fb595f0): **187 tests — 186 passed / 1 failed**.

The single failure is `test_bootstrap_cross_os.bats` test 75 ("Linux with WSK_PKG_MGR=apt routes packages through apt-get, not brew") — the pre-existing apt-get routing failure confirmed present at baseline 328d4d2. Acceptance criterion met: no other failures.

The 18 tests regressed at the prior verify (test_doctor_ai.bats x14, test_claude_config_hygiene.bats x4) are all green again (re-run in isolation: 36/36 pass across both files).

## C-1: `wsk doctor` — FIXED (verified empirically)

`run_doctor` (lib/doctor.sh:423-435) now calls `load_accounts` first, then an inline accounts guard, then `_run_doctor_output`.

Evidence (sandboxed HOME + WSK_DIR, two configured accounts, one https remote):
- Dispatch path (`bash install.sh doctor`): exit 0, 97 lines of full doctor output, NO "No accounts configured" early-exit, and the https remote correctly flagged: "myrepo: remote origin is https — ... (consider: wsk fix-git)".
- Standalone path (source log/ui/os/accounts/doctor WITHOUT lib/preflight.sh, call `run_doctor` under `set -euo pipefail`): exit 0, 91 lines of output — the test-harness pattern that previously hit command-not-found 127.
- Empty-accounts path (no accounts/*.env): exit 0, prints "No accounts configured — run: wsk accounts", no set -u crash.

## C-2: `wsk fix-git --apply` — FIXED (verified empirically)

- install.sh:168 now dispatches `dispatch "$COMMAND" "${@:2}"`; `run_fix_git_cmd` (install.sh:115-119) shifts off the command name and forwards remaining args to `run_fix_git`.
- FG-8 test ("install.sh dispatch forwards --apply so run_fix_git receives it") passes.
- Manual CLI repro (sandboxed HOME, gum confirm stubbed to accept): `bash install.sh fix-git --apply` reached apply mode, prompted per-repo, and rewrote origin `https://github.com/testwork/myrepo` → `git@github-work:testwork/myrepo.git`; post-rewrite gh switch offer reached (non-fatal failure path, exit 0). Dry-run CLI repro confirmed `[dry-run] would rewrite ...` with no write.

## Warning Fixes Spot-Check

| Prior | Status | Evidence |
|---|---|---|
| W-1 tasks.md checkboxes | FIXED | 41/41 implementation + V.1/V.2 tasks checked. V.3-V.5 honestly annotated "manual-smoke" (now performed during this re-verification: doctor sandbox, fix-git dry-run, fix-git --apply — all pass); V.6 annotated "covered by PF-relink bats test" (green). |
| W-2 "No https remotes found" | FIXED | lib/fix-git.sh:138 `check_pass "No https remotes found — all remotes already use SSH aliases"`; FG-0 test green; CLI repro printed the message when all remotes SSH. |
| W-3 legacy migration duplication | FIXED | templates/gitconfig.sh:41-54 strips WSK-generated sections ([user],[core],[pull],[push],[alias],[includeIf]) before re-wrap; GC-6b test ("legacy migration does not duplicate WSK-generated sections") green. |
| W-4 silent render_all skip | FIXED | lib/accounts.sh:106-111 else-branch emits `check_warn "render_all not available — run: wsk relink ..."`. |
| W-5 untested scenarios | FIXED | New green tests: GI-9 strengthened (check_pass asserted), GI-10 (gh not installed), FG-repo-no-acct (repo outside PROJECTS_DIR), PF-relink (run_relink aborts when no accounts). gh-session "directory matches no known account" deliberately marked manual-smoke (zsh-runtime only) — acceptable. |
| W-6 require_state interface | FIXED | lib/preflight.sh:16-48 implements `require_state accounts\|rendered\|linked`; `preflight_accounts` refactored as backwards-compatible wrapper (line 67: `require_state accounts`). |

## shellcheck

`shellcheck lib/doctor.sh install.sh lib/fix-git.sh lib/accounts.sh lib/preflight.sh templates/gitconfig.sh`:
- lib/doctor.sh: SC2088 x3 (lines 267-271) — confirmed pre-existing at baseline 328d4d2 (baseline file produces the same SC2088 findings).
- All other remediation-touched files: clean, exit 0. No new findings.

## Sanity: Inline Accounts Guard Deviation

`run_doctor` uses an inline guard instead of calling `preflight_accounts`. The inline logic (lib/doctor.sh:428-433) is identical to `require_state accounts` (lib/preflight.sh:21-26): same `${WSK_ACCOUNTS+x}` bash-3.2-safe existence check, same count check, same `check_warn "No accounts configured — run: wsk accounts"` message. `run_doctor` returns 0 after the warn — semantically identical to the previous `preflight_accounts || return 0` pattern. Rationale (doctor must work when sourced standalone without preflight.sh) is valid; no flow-preflight spec scenario names `preflight_accounts` as the required mechanism — the spec requires abort-without-crash on empty accounts, which is empirically satisfied. **No spec violation.**

## Remaining SUGGESTIONS (non-blocking, carried over / new)

- S-1: Two managed-section marker conventions coexist (gitconfig `# WSK:BEGIN/END` vs zshrc `# >>> work-swift-kit >>>`). Consider unifying.
- S-2: Pre-existing shellcheck SC2088/SC2034/SC2129 warnings remain in untouched lines.
- S-3: GH-5 assertion is textual, not behavioral.
- S-4 (new): `require_state rendered|linked` flags are implemented and tested but have no production call site yet — interface available for future flows.

## Verdict (Final)

**PASS WITH SUGGESTIONS** — both CRITICAL issues fixed and proven via real CLI execution; all six warnings remediated; full suite green except the one accepted pre-existing failure. Ready for sdd-archive.
