# Tasks — quick-dev-setup

> Strict TDD Mode: ON — bats test (RED) precedes every implementation task (GREEN).
> Lint gate: `shellcheck lib/*.sh templates/*.sh install.sh` must pass after every work unit.
> Test runner: `bats tests/e2e/`
> PR budget: 400 changed lines max per PR (see Review Workload Forecast at bottom).

---

## Locked URL Corrections (override design.md placeholders)

The following URLs are LOCKED and MUST be used by sdd-apply. These correct placeholders in design.md:

| Item | URL in design.md | LOCKED correct URL |
|------|-------------------|---------------------|
| gsd git-clone fallback remote | `https://github.com/Gentleman-Programming/get-shit-done` | `https://github.com/gsd-build/get-shit-done` |
| gsd npm primary | `npx --yes get-shit-done-cc --global` | `npx get-shit-done-cc --global` (primary) |
| Curated skills source repo | `https://github.com/Gentleman-Programming/wsk-skills` (variable `WSK_SKILLS_REPO`) | `https://github.com/Gentleman-Programming/gentle-ai` |
| Skills path inside that repo | `skills/{name}/` | `skills/{name}/` (same layout, different repo) |

design.md MUST be updated at apply time with these corrections before any implementation proceeds.

---

## Dependency Graph

```
WU-0 (stubs) ──► WU-1 (os.sh) ──► WU-2 (bootstrap refactor) ──► WU-3 (node.sh)
                                                                        │
                                                             ──► WU-4 (claude.sh)
                                                                        │
                                                             ──► WU-5 (frameworks.sh)
                                                                        │
                                         WU-2 + WU-5 ──► WU-6 (install.sh integration)
                                                                        │
                                         WU-1 + WU-5 ──► WU-7 (doctor.sh additions)
                                                                        │
                                                             ──► WU-8 (CI matrix)
                                                                        │
                                                             ──► WU-9 (README + Formula)
```

Parallel opportunities:
- WU-3, WU-4, WU-5 can proceed in parallel once WU-1 is green.
- WU-6 and WU-7 can proceed in parallel once WU-5 is green.
- WU-8 can proceed in parallel with WU-6/WU-7.
- WU-9 can proceed last or in parallel with WU-8.

---

## Work Unit 0 — Test Infrastructure: PATH shims + stub helpers

**PR boundary**: `feat/test-stubs` → main
**Spec**: os-abstraction §CI Coverage, design §6 stub matrix
**Sequential**: must land before any other work unit's RED tests

### 0.1 — Extend `tests/helpers/setup.bash` with stub infrastructure

- [x] Add `WSK_STUB_LOG` initialisation in `init_test_home` (creates `$WSK_TEST_HOME/stub-calls.log`).
- [x] Add a `stub_bin_dir` (`$WSK_TEST_HOME/bin`) prepended to `PATH` in `init_test_home`.
- [x] Add helper `stub_present <name>` — writes an executable shim at `$stub_bin_dir/<name>` that records invocation to `$WSK_STUB_LOG` and returns 0.
- [x] Add helper `stub_absent <name>` — removes `$stub_bin_dir/<name>`.
- [x] Add helper `assert_stub_called <pattern>` — `grep -q "<pattern>" "$WSK_STUB_LOG"` or fail with diff.
- [x] Add helper `assert_stub_not_called <pattern>` — inverse of above.
- [x] Add helper `stub_log` — prints `$WSK_STUB_LOG` for debugging.

### 0.2 — Add all required PATH shims

Write shims for: `node`, `npm`, `pnpm`, `corepack`, `claude`, `gentle-ai`, `codegraph`, `git`, `npx`, `winget`, `apt-get`, `dnf`, `pacman`, `curl`, `jq`, `sd`, `gum` (PATH-level, not exported-function; overrides existing exported-function gum stub for `command -v` satisfaction).

Each shim:
- Records `<name> <args>` to `$WSK_STUB_LOG` (or `$WSK_STUB_LOG_<NAME>` partition if preferred).
- Returns 0 by default.
- Reads `WSK_STUB_<NAME>_EXIT` env to override exit code.
- Reads `WSK_STUB_<NAME>_OUTPUT` env to echo output.

Special shim behaviors:
- `node --version` → echo `v20.0.0`.
- `git clone <remote> <dest>` → `mkdir -p "$dest"; touch "$dest/.stub-cloned"` (satisfies `[[ -d ]]` checks).
- `jq` → delegate to real `jq` (base package on CI; tests that call `_write_codegraph_mcp_config` need real JSON merging).
- `sd` → delegate to real `sd` (base package; `_persist_account_kv` needs it).
- `gum spin -- <cmd...>` → execute `<cmd...>` (same as current exported-function stub).

### 0.3 — Presence toggle helpers

- [x] Add `node_present` / `node_absent` convenience wrappers around `stub_present node` / `stub_absent node`.
- [x] Add equivalent wrappers for `pnpm`, `corepack`, `claude`, `codegraph`, `npx`, `gentle-ai`.

