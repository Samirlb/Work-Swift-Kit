# Gitconfig Preservation Specification

## Purpose

`render_gitconfig` currently overwrites `stow/.gitconfig` on every render, destroying externally-added blocks (e.g. `[credential]` written by `gh auth login`). After this change, rendering MUST use a marker-delimited managed section so external blocks survive re-renders.

## Requirements

### Requirement: Managed-Section Rendering

`render_gitconfig` MUST write only the WSK-managed section of `stow/.gitconfig`, bounded by `# WSK:BEGIN` / `# WSK:END` markers. Content outside these markers MUST be preserved verbatim. If the markers do not exist, the managed block is appended.

#### Scenario: Initial render on empty file

- GIVEN `stow/.gitconfig` does not exist
- WHEN `render_gitconfig` runs
- THEN `stow/.gitconfig` is created with `# WSK:BEGIN` … `# WSK:END` wrapping the generated content

#### Scenario: Re-render preserves external credential block

- GIVEN `stow/.gitconfig` contains a `[credential]` block outside the managed markers
- WHEN `render_gitconfig` runs again
- THEN the `[credential]` block is still present in `stow/.gitconfig` after the render
- AND the managed section between the markers is updated with fresh account data

#### Scenario: Re-render is idempotent

- GIVEN a fully rendered `stow/.gitconfig` with managed markers and no external blocks
- WHEN `render_gitconfig` runs twice in succession
- THEN `stow/.gitconfig` content is byte-identical after both runs

---

### Requirement: Legacy File Migration

When `stow/.gitconfig` exists without WSK markers (legacy format from a prior install), the first render MUST migrate it by backing up the file, then writing a fresh managed-section file that re-inserts any detected external blocks outside the backup's managed content.

#### Scenario: Legacy file backed up before migration

- GIVEN `stow/.gitconfig` exists with content but no `# WSK:BEGIN` marker
- WHEN `render_gitconfig` runs for the first time
- THEN a backup is created at `stow/.gitconfig.bak.{timestamp}`
- AND `stow/.gitconfig` is rewritten with WSK markers wrapping the generated content

#### Scenario: External blocks in legacy file are preserved

- GIVEN a legacy `stow/.gitconfig` that contains a `[credential]` block alongside WSK-generated includeIf lines
- WHEN migration runs
- THEN the `[credential]` block appears outside the managed section in the migrated file

---

### Requirement: Auto Re-Render and Re-Link After Account Changes

After a successful `add-account` or `edit-account` operation, WSK MUST either automatically call `render_all` + `link_dotfiles` OR print a clear actionable warning that the machine is in a half-configured state until `wsk relink` is run.

#### Scenario: Add account triggers re-render

- GIVEN one account already exists
- WHEN `wsk accounts` adds a new account and completes successfully
- THEN `render_all` and `link_dotfiles` are called (or a warning is printed: `"Run 'wsk relink' to activate new account configuration"`)
- AND the terminal does NOT silently exit without any indication of pending work

#### Scenario: Edit account triggers re-render

- GIVEN an account env is modified
- WHEN the edit flow completes
- THEN the same re-render-or-warn behavior as add-account applies
