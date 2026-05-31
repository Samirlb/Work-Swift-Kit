# Doctor (Configuration Health Check) Specification

## Purpose

Extended configuration health checks to verify OS, package manager, Node.js, pnpm, Claude Code, AI frameworks, codegraph, and per-account skills installation.

## Requirements

### Requirement: OS and Package Manager Health Section

`run_doctor` MUST include a `ui_subhead "OS / Package manager"` sub-section that reports the detected OS (`WSK_OS`) and package manager (`WSK_PKG_MGR`) using `check_pass` or `check_warn`.

#### Scenario: OS and pkg manager detected

- GIVEN `detect_os` and `detect_pkg_mgr` have been called
- WHEN `run_doctor` runs the OS/pkg-mgr sub-section
- THEN `check_pass "OS: macos"` (or linux/windows) is printed
- AND `check_pass "pkg manager: brew"` (or apt/dnf/etc.) is printed

#### Scenario: No recognized package manager

- GIVEN `WSK_PKG_MGR` is empty or unset
- WHEN `run_doctor` runs the OS/pkg-mgr sub-section
- THEN `check_warn "no recognized package manager detected"` is printed

---

### Requirement: Node and pnpm Health Section

`run_doctor` MUST include a `ui_subhead "Node / pnpm"` sub-section that checks for `node` and `pnpm` binaries using `command -v`, reporting `check_pass` or `check_fail` for each.

#### Scenario: Both present

- GIVEN `command -v node` and `command -v pnpm` both succeed
- WHEN the Node/pnpm sub-section runs
- THEN `check_pass "node installed"` and `check_pass "pnpm installed"` are printed

#### Scenario: pnpm absent

- GIVEN `command -v node` succeeds and `command -v pnpm` fails
- WHEN the Node/pnpm sub-section runs
- THEN `check_fail "pnpm missing"` is printed

---

### Requirement: Claude Code Health Section

`run_doctor` MUST include a `ui_subhead "Claude Code"` sub-section that checks `command -v claude`, reporting `check_pass` or `check_fail`.

#### Scenario: Claude Code installed

- GIVEN `command -v claude` succeeds
- WHEN the Claude Code sub-section runs
- THEN `check_pass "claude installed"` is printed

#### Scenario: Claude Code absent

- GIVEN `command -v claude` fails
- WHEN the Claude Code sub-section runs
- THEN `check_fail "claude not installed — run: wsk ai"` is printed

---

### Requirement: Per-Account AI Framework Health Section

For each account in `WSK_ACCOUNTS`, `run_doctor` MUST check that:
1. `accounts/{acct}.env` contains an `AI_FRAMEWORK=` entry.
2. The chosen framework's binary or directory is present.

Checks MUST use `check_pass` / `check_fail` / `check_warn`.

| Framework | Presence check |
|-----------|----------------|
| `gentle-ai` | `command -v gentle-ai` |
| `gsd` | `command -v get-shit-done-cc` OR `command -v gsd` |
| `superpowers` | `~/.claude-{acct}/superpowers/` directory exists |

#### Scenario: Account with gentle-ai configured and installed

- GIVEN `accounts/work.env` contains `AI_FRAMEWORK=gentle-ai` and `command -v gentle-ai` succeeds
- WHEN the per-account framework sub-section runs for `work`
- THEN `check_pass "work: AI_FRAMEWORK=gentle-ai (installed)"` is printed

#### Scenario: Account with AI_FRAMEWORK missing from env

- GIVEN `accounts/work.env` does not contain `AI_FRAMEWORK=`
- WHEN the per-account framework sub-section runs for `work`
- THEN `check_warn "work: AI_FRAMEWORK not set — run: wsk ai"` is printed

#### Scenario: Account has framework set but binary absent

- GIVEN `accounts/personal.env` contains `AI_FRAMEWORK=gsd` and `command -v get-shit-done-cc` fails
- WHEN the per-account framework sub-section runs for `personal`
- THEN `check_fail "personal: gsd not found on PATH"` is printed

---

### Requirement: Codegraph Health Section

`run_doctor` MUST include a check for `codegraph` within the per-account or global AI section: `command -v codegraph` yields `check_pass` or `check_warn`.

#### Scenario: Codegraph installed

- GIVEN `command -v codegraph` succeeds
- WHEN the codegraph check runs
- THEN `check_pass "codegraph installed"` is printed

#### Scenario: Codegraph absent

- GIVEN `command -v codegraph` fails
- WHEN the codegraph check runs
- THEN `check_warn "codegraph not installed (optional)"` is printed

---

### Requirement: Per-Account Skills Health Section

For each account in `WSK_ACCOUNTS`, `run_doctor` MUST verify that each of the 6 curated skills (`branch-pr`, `chained-pr`, `work-unit-commits`, `comment-writer`, `issue-creation`, `judgment-day`) has a directory present under `~/.claude-{acct}/skills/{name}/`. Missing skills MUST use `check_warn`.

#### Scenario: All skills present for an account

- GIVEN all 6 skill directories exist under `~/.claude-work/skills/`
- WHEN the skills sub-section runs for `work`
- THEN 6 `check_pass` lines are printed, one per skill

#### Scenario: One skill missing

- GIVEN `~/.claude-work/skills/judgment-day/` does not exist
- WHEN the skills sub-section runs for `work`
- THEN `check_warn "work: judgment-day skill missing"` is printed
- AND the other 5 skills show `check_pass`

#### Scenario: gentle-ai account — skills bundled

- GIVEN `accounts/work.env` has `AI_FRAMEWORK=gentle-ai`
- WHEN the skills sub-section runs for `work`
- THEN a `check_pass "work: skills bundled by gentle-ai"` message is printed instead of individual skill checks