### 0.4 — Shellcheck + CI sanity

- [x] Run `shellcheck tests/helpers/setup.bash` (use `bash` dialect directive if needed).
- [x] Verify bats loads correctly: `bats tests/e2e/test_fresh_install.bats` still passes (existing tests unbroken).

**Commit**: `test(stubs): add PATH-shim infrastructure and stub helpers to setup.bash`

---

## Work Unit 1 — `lib/os.sh` (OS abstraction)

**PR boundary**: `feat/os-abstraction` → main (or stacked onto WU-0)
**Spec**: os-abstraction spec — all 4 requirements
**Depends on**: WU-0 (stubs must exist for RED tests)

### 1.1 — RED: write failing bats test file `tests/e2e/test_os_detection.bats`

- [x] Test: `detect_os` sets `WSK_OS=macos` when `uname` returns `Darwin`.
- [x] Test: `detect_os` sets `WSK_OS=linux` when `uname` returns `Linux` and `MSYSTEM` unset.
- [x] Test: `detect_os` sets `WSK_OS=windows` when `MSYSTEM` is set.
- [x] Test: `detect_os` sets `WSK_OS=windows` when `/proc/version` contains `microsoft`.
- [x] Test: `detect_pkg_mgr` sets `WSK_PKG_MGR=brew` when `brew` shim present, others absent.
- [x] Test: `detect_pkg_mgr` sets `WSK_PKG_MGR=apt` when `apt-get` shim present, brew absent.
- [x] Test: `detect_pkg_mgr` sets `WSK_PKG_MGR=dnf` correctly.
- [x] Test: `detect_pkg_mgr` sets `WSK_PKG_MGR=pacman` correctly.
- [x] Test: `detect_pkg_mgr` returns non-zero and prints warning when no manager present.

Verify these tests FAIL (RED) — `lib/os.sh` does not exist yet.

**Commit**: `test(os): RED — bats tests for detect_os and detect_pkg_mgr`

### 1.2 — RED: write failing bats test file `tests/e2e/test_pkg_install.bats`

- [x] Test: `WSK_PKG_MGR=brew`, `pkg_install <absent-pkg>` → `brew install <pkg>` recorded in stub log.
- [x] Test: `WSK_PKG_MGR=apt`, `pkg_install <absent-pkg>` → `apt-get install -y <pkg>` recorded.
- [x] Test: `WSK_PKG_MGR=dnf`, `pkg_install <absent-pkg>` → `dnf install -y <pkg>` recorded.
- [x] Test: `WSK_PKG_MGR=pacman`, `pkg_install <absent-pkg>` → `pacman -S --noconfirm <pkg>` recorded.
- [x] Test: `WSK_OS=windows`, `pkg_install <pkg>` → no manager stub called; instruction printed.
- [x] Test: idempotency — package shim present → no manager called; "already installed" in output.
- [x] Test: `--cask` flag with `WSK_PKG_MGR=brew` → `brew install --cask <pkg>` recorded.
- [x] Test: `--cask` guard uses `brew list --cask` instead of `command -v`.

Verify FAIL (RED).

**Commit**: `test(pkg-install): RED — bats tests for pkg_install router`

### 1.3 — GREEN: implement `lib/os.sh`

- [x] Create `lib/os.sh` with `#!/usr/bin/env bash` + `set -euo pipefail`.
- [x] Implement `detect_os` exactly as designed (Windows → `/proc/version` + MSYSTEM + uname MINGW/MSYS/CYGWIN; Darwin; Linux; default linux).
- [x] Implement `detect_pkg_mgr` exactly as designed (priority order: brew → apt-get → dnf → pacman → winget; warn + return 1 if none).
- [x] Implement `pkg_install <package> [--cask]` exactly as designed:
  - Parse `--cask` flag.
  - Idempotency: `command -v` for regular packages; `brew list --cask` for cask.
  - Windows: print instruction, return 0.
  - Brew (no cask): `ui_spin "Installing $pkg..." -- brew install "$pkg"`.
  - Brew (cask): `ui_spin "Installing $pkg..." -- brew install --cask "$pkg"`.
  - apt: `log_info "Installing $pkg..."` then `sudo apt-get install -y "$pkg"`.
  - dnf: `log_info "Installing $pkg..."` then `sudo dnf install -y "$pkg"`.
  - pacman: `log_info "Installing $pkg..."` then `sudo pacman -S --noconfirm "$pkg"`.
- [x] Run `shellcheck lib/os.sh` → clean.
- [x] Run `bats tests/e2e/test_os_detection.bats` → all pass (GREEN).
- [x] Run `bats tests/e2e/test_pkg_install.bats` → all pass (GREEN).
- [x] Run existing tests → all still pass.

**Commit**: `feat(os): implement lib/os.sh — detect_os, detect_pkg_mgr, pkg_install`

---

## Work Unit 2 — Bootstrap + packages + terminals cross-OS refactor

