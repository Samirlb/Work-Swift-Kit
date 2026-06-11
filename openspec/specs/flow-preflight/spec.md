# Flow Preflight Specification

## Purpose

Shared state/dependency validation that every WSK flow MUST invoke before operating on accounts or dotfiles. Prevents `set -u` crashes on empty arrays, missing binaries, and missing accounts.

## Requirements

### Requirement: Account Array Guard

`preflight_accounts` MUST verify that `WSK_ACCOUNTS` is non-empty before allowing any flow that reads `${WSK_ACCOUNTS[0]}` or iterates accounts. Under bash 3.2 with `set -u`, referencing an unset or empty array index is a fatal unbound-variable error. The guard MUST print a human-readable error and return non-zero when no accounts are loaded.

#### Scenario: Accounts loaded

- GIVEN `WSK_ACCOUNTS` contains at least one entry
- WHEN `preflight_accounts` is called
- THEN it returns 0 with no output

#### Scenario: Empty accounts array on clean machine

- GIVEN `WSK_ACCOUNTS` is unset or empty (no `accounts/*.env` files)
- WHEN `preflight_accounts` is called
- THEN it prints an error: `"No accounts configured — run: wsk accounts"`
- AND it returns non-zero

#### Scenario: Flow aborts when preflight fails

- GIVEN `WSK_ACCOUNTS` is empty
- WHEN `wsk relink` is invoked
- THEN the flow calls `preflight_accounts`, receives non-zero, and exits without reaching `render_gitconfig`
- AND no `set -u` unbound-variable abort occurs

---

### Requirement: Optional Dependency Guards

`preflight_deps` MUST check for optional binaries (`sd`, `rg`, `python3`) used in non-critical paths. Missing binaries MUST emit a `check_warn` and allow the flow to continue (degraded mode). They MUST NOT cause `set -e` exits.

#### Scenario: sd missing — persist falls back

- GIVEN `command -v sd` fails
- WHEN `preflight_deps` is called
- THEN `check_warn "sd not found — key-value persistence will use fallback"` is printed
- AND the function returns 0

#### Scenario: python3 missing — gentle-ai patch skipped

- GIVEN `command -v python3` fails
- WHEN `preflight_deps` is called
- THEN `check_warn "python3 not found — claude-md patching will be skipped"` is printed
- AND the function returns 0

#### Scenario: rg missing — cosmetic only

- GIVEN `command -v rg` fails
- WHEN `preflight_deps` is called
- THEN `check_warn "rg not found — update progress display skipped"` is printed
- AND the function returns 0

#### Scenario: All optional deps present

- GIVEN `sd`, `rg`, and `python3` are all on PATH
- WHEN `preflight_deps` is called
- THEN it returns 0 with no warnings

---

### Requirement: Bash 3.2 Empty-Array Safety

Any helper that iterates `WSK_ACCOUNTS` MUST use `${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}` (the `+` expansion guard) so that an empty array does not trigger an unbound-variable error under `set -u` on bash 3.2.

#### Scenario: Empty array with set -u does not abort

- GIVEN `WSK_ACCOUNTS=()` (empty) and `set -uo pipefail` active
- WHEN a function iterates `${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}` with a `for` loop
- THEN the loop body is never entered and the script continues without error

#### Scenario: Populated array iterates normally

- GIVEN `WSK_ACCOUNTS=("work" "personal")`
- WHEN the guarded loop runs
- THEN both entries are processed in order
