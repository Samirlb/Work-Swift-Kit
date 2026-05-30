# Design — quick-dev-setup

Technical design for the AI dev layer + cross-OS package abstraction. This is the HOW at the
architectural level; `sdd-tasks` slices it into ordered steps. All decisions honor the locked
proposal decisions and the 5 delta specs (os-abstraction, node-toolchain, ai-dev-tools, bootstrap,
doctor).

## Design Principles (inherited from WSK style)

- Every new `.sh` starts with `#!/usr/bin/env bash` + `set -euo pipefail` and is shellcheck-clean.
- Functions are small, single-purpose, idempotent, and composable. No function both prompts AND
  installs AND persists unless it is an orchestrating loop.
- All user-facing prompts go through `lib/ui.sh` (`ui_choose`, `ui_confirm`, `ui_spin`); all status
  lines through `check_pass/fail/warn`; all logs through `log_*`. No raw `echo` for UX.
- State lives in `accounts/{acct}.env` (key=value, `grep '^KEY=' | cut -d= -f2-` reader pattern,
  matching `lib/accounts.sh` / `templates/zshrc.sh`).
- Per-account isolation is achieved by exporting `CLAUDE_CONFIG_DIR=$HOME/.claude-{acct}` for the
  duration of each Claude-adjacent call — never writing to the default `~/.claude/`.
- Idempotency guard order: cheap `command -v` / directory `[[ -d ]]` checks BEFORE any installer.

## Architecture Overview

```
install.sh (source order)
  log.sh
  bootstrap.sh ── sources ──> os.sh   (detect_os, detect_pkg_mgr, pkg_install)
  ui.sh
  accounts.sh
  os.sh        (also sourced top-level so all modules see it)
  node.sh      ── uses ──> os.sh (pkg_install), log.sh, ui.sh
  claude.sh    ── uses ──> os.sh, node.sh (node prereq), ui.sh
  frameworks.sh── uses ──> os.sh, claude.sh, ui.sh, accounts.sh (per-acct env IO)
  terminals.sh ── uses ──> os.sh (pkg_install / cask routing)
  packages.sh  ── uses ──> os.sh (pkg_install)
  render.sh, stow.sh, gh.sh
  doctor.sh    ── reads ──> os.sh vars + accounts/{acct}.env
  update.sh, tui.sh
```

Dependency rule: `os.sh` is the lowest new layer (no deps but log.sh). `node.sh` depends on
`os.sh`. `claude.sh` depends on `node.sh`/`os.sh`. `frameworks.sh` is the top orchestrator and
depends on everything below + `accounts.sh`. No cycles.

### Component / data-flow map

```
run_full_setup / wsk ai
        │
        ├─ detect_os ──► WSK_OS  ─────────────┐
        ├─ detect_pkg_mgr ──► WSK_PKG_MGR ────┤ (env, set once, exported)
        │                                     │
        ├─ install_node       (global, once) ─┤ uses pkg_install
        ├─ install_pnpm       (global, once) ─┤ node prereq
        ├─ install_claude_code(global, once) ─┘ curl native
        │
        └─ for acct in WSK_ACCOUNTS:           ┌── CLAUDE_CONFIG_DIR=~/.claude-{acct}
              install_ai_framework "$acct" ────┤   ui_choose → install → persist AI_FRAMEWORK=
              install_codegraph "$acct"    ────┤   ui_confirm → npm i -g → MCP config write
              install_curated_skills "$acct" ──┘   git fetch → ~/.claude-{acct}/skills/{name}/
```

---

## 1. `lib/os.sh` (NEW) — OS abstraction

Lowest layer. Sets two exported globals and provides the install router. Sourced both inside
`bootstrap.sh` (so bootstrap can use `pkg_install`) and top-level in `install.sh`.

### `detect_os`

Sets and exports `WSK_OS` ∈ {`macos`,`linux`,`windows`}. Detection order (Windows first because a
Git-Bash/WSL shell still reports `Linux`/`MINGW` from uname):

```sh
detect_os() {
  if [[ -n "${MSYSTEM:-}" ]] \
     || [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || "$(uname -s)" == CYGWIN* ]] \
     || grep -qi microsoft /proc/version 2>/dev/null; then
    WSK_OS="windows"
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    WSK_OS="macos"
  elif [[ "$(uname -s)" == "Linux" ]]; then
    WSK_OS="linux"
  else
    WSK_OS="linux"   # safe default for other unices; pkg_mgr detection gates real action
  fi
  export WSK_OS
}
```

Note: `grep -qi microsoft /proc/version` distinguishes WSL from native Linux (spec scenario
"Windows environment detected"). `MSYSTEM` set ⇒ Git Bash. Native Ubuntu has neither ⇒ `linux`.

### `detect_pkg_mgr`

Sets/exports `WSK_PKG_MGR` ∈ {`brew`,`apt`,`dnf`,`pacman`,`winget`}. Binary-presence based, checked
in priority order. Returns non-zero + warns when none found (spec: "No recognized package manager").

