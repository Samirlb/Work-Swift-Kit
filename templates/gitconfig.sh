#!/usr/bin/env bash
# gitconfig.sh — Render the WSK-managed section of stow/.gitconfig.
# Uses managed-section markers (mirrors inject_zshrc_block in lib/stow.sh).
# Content outside the markers is preserved verbatim.
set -euo pipefail

render_gitconfig() {
  # Bail early if no accounts configured (bash 3.2 safe array check)
  local count=0
  if [[ -n "${WSK_ACCOUNTS+x}" ]]; then
    count="${#WSK_ACCOUNTS[@]}"
  fi
  if [[ "$count" -eq 0 ]]; then
    return 0
  fi

  local first_account="${WSK_ACCOUNTS[0]}"
  local first_env="${WSK_DIR}/accounts/${first_account}.env"

  local first_name first_email
  first_name=$(grep '^GIT_NAME=' "$first_env" | cut -d= -f2-)
  first_email=$(grep '^GIT_EMAIL=' "$first_env" | cut -d= -f2-)

  local out="${WSK_DIR}/stow/.gitconfig"
  local begin="# WSK:BEGIN"
  local end="# WSK:END"

  mkdir -p "${WSK_DIR}/stow"

  # ── Legacy migration ──────────────────────────────────────────────────
  # If the file exists but has no managed markers it is a legacy fully-rendered
  # gitconfig. Back it up, then strip out the sections WSK generates so they
  # are not duplicated alongside the new managed block. Any external sections
  # (e.g. [credential], [url], [http]) are preserved verbatim.
  if [[ -f "$out" ]] && ! grep -qF "$begin" "$out" 2>/dev/null; then
    local backup
    backup="${out}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$out" "$backup"
    log_info "gitconfig: legacy file backed up to ${backup##*/}"

    # Strip WSK-generated sections: [user], [core], [pull], [push], [alias],
    # [includeIf]. Blank lines between a removed section and the next are also
    # removed to avoid accumulating whitespace. External sections are kept.
    local stripped_tmp
    stripped_tmp="$(mktemp)"
    awk '
      /^\[user\]/ || /^\[core\]/ || /^\[pull\]/ || /^\[push\]/ || /^\[alias\]/ || /^\[includeIf / {
        skip=1; next
      }
      /^\[/ { skip=0 }
      skip { next }
      { print }
    ' "$out" > "$stripped_tmp"
    mv "$stripped_tmp" "$out"
  fi

  # ── Build the new WSK-managed content block ───────────────────────────
  local wsk_content
  wsk_content="$(cat <<EOF
[user]
	name = ${first_name}
	email = ${first_email}

[core]
	excludesfile = ~/.gitignore_global

[pull]
	rebase = true

[push]
	default = current

[alias]
	st = status
	co = checkout
	br = branch
	lg = log --oneline --graph --decorate --all

EOF
)"

  for acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    local env_file="${WSK_DIR}/accounts/${acct}.env"
    local projects_dir
    projects_dir=$(grep '^PROJECTS_DIR=' "$env_file" | cut -d= -f2-)
    wsk_content+="$(cat <<EOF
[includeIf "gitdir:${projects_dir}/"]
	path = ~/.gitconfig-${acct}

EOF
)"
  done

  # ── Strip old managed section; reappend fresh one ─────────────────────
  # Mirror the awk splice from lib/stow.sh:inject_zshrc_block (lines 78-89).
  [[ -e "$out" ]] || touch "$out"

  local tmp
  tmp="$(mktemp)"

  awk -v b="$begin" -v e="$end" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "$out" > "$tmp"

  {
    printf '%s\n' "$begin"
    printf '# Managed by Work-Swift-Kit — edits between these markers are overwritten.\n'
    printf '%s' "$wsk_content"
    printf '%s\n' "$end"
  } >> "$tmp"

  mv "$tmp" "$out"
}
