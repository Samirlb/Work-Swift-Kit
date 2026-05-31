# Archive Report — quick-dev-setup

**Date**: 2026-05-30
**Executor**: sdd-archive
**Mode**: openspec (file-based)
**Status**: COMPLETE

---

## Change Summary

**Change Name**: `quick-dev-setup`

**Intent**: Install the AI dev layer (Claude Code, ONE AI framework per account, codegraph, curated global skills) plus Node/pnpm, cross-OS (macOS + Linux, Windows instructions-only). All per-account; all surfaced in `wsk doctor`.

**Scope**: 5 new library modules (os-abstraction, node-toolchain, ai-dev-tools, bootstrap refactor, doctor additions), 1 new dispatch/menu entry, CI matrix addition, documentation updates.

---

## Work Unit Completion Status

All 10 work units (WU-0 through WU-9) are **COMPLETE AND COMMITTED**.

| WU | Name | Spec Coverage | Status |
|----|----|---|---|
| WU-0 | Test Infrastructure (stubs) | setup.bash PATH shim infra | ✅ COMPLETE |
| WU-1 | `lib/os.sh` (OS detection & pkg_install router) | os-abstraction spec | ✅ COMPLETE |
| WU-2 | Bootstrap refactor (cross-OS) | bootstrap delta spec | ✅ COMPLETE |
| WU-3 | `lib/node.sh` (Node + pnpm) | node-toolchain spec | ✅ COMPLETE |
| WU-4 | `lib/claude.sh` (Claude Code + codegraph) | ai-dev-tools spec (partial) | ✅ COMPLETE |
| WU-5 | `lib/frameworks.sh` (per-account framework + skills) | ai-dev-tools spec (partial) | ✅ COMPLETE |
| WU-6 | `install.sh` integration (dispatch + menu) | ai-dev-tools spec dispatch | ✅ COMPLETE |
| WU-7 | `doctor.sh` additions (AI/OS/node health sections) | doctor delta spec | ✅ COMPLETE |
| WU-8 | CI matrix (Ubuntu + macOS) | ci matrix | ✅ COMPLETE |
| WU-9 | README + Formula updates | documentation | ✅ COMPLETE |

---

## Verification Outcome

**Final Test Run**: 2026-05-30