```sh
detect_pkg_mgr() {
  if   command -v brew    &>/dev/null; then WSK_PKG_MGR="brew"
  elif command -v apt-get &>/dev/null; then WSK_PKG_MGR="apt"
  elif command -v dnf     &>/dev/null; then WSK_PKG_MGR="dnf"
  elif command -v pacman  &>/dev/null; then WSK_PKG_MGR="pacman"
  elif command -v winget  &>/dev/null; then WSK_PKG_MGR="winget"
  else
    WSK_PKG_MGR=""
    export WSK_PKG_MGR
    log_warn "No recognized package manager detected."
    return 1
  fi
  export WSK_PKG_MGR
}
```

### `pkg_install <package> [--cask]`

Router + idempotency guard. Signature accepts an optional `--cask` flag for macOS GUI apps
(consumed by `terminals.sh`); the flag is ignored on non-brew managers.

Behavior:
1. Parse args: first positional = `pkg`, optional `--cask`.
2. Idempotency: `command -v "$pkg"` → if present, `check_pass "$pkg already installed"`, return 0.
   (Casks have no PATH binary; for `--cask` use `brew list --cask "$pkg"` as the guard instead.)
3. Windows: `print` a manual instruction (`"Please install $pkg manually via winget or the
   Microsoft Store"`), return 0 — never execute.
4. Route on `WSK_PKG_MGR`:

| WSK_PKG_MGR | command |
|-------------|---------|
| brew (no flag) | `brew install "$pkg"` |
| brew (`--cask`) | `brew install --cask "$pkg"` |
| apt | `sudo apt-get install -y "$pkg"` |
| dnf | `sudo dnf install -y "$pkg"` |
| pacman | `sudo pacman -S --noconfirm "$pkg"` |
| winget | `winget install -e --id "$pkg"` (only reached if a Windows winget path is wired; default Windows branch is instruction-only) |

The actual install is wrapped in `ui_spin "Installing $pkg..." -- <cmd...>` to match
`packages.sh`/`terminals.sh` UX, EXCEPT on apt/dnf/pacman where `sudo` may prompt for a password —
those run un-spun (a spinner hides the password prompt). Decision: spin only on brew; run linux
managers directly with a `log_info "Installing $pkg..."` line.

Idempotency strategy summary (per spec "pkg_install Idempotency"): `command -v` for CLI tools,
`brew list --cask` for casks. The package NAME and the BINARY name can differ (e.g. `ripgrep`→`rg`);
for those callers pass the binary name when it differs, or the caller does its own pre-check (see
how `packages.sh` already maps `ripgrep:rg`). `pkg_install` uses the single argument it receives as
both install target and `command -v` probe; callers needing a different probe must guard themselves.
→ Decision D7 below resolves this cleanly.

### How consumers use it

- `bootstrap.sh`: `source lib/os.sh; detect_os; detect_pkg_mgr; for p in gum stow fzf gettext; do
  pkg_install "$p"; done`. On Windows → print instructions, `exit 0`.
- `packages.sh`: replace the `brew list / brew install` loop body with `pkg_install "$bin"` where
  `$bin` is the binary name (so the `command -v` guard works) — keeps the `ripgrep:rg` label/binary
  split, passing the BINARY to `pkg_install`.
- `terminals.sh`: GUI terminals via `pkg_install <cask> --cask` on macOS; on Linux map to the
  native package where one exists (alacritty, kitty, wezterm, neovim available via apt/dnf/pacman)
  and `check_warn` + skip where not. Windows → instruction only.

---

## 2. `lib/node.sh` (NEW) — Node + pnpm

### `install_node`

Idempotent via `command -v node`. Method matrix (spec table):

| WSK_OS | method |
|--------|--------|
| macos | `pkg_install node` (resolves to `brew install node`) |
| linux | `pkg_install node` (apt/dnf/pacman) |
| windows | print `"Install Node via winget: winget install OpenJS.NodeJS"`, return 0 |

```sh
install_node() {
  if command -v node &>/dev/null; then check_pass "node already installed"; return 0; fi
  if [[ "$WSK_OS" == "windows" ]]; then
    log_info "Install Node via winget: winget install OpenJS.NodeJS"; return 0
  fi
  pkg_install node
}
```

Decision D6 (fnm vs system node on linux): use **system node via `pkg_install`** as primary. Rationale
below. We do NOT introduce fnm in this change (keeps the matrix small and the idempotency guard a
plain `command -v node`). fnm is recorded as a future option.

### `install_pnpm`

Order-enforced + idempotent. Per spec "Install Order Enforcement": MUST verify `command -v node`
first; if absent → `log_error "Node.js is required before pnpm"`, return 1.

| WSK_OS | method |
|--------|--------|
| macos (any arch) | `brew install pnpm` — ALWAYS. Never the get.pnpm.io standalone script (fails on Intel darwin-x64). |
| linux + corepack present | `corepack enable pnpm` |
| linux, no corepack | `curl -fsSL https://get.pnpm.io/install.sh \| sh -` |
| windows | print `"Install pnpm via winget: winget install pnpm.pnpm"`, return 0 |

