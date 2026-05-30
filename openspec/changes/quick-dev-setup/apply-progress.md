# Apply Progress — quick-dev-setup

## Batch: 1 (WU-0 and WU-1)

### Status

- **WU-0**: DONE
- **WU-1**: DONE

### Commits

| Hash    | Message                                                            | Work Unit |
|---------|--------------------------------------------------------------------|-----------|
| 39e38e9 | test(stubs): add PATH-shim infrastructure and stub helpers to setup.bash | WU-0 |
| 35f05a6 | test(os): RED — bats tests for detect_os and detect_pkg_mgr       | WU-1 RED  |
| c97fb4f | test(pkg-install): RED — bats tests for pkg_install router         | WU-1 RED  |
| 3b90d5d | feat(os): implement lib/os.sh — detect_os, detect_pkg_mgr, pkg_install | WU-1 GREEN |

### Test Results

**bats tests/e2e/**:
- Total: 37 tests
- Passed: 36
- Failed: 1 (pre-existing: test 16 `.zshrc has three claude-{account} functions` — unrelated to WU-0/WU-1)
- New tests added: 17 (9 in test_os_detection.bats, 8 in test_pkg_install.bats)
- All new tests: PASS

**shellcheck lib/*.sh templates/*.sh install.sh**:
- Result: CLEAN (no errors or warnings)

**shellcheck tests/helpers/setup.bash**:
- Result: CLEAN

### Key Decisions and Gotchas

1. **PATH shim vs exported function priority**: Bash exported functions take priority over PATH
   executables for `command -v` lookups and direct invocation. Tests that use `detect_pkg_mgr`
   must `unset -f brew` (and other exported stub functions) before testing, or use isolated
   subprocess invocations with a clean PATH.

2. **detect_pkg_mgr isolation**: Tests that assert which package manager is detected must run
   `detect_pkg_mgr` in a fresh `bash -c` subprocess with a stripped PATH (only `$iso_bin:/usr/bin:/bin`)
   because on macOS, the real `/opt/homebrew/bin/brew` is in PATH.

3. **pkg_install idempotency tests**: Cannot use `git` as the test package because macOS has
   `/usr/bin/git` on PATH. Tests use a synthetic package name `wsk-fake-pkg-zz9` that is
   guaranteed absent, or `stub_present` for the already-installed case.

4. **design.md URL corrections applied**: The following locked URL corrections from tasks.md
   were applied to design.md before implementation:
   - gsd git fallback: `https://github.com/gsd-build/get-shit-done`
   - gsd npx primary: `npx get-shit-done-cc --global` (no `--yes`)
   - WSK_SKILLS_REPO: `https://github.com/Gentleman-Programming/gentle-ai`

5. **double-source guard**: `lib/os.sh` includes a `declare -f detect_os` guard to prevent
   double-source redefinition. This is harmless in production but tests that run in fresh
   subprocesses are unaffected.

### Files Changed

| File | Change |
|------|--------|
| `tests/helpers/setup.bash` | Extended: PATH shim infra, stub helpers, presence toggle wrappers |
| `tests/e2e/test_os_detection.bats` | NEW: 9 tests for detect_os and detect_pkg_mgr |
| `tests/e2e/test_pkg_install.bats` | NEW: 8 tests for pkg_install router |
| `lib/os.sh` | NEW: detect_os, detect_pkg_mgr, pkg_install |
| `openspec/changes/quick-dev-setup/design.md` | URL corrections applied |

---

## Remaining Work Units

- WU-2: Bootstrap + packages + terminals cross-OS refactor
- WU-3: lib/node.sh (Node + pnpm)
- WU-4: lib/claude.sh (Claude Code + codegraph MCP)
- WU-5: lib/frameworks.sh (per-account AI framework + skills)
- WU-6: install.sh integration (source order, menu, dispatch)
- WU-7: lib/doctor.sh additions
- WU-8: CI Ubuntu bats matrix
- WU-9: README + Formula updates