**PR boundary**: `refactor/cross-os-bootstrap` → main (or stacked onto WU-1)
**Spec**: bootstrap spec — OS Compatibility + pkg_install Prereqs requirements
**Depends on**: WU-1 (`lib/os.sh` must exist)

### 2.1 — RED: write failing tests in `tests/e2e/test_bootstrap_cross_os.bats`

- [x] Test: macOS path — `bootstrap` proceeds normally; `detect_os` called; no hard-exit.
- [x] Test: Linux path — `WSK_OS=linux` set; no exit; prereq packages installed via `pkg_install` (apt-get stub recorded calls to gum, stow, fzf, gettext).
- [x] Test: Windows path — `WSK_OS=windows` → instructions printed, exit 0.
- [x] Test: `packages.sh` on Linux — `WSK_PKG_MGR=apt` → each package installed via `apt-get`, NOT `brew`.
- [x] Test: `terminals.sh` on Linux — cask flag ignored; linux-native paths used for alacritty/kitty/wezterm/neovim; `check_warn` for unavailable items; Windows → instruction only.

Verify FAIL (RED) — bootstrap still exits on non-Darwin.

**Commit**: `test(bootstrap): RED — cross-OS bootstrap and package install tests`

### 2.2 — GREEN: refactor `lib/bootstrap.sh`

- [x] Remove Darwin-only `exit 1` guard.
- [x] Add `source "${WSK_DIR}/lib/os.sh"` (guard for double-source: wrap in `if ! declare -F detect_os > /dev/null` or just re-source idempotently since functions redefine).
- [x] Call `detect_os; detect_pkg_mgr || true`.
- [x] On Windows: print manual setup instructions, `exit 0`.
- [x] On macOS: existing Homebrew install path; replace `brew list` loop with `pkg_install` calls for `gum stow fzf gettext`.
- [x] On Linux: `pkg_install gum stow fzf gettext` (gum PATH shim already present in bats; on real Linux the charm repo or a workaround applies — document as known limitation, installer should warn, not fail).
- [x] Run `shellcheck lib/bootstrap.sh` → clean.

### 2.3 — GREEN: refactor `lib/packages.sh`

- [x] Replace `brew list "$pkg"` guard + `brew install "$pkg"` loop with `pkg_install "$bin"` (binary name, not label) using the existing label:binary mapping pattern.
- [x] Keep the `label:binary` pairs logic; pass the BINARY to `pkg_install` so the `command -v` guard works.
- [x] Run `shellcheck lib/packages.sh` → clean.

### 2.4 — GREEN: refactor `lib/terminals.sh`

- [x] On macOS: existing `brew install --cask <cask>` replaced with `pkg_install <cask> --cask`.
- [x] On Linux: map terminal names to native packages where available:
  - Alacritty → `pkg_install alacritty`
  - Kitty → `pkg_install kitty`
  - WezTerm → `pkg_install wezterm` (check_warn if not available via active mgr)
  - Neovim → `pkg_install neovim`
  - Warp / iTerm2 → macOS-only; `check_warn "$item not available on Linux"`, skip.
- [x] On Windows: `check_warn "$item: install manually on Windows"`, skip.
- [x] Run `shellcheck lib/terminals.sh` → clean.
- [x] Run `bats tests/e2e/test_bootstrap_cross_os.bats` → all pass (GREEN).
- [x] Run all existing tests → all pass.

**Commit**: `refactor(bootstrap): drop Darwin guard; use pkg_install for prereqs, packages, and terminals`

---

## Work Unit 3 — `lib/node.sh` (Node + pnpm)

**PR boundary**: `feat/node-toolchain` → main (or stacked onto WU-1)
**Spec**: node-toolchain spec — all 3 requirements
**Depends on**: WU-1 (`lib/os.sh`, `pkg_install`); WU-0 (stubs)
**Can run in parallel with**: WU-4, WU-5 (after WU-1 green)

### 3.1 — RED: write failing `tests/e2e/test_node_toolchain.bats`

- [x] Test: `install_node` — node absent, `WSK_OS=macos`, `WSK_PKG_MGR=brew` → brew stub records `install node`.
- [x] Test: `install_node` — node absent, `WSK_OS=linux`, `WSK_PKG_MGR=apt` → apt-get stub records `install -y node`.
- [x] Test: `install_node` — node present → no installer called; "already installed" in output.
- [x] Test: `install_node` — `WSK_OS=windows` → instruction printed; no installer called.
- [x] Test: `install_pnpm` — pnpm absent, `WSK_OS=macos` → brew stub records `install pnpm`; curl stub NOT called with pnpm URL.
- [x] Test: `install_pnpm` — pnpm absent, `WSK_OS=linux`, corepack shim present → corepack stub records `enable pnpm`.
- [x] Test: `install_pnpm` — pnpm absent, `WSK_OS=linux`, corepack absent → curl stub records `https://get.pnpm.io/install.sh`.
- [x] Test: `install_pnpm` — pnpm present → no installer called.
- [x] Test: `install_pnpm` — node absent → error "Node.js is required before pnpm" printed; non-zero exit; pnpm NOT attempted.
- [x] Test: `install_pnpm` — `WSK_OS=windows` → instruction printed; no installer called.