```sh
install_pnpm() {
  if command -v pnpm &>/dev/null; then check_pass "pnpm already installed"; return 0; fi
  if [[ "$WSK_OS" == "windows" ]]; then
    log_info "Install pnpm via winget: winget install pnpm.pnpm"; return 0
  fi
  if ! command -v node &>/dev/null; then
    log_error "Node.js is required before pnpm"; return 1
  fi
  case "$WSK_OS" in
    macos) ui_spin "Installing pnpm..." -- brew install pnpm ;;   # NOT pkg_install: must force brew, never standalone
    linux)
      if command -v corepack &>/dev/null; then corepack enable pnpm
      else curl -fsSL https://get.pnpm.io/install.sh | sh -; fi ;;
  esac
}
```

Note: macOS uses `brew install pnpm` directly (not `pkg_install pnpm`) only to make the "must be
brew, never standalone" guarantee unmistakable at the call site; functionally `pkg_install pnpm`
would also resolve to brew on macOS. Either is spec-compliant — chosen the explicit form for intent
clarity. Decision D6b.

---

## 3. `lib/claude.sh` (NEW) — Claude Code + codegraph

### `install_claude_code`

Global, once. Idempotent via `command -v claude`.

```sh
install_claude_code() {
  if command -v claude &>/dev/null; then check_pass "claude already installed"; return 0; fi
  if [[ "$WSK_OS" == "windows" ]]; then
    log_info "Run in PowerShell: irm https://claude.ai/install.ps1 | iex"; return 0
  fi
  ui_spin "Installing Claude Code..." -- bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
}
```

### `install_codegraph <account>`

Per-account-invoked but installs a global binary (`npm i -g`). Idempotent via `command -v
codegraph`. Node prereq enforced. Takes the account so it can write the per-account MCP config.

```sh
install_codegraph() {
  local acct="$1"
  local cfg_dir="$HOME/.claude-${acct}"
  if ! command -v node &>/dev/null; then
    log_error "Node.js is required for codegraph"; return 1
  fi
  if ! command -v codegraph &>/dev/null; then
    ui_spin "Installing codegraph..." -- npm i -g @colbymchenry/codegraph
  else
    check_pass "codegraph already installed"
  fi
  _write_codegraph_mcp_config "$acct" "$cfg_dir"
}
```

### Per-account codegraph MCP config — RESOLVES SPEC RISK #3

Spec said "codegraph MCP config is written into `~/.claude-work/`" without a format. Decision:

- **File path**: `$HOME/.claude-{acct}/.mcp.json` (Claude Code's project/config-dir MCP manifest;
  when `CLAUDE_CONFIG_DIR=~/.claude-{acct}` this is the file Claude reads for MCP servers).
- **Format**: standard Claude MCP JSON:

```json
{
  "mcpServers": {
    "codegraph": {
      "command": "codegraph",
      "args": ["mcp"],
      "env": {}
    }
  }
}
```

- **Writer** `_write_codegraph_mcp_config <acct> <cfg_dir>`:
  1. `mkdir -p "$cfg_dir"`.
  2. Idempotency: if `.mcp.json` already contains a `"codegraph"` server key → `check_pass
     "codegraph MCP already configured for {acct}"`, return.
  3. If `.mcp.json` is absent → write the full object above.
  4. If `.mcp.json` exists WITHOUT codegraph → merge. Prefer `jq` (already a base package, see
     `packages.sh`): `jq '.mcpServers.codegraph = {...}'`. Fallback when `jq` absent: write the
     object only if file is absent, else `check_warn "{acct}: .mcp.json exists, add codegraph
     server manually"` (non-destructive — never clobber an existing manifest).

Rationale: `.mcp.json` is the documented Claude Code MCP config name; writing into the per-account
`CLAUDE_CONFIG_DIR` keeps codegraph scoped to that account. `jq`-merge keeps it non-destructive and
idempotent; the absence-only fallback guarantees we never corrupt a hand-edited manifest.

---

## 4. `lib/frameworks.sh` (NEW) — per-account framework + skills

Top orchestrator over Claude config. Two public functions + the per-account loop driver.

### `install_ai_framework <account>`

Steps:
1. Resolve `env_file="${WSK_DIR}/accounts/${acct}.env"`, `cfg_dir="$HOME/.claude-${acct}"`.
2. **Re-run honoring** (spec "Existing framework choice honored"): read existing
   `AI_FRAMEWORK=` via `grep '^AI_FRAMEWORK=' "$env_file" | cut -d= -f2-`. If non-empty → use it,
   do NOT `ui_choose`.
3. Else `choice=$(ui_choose "AI framework for ${acct}:" "gentle-ai" "gsd" "superpowers")`. Exclusive
   by construction (`ui_choose` = single select).
4. Install with `CLAUDE_CONFIG_DIR="$cfg_dir"` exported for the call duration:
   - **gentle-ai**: `pkg_install` can't add a tap, so: `brew tap Gentleman-Programming/homebrew-tap`
     then `pkg_install gentle-ai` (or `brew install gentle-ai` on macOS/linux-brew); then
     `CLAUDE_CONFIG_DIR="$cfg_dir" gentle-ai install --agent claude-code`. Idempotent via
     `command -v gentle-ai` before tap/install.
   - **gsd**: `CLAUDE_CONFIG_DIR="$cfg_dir" npx --yes get-shit-done-cc --global` (Node prereq —
     guard `command -v node`). Fallback if npx package unavailable: git clone (Decision D2).
   - **superpowers**: `git clone https://github.com/obra/superpowers "$cfg_dir/superpowers"` (skip
     if dir exists); then `log_info "Open Claude and run: /plugin install"`.
