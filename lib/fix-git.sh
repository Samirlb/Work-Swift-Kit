#!/usr/bin/env bash
# fix-git.sh — Convert https github remotes to per-account SSH aliases.
# Dry-run by default; use --apply to write changes with per-repo confirmation.
# Reuses _scan_remotes and account PROJECTS_DIR logic from lib/doctor.sh.
# Requires: lib/log.sh, lib/ui.sh, lib/doctor.sh to be sourced first.
set -euo pipefail

# ---------------------------------------------------------------------------
# _fix_git_resolve_acct <repo_path>
# Matches repo_path against each account's PROJECTS_DIR (longest-prefix wins).
# Prints the account name, or empty string if no match.
# ---------------------------------------------------------------------------
_fix_git_resolve_acct() {
  local repo_path="$1"
  local best_acct="" best_len=0
  local acct projects_dir env_file

  for acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    env_file="${WSK_DIR}/accounts/${acct}.env"
    [[ -f "$env_file" ]] || continue
    projects_dir="$(grep '^PROJECTS_DIR=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"
    [[ -z "$projects_dir" ]] && continue

    # Expand ~ in projects_dir
    projects_dir="${projects_dir/#\~/$HOME}"

    local len="${#projects_dir}"
    if [[ "$repo_path" == "${projects_dir}"/* || "$repo_path" == "$projects_dir" ]]; then
      if [[ "$len" -gt "$best_len" ]]; then
        best_len="$len"
        best_acct="$acct"
      fi
    fi
  done

  printf '%s' "$best_acct"
}

# ---------------------------------------------------------------------------
# _fix_git_rewrite_url <current_url> <acct>
# Returns the canonical SSH alias URL for the given github remote URL.
# Handles https://github.com/<o>/<r>[.git] and git@github.com:<o>/<r>[.git].
# ---------------------------------------------------------------------------
_fix_git_rewrite_url() {
  local url="$1" acct="$2"
  local org_repo=""

  if echo "$url" | grep -qF "https://github.com/"; then
    org_repo="${url#https://github.com/}"
  elif echo "$url" | grep -q "git@github\.com:"; then
    org_repo="${url#git@github.com:}"
  else
    printf '%s' "$url"
    return 0
  fi

  # Strip trailing .git if present, then re-add it canonically
  org_repo="${org_repo%.git}"
  printf 'git@github-%s:%s.git' "$acct" "$org_repo"
}

# ---------------------------------------------------------------------------
# run_fix_git [--apply]
# Scans PROJECTS_DIR/*/.git for https/wrong-alias remotes and either prints
# the planned rewrite (dry-run) or applies with per-repo confirmation (--apply).
# After rewrites, offers gh auth switch.
# ---------------------------------------------------------------------------
run_fix_git() {
  local apply=0
  if [[ "${1:-}" == "--apply" ]]; then
    apply=1
  fi

  preflight_accounts || return 0

  local rewrote_count=0
  local rewrote_gh_user=""
  local candidate_count=0

  local acct env_file projects_dir
  for acct in "${WSK_ACCOUNTS[@]+"${WSK_ACCOUNTS[@]}"}"; do
    env_file="${WSK_DIR}/accounts/${acct}.env"
    [[ -f "$env_file" ]] || continue
    projects_dir="$(grep '^PROJECTS_DIR=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"
    [[ -z "$projects_dir" ]] && continue
    projects_dir="${projects_dir/#\~/$HOME}"
    [[ -d "$projects_dir" ]] || continue

    local git_dir repo_path repo_name remote_url
    for git_dir in "${projects_dir}"/*/.git; do
      [[ -d "$git_dir" ]] || continue
      repo_path="${git_dir%/.git}"
      repo_name="${repo_path##*/}"

      remote_url="$(git -C "$repo_path" remote get-url origin 2>/dev/null || true)"
      [[ -z "$remote_url" ]] && continue

      # Determine if this URL needs rewriting
      local needs_rewrite=0
      if echo "$remote_url" | grep -qF "https://github.com/"; then
        needs_rewrite=1
      elif echo "$remote_url" | grep -q "git@github\.com:"; then
        needs_rewrite=1
      fi

      [[ "$needs_rewrite" -eq 0 ]] && continue

      candidate_count=$(( candidate_count + 1 ))

      local resolved_acct
      resolved_acct="$(_fix_git_resolve_acct "$repo_path")"

      if [[ -z "$resolved_acct" ]]; then
        check_warn "${repo_name}: cannot determine owning account — skipping"
        continue
      fi

      local new_url
      new_url="$(_fix_git_rewrite_url "$remote_url" "$resolved_acct")"

      if [[ "$apply" -eq 0 ]]; then
        log_info "[dry-run] would rewrite origin: ${remote_url} → ${new_url}"
      else
        if ui_confirm "Rewrite origin for ${repo_name}: ${remote_url} → ${new_url}?"; then
          git -C "$repo_path" remote set-url origin "$new_url"
          check_pass "${repo_name}: origin rewritten to ${new_url}"
          rewrote_count=$(( rewrote_count + 1 ))
          rewrote_gh_user="$(grep '^GIT_GITHUB_USER=' "$env_file" 2>/dev/null | cut -d= -f2- || true)"
        else
          log_info "${repo_name}: skipped"
        fi
      fi
    done
  done

  # Report when no candidates were found at all
  if [[ "$candidate_count" -eq 0 ]]; then
    check_pass "No https remotes found — all remotes already use SSH aliases"
  fi

  # Post-rewrite: offer gh auth switch
  if [[ "$apply" -eq 1 && "$rewrote_count" -gt 0 && -n "$rewrote_gh_user" ]]; then
    if ui_confirm "Switch gh active account to ${rewrote_gh_user}?"; then
      if gh auth switch --user "$rewrote_gh_user" 2>/dev/null; then
        check_pass "gh active account → ${rewrote_gh_user}"
      else
        check_warn "gh auth switch failed"
      fi
    fi
  fi
}