Verify FAIL (RED).

**Commit**: `test(node): RED — bats tests for install_node and install_pnpm`

### 3.2 — GREEN: implement `lib/node.sh`

- [x] Create `lib/node.sh` with `#!/usr/bin/env bash` + `set -euo pipefail`.
- [x] Implement `install_node` as designed (idempotent via `command -v node`; macOS/linux: `pkg_install node`; windows: instruction).
- [x] Implement `install_pnpm` as designed:
  - Idempotent via `command -v pnpm`.
  - Windows: instruction, return 0.
  - Node prereq guard: if no `node` → `log_error ...`, return 1.
  - macOS: `ui_spin "Installing pnpm..." -- brew install pnpm` (explicit brew, NOT `pkg_install`).
  - Linux + corepack: `corepack enable pnpm`.
  - Linux, no corepack: `curl -fsSL https://get.pnpm.io/install.sh | sh -`.
- [x] Run `shellcheck lib/node.sh` → clean.
- [x] Run `bats tests/e2e/test_node_toolchain.bats` → all pass (GREEN).
- [x] Run all existing tests → all pass.

**Commit**: `feat(node): implement lib/node.sh — install_node and install_pnpm`

---

## Work Unit 4 — `lib/claude.sh` (Claude Code + codegraph MCP)

**PR boundary**: `feat/claude-install` → main (or stacked onto WU-3)
**Spec**: ai-dev-tools spec — Claude Code Installation + Codegraph Installation requirements
**Depends on**: WU-1 (os.sh), WU-3 (node.sh node prereq guard); WU-0 (stubs)
**Can run in parallel with**: WU-3 (if node stub is available)

### 4.1 — RED: write failing `tests/e2e/test_claude_install.bats`

- [x] Test: `install_claude_code` — claude absent, `WSK_OS=macos/linux` → curl stub records `https://claude.ai/install.sh`; no brew call.
- [x] Test: `install_claude_code` — claude present → curl NOT called; "claude already installed" in output.
- [x] Test: `install_claude_code` — `WSK_OS=windows` → PowerShell instruction printed; curl NOT called.
- [x] Test: `install_codegraph <acct>` — codegraph absent, node present → npm stub records `i -g @colbymchenry/codegraph`; `~/.claude-<acct>/.mcp.json` created containing `"codegraph"` key.
- [x] Test: `install_codegraph` — codegraph present → npm NOT called; "already installed" in output.
- [x] Test: `install_codegraph` — node absent → error "Node.js is required for codegraph"; npm NOT called; non-zero exit.
- [x] Test: `_write_codegraph_mcp_config` — `.mcp.json` absent → written with correct JSON structure.
- [x] Test: `_write_codegraph_mcp_config` — `.mcp.json` present, no codegraph key → jq merges codegraph key in; existing keys preserved.
- [x] Test: `_write_codegraph_mcp_config` — `.mcp.json` present with `codegraph` already → no overwrite; "already configured" in output.
- [x] Test: `_write_codegraph_mcp_config` — jq absent → warns "add codegraph server manually"; does NOT clobber existing file.

Verify FAIL (RED).

**Commit**: `test(claude): RED — bats tests for install_claude_code and install_codegraph`

### 4.2 — GREEN: implement `lib/claude.sh`

- [x] Create `lib/claude.sh` with `#!/usr/bin/env bash` + `set -euo pipefail`.
- [x] Implement `install_claude_code` as designed.
- [x] Implement `_write_codegraph_mcp_config <acct> <cfg_dir>`:
  - `mkdir -p "$cfg_dir"`.
  - Idempotency: if `.mcp.json` contains `"codegraph"` key → pass + return.
  - Absent: write full MCP JSON object.
  - Present without codegraph + jq available: `jq '.mcpServers.codegraph = {...}'` merge in-place.
  - Present without codegraph, no jq: `check_warn` "add codegraph server manually".
- [x] Implement `install_codegraph <acct>` as designed (node prereq, idempotent, calls `_write_codegraph_mcp_config`).
- [x] Run `shellcheck lib/claude.sh` → clean.
- [x] Run `bats tests/e2e/test_claude_install.bats` → all pass (GREEN).
- [x] Run all existing tests → all pass.

**Commit**: `feat(claude): implement lib/claude.sh — install_claude_code, install_codegraph, MCP config writer`

---

## Work Unit 5 — `lib/frameworks.sh` (per-account AI framework + skills)

**PR boundary**: `feat/ai-frameworks` → main (or stacked onto WU-4)
**Spec**: ai-dev-tools spec — Per-Account Framework Selection, CLAUDE_CONFIG_DIR Isolation, Curated Skills, Standalone Menu/Dispatch requirements
**Depends on**: WU-1 (os.sh), WU-3 (node.sh), WU-4 (claude.sh); WU-0 (stubs)
**Can run in parallel with**: WU-3, WU-4 (authoring; integration waits for WU-4 green)

