# Design: Flows & Git Identity Hardening

## Technical Approach

Harden existing flows without redesigning the TUI. Add one shared `lib/preflight.sh` invoked at each dispatch entry (set -u/bash 3.2 safe), convert `render_gitconfig` to a marker-delimited managed section mirroring the proven `inject_zshrc_block` awk splice (`lib/stow.sh:78-89`), extend `run_doctor` with a bounded git/gh identity audit, add a dry-run-default `wsk fix-git`, and inject `gh auth switch` into zsh wrappers via a shared helper plus auto re-render of `.rendered/wsk-zshrc` on update/relink. Strict TDD: bats e2e under `tests/e2e/` with sandboxed `$HOME`, shellcheck clean.

## Architecture Decisions

### Decision: Gitconfig preservation strategy
**Choice**: Managed-section markers — render WSK content only between `# >>> work-swift-kit >>>` / `# <<< <<<`, preserve everything outside via awk strip-and-reappend.
**Alternatives**: merge-on-render (parse/merge INI — fragile in bash 3.2); include-file split (`[include] path=.gitconfig-wsk` — leaves user file but `gh` still writes credential blocks to the managed file).
**Rationale**: Identical proven pattern already exists for `~/.zshrc`. `gh auth login` writes `[credential]` outside the markers → survives. One-time migration: if `~/.gitconfig` lacks markers, back up `${file}.bak.$(date +%Y%m%d-%H%M%S)` then wrap. Render targets `stow/.gitconfig`; since stow symlinks it, the splice must operate on the rendered stow file before linking, and detect the legacy fully-rendered file (no markers) for migration.

### Decision: Flow preflight
**Choice**: Single `require_state <flag>...` helper in `lib/preflight.sh`, called per dispatch entry. Flags: `accounts`, `rendered`, `linked`. Returns non-zero with a `check_warn` + remediation hint instead of crashing.
**Alternatives**: per-function guards (duplicated, drift-prone).
**Rationale**: One audited place to fix the `${WSK_ACCOUNTS[0]}` class. Use `${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}` for iteration and `${WSK_ACCOUNTS[0]:-}` for index access; guard count with `${#WSK_ACCOUNTS[@]}` only after confirming the array is set. `render_gitconfig`/`link_dotfiles` early-return when accounts empty.

### Decision: Doctor git identity audit (perf-bounded)
**Choice**: Per-account checks — `gh auth status` parsed for the account's `GIT_GITHUB_USER` (exact token match, not substring), active gh account read once, remote transport scan under each `PROJECTS_DIR` at `maxdepth 2` (`<dir>/<repo>/.git`), alias-vs-containing-dir mismatch.
**Alternatives**: deep recursive scan (slow on large trees); cache file (staleness risk).
**Rationale**: `maxdepth 2` matches the flat `PROJECTS_DIR/<repo>` layout; bounded and cache-free. Parse `gh auth status` by line-matching `Logged in to github.com account <user>` rather than `grep -q "$user"` (fixes EC-3.5/3.1). Read remotes via `git -C <repo> remote get-url origin`.

### Decision: `wsk fix-git`
**Choice**: Dry-run by default (`--apply` to write), per-repo confirm. Maps repo → account by which `PROJECTS_DIR` contains it; rewrites `https://github.com/<o>/<r>` (and `git@github.com:`) origin to `git@github-{acct}:<o>/<r>.git`; offers `gh auth switch` to align active account.
**Alternatives**: auto-rewrite all (destructive, EC risk).
**Rationale**: Opt-in + dry-run + per-repo confirm matches the proposal risk mitigation. Doctor-driven: reuses the same scan to list candidates.