5. Persist: `_persist_account_kv "$env_file" AI_FRAMEWORK "$choice"` (see helper below).
6. Codegraph offer is NOT inside this function — the loop calls `install_codegraph` after, gated by
   `ui_confirm`, so framework selection stays single-purpose.

`_persist_account_kv <env_file> <key> <value>` helper (idempotent upsert):
```sh
_persist_account_kv() {
  local file="$1" key="$2" val="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sd "^${key}=.*" "${key}=${val}" "$file"      # sd is a base package
  else
    printf '%s=%s\n' "$key" "$val" >> "$file"
  fi
}
```
(`sd` is already installed by `packages.sh`; bats stub will provide it. Avoids fragile in-place
`sed -i` portability differences between macOS/Linux — Decision D8.)

### gsd source — Decision D2 (resolves proposal open question #1)

- **Primary**: `npx --yes get-shit-done-cc --global` (npm, documented in exploration).
- **Fallback remote (named)**: `https://github.com/Gentleman-Programming/get-shit-done` — git clone
  into `$cfg_dir/gsd` if the npm package errors/404s. The fallback remote is pinned here so tasks
  and apply do not re-litigate it. (If apply discovers the canonical repo differs, that is a verify
  finding, not a silent change.)

### `install_curated_skills <account>` — RESOLVES SPEC RISK #2

Installs the 6 curated skills into `$HOME/.claude-{acct}/skills/{name}/`:
`branch-pr`, `chained-pr`, `work-unit-commits`, `comment-writer`, `issue-creation`, `judgment-day`.