### 5.1 — RED: write failing `tests/e2e/test_ai_frameworks.bats`

**Framework install scenarios:**

- [ ] Test: `install_ai_framework work` — `ui_choose` returns `gentle-ai` → gentle-ai tap + install + `gentle-ai install --agent claude-code` called with `CLAUDE_CONFIG_DIR=$HOME/.claude-work`; `accounts/work.env` contains `AI_FRAMEWORK=gentle-ai`.
- [ ] Test: `install_ai_framework personal` — `ui_choose` returns `gsd` → npx stub records `get-shit-done-cc --global`; `accounts/personal.env` has `AI_FRAMEWORK=gsd`.
- [ ] Test: gsd fallback — `WSK_STUB_NPX_EXIT=1` → git stub records clone of `https://github.com/gsd-build/get-shit-done` (LOCKED URL).
- [ ] Test: `install_ai_framework work` — `ui_choose` returns `superpowers` → git stub records clone of `https://github.com/obra/superpowers` into `~/.claude-work/superpowers`; `/plugin install` instruction printed; env has `AI_FRAMEWORK=superpowers`.
- [ ] Test: per-account independence — work=gentle-ai, personal=gsd → env files independent; no cross-contamination.
- [ ] Test: re-run honoring — pre-seed `AI_FRAMEWORK=gentle-ai` in work.env → gum choose NOT recorded in stub log.
- [ ] Test: `CLAUDE_CONFIG_DIR` isolation — no write to `~/.claude/` (default dir) during any framework install.

**Codegraph offer in loop:**

- [ ] Test: `run_ai_for_all_accounts` — `ui_confirm` returns true → `install_codegraph` called for that account.
- [ ] Test: `ui_confirm` returns false → codegraph NOT installed; no error.

**Curated skills:**

- [ ] Test: `install_curated_skills personal gsd` → git stub records clone of `https://github.com/Gentleman-Programming/gentle-ai` (LOCKED URL); 6 skill dirs created under `~/.claude-personal/skills/`.
- [ ] Test: `install_curated_skills work gentle-ai` → git NOT called; "bundled by gentle-ai" in output.
- [ ] Test: idempotency — pre-create `~/.claude-personal/skills/branch-pr/` → git NOT called for branch-pr; other 5 still fetched.
- [ ] Test: skills source unavailable (`WSK_STUB_GIT_EXIT=1`) → `check_warn` per skill; no crash.

**`_persist_account_kv` helper:**

- [ ] Test: key absent → appended to env file.
- [ ] Test: key present → updated in-place (sd stub records the call; value changed).

**`_fetch_skill` helper:**

- [ ] Test: skills from `https://github.com/Gentleman-Programming/gentle-ai`, copied from `skills/{name}/`.
- [ ] Test: dest `[[ -d ]]` already exists → skip; git NOT called.

Verify FAIL (RED).

**Commit**: `test(frameworks): RED — bats tests for install_ai_framework, curated skills, per-account loop`

### 5.2 — GREEN: implement `lib/frameworks.sh`

- [ ] Create `lib/frameworks.sh` with `#!/usr/bin/env bash` + `set -euo pipefail`.
- [ ] Implement `_persist_account_kv <env_file> <key> <value>` (grep check → sd replace; else append).
- [ ] Implement `_fetch_skill <name> <dest>`:
  - Use `WSK_SKILLS_REPO="${WSK_SKILLS_REPO:-https://github.com/Gentleman-Programming/gentle-ai}"` (LOCKED URL).
  - Shallow clone to tmp; copy `skills/<name>/` to dest; cleanup tmp; `check_warn` on failure.
- [ ] Implement `install_curated_skills <acct> <framework>`:
  - gentle-ai: `check_pass "skills bundled by gentle-ai"`, return 0.
  - Others: loop 6 skills, `[[ -d ]]` guard, call `_fetch_skill`.
- [ ] Implement `install_ai_framework <acct>`:
  - Resolve env_file and cfg_dir.
  - Read existing `AI_FRAMEWORK=`; if set → skip `ui_choose`.
  - Else `ui_choose` among gentle-ai / gsd / superpowers.
  - Install per framework with `CLAUDE_CONFIG_DIR="$cfg_dir"` exported:
    - gentle-ai: brew tap `Gentleman-Programming/homebrew-tap`, `brew install gentle-ai` (idempotent via `command -v gentle-ai`), then `CLAUDE_CONFIG_DIR="$cfg_dir" gentle-ai install --agent claude-code`.
    - gsd: `CLAUDE_CONFIG_DIR="$cfg_dir" npx get-shit-done-cc --global`; on failure git-clone `https://github.com/gsd-build/get-shit-done` into `$cfg_dir/gsd` (LOCKED URL).
    - superpowers: git-clone `https://github.com/obra/superpowers` into `$cfg_dir/superpowers` (skip if dir exists); print `/plugin install` instruction.
  - `_persist_account_kv "$env_file" AI_FRAMEWORK "$choice"`.
