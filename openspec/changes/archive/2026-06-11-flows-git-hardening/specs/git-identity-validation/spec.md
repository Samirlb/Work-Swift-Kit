# Git Identity Validation Specification

## Purpose

Extend `run_doctor` with a `git / gh identity` section that validates: per-account gh login status (not substring-grep), remote transport type (https vs SSH), and remote alias vs containing-directory mismatch. Fills gaps 3.1–3.3 and 3.5 from the exploration.

## Requirements

### Requirement: Per-Account gh Login Check

For each account in `WSK_ACCOUNTS`, `run_doctor` MUST verify that the corresponding `GIT_GITHUB_USER` is authenticated in `gh auth status` output. The check MUST parse `gh auth status` output robustly — not via substring grep on raw output — and MUST detect whether that account is the currently active gh session.

#### Scenario: Account logged in and active

- GIVEN `accounts/work.env` has `GIT_GITHUB_USER=acme-corp-user` and `gh auth status` reports that user as logged in and active
- WHEN the gh login sub-section runs for `work`
- THEN `check_pass "work: gh logged in as acme-corp-user (active)"` is printed

#### Scenario: Account logged in but not active

- GIVEN `GIT_GITHUB_USER=acme-corp-user` is logged in but a different account is active
- WHEN the gh login sub-section runs for `work`
- THEN `check_warn "work: gh logged in as acme-corp-user (not active — run: gh auth switch)"` is printed

#### Scenario: Account not logged in

- GIVEN `GIT_GITHUB_USER=acme-corp-user` does not appear in `gh auth status` output
- WHEN the gh login sub-section runs for `work`
- THEN `check_fail "work: gh not logged in for acme-corp-user — run: gh auth login"` is printed

#### Scenario: gh not installed

- GIVEN `command -v gh` fails
- WHEN the gh login sub-section runs
- THEN `check_warn "gh CLI not found — skipping gh identity checks"` is printed
- AND the function returns 0 (non-fatal)

---

### Requirement: Remote Transport Detection

For each account, `run_doctor` MUST scan git remotes under `PROJECTS_DIR` and flag any `github.com` remote that uses an HTTPS URL. HTTPS remotes depend on whichever gh account is currently active (credential helper) and bypass the per-account SSH design.

#### Scenario: HTTPS remote detected

- GIVEN a repo under `PROJECTS_DIR` has remote URL `https://github.com/org/repo.git`
- WHEN the transport check runs
- THEN `check_warn "{repo}: remote origin is https — will use active gh account (consider: wsk fix-git)"` is printed

#### Scenario: SSH remote with correct alias

- GIVEN a repo remote URL is `git@github-work:org/repo.git`
- WHEN the transport check runs
- THEN no warning is printed for that remote

#### Scenario: No repos under PROJECTS_DIR

- GIVEN `PROJECTS_DIR` is empty or contains no `.git` directories
- WHEN the transport check runs
- THEN `check_pass "{acct}: no git repos found under PROJECTS_DIR"` is printed

---

### Requirement: Remote Alias vs Directory Mismatch

`run_doctor` MUST check that repos residing under an account's `PROJECTS_DIR` use a remote alias matching that account (e.g. `git@github-work:` for repos under Work/). A repo under Personal/ using a `github-work` remote (or vice versa) is a mismatch.

#### Scenario: Mismatch detected

- GIVEN a repo at `~/Documents/Personal/my-repo` has remote `git@github-work:user/my-repo.git`
- WHEN the alias/directory check runs
- THEN `check_warn "my-repo: remote alias 'github-work' does not match directory account 'personal'"` is printed

#### Scenario: Alias matches directory

- GIVEN a repo at `~/Documents/Work/my-repo` uses remote `git@github-work:org/my-repo.git`
- WHEN the alias/directory check runs
- THEN no warning is printed for that repo
