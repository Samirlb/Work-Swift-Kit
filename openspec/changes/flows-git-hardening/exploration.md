# Exploration — flows-git-hardening

Date: 2026-06-11
Scope: TUI menu/flow map, clean-install vs re-run vs standalone state dependencies, git/gh/SSH validation gaps, edge-case inventory.

## 1. Menu/Flow Tree

### install.sh top-level dispatch

`install.sh` sources `lib/bootstrap.sh` and calls `bootstrap()` unconditionally at startup (installs gum, stow, fzf, gettext, Homebrew on macOS). Then it sources all lib files and, if called as `wsk <command>`, routes through `dispatch()`. Otherwise it loops on the interactive menu.

### Direct command dispatch (`wsk <command>`)

| Command arg | Function | Reads | Writes |
|---|---|---|---|
| `setup\|full` | `run_full_setup` | accounts/*.env | stow/{.gitconfig,.gitconfig-*,.ssh/config,.gitignore_global,.claude-*/CLAUDE.md}, ~/.zshrc (block splice), ~/.claude-*/settings.json |
| `accounts` | `run_accounts` | accounts/*.env | same as above |
| `terminals` | `install_terminals` | none (uses `WSK_OS` from bootstrap) | none (calls `pkg_install`) |
| `relink` | `run_relink` | accounts/*.env | stow/* re-rendered, ~/.zshrc block replaced |
| `doctor\|check` | `run_doctor` | accounts/*.env, ~/.claude-*/settings.json, ~/.gitconfig-* | none (read-only) |
| `fix-claude` | `run_fix_claude_cmd` → `run_fix_claude` | accounts/*.env, ~/.claude-*/RTK.md | ~/.claude (removed), ~/.claude-*/RTK.md (copied), ~/.claude-*/CLAUDE.md (patched) |
| `update` | `run_update` | accounts/*.env, git/brew state | ~/.wsk (git pull), /usr/local/bin/wsk (wrapper), stow/* re-rendered, ~/.zshrc block |
| `ai` | `run_ai` | accounts/*.env | ~/.claude-*/settings.json, ~/.claude-*/CLAUDE.md, ~/.claude-*/.mcp.json |
| `sync` | `run_sync` → `sync_gentle_ai_accounts` | accounts/*.env | ~/.claude-*/CLAUDE.md, ~/.claude-*/commands/*.md (patched) |
| `version\|-v\|--version` | prints version | `WSK_VERSION` | none |
| `help\|-h\|--help` | `run_help` | none | none |

### Interactive menu (gum/fzf or WSK_UI=tui)

`install.sh:167–203` — `while true` loop:

| Menu label | Function invoked |
|---|---|
| Full setup | `tui_wrap_action run_full_setup` |
| Accounts only | `tui_wrap_action run_accounts` |
| Terminals only | `tui_wrap_action install_terminals` |
| AI dev tools | `tui_wrap_action run_ai` |
| Sync AI configs | `tui_wrap_action run_sync` |
| Check configuration | `tui_wrap_action --paged run_doctor` |
| Update | `tui_wrap_action run_update` |
| Re-link configs | `tui_wrap_action --paged run_relink` |
| Quit | `exit 0` |

Note: there is no menu entry for `fix-claude` (only accessible via `wsk fix-claude` direct command).

### run_full_setup detail (install.sh:66–86)

1. `ui_confirm` (gum confirm)
2. `collect_accounts || load_accounts` → prompts for or reads accounts/*.env
3. `install_packages` → pkg_install for 12 packages
4. `install_terminals` → gum multiselect → pkg_install
5. `detect_os; detect_pkg_mgr || true` (redundant — bootstrap already ran these)
6. `install_node`, `install_pnpm`, `install_claude_code`
7. Conditional `install_rtk` and `install_caveman`
8. `run_ai_for_all_accounts` → per account: `install_ai_framework` → `_gentle_ai_scoped install` (first time only) + `sync` → `_patch_gentle_ai_commands` → `_patch_gentle_ai_claude_md`; optionally `install_codegraph`; `install_curated_skills`
9. `setup_gh_accounts` → `gh auth login --web` per account
10. `render_all` → renders all stow/* templates
11. `link_dotfiles` → `stow --restow` + `inject_zshrc_block`

### Template read/write map

| Template function | Reads | Writes |
|---|---|---|
| `render_gitconfig` | `WSK_ACCOUNTS[0]`.env (GIT_NAME, GIT_EMAIL, PROJECTS_DIR all accounts) | `stow/.gitconfig` (overwrite) |
| `render_gitconfig_account` | each account.env (GIT_NAME, GIT_EMAIL, GIT_GITHUB_USER, WSK_SSH_KEY) | `stow/.gitconfig-{acct}` (overwrite) |
| `render_gitignore_global` | nothing | `stow/.gitignore_global` (overwrite) |
| `render_ssh_config` | each account.env (WSK_SSH_KEY) | `stow/.ssh/config` (overwrite) |
| `render_zshrc` | each account.env (PROJECTS_DIR, GIT_GITHUB_USER) | `.rendered/wsk-zshrc` (overwrite) |
| `render_claude_md` | each account.env (AI_FRAMEWORK, DISPLAY_NAME, PROJECTS_DIR) | `stow/.claude-{acct}/CLAUDE.md` (non-gentle-ai only; removed for gentle-ai accounts) |
| `link_dotfiles` (stow.sh) | stow/* | ~/.gitconfig, ~/.gitignore_global, ~/.ssh/config, ~/.gitconfig-{acct}, ~/.claude-{acct}/CLAUDE.md (symlinks); splices ~/.zshrc |

## 2. Per-Flow State Dependencies and Break Scenarios

### (a) Clean machine (no accounts, no dotfiles, no gum/stow)

| Flow | What breaks |
|---|---|
| `wsk` (interactive) | Works — `bootstrap()` designed for clean installs. |
| `wsk relink` | **Breaks**: `load_accounts` → empty `WSK_ACCOUNTS`; `render_gitconfig` reads `${WSK_ACCOUNTS[0]}` → with `set -u` on bash 3.2 → unbound variable abort; `render_all` fails mid-way. |
| `wsk doctor` | Works — reports warnings. |
| `wsk ai` / `wsk sync` | No-op with "No accounts configured" warning. |
| `wsk fix-claude` | Works. |
| `wsk update` / `wsk terminals` | Work. |

Clean-install ordering requirement: accounts must be collected before `render_all` / `link_dotfiles` / `run_ai_for_all_accounts`. Only `run_full_setup` and `run_accounts` satisfy this.

### (b) Re-run after completed setup

| Flow | Issue |
|---|---|
| `run_full_setup` again | Mostly clean (collect_accounts offers Keep/Edit/Add/Recreate; settings.json guard prevents double gentle-ai install). |
| `wsk relink` | **Bug**: re-renders `stow/.gitconfig` from template, destroying externally-added `[credential]` blocks (added by `gh auth login`). HTTPS auth silently broken after every relink/accounts/update re-render. |
| `run_sync` | Idempotent. |

### (c) Partial/aborted setup

| Scenario | Consequence |
|---|---|
| Abort after `collect_accounts`, before `render_all` | accounts/*.env written, stow/ stale. `wsk relink` recovers. |
| Abort during `_gentle_ai_scoped` swap | Account dir may be left at `~/.claude`. Re-running `wsk ai` recovers (stash path snapshots it as real dir). |
| Abort during `stow --restow` | Partial links possible; `wsk relink` recovers. |
| `inject_zshrc_block` frag missing | Warn + return 0, no write. |
| `_write_rtk_hook` / `_enable_caveman_plugin` with jq absent | check_warn, settings incomplete, no crash. |

### (d) Account added/removed later

| Action | Issue |
|---|---|
| Add account (`wsk accounts → Add`) | **Silent state mismatch**: saves .env but does NOT `render_all`/`link_dotfiles`. No `{acct}()` zsh functions, no gitconfig includeIf, no SSH alias until manual `wsk relink`. No warning printed. (lib/accounts.sh:138–140) |
| Remove account (delete .env manually) | Stale `~/.gitconfig-{acct}` symlink becomes broken; stow does not remove old links. |
| Edit account | New .env values not reflected until `wsk relink`; no warning. |

## 3. Git/gh/SSH Validation Gaps (confirmed live on this machine)

Deployed design: `~/.gitconfig` `includeIf gitdir` per Work/Personal → `.gitconfig-{acct}` with `core.sshCommand = ssh -i ~/.ssh/id_{acct}`; `~/.ssh/config` Host aliases `github-{acct}` with `IdentitiesOnly yes`; HTTPS github remotes use credential helper `gh auth git-credential` (ACTIVE gh account wins).

| # | Gap | Location |
|---|---|---|
| 3.1 | Doctor gh check is a single `gh auth status` — does not validate per-account `GIT_GITHUB_USER` logged in, remote transport type, or active account vs repo account | `lib/doctor.sh:273–278` |
| 3.2 | HTTPS remote bypass: no detection anywhere. HTTPS remotes depend on whichever gh account is active. The credential helper block in `stow/.gitconfig` is NOT generated by `templates/gitconfig.sh` — it was added externally by `gh auth login` and is destroyed on every re-render | gap; `templates/gitconfig.sh:14` |
| 3.3 | Remote alias vs containing directory mismatch (e.g. `git@github-work:` remote inside Documents/Personal → two identities offered via sshCommand + Host alias, possible wrong-user auth) — no validation | gap — no file |
| 3.4 | `claude()` auto-detect wrapper and `claude-{acct}()` never call `gh auth switch` → gh active account drifts from session account. Only `work()`/`personal()` (via `_wsk_switch_profile`) and `gh-{acct}()` switch | `templates/zshrc.sh:82–101, 155–158` |
| 3.5 | `gh auth status ... \| grep -q "$github_user"` is substring-fragile (false positives, output format drift) | `lib/gh.sh:43` |
| 3.6 | gh auth login ordering only special-cases `work`/`personal` names; third+ accounts arbitrary order | `lib/gh.sh:24–35` |

Live evidence (2026-06-11): repos with https github remotes that bypass the SSH design: Work/BeCapital-Back-Refactor, Personal/Work-Swift-Kit (itself), Personal/Discuss News, Personal/LangChain Training. Active gh account was `work` while WSK (a `personal` repo) needed push → would 403.

## 4. Edge-Case Inventory (ranked)

### CRITICAL

- **EC-1** `stow/.gitconfig` credential blocks destroyed on every re-render — `templates/gitconfig.sh:14` (`cat > "$out"` overwrite); called from full setup, accounts, relink, update.
- **EC-2** `.rendered/wsk-zshrc` stale — missing `gentle-ai()` interceptor and `claude()` ~/.claude warning added in v0.3.1 (`templates/zshrc.sh:42–59` vs rendered file). Not auto-regenerated on update.
- **EC-3** `render_gitconfig` reads `${WSK_ACCOUNTS[0]}` with empty array under `set -u` — crash on `wsk relink` on clean machine — `templates/gitconfig.sh:5`.

### HIGH

- **EC-4** `command gentle-ai "$@" || true` swallows all gentle-ai failures; account still marked `AI_FRAMEWORK=gentle-ai` via `_persist_account_kv` → configured-but-broken state — `lib/frameworks.sh:328`.
- **EC-5** Add-account flow does not re-render/re-link and prints no warning — `lib/accounts.sh:138–140`.
- **EC-6** `sd` used without `command -v` guard in `_persist_account_kv`; if absent → silent failure → duplicate key appended — `lib/frameworks.sh:23`.
- **EC-7** `python3` used without guard in `_patch_gentle_ai_claude_md`; absent python3 aborts install under `set -e` — `lib/frameworks.sh:138`.
- **EC-8** `gentle-ai sync` run directly bypasses WSK scoping when interceptor missing (combined with EC-2).

### MEDIUM

- **EC-9** `rg` without guard in `ui_updates` (cosmetic, `|| true`) — `lib/ui.sh:92`.
- **EC-10** gh login ordering only handles work/personal; N-account ordering arbitrary — `lib/gh.sh:24–35`.
- **EC-12** `grep -i "^$arg"` with unquoted user input regex metacharacters in `_wsk_switch_profile` — `templates/zshrc.sh:124`.
- **EC-13** `inject_zshrc_block` tmp-file abandonment window — `lib/stow.sh:77–90`.
- **EC-14** `pkg_install` idempotency checks `command -v <label>` not `<binary>` (ripgrep/rg) → always re-attempts — `lib/os.sh:83` vs `lib/packages.sh:31–36`.
- **EC-15** macOS system `readlink -f` unsupported → symlink-to-real-file zshrc migration silently broken without coreutils — `lib/stow.sh:42`.
- **EC-16** Single-account mode hardcodes name choice to work|personal — `lib/accounts.sh:164`.
- **EC-21** `_write_rtk_hook` duplicate-guard via grep may miss differently-formatted hooks → duplicate hook append — `lib/claude.sh:107–112`.
- **EC-22** `link_dotfiles` loops `"${WSK_ACCOUNTS[@]}"` without `+` empty-array guard (bash 3.2 + set -u) — `lib/stow.sh:104`.

### LOW

- **EC-19** `stow/.gitconfig` committed with machine-specific absolute includeIf paths — `stow/.gitconfig:20,23`.
- **EC-20** `wsk update` brew upgrade list hardcoded; excludes node/pnpm/claude — `lib/update.sh:35`.
- **EC-23** account .env values written unquoted; multi-line values break parsing — `lib/accounts.sh:91–99`.

## Constraints

- Bash 3.2 compatible, macOS primary (Linux best-effort).
- Strict TDD: bats-core e2e under `tests/e2e/` (`bats tests/e2e/`), shellcheck required for new `.sh` files.
- gentle-ai owns `~/.claude-{acct}` content for gentle-ai accounts; persistent rules must be applied as post-sync patches.