- [ ] Implement `run_ai_for_all_accounts`:
  - Loop `WSK_ACCOUNTS`; call `install_ai_framework`; read persisted `AI_FRAMEWORK`; `ui_confirm "Install codegraph for $acct?"` → `install_codegraph`; `install_curated_skills "$acct" "$framework"`.
- [ ] Implement `run_ai`:
  - `load_accounts; detect_os; detect_pkg_mgr || true; install_node; install_pnpm; install_claude_code; run_ai_for_all_accounts`.
- [ ] Run `shellcheck lib/frameworks.sh` → clean.
- [ ] Run `bats tests/e2e/test_ai_frameworks.bats` → all pass (GREEN).
- [ ] Run all existing tests → all pass.

**Commit**: `feat(frameworks): implement lib/frameworks.sh — per-account framework, skills, codegraph loop`

---

## Work Unit 6 — `install.sh` integration (source order, menu, dispatch)

**PR boundary**: `feat/install-ai-menu` → main (or stacked onto WU-5)
**Spec**: ai-dev-tools spec — Standalone AI Dev Tools Menu Entry and Dispatch requirement
**Depends on**: WU-5 (frameworks.sh must exist); WU-3 (node.sh), WU-4 (claude.sh)

### 6.1 — RED: write failing `tests/e2e/test_install_ai_dispatch.bats`

- [ ] Test: `wsk ai` dispatch → `run_ai` called; accounts loaded; node/pnpm/claude/framework install loop runs.
- [ ] Test: `run_full_setup` order — AI steps (node → pnpm → claude → per-account loop) run after packages and before render.
- [ ] Test: menu entry "AI dev tools" exists in `ui_menu` call and triggers `run_ai`.

Verify FAIL (RED).

**Commit**: `test(install): RED — dispatch and menu entry tests for wsk ai`

### 6.2 — GREEN: update `install.sh`

- [ ] Add source statements after `accounts.sh` and before `terminals.sh`:
  ```bash
  source "${WSK_DIR}/lib/os.sh"
  source "${WSK_DIR}/lib/node.sh"
  source "${WSK_DIR}/lib/claude.sh"
  source "${WSK_DIR}/lib/frameworks.sh"
  ```
- [ ] Update `run_full_setup` to insert AI steps:
  ```bash
  detect_os; detect_pkg_mgr || true
  install_node
  install_pnpm
  install_claude_code
  run_ai_for_all_accounts
  ```
  (placed after `setup_gh_accounts` and before `render_all`).
- [ ] Add `ai) run_ai ;;` to `dispatch()`.
- [ ] Update usage string: `wsk [setup|accounts|terminals|relink|doctor|update|ai]`.
- [ ] Add menu entry in `ui_menu` call: `"AI dev tools::Install Claude Code, framework, codegraph and skills per account"`.
- [ ] Add case in menu switch: `*"AI dev tools"*) run_ai ;;`.
- [ ] Add tui_menu entry: `"ai::AI dev tools::Install Claude Code, framework, codegraph and skills per account"`.
- [ ] Run `shellcheck install.sh` → clean.
- [ ] Run `bats tests/e2e/test_install_ai_dispatch.bats` → all pass (GREEN).
- [ ] Run all existing tests → all pass.

**Commit**: `feat(install): wire ai dispatch, menu entry, and full-setup AI steps`

---

## Work Unit 7 — `lib/doctor.sh` additions

**PR boundary**: `feat/doctor-ai-sections` → main (or stacked onto WU-6)
**Spec**: doctor spec — all 5 new requirements
**Depends on**: WU-1 (os.sh vars), WU-5 (frameworks.sh — `AI_FRAMEWORK` env pattern)
**Can run in parallel with**: WU-6

### 7.1 — RED: write failing `tests/e2e/test_doctor_ai.bats`

OS/pkg-mgr section:
- [ ] Test: both present → `check_pass "OS: macos"` and `check_pass "pkg manager: brew"` in output.
- [ ] Test: `WSK_PKG_MGR` empty → `check_warn "no recognized package manager detected"` in output.

Node/pnpm section:
- [ ] Test: both present → `check_pass "node installed"` and `check_pass "pnpm installed"`.
- [ ] Test: pnpm absent → `check_fail "pnpm missing"`.

Claude Code section:
- [ ] Test: claude present → `check_pass "claude installed"`.
- [ ] Test: claude absent → `check_fail "claude not installed — run: wsk ai"`.

Per-account framework section:
- [ ] Test: `AI_FRAMEWORK=gentle-ai`, `gentle-ai` on PATH → `check_pass "work: AI_FRAMEWORK=gentle-ai (installed)"`.
- [ ] Test: `AI_FRAMEWORK=gsd`, gsd absent → `check_fail "personal: gsd not found on PATH"`.
- [ ] Test: `AI_FRAMEWORK=superpowers`, dir exists → `check_pass "work: AI_FRAMEWORK=superpowers (installed)"`.
- [ ] Test: `AI_FRAMEWORK` missing from env → `check_warn "work: AI_FRAMEWORK not set — run: wsk ai"`.