### Decision: gh session switching + stale rendered zshrc
**Choice**: Add shared `_wsk_gh_switch <user>` helper (guarded `command -v gh`, non-fatal) in the rendered zshrc; call it from `claude()` (after account auto-detect) and `claude-{acct}()`. Auto re-render `.rendered/wsk-zshrc` on `update` and `relink`.
**Alternatives**: inline switch in each wrapper (duplication); switch only in `claude()` (leaves `claude-{acct}` drifting).
**Rationale**: `_wsk_switch_profile` already switches gh; reuse the same approach for claude wrappers. Auto re-render fixes EC-2/EC-8 — `run_update` and `run_relink` always call `render_zshrc` before `inject_zshrc_block`.

### Decision: Dependency guards
**Choice**: `command -v` guards with fallbacks — `_persist_account_kv` falls back to POSIX awk rewrite when `sd` absent; marker patch and `_patch_gentle_ai_claude_md` fall back to awk when `python3` absent; `rg` already `|| true`.
**Rationale**: Removes silent duplicate-key (EC-6) and `set -e` aborts (EC-7) without adding hard deps.

### Decision: `_gentle_ai_scoped` error propagation (EC-4)
**Choice**: Capture `command gentle-ai "$@"` rc; on failure `check_warn` and do NOT persist `AI_FRAMEWORK=gentle-ai`; return rc to caller but caller (menu loop) treats it as non-fatal `check_warn`.
**Rationale**: Stops the configured-but-broken state without breaking the menu UX loop.

## Data Flow

    dispatch(cmd) ──→ require_state(flags) ──→ flow body
                          │ (fail)
                          └──→ check_warn + hint, return 0 (no crash)

    render_gitconfig ──→ awk strip markers (preserve [credential]) ──→ re-append WSK section
    run_doctor/fix-git ──→ scan PROJECTS_DIR/*/.git ──→ remote transport + alias/dir + gh account audit

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `lib/preflight.sh` | Create | `require_state`, array-safe guards, binary guards |
| `lib/fix-git.sh` | Create | `run_fix_git` + shared remote-scan used by doctor |
| `tests/e2e/*.bats` | Create | Coverage per capability, sandboxed `$HOME` |
| `templates/gitconfig.sh` | Modify | Marker-delimited managed section + legacy migration |
| `lib/doctor.sh` | Modify | Per-account gh user, transport, alias/dir audit |
| `templates/zshrc.sh` | Modify | `_wsk_gh_switch` helper; call in `claude()`/`claude-{acct}()` |
| `lib/update.sh`, `lib/relink` path | Modify | Always `render_zshrc` before inject (EC-2/8) |
| `lib/accounts.sh` | Modify | Re-render/re-link (or explicit warn) after add/edit |
| `lib/frameworks.sh` | Modify | EC-4 rc handling, EC-6/7 fallbacks |
| `install.sh` | Modify | Source preflight, wire `require_state`, add `fix-git` dispatch |

## Interfaces / Contracts

```bash
# lib/preflight.sh
require_state accounts rendered linked   # 0 ok; non-zero + check_warn on miss

# lib/fix-git.sh
run_fix_git [--apply]                     # dry-run default; per-repo confirm

# rendered zshrc helper
_wsk_gh_switch <github_user>              # guarded, non-fatal
```

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| E2E (bats) | relink/doctor/ai/sync on empty accounts (no set -u crash); re-render preserves `[credential]`; add-account re-renders/warns; doctor flags https + wrong account + alias/dir mismatch; fix-git dry-run vs --apply | sandboxed `$HOME`, stubbed `gh`/`git`, fixture `PROJECTS_DIR` |
| Static | All new/modified `.sh` | shellcheck gate |

## Migration / Rollout

One-time `~/.gitconfig` migration on first render: detect missing markers, back up timestamped copy, wrap existing content. No data migration beyond file rewrites; all writes preceded by `.bak` per existing `backup_if_real` convention.

## Open Questions

- [ ] Should `fix-git` also rewrite non-`origin` remotes, or `origin` only for v1? (lean: origin only)
- [ ] Add a `fix-git` menu entry, or keep direct-command only like `fix-claude`? (lean: direct-command only, per existing convention)
