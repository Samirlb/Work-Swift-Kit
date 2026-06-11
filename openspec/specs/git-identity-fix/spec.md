# Git Identity Fix Specification

## Purpose

`wsk fix-git` converts https github remotes to per-account SSH aliases and offers `gh auth switch` to align the active gh account. It is opt-in, dry-run by default, and requires per-repo confirmation before writing.

## Requirements

### Requirement: Dry-Run Default

`wsk fix-git` MUST run in dry-run mode unless an explicit `--apply` flag is passed. In dry-run mode it MUST list every proposed change without modifying any repo.

#### Scenario: No flag — dry-run output only

- GIVEN one repo has an https remote
- WHEN `wsk fix-git` is invoked without `--apply`
- THEN each proposed rewrite is printed: `"[dry-run] would rewrite origin: https://github.com/org/repo.git → git@github-{acct}:org/repo.git"`
- AND no `git remote set-url` command is executed
- AND the command exits 0

#### Scenario: Apply flag — rewrites proceed

- GIVEN `wsk fix-git --apply` is invoked
- THEN the command proceeds to the per-repo confirmation step (see next requirement)

---

### Requirement: Per-Repo Confirmation

When `--apply` is passed, `wsk fix-git` MUST prompt for confirmation on each repo individually before rewriting its remote. Declining a repo MUST skip that repo and continue to the next.

#### Scenario: User confirms one repo, declines another

- GIVEN two repos with https remotes
- WHEN `wsk fix-git --apply` runs and user confirms the first repo but declines the second
- THEN the first repo's remote is rewritten to the SSH alias
- AND the second repo's remote is unchanged

#### Scenario: No https remotes found

- GIVEN all remotes are already SSH aliases
- WHEN `wsk fix-git` or `wsk fix-git --apply` is invoked
- THEN `"No https github remotes found — nothing to fix"` is printed
- AND the command exits 0

---

### Requirement: SSH Alias Resolution

`wsk fix-git` MUST resolve which account alias to use by matching the repo's containing directory against each account's `PROJECTS_DIR`. The rewrite target MUST be `git@github-{acct}:org/repo-name.git`.

#### Scenario: Repo under work PROJECTS_DIR

- GIVEN a repo at `~/Documents/Work/repo` with remote `https://github.com/org/repo.git`
- AND `accounts/work.env` has `PROJECTS_DIR=~/Documents/Work`
- WHEN `wsk fix-git --apply` confirms the rewrite
- THEN `git remote set-url origin git@github-work:org/repo.git` is executed

#### Scenario: Repo not under any known PROJECTS_DIR

- GIVEN a repo whose path does not match any account's `PROJECTS_DIR`
- WHEN `wsk fix-git` evaluates that repo
- THEN `check_warn "{repo}: cannot determine owning account — skipping"` is printed
- AND the repo is not rewritten

---

### Requirement: gh Account Alignment Offer

After rewriting remotes, `wsk fix-git` SHOULD offer to run `gh auth switch` to align the active gh account with the repos that were fixed. The offer MUST be skippable.

#### Scenario: Offer accepted after rewrite

- GIVEN at least one remote was rewritten for the `work` account
- WHEN the user accepts the gh switch offer
- THEN `gh auth switch --user {GIT_GITHUB_USER_work}` is executed
- AND a `check_pass` confirmation is printed

#### Scenario: Offer declined

- GIVEN at least one remote was rewritten
- WHEN the user declines the gh switch offer
- THEN no `gh auth switch` is executed and the command exits 0