Codegraph section:
- [ ] Test: codegraph present → `check_pass "codegraph installed"`.
- [ ] Test: codegraph absent → `check_warn "codegraph not installed (optional)"`.

Skills section:
- [ ] Test: all 6 dirs present → 6 `check_pass` lines.
- [ ] Test: `judgment-day/` missing → `check_warn "work: judgment-day skill missing"`.
- [ ] Test: `AI_FRAMEWORK=gentle-ai` → `check_pass "work: skills bundled by gentle-ai"` (no per-skill checks).

Verify FAIL (RED).

**Commit**: `test(doctor): RED — bats tests for AI/OS/node/framework/skills health sections`

### 7.2 — GREEN: update `lib/doctor.sh`

- [ ] After `ui_subhead "Base packages"` block and before/replacing existing account loop top, insert new `ui_subhead` blocks in order:
  1. `ui_subhead "OS / Package manager"` — call `detect_os; detect_pkg_mgr || true`; output `check_pass/check_warn`.
  2. `ui_subhead "Node / pnpm"` — `command -v node/pnpm` checks.
  3. `ui_subhead "Claude Code"` — `command -v claude` check.
  4. `ui_subhead "AI frameworks (per account)"` — loop `WSK_ACCOUNTS`; read `AI_FRAMEWORK`; framework-specific presence check.
  5. Codegraph check inside the AI section.
  6. `ui_subhead "Skills (per account)"` — loop; gentle-ai short-circuit; else 6-skill dir loop.
- [ ] Run `shellcheck lib/doctor.sh` → clean.
- [ ] Run `bats tests/e2e/test_doctor_ai.bats` → all pass (GREEN).
- [ ] Run all existing tests → all pass.

**Commit**: `feat(doctor): add OS/node/claude/framework/codegraph/skills health sections`

---

## Work Unit 8 — CI: Ubuntu bats matrix

**PR boundary**: `ci/ubuntu-bats-matrix` → main
**Spec**: os-abstraction spec §CI Coverage requirement, design §6 Ubuntu job
**Depends on**: WU-0 (stub PATH shims must exist for Ubuntu to work without real installers)
**Can run in parallel with**: WU-6, WU-7

### 8.1 — Update `.github/workflows/ci.yml`

- [ ] Convert `test` job to matrix strategy:
  ```yaml
  strategy:
    fail-fast: false
    matrix:
      os: [macos-latest, ubuntu-latest]
  runs-on: ${{ matrix.os }}
  ```
- [ ] Add conditional dep install steps:
  - macOS: `brew install bats-core gum stow fzf gettext jq sd`
  - Ubuntu:
    ```bash
    sudo apt-get update
    sudo apt-get install -y bats stow gettext-base jq fzf
    # sd via cargo or release binary (sd not in default apt; use cargo install sd or snap)
    cargo install sd || true
    ```
  - Note: `gum` not in apt; bats stubs supply the gum PATH shim so no charm repo needed.
- [ ] Add `shellcheck` to Ubuntu lint job if not already there (it is — no change needed to lint job).
- [ ] Verify existing test run command `bats tests/e2e/` works on both runners (PATH stubs make it hermetic).

### 8.2 — Verify CI changes pass locally (manual check)

- [ ] Run `bats tests/e2e/` locally after WU-0 stubs are in place.
- [ ] Confirm `shellcheck lib/*.sh templates/*.sh install.sh` passes.

**Commit**: `ci: add ubuntu-latest to bats test matrix`

---

## Work Unit 9 — README + Formula updates

**PR boundary**: `docs/quick-dev-setup-readme` → main
**Spec**: proposal §Success Criteria; design §5 `wsk ai` dispatch
**Depends on**: WU-6 (wsk ai command finalized)
**Can run in parallel with**: WU-8

### 9.1 — Update `README.md`

- [ ] Add `wsk ai` to the commands table / usage section.
- [ ] Add cross-OS note: "macOS and Linux supported; Windows prints setup instructions without crashing."
- [ ] Add new dependencies section: Node.js, pnpm, Claude Code, codegraph (optional).
- [ ] Document the AI dev layer setup flow (framework choice per account, curated skills).
- [ ] Update `wsk doctor` / `wsk check` section noting new health sub-sections.

### 9.2 — Update Homebrew Formula (if present)

- [ ] Check for a `Formula/*.rb` file; if found update `desc`, `depends_on` (jq, sd if not already listed), and usage string.
- [ ] Verify formula references the updated `install.sh` dispatch.

**Commit**: `docs(readme): add wsk ai command, cross-OS note, and AI dev layer docs`

---

## Summary Checklist (by file)

