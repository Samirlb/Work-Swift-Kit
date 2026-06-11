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

## Work Unit Summaries (All Completed)

**WU-1**: Shared preflight guard via `lib/preflight.sh` with `require_state` function, optional dependency guards, bash 3.2 safe array patterns.

**WU-2**: Gitconfig managed-section with `# WSK:BEGIN/# WSK:END` markers, awk strip-and-reappend preservation, legacy file migration with timestamped backup.

**WU-3**: Doctor extended with per-account gh login validation, remote transport detection (https bypass), remote alias vs directory mismatch detection.

**WU-4**: New `wsk fix-git` command with dry-run default, `--apply` flag for per-repo confirmation, SSH alias resolution via longest-prefix PROJECTS_DIR matching, gh account alignment offer.

**WU-5**: Shared `_wsk_gh_switch` helper in zshrc, injection in `claude()` and `claude-{acct}()` wrappers, auto re-render of `.rendered/wsk-zshrc` on update and relink.

**WU-6**: `_gentle_ai_scoped` error handling with rc capture and non-persist on failure, `sd` absence fallback in `_persist_account_kv`, `python3` absence fallback in `_patch_gentle_ai_claude_md`.

**WU-7**: Auto re-render/re-link after add-account and edit-account via `render_all` call in `_collect_single_account`, with clear messaging.

**WU-R1**: Fixed doctor ordering (`load_accounts` before preflight) and dispatch arg forwarding for `wsk fix-git --apply`.

**WU-R2**: Fixed "No https remotes" message, legacy migration deduplication, render_all undefined warning, `require_state` interface with full `rendered|linked` flags, strengthened untested scenarios with 4 new tests.

---

## Validation Status

- [x] V.1 Full bats suite: 187 tests — 186 passed / 1 pre-existing failure
- [x] V.2 Shellcheck all new/modified files → exit 0
- [x] V.3 Manual smoke-test `wsk doctor` (sandbox HOME)
- [x] V.4 Manual smoke-test `wsk fix-git` dry-run
- [x] V.5 Manual smoke-test `wsk fix-git --apply`
- [x] V.6 Confirm `wsk relink` no crash on empty WSK_ACCOUNTS (bats PF-relink test)

All checkboxes marked; all tasks implemented and verified.