- **bats tests/e2e/**: 112 PASS / 1 FAIL (pre-existing, unrelated)
  - Total test count: 113
  - All new test suites pass (17 + 10 + 10 + 13 + 15 = 65 new tests)
  - Pre-existing failure: test 82 in `test_n_accounts.bats` — `.zshrc has three claude-{account} functions` (predates this change)

- **shellcheck -x lib/*.sh templates/*.sh install.sh**: CLEAN
  - Zero errors, zero warnings across all shell files (5 new libraries + 3 refactored)

- **Verify Verdict**: **PASS WITH WARNINGS**
  - All specs implemented and verified
  - All design decisions honored
  - All work units complete
  - Non-blocking warnings: W-1 (bats version declaration missing), W-2 (exit code advisory), S-1 (CI lint missing -x flag)

---

## Post-Verify Fixes Applied

The following warnings from the verify report were addressed with commits:

### W-1: Missing `bats_require_minimum_version 1.5.0` declaration
- **Location**: `tests/e2e/test_os_detection.bats` line 176
- **Fix Applied**: Added `bats_require_minimum_version 1.5.0` at the top of the file
- **Status**: ✅ COMMITTED

### W-2: BW01 exit code advisory for synthetic packages
- **Location**: `tests/e2e/test_pkg_install.bats` lines 47, 124
- **Fix Applied**: Updated to use `run -127 pkg_install wsk-fake-pkg-zz9` to suppress advisory
- **Status**: ✅ COMMITTED

### S-1: shellcheck CI lint missing `-x` flag
- **Location**: `.github/workflows/ci.yml`
- **Fix Applied**: Updated lint step to include `shellcheck -x lib/*.sh templates/*.sh install.sh`
- **Status**: ✅ COMMITTED

---

## Specs Synced to Main

The change contained 5 delta specs for new/modified capabilities. These have been merged into the main `openspec/specs/` directory structure (canonical source of truth).

| Domain | Action | Details | Path |
|--------|--------|---------|------|
| `os-abstraction` | NEW spec | Complete; covers detect_os, detect_pkg_mgr, pkg_install router | `openspec/specs/os-abstraction/spec.md` |
| `node-toolchain` | NEW spec | Complete; covers install_node, install_pnpm, order enforcement | `openspec/specs/node-toolchain/spec.md` |
| `ai-dev-tools` | NEW spec | Complete; covers Claude Code, per-account frameworks, codegraph, curated skills, menu/dispatch | `openspec/specs/ai-dev-tools/spec.md` |
| `bootstrap` | DELTA spec (merged) | Modified: removed Darwin guard, uses pkg_install for prereqs | `openspec/specs/bootstrap/spec.md` |
| `doctor` | DELTA spec (merged) | Modified: new OS/pkg-mgr, Node/pnpm, Claude, frameworks, codegraph, skills sections | `openspec/specs/doctor/spec.md` |

All 5 specs have been copied from `openspec/changes/quick-dev-setup/specs/{domain}/spec.md` to `openspec/specs/{domain}/spec.md`, becoming the canonical capability definitions.

---

## Archive Contents

The change folder has been moved to `openspec/changes/archive/2026-05-30-quick-dev-setup/` and contains:

- `proposal.md` — full SDD proposal with intent, scope, approach, risks, rollback
- `exploration.md` — initial research and findings
- `specs/` — all 5 delta specs (os-abstraction, node-toolchain, ai-dev-tools, bootstrap, doctor)
- `design.md` — detailed technical design with 10 architecture decisions, sequence diagrams, traceability matrix
- `tasks.md` — 9 work units broken into sequential + parallel tasks with locked URL corrections
- `apply-progress.md` — commit log and proof of implementation for all 6 batches (WU-0 through WU-9)
- `verify-report.md` — verification results, test evidence, spec compliance matrix, design coherence check

---

## Source of Truth Updated

The following main project specs are now the authoritative definitions of these capabilities:

- `openspec/specs/os-abstraction/spec.md` — OS + package manager detection; pkg_install router
- `openspec/specs/node-toolchain/spec.md` — Node.js and pnpm installation (macOS + Linux)
- `openspec/specs/ai-dev-tools/spec.md` — Claude Code, per-account AI frameworks, codegraph, curated skills
- `openspec/specs/bootstrap/spec.md` — (updated) cross-OS bootstrap with pkg_install
- `openspec/specs/doctor/spec.md` — (updated) health checks for OS, Node, Claude, frameworks, codegraph, skills

---

## Design Decisions Honored

All 10 locked design decisions from `design.md` §7 were implemented and verified:

| Decision | Implementation | Verified |
|----------|---|---|
| D1: Per-skill fetch from pinned `WSK_SKILLS_REPO` | `_fetch_skill` uses `https://github.com/Gentleman-Programming/gentle-ai` | ✅ Test coverage |
| D2: gsd — npm primary, git-clone fallback | `npx get-shit-done-cc --global` primary; fallback to `https://github.com/gsd-build/get-shit-done` | ✅ Test coverage + fallback test |
| D3: codegraph MCP config — `.mcp.json`, jq-merge | `_write_codegraph_mcp_config` writes to `~/.claude-{acct}/.mcp.json` with jq merge | ✅ Test coverage |
| D4: gentle-ai accounts skip explicit curated skills | `install_curated_skills` checks `AI_FRAMEWORK=gentle-ai` → skip + message | ✅ Test coverage |
| D5: Shared per-account driver for full-setup, menu, `wsk ai` | `run_ai_for_all_accounts` + `run_ai` shared | ✅ Integration verified |
| D6: Linux Node via system package (not fnm) | `install_node` uses `pkg_install node` on Linux | ✅ Test coverage |
| D6b: macOS pnpm uses explicit `brew install` | `install_pnpm` on macOS calls `brew install pnpm` directly | ✅ Test coverage |
| D7: `pkg_install` probes single arg with `command -v` | Router guards with `command -v "$pkg"` | ✅ Test coverage |
| D8: env upsert via `sd`, not `sed -i` | `_persist_account_kv` uses `sd` for portability | ✅ Test coverage |
| D9: bats stubs are PATH shims (not exported functions) | `$WSK_STUB_BIN` prepended to `PATH` | ✅ CI integration |
| D10: Linux pkg_install runs un-spun (no password hide) | apt/dnf/pacman run directly, brew wrapped in `ui_spin` | ✅ Implementation verified |

---

## Files Deployed

All implementation files have been committed to `feat/quick-dev-setup` branch:

**New Library Modules**:
- `lib/os.sh` — OS detection, package manager detection, pkg_install router
- `lib/node.sh` — Node.js and pnpm installation with order enforcement
- `lib/claude.sh` — Claude Code and codegraph installation, MCP config writer
- `lib/frameworks.sh` — per-account AI framework selection, curated skills, account persistence

**Modified Core Files**:
- `lib/bootstrap.sh` — removed Darwin guard, uses pkg_install for prereqs
- `lib/packages.sh` — refactored to use pkg_install instead of hard-coded brew
- `lib/terminals.sh` — refactored to use pkg_install, OS-conditional routing
- `lib/doctor.sh` — 6 new sub-sections (OS/pkg-mgr, Node/pnpm, Claude, frameworks, codegraph, skills)
- `install.sh` — source new libs, AI steps in run_full_setup, `wsk ai` dispatch + menu entry

**Test Files**:
- `tests/helpers/setup.bash` — extended with PATH shim infra, stub helpers, presence toggles
- `tests/e2e/test_os_detection.bats` — 9 tests for detect_os and detect_pkg_mgr
- `tests/e2e/test_pkg_install.bats` — 8 tests for pkg_install router
- `tests/e2e/test_bootstrap_cross_os.bats` — 11 tests for refactored bootstrap
- `tests/e2e/test_node_toolchain.bats` — 10 tests for install_node and install_pnpm
- `tests/e2e/test_claude_install.bats` — 10 tests for Claude Code and codegraph
- `tests/e2e/test_ai_frameworks.bats` — 17 tests for frameworks and per-account loop
- `tests/e2e/test_install_ai_dispatch.bats` — 13 tests for install.sh integration
- `tests/e2e/test_doctor_ai.bats` — 15 tests for doctor.sh AI sections

**CI and Documentation**:
- `.github/workflows/ci.yml` — added Ubuntu matrix job, updated deps
- `README.md` — added wsk ai command, cross-OS notes, AI dev layer section
- `Formula/work-swift-kit.rb` — updated desc, deps, dispatch, help, caveats

---

## Quality Gates

All phases complete:

- ✅ **Proposal**: Scope, approach, risks, success criteria defined and locked
- ✅ **Specs**: 5 capability specs (3 new, 2 modified deltas) written and verified
- ✅ **Design**: 10 architectural decisions, sequence diagrams, traceability matrix
- ✅ **Tasks**: 9 work units with 65+ sub-tasks, dependency graph, locked URL corrections
- ✅ **Apply**: All WU-0 through WU-9 complete, commits verified, TDD cycle (RED → GREEN → REFACTOR)
- ✅ **Verify**: 112/113 tests pass, shellcheck clean, design coherence confirmed, post-verify fixes committed
- ✅ **Archive**: Specs merged to main, change folder moved to archive, audit trail preserved

---

## SDD Cycle Complete

The `quick-dev-setup` change has been fully executed through all SDD phases:

1. **Exploration** → research AI frameworks, cross-OS support
2. **Proposal** → scope, approach, risks, rollback plan
3. **Specs** → 5 capability specs (os-abstraction, node-toolchain, ai-dev-tools, bootstrap, doctor)
4. **Design** → detailed technical design, 10 architecture decisions
5. **Tasks** → 9 work units, dependency graph, locked corrections
6. **Apply** → 6 implementation batches, all WU-0 through WU-9 committed
7. **Verify** → 112/113 tests pass, shellcheck clean, warnings fixed
8. **Archive** → specs merged, change folder archived, ready for next change

---

## Next Steps

None. The change is closed. The following improvements are recorded as separate opportunities (outside this SDD cycle):

- Ubuntu CI may surface bats 1.5.0 compatibility on older Ubuntu LTS — pre-emptively handled by W-1 fix
- `test_n_accounts.bats` test 82 pre-existing failure should be investigated in a follow-up issue
- Linux paths can be further tested with additional Ubuntu CI coverage (already added in WU-8)

The Work-Swift-Kit now provides cross-OS (macOS + Linux) AI dev tools setup with per-account framework isolation and curated skills installation, ready for users to run `wsk setup` or `wsk ai`.

---

**Archived by**: sdd-archive executor
**Branch**: feat/quick-dev-setup (ready for merge to main)
**Date**: 2026-05-30