| File | Action | Work Unit |
|------|--------|-----------|
| `tests/helpers/setup.bash` | Extend with PATH shims + helpers | WU-0 |
| `lib/os.sh` | NEW | WU-1 |
| `tests/e2e/test_os_detection.bats` | NEW | WU-1 |
| `tests/e2e/test_pkg_install.bats` | NEW | WU-1 |
| `lib/bootstrap.sh` | Drop Darwin guard; use pkg_install | WU-2 |
| `lib/packages.sh` | Replace brew loop with pkg_install | WU-2 |
| `lib/terminals.sh` | OS-aware cask/native routing | WU-2 |
| `tests/e2e/test_bootstrap_cross_os.bats` | NEW | WU-2 |
| `lib/node.sh` | NEW | WU-3 |
| `tests/e2e/test_node_toolchain.bats` | NEW | WU-3 |
| `lib/claude.sh` | NEW | WU-4 |
| `tests/e2e/test_claude_install.bats` | NEW | WU-4 |
| `lib/frameworks.sh` | NEW | WU-5 |
| `tests/e2e/test_ai_frameworks.bats` | NEW | WU-5 |
| `install.sh` | Source order, dispatch, menu entry, run_full_setup | WU-6 |
| `tests/e2e/test_install_ai_dispatch.bats` | NEW | WU-6 |
| `lib/doctor.sh` | Add 6 new sub-sections | WU-7 |
| `tests/e2e/test_doctor_ai.bats` | NEW | WU-7 |
| `.github/workflows/ci.yml` | Ubuntu matrix job | WU-8 |
| `README.md` | wsk ai docs, cross-OS, deps | WU-9 |
| `Formula/*.rb` (if exists) | Update desc + deps | WU-9 |

---

## Review Workload Forecast

### Estimated Changed Lines per Work Unit

| Work Unit | Files touched | Estimated additions | Estimated deletions | Net lines |
|-----------|---------------|--------------------|--------------------|-----------|
| WU-0 stubs | `setup.bash` | ~130 | ~0 | 130 |
| WU-1 os.sh | `lib/os.sh` (new ~90L) + 2 bats files (~110L) | ~200 | 0 | 200 |
| WU-2 refactor | `bootstrap.sh`, `packages.sh`, `terminals.sh` + 1 bats (~80L) | ~130 | ~40 | 170 |
| WU-3 node.sh | `lib/node.sh` (~60L) + 1 bats (~90L) | ~150 | 0 | 150 |
| WU-4 claude.sh | `lib/claude.sh` (~80L) + 1 bats (~110L) | ~190 | 0 | 190 |
| WU-5 frameworks.sh | `lib/frameworks.sh` (~160L) + 1 bats (~170L) | ~330 | 0 | 330 |
| WU-6 install.sh | `install.sh` (~30L) + 1 bats (~40L) | ~70 | ~5 | 75 |
| WU-7 doctor.sh | `lib/doctor.sh` (~80L) + 1 bats (~120L) | ~200 | 0 | 200 |
| WU-8 CI | `.github/workflows/ci.yml` (~20L) | ~25 | ~3 | 28 |
| WU-9 docs | `README.md`, Formula (~40L total) | ~50 | ~5 | 55 |
| **TOTAL** | **20+ files** | **~1475** | **~53** | **~1528** |

### Budget Assessment

| Metric | Value |
|--------|-------|
| Total estimated changed lines | ~1,528 |
| 400-line single-PR budget | 400 |
| Budget exceeded by | ~3.8× |
| **400-line budget risk** | **High** |
| **Chained PRs recommended** | **Yes** |
| **Decision needed before apply** | **Yes** |

### Suggested PR Slice Boundaries

All slices target `main` (Stacked PRs to main strategy). Each is independently reviewable and testable.

| PR | Branch | Work Units | Estimated lines | Content |
|----|--------|------------|----------------|---------|
| PR 1 | `feat/test-stubs` | WU-0 | ~130 | PATH shim infrastructure; no production code |
| PR 2 | `feat/os-abstraction` | WU-1 | ~200 | `lib/os.sh` + os/pkg-install bats |
| PR 3 | `refactor/cross-os-bootstrap` | WU-2 | ~170 | Bootstrap/packages/terminals refactor |
| PR 4 | `feat/node-toolchain` | WU-3 | ~150 | `lib/node.sh` + bats |
| PR 5 | `feat/claude-codegraph` | WU-4 | ~190 | `lib/claude.sh` + bats |
| PR 6 | `feat/ai-frameworks` | WU-5 | ~330 | `lib/frameworks.sh` + bats (largest; within budget) |
| PR 7 | `feat/install-ai-menu` | WU-6 | ~75 | `install.sh` wiring + bats |
| PR 8 | `feat/doctor-ai-sections` | WU-7 | ~200 | `lib/doctor.sh` additions + bats |
| PR 9 | `ci/ubuntu-bats-matrix` | WU-8 | ~28 | CI matrix |
| PR 10 | `docs/quick-dev-setup-readme` | WU-9 | ~55 | README + Formula |

Every PR is within the 400-line budget. Sequencing constraint: PR 1 → PR 2 → PR 3 and PR 4 and PR 5 (these three can batch-review in parallel after PR 2) → PR 6 → PR 7 and PR 8 (parallel) → PR 9 → PR 10.
