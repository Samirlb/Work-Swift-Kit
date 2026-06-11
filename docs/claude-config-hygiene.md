# Claude Config Hygiene

This document explains how Work-Swift-Kit manages Claude Code's config directories,
why `~/.claude` must not exist while per-account dirs are present, and what the
`wsk fix-claude` command does.

---

## The multi-account model

WSK provisions one config directory per account:

```
~/.claude-work/        ← CLAUDE_CONFIG_DIR for the "work" account
~/.claude-personal/    ← CLAUDE_CONFIG_DIR for the "personal" account
```

The `claude()` shell wrapper (injected into `~/.zshrc` by WSK) sets
`CLAUDE_CONFIG_DIR` to the appropriate account dir at launch time:

```zsh
CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude
```

Claude Code reads skills, CLAUDE.md, settings, and agents from `CLAUDE_CONFIG_DIR`.
This keeps the two accounts completely isolated — different skills, different
CLAUDE.md content, different settings.

---

## Why `~/.claude` must not exist

Claude Code performs **ancestor-directory traversal**: starting from `$PWD`, it
walks up every parent directory looking for a `.claude/` directory to load global
CLAUDE.md and skills from. Your home directory (`/Users/you`) is an ancestor of
every project on your machine.

If `~/.claude` exists as a symlink or real directory **and** you also have
`~/.claude-work` or `~/.claude-personal`, Claude Code loads **both**:

1. The per-account dir via `CLAUDE_CONFIG_DIR` (correct, intended)
2. `~/.claude` via the ancestor traversal (unintended)

This causes:
- **CLAUDE.md loaded twice** — roughly 36 KB loaded on every session start,
  wasting ~10 000 tokens per session
- **All skills listed twice** — every skill appears twice in `/skills`; the
  duplicate entries are confusing and slow down skill resolution
- **Instruction conflicts** — if the two CLAUDE.md files differ (e.g. after a
  raw `gentle-ai sync` overwrites one), the merged instructions may be
  contradictory

The root cause was a leftover in the old `_gentle_ai_scoped` restore step: after
running `gentle-ai`, it recreated `~/.claude` as a symlink pointing to the
last-synced account dir. WSK no longer does this.

---

## `wsk fix-claude`

Runs the one-shot remediation:

1. **Removes `~/.claude`** if it is a symlink.  
   Moves it to `~/.claude.wsk-backup-YYYYmmdd-HHMMSS` if it is a real directory
   (so user data is never silently discarded).  
   Reports "already absent" if it is not present.

2. For each account with `AI_FRAMEWORK=gentle-ai`:
   - Copies `RTK.md` from any sibling account dir that already has it, if this
     account dir is missing it.
   - Runs `_patch_gentle_ai_claude_md` to ensure `CLAUDE.md` contains the
     WSK-managed content (see below).

The command is **idempotent** — running it twice is always safe.

---

## What `_patch_gentle_ai_claude_md` does

After every `gentle-ai install` or `gentle-ai sync`, WSK calls this function to
ensure two things in the account's `CLAUDE.md`:

### 1. Sub-Agent Context Minimalism block

gentle-ai regenerates `CLAUDE.md` on every sync. WSK re-injects a
marker-guarded block that enforces disciplined sub-agent context usage:

```
<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:BEGIN -->
## Sub-Agent Context Minimalism (MANDATORY)
...
<!-- WSK:SUBAGENT-CONTEXT-MINIMALISM:END -->
```

If the block already exists (from a previous run), its content is **replaced**
so it stays current. It is never duplicated.

### 2. `@RTK.md` import

If `RTK.md` exists in the account dir, an `@RTK.md` import line is appended to
`CLAUDE.md` (once — not duplicated on re-runs).

---

## Sub-Agent Context Minimalism — rationale

Claude Code's SDD orchestrator spawns sub-agents for each planning/implementation
phase. Each sub-agent starts with a fresh context window. Passing everything to
every sub-agent (full skill registry, orchestrator instructions, conversation
history, unrelated artifact content) saturates their context and degrades output
quality.

The minimalism rule enforces the principle that **a sub-agent should receive only
what its specific task requires**:

- Inject skill paths that match the phase's code context and task context only.
- Pass artifact references (engram topic keys or file paths), not inlined content.
- Forward only the role contract for that phase — not the orchestrator's full
  instructions, persona, or conversation history.
- SDD phases read only their declared dependencies from the phase read/write table.
- Sub-agents must not orchestrate or spawn further agents.

Saturating sub-agent context is a discipline failure, not a best-effort tradeoff.

---

## `wsk doctor` hygiene checks

`wsk doctor` reports three hygiene conditions under "Claude config hygiene":

| Condition | Severity | Fix |
|-----------|----------|-----|
| `~/.claude` exists while `~/.claude-{acct}` dirs are present | FAIL | `wsk fix-claude` |
| CLAUDE.md references `@RTK.md` but RTK.md is missing | WARN | `wsk fix-claude` |
| CLAUDE.md is missing the minimalism block markers (drift after raw `gentle-ai sync`) | WARN | `wsk fix-claude` |

---

## `gentle-ai()` interceptor

WSK injects a `gentle-ai()` shell function that intercepts the subcommands which
regenerate `~/.claude` (`install`, `sync`, `upgrade`, `restore`) and routes them
through `wsk sync` instead. This prevents a raw `gentle-ai sync` from recreating
`~/.claude` or breaking account isolation.

All other `gentle-ai` subcommands (e.g. `gentle-ai --version`) pass straight
through to the real binary.