**gentle-ai handling (spec risk #2)** — Decision: **SKIP** the explicit curated install for
gentle-ai accounts. gentle-ai's `install --agent claude-code` already injects an equivalent skills
set; re-cloning would duplicate/conflict. Doctor reflects this with `check_pass "{acct}: skills
bundled by gentle-ai"` (matches doctor spec scenario). For `gsd` and `superpowers` accounts, run the
explicit clone loop.

```sh
install_curated_skills() {
  local acct="$1" framework="$2"
  local skills_dir="$HOME/.claude-${acct}/skills"
  if [[ "$framework" == "gentle-ai" ]]; then
    check_pass "${acct}: skills bundled by gentle-ai"; return 0
  fi
  mkdir -p "$skills_dir"
  local name
  for name in branch-pr chained-pr work-unit-commits comment-writer issue-creation judgment-day; do
    if [[ -d "$skills_dir/$name" ]]; then
      check_pass "${acct}: ${name} skill present"; continue        # idempotent
    fi
    _fetch_skill "$name" "$skills_dir/$name"
  done
}
```

### Skills fetch method — Decision D1 (resolves proposal open question #2 / exploration Q1)

Two candidates:

| Option | Pros | Cons |
|--------|------|------|
| **A. Single mono-repo sparse/partial clone** of one curated-skills repo, copying `skills/{name}` out | one network op, one source of truth | needs a real curated repo to exist; sparse-checkout adds complexity |
| **B. Per-skill git clone** from a skills repo into the target dir | simplest, idempotent per-skill, matches `[[ -d ]]` guard | N clone calls; needs each skill resolvable |

**Decision: Option B (per-skill fetch) via a single helper `_fetch_skill <name> <dest>`** that
clones from a configurable base repo, with the base pinned as a variable so tasks don't hardcode it
in six places:

```sh
WSK_SKILLS_REPO="${WSK_SKILLS_REPO:-https://github.com/Gentleman-Programming/wsk-skills}"
_fetch_skill() {
  local name="$1" dest="$2"
  # Layout assumption: repo contains skills/{name}/ ; shallow clone to tmp, copy one skill out.
  local tmp; tmp="$(mktemp -d)"
  if git clone --depth 1 "$WSK_SKILLS_REPO" "$tmp" &>/dev/null \
     && [[ -d "$tmp/skills/$name" ]]; then
    mkdir -p "$dest"; cp -R "$tmp/skills/$name/." "$dest/"
    check_pass "${name} skill installed"
  else
    check_warn "${name}: skill source unavailable (set WSK_SKILLS_REPO)"
  fi
  rm -rf "$tmp"
}
```

Rationale: keeps each skill's presence individually idempotent (`[[ -d "$dest" ]]`), uses one pinned
repo var (override-friendly for the user's real global set), degrades to `check_warn` rather than
failing the whole setup when the source is unreachable. `WSK_SKILLS_REPO` is the single seam tasks
must wire and tests must stub. (If a real per-skill repo set is preferred later, only `_fetch_skill`
changes — callers are stable.)

---

## 5. Integration

### `install.sh` source order

Add, after `accounts.sh` and before `terminals.sh`:
```
source "${WSK_DIR}/lib/os.sh"
source "${WSK_DIR}/lib/node.sh"
source "${WSK_DIR}/lib/claude.sh"
source "${WSK_DIR}/lib/frameworks.sh"
```
`bootstrap.sh` also sources `os.sh` internally (it runs before the rest are sourced), guarded so a
double-source is harmless (functions just redefine).

### `run_full_setup` new order

```sh
run_full_setup() {
  collect_accounts
  install_packages          # now via pkg_install
  install_terminals         # now OS-aware
  setup_gh_accounts
  # ── AI dev layer ──
  detect_os; detect_pkg_mgr || true
  install_node
  install_pnpm
  install_claude_code
  run_ai_for_all_accounts   # per-account loop (shared with `wsk ai`)
  # ── dotfiles ──
  render_all
  link_dotfiles
  log_info "Restart your terminal or run: source ~/.zshrc"
}
```

Note `detect_os/detect_pkg_mgr` already run inside `bootstrap` at startup, but `run_full_setup` is
also reachable via `wsk setup` after bootstrap; calling them again is cheap + idempotent and
guarantees the vars are set even if invoked standalone.

### Shared per-account loop + `wsk ai`

One driver function used by BOTH the menu entry and the CLI (spec "Standalone AI Dev Tools Menu Entry
and Dispatch"):

```sh
run_ai_for_all_accounts() {
  local acct framework
  for acct in "${WSK_ACCOUNTS[@]}"; do
    install_ai_framework "$acct"
    framework=$(grep '^AI_FRAMEWORK=' "${WSK_DIR}/accounts/${acct}.env" | cut -d= -f2-)
    if ui_confirm "Install codegraph for ${acct}?"; then
      install_codegraph "$acct"
    fi
    install_curated_skills "$acct" "$framework"
  done
}

run_ai() {                # wsk ai entry — loads accounts first (standalone)
  load_accounts
  detect_os; detect_pkg_mgr || true
  install_node; install_pnpm; install_claude_code
  run_ai_for_all_accounts
}
```

`dispatch()` gets `ai) run_ai ;;` and the usage string adds `ai`. The interactive menu gets a new
entry `"AI dev tools::Install Claude Code, framework, codegraph and skills per account"` mapped to
`*"AI dev tools"*) run_ai ;;` (and the `tui_menu` variant `"ai::AI dev tools::..."`).

`run_full_setup` calls `run_ai_for_all_accounts` directly (accounts already loaded by
`collect_accounts`), so global installers (node/pnpm/claude) aren't duplicated.

### `doctor.sh` new sub-sections

All additive, placed after "Base packages" and before/around "Accounts". Each uses
`check_pass/fail/warn` and reads per-account `AI_FRAMEWORK` from env. New `ui_subhead` sections:

1. **`ui_subhead "OS / Package manager"`** — `detect_os; detect_pkg_mgr || true`; then
   `check_pass "OS: $WSK_OS"`; if `$WSK_PKG_MGR` non-empty → `check_pass "pkg manager:
   $WSK_PKG_MGR"` else `check_warn "no recognized package manager detected"`.
2. **`ui_subhead "Node / pnpm"`** — `command -v node` → pass/fail; `command -v pnpm` → pass
   (`check_fail "pnpm missing"` when absent).
3. **`ui_subhead "Claude Code"`** — `command -v claude` → `check_pass "claude installed"` /
   `check_fail "claude not installed — run: wsk ai"`.
4. **`ui_subhead "AI frameworks (per account)"`** — loop `WSK_ACCOUNTS`; read `AI_FRAMEWORK=`:
   - missing → `check_warn "$acct: AI_FRAMEWORK not set — run: wsk ai"`.
   - present → presence check per table: gentle-ai→`command -v gentle-ai`; gsd→`command -v
     get-shit-done-cc || command -v gsd`; superpowers→`[[ -d ~/.claude-$acct/superpowers ]]`.
     Pass → `check_pass "$acct: AI_FRAMEWORK=$fw (installed)"`; binary absent → `check_fail "$acct:
     $fw not found on PATH"`.
5. **codegraph** — `command -v codegraph` → `check_pass "codegraph installed"` / `check_warn
   "codegraph not installed (optional)"` (can live inside the AI section).
6. **`ui_subhead "Skills (per account)"`** — loop accounts; if `AI_FRAMEWORK=gentle-ai` →
   `check_pass "$acct: skills bundled by gentle-ai"`; else for each of the 6 skills `[[ -d
   ~/.claude-$acct/skills/$name ]]` → `check_pass` / `check_warn "$acct: $name skill missing"`.

`run_doctor` already calls `load_accounts`, so `WSK_ACCOUNTS` is populated for all loops.

---

## 6. Test design (Strict TDD ON — RED → GREEN → REFACTOR)

Test runner: `bats tests/e2e/`. Lint gate: `shellcheck lib/*.sh templates/*.sh install.sh`.
Every new `.sh` MUST pass shellcheck. Tests source the lib under test directly and assert against
stub-recorded invocations + filesystem state in an isolated `$HOME`.

### Stub matrix — additions to `tests/helpers/setup.bash`

Existing stubs: `gum`, `brew`, `ssh-keygen`. Add the following. Pattern: each stub records its
invocation to a per-test log file (`$WSK_STUB_LOG`) so tests can assert routing, AND no-ops the real
side effect. Provide a `stub_log()` helper + `assert_stub_called <pattern>`.

| Stub | Behavior |
|------|----------|
| `node` | `command -v node` must succeed when "present"; toggled via a `WSK_STUB_NODE=1/0` env. When `node --version` called → echo `v20.0.0`. |
| `npm` | record args (`i -g @colbymchenry/codegraph`, etc.), return 0. |
| `pnpm` | presence toggle `WSK_STUB_PNPM`; record. |
| `corepack` | presence toggle `WSK_STUB_COREPACK`; `enable pnpm` → record, return 0. |
| `claude` | presence toggle `WSK_STUB_CLAUDE`; record. |
| `gentle-ai` | presence toggle; `install --agent claude-code` → assert `CLAUDE_CONFIG_DIR` env is the per-acct dir, record. |
| `codegraph` | presence toggle `WSK_STUB_CODEGRAPH`; `mcp` subcommand harmless. |
| `git` | `clone ...` → `mkdir -p "$dest"` + write a marker file (so `[[ -d ]]` idempotency + skill/superpowers dir assertions pass); record the remote URL. |
| `npx` | `--yes get-shit-done-cc --global` → record, return 0 (toggle a failure mode `WSK_STUB_NPX_FAIL=1` to exercise the gsd git fallback). |
| `winget` | record only (Windows path is instruction-only; present so a forced `WSK_OS=windows` test asserts it is NEVER called). |
| `apt-get` / `dnf` / `pacman` | record args; return 0. Used by `pkg_install` routing tests with `WSK_PKG_MGR` forced. |
| `curl` | record URL; for `claude.ai/install.sh` and `get.pnpm.io` paths return 0 without network. |
| `jq` / `sd` | thin real-ish stubs OR rely on real binaries (both are base packages; on CI runners install them). Decision: install real `jq`/`sd` on CI; in unit-ish bats use the real binaries against tmp files. |

Presence toggling: a single helper `stub_present <name>` (creates an executable shim on `PATH`)
and `stub_absent <name>` (removes it / makes `command -v` fail by pointing `PATH` to a clean dir).
The existing `init_test_home` is extended to also create `$WSK_STUB_LOG` and a stub `bin/` prepended
to `PATH`.

### What bats asserts (per spec scenarios)

New test files (one concern each, mirroring existing naming):

- `test_os_detection.bats`
  - Force `uname`/`MSYSTEM`/`/proc/version` via stubbing or env → `detect_os` sets `WSK_OS`
    correctly for macos / linux / windows (3 tests).
  - `detect_pkg_mgr` with each manager present (forced PATH) → correct `WSK_PKG_MGR` (brew/apt/...).
  - No manager present → returns non-zero + warns.
- `test_pkg_install.bats`
  - `WSK_PKG_MGR=brew` + `pkg_install git` → brew stub recorded `install git`.
  - `WSK_PKG_MGR=apt` + `pkg_install git` → apt-get stub recorded `install -y git`.
  - idempotency: `git` present → no manager stub call, "already installed" printed.
  - `WSK_OS=windows` → instruction printed, NO manager stub called.
  - `--cask` on brew → `install --cask`.
- `test_node_toolchain.bats`
  - node absent macos → brew `install node` recorded; node absent linux → pkg_install routes to
    active mgr; node present → no install.
  - pnpm: macos always brew, never `get.pnpm.io` (assert curl NOT called with pnpm URL); linux
    corepack-present → `corepack enable pnpm`; linux no corepack → curl get.pnpm.io; node absent →
    error + non-zero + pnpm NOT attempted.
- `test_ai_dev_tools.bats`
  - `install_claude_code`: absent → curl recorded; present → not called; windows → ps1 instruction.
  - `install_ai_framework work` with `ui_choose`→gentle-ai: gentle-ai install ran with
    `CLAUDE_CONFIG_DIR=$HOME/.claude-work`; `accounts/work.env` contains `AI_FRAMEWORK=gentle-ai`.
  - gsd path: `accounts/personal.env` gets `AI_FRAMEWORK=gsd`; npx recorded; with `WSK_STUB_NPX_FAIL`
    → git clone fallback recorded.
  - superpowers: `~/.claude-work/superpowers/` dir exists after; `/plugin install` line printed;
    env has `AI_FRAMEWORK=superpowers`.
  - per-account divergence: work=gentle-ai, personal=gsd → both env files independent.
  - re-run honoring: pre-seed `AI_FRAMEWORK=gentle-ai` → `ui_choose` NOT invoked (assert gum choose
    not recorded), framework unchanged.
  - codegraph: confirm→`npm i -g @colbymchenry/codegraph` recorded + `~/.claude-work/.mcp.json`
    contains `codegraph`; node absent → error + skipped; present → not re-installed; decline → not
    installed.
  - skills: gsd account → 6 dirs under `~/.claude-personal/skills/`; gentle-ai account → skipped +
    "bundled" message; idempotent: pre-create `branch-pr` dir → not re-fetched.
- `test_doctor_ai.bats`
  - OS/pkg-mgr lines; node/pnpm pass+fail; claude pass/fail; per-account framework pass/warn/fail
    matrix; codegraph pass/warn; skills present/missing/gentle-ai-bundled. Assert exact
    `check_pass`/`check_warn`/`check_fail` substrings from the doctor spec.

Strict-TDD ordering for `sdd-apply`: for each function, write the failing bats test first (RED),
implement minimal lib code (GREEN), then shellcheck + refactor. The stub additions land first as
infrastructure (they have no behavior to test themselves but are prerequisites — committed alongside
the first RED test that needs them).

### CI — add Ubuntu bats job (resolves proposal open question #3)

`.github/workflows/ci.yml` `test` job becomes a matrix over macOS + Ubuntu so Linux `pkg_install`
paths (apt routing, corepack pnpm, `WSK_OS=linux`) are exercised — with stubs so NO real installs
run.

```yaml
  test:
    name: E2E Tests
    strategy:
      fail-fast: false
      matrix:
        os: [macos-latest, ubuntu-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Install deps (macOS)
        if: runner.os == 'macOS'
        run: brew install bats-core gum stow fzf gettext jq sd
      - name: Install deps (Ubuntu)
        if: runner.os == 'Linux'
        run: |
          sudo apt-get update
          sudo apt-get install -y bats stow gettext-base jq
          # gum via charm apt repo or `go install`; sd via cargo/apt; fzf via apt
          sudo apt-get install -y fzf
          # gum: add charm repo (or skip — ui.sh exits without gum, so tests that don't need
          #      interactive UI stub gum anyway). The bats stubs override gum for behavior tests.
      - name: Run E2E tests
        run: bats tests/e2e/
```

Note: `lib/ui.sh` hard-exits at source time if `gum` is absent. Tests already stub `gum` (exported
function) BEFORE sourcing ui.sh — but the top-level `command -v gum` check in ui.sh runs at source.
Decision D9: tests that source `ui.sh` must ensure `gum` resolves. The cleanest portable fix: bats
stubs install a `gum` shim on `PATH` (not only an exported function) so the source-time guard passes
on Ubuntu where gum isn't apt-available. The stub `bin/` on `PATH` (from `init_test_home`
extension) provides `gum`, `git`, `node`, etc. as executable shims — this is also why presence
toggling is PATH-based. This keeps the Ubuntu job from needing the charm apt repo.

---

## 7. Architecture Decisions (ADR-style)

### D1 — Curated skills fetch: per-skill copy from one pinned repo
**Decision**: `_fetch_skill` shallow-clones a single `WSK_SKILLS_REPO` and copies `skills/{name}/`
into the per-account dir, per skill, guarded by `[[ -d dest ]]`.
**Why**: individual idempotency, one override seam, graceful `check_warn` degradation.
**Rejected**: (a) per-skill independent remotes — six URLs to maintain; (b) `/plugin install` headless
— not reliably scriptable (same reason superpowers needs the clone fallback); (c) sparse-checkout
mono-repo — more complex for no idempotency gain.
**Risk**: assumes the pinned repo's `skills/{name}/` layout. Mitigated by the env override + warn.

### D2 — gsd source: npm primary, git-clone fallback to `Gentleman-Programming/get-shit-done`
**Decision**: `npx --yes get-shit-done-cc --global` first; on failure git-clone the named fallback
remote into `$cfg_dir/gsd`.
**Why**: resolves proposal open Q#1 without blocking; pins the fallback so apply/tasks don't guess.
**Rejected**: clone-only (slower, no npm auto-update); npm-only (no recovery if package unpublished).
**Risk**: canonical repo ownership still externally uncertain — flagged for verify, not silently
swapped.

### D3 — codegraph MCP config: `.mcp.json` in `CLAUDE_CONFIG_DIR`, jq-merge, absence-only fallback
**Decision**: write `mcpServers.codegraph` into `$HOME/.claude-{acct}/.mcp.json`, merging via `jq`,
never clobbering an existing manifest when `jq` is unavailable.
**Why**: `.mcp.json` is the documented Claude MCP manifest; per-account dir keeps scope; non-destructive
merge is idempotent. Resolves spec risk #3.
**Rejected**: a bespoke config filename (Claude wouldn't read it); blind overwrite (destroys
hand-edited servers).

### D4 — gentle-ai accounts skip explicit curated-skills install
**Decision**: when `AI_FRAMEWORK=gentle-ai`, skip the clone loop; doctor reports "skills bundled by
gentle-ai". Resolves spec risk #2.
**Why**: gentle-ai injects an equivalent set; duplicating risks conflicts.
**Rejected**: always-install (duplication); verify-bundled-then-fill-gaps (needs knowledge of
gentle-ai's exact bundle — brittle).

### D5 — Single shared per-account driver for full-setup, menu, and `wsk ai`
**Decision**: `run_ai_for_all_accounts` is the one loop; `run_ai` wraps it with `load_accounts` +
global installers for standalone use; `run_full_setup` calls the loop directly.
**Why**: spec mandates "same shared functions"; avoids divergence/duplication.
**Rejected**: separate menu vs CLI implementations (drift risk).

### D6 — Linux Node: system package via `pkg_install`, not fnm (this change)
**Decision**: `pkg_install node` on Linux; fnm deferred.
**Why**: keeps the idempotency guard a plain `command -v node`; smaller matrix; no shell-init
mutation (fnm needs PATH/eval wiring in zshrc). **Tradeoff**: system node can be older than fnm's
latest; acceptable for "start fast", and the user can layer fnm later. fnm recorded as future option.
**Rejected**: fnm-primary (adds zshrc PATH wiring + per-shell eval, out of scope here).

### D6b — macOS pnpm calls `brew install pnpm` explicitly (not via `pkg_install`)
**Decision**: explicit `brew install pnpm` on macOS.
**Why**: makes the "must be brew, never the Intel-breaking standalone script" guarantee unmissable at
the call site (spec hard requirement). Functionally equal to `pkg_install pnpm` on macOS.
**Rejected**: `pkg_install pnpm` (correct but hides the critical intent).

### D7 — `pkg_install` probes the single arg with `command -v`; callers own binary≠package cases
**Decision**: `pkg_install <pkg>` uses `<pkg>` as both install target and `command -v` guard. Callers
where binary name differs (e.g. `ripgrep`/`rg`) pass the BINARY name, or pre-guard themselves.
**Why**: keeps the router simple and the guard correct for the common case; `packages.sh` already
carries the label:binary mapping.
**Rejected**: a `pkg_install <pkg> <binary>` two-arg form (more ceremony for one edge case; `--cask`
already consumes the optional slot).

### D8 — env upsert via `sd`, not `sed -i`
**Decision**: `_persist_account_kv` uses `sd` (base package) for in-place replace, append otherwise.
**Why**: `sed -i` syntax differs macOS (`-i ''`) vs GNU (`-i`); `sd` is portable and already a
dependency. Idempotent upsert.
**Rejected**: portable `sed` with a tmp file (works but noisier); `sed -i` (non-portable).

### D9 — bats stubs are PATH shims (not only exported functions)
**Decision**: test stubs (`gum`, `git`, `node`, `npm`, ...) are executable shims placed on a
test-controlled `PATH` prefix; presence toggled by adding/removing the shim.
**Why**: `lib/ui.sh` runs `command -v gum` at SOURCE time — an exported bash function does not satisfy
`command -v` reliably across environments, and Ubuntu CI has no apt `gum`. PATH shims satisfy
`command -v`, enable clean presence toggling, and remove the need for a charm apt repo in CI.
**Rejected**: exported-function-only stubs (don't satisfy source-time `command -v` on Ubuntu);
installing real gum on Ubuntu (extra CI fragility).

### D10 — Linux package installs run un-spun (sudo password visibility)
**Decision**: `pkg_install` wraps brew installs in `ui_spin`; apt/dnf/pacman run directly with a
`log_info` line.
**Why**: `gum spin` hides stdout, which would swallow `sudo`'s password prompt and hang.
**Rejected**: spinning everything (breaks sudo UX on Linux).

---

## Sequence diagram — `wsk ai` (per config.yaml design rule)

```
User ──wsk ai──► run_ai
  run_ai ─► load_accounts ─► WSK_ACCOUNTS=(work personal)
  run_ai ─► detect_os ─► WSK_OS ; detect_pkg_mgr ─► WSK_PKG_MGR
  run_ai ─► install_node ─► [command -v node? skip : pkg_install node]
  run_ai ─► install_pnpm ─► [node? : err] ─► [macos: brew | linux: corepack/curl]
  run_ai ─► install_claude_code ─► [command -v claude? skip : curl|bash]
  run_ai ─► run_ai_for_all_accounts
     loop acct ∈ WSK_ACCOUNTS:
        install_ai_framework acct
           ├─ env has AI_FRAMEWORK? ──yes──► reuse, no prompt
           └─ no ─► ui_choose ─► {gentle-ai|gsd|superpowers}
                    CLAUDE_CONFIG_DIR=~/.claude-acct ► install
                    _persist_account_kv AI_FRAMEWORK=...
        ui_confirm "codegraph?" ──yes──► install_codegraph acct
                    └─ node? ─► npm i -g ─► _write_codegraph_mcp_config (.mcp.json, jq-merge)
        install_curated_skills acct framework
           ├─ gentle-ai ──► skip ("bundled")
           └─ else ─► for 6 skills: [dir exists? skip : _fetch_skill]
```

## Traceability — every spec requirement maps to a component

| Spec requirement | Component |
|---|---|
| OS Detection | `detect_os` (§1) |
| Package Manager Detection | `detect_pkg_mgr` (§1) |
| pkg_install Router / Idempotency / Windows | `pkg_install` (§1, D7, D10) |
| CI Coverage macOS+Linux | Ubuntu matrix job (§6) |
| Node / pnpm install + order + Intel-brew | `install_node`/`install_pnpm` (§2, D6/D6b) |
| Claude Code install | `install_claude_code` (§3) |
| Per-Account Framework + persist + re-run honoring | `install_ai_framework` + `_persist_account_kv` (§4) |
| CLAUDE_CONFIG_DIR isolation | per-call export in §4/§3 |
| Codegraph install + MCP config | `install_codegraph` + `_write_codegraph_mcp_config` (§3, D3) |
| Curated skills + gentle-ai skip + idempotency | `install_curated_skills`/`_fetch_skill` (§4, D1, D4) |
| Menu entry + `wsk ai` dispatch | `run_ai`/`run_ai_for_all_accounts` + install.sh (§5, D5) |
| Bootstrap OS compat + pkg_install prereqs | bootstrap.sh refactor (§1, §5) |
| All doctor sub-sections | doctor.sh additions (§5) |
```
