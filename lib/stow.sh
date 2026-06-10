#!/usr/bin/env bash
set -euo pipefail

backup_if_real() {
  local target="$1"
  if [[ -L "$target" ]]; then
    # Symlink pointing to a different WSK stow dir — remove so stow can recreate it.
    local link_dest; link_dest="$(readlink "$target" 2>/dev/null || true)"
    local expected_prefix="${WSK_DIR}/stow/"
    local resolved_dest; resolved_dest="$(cd "$(dirname "$target")" && realpath "$link_dest" 2>/dev/null || true)"
    if [[ "$resolved_dest" != "${expected_prefix}"* ]]; then
      rm "$target"
      log_warn "Removed stale stow symlink: $target (was → $link_dest)"
    fi
  elif [[ -e "$target" ]]; then
    local backup
    backup="${target}.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$target" "$backup"
    log_warn "Backed up real file: $target -> $backup"
  fi
}

# inject_zshrc_block — splice the rendered WSK fragment into ~/.zshrc between
# managed markers instead of replacing the file. Idempotent: re-running strips
# the old block and writes a fresh one, preserving all user content around it.
inject_zshrc_block() {
  local rc="$HOME/.zshrc"
  local frag="${WSK_DIR}/.rendered/wsk-zshrc"
  local begin="# >>> work-swift-kit >>>"
  local end="# <<< work-swift-kit <<<"

  if [[ ! -f "$frag" ]]; then
    log_warn "zsh fragment not rendered ($frag) — skipping ~/.zshrc update."
    return 0
  fi

  # Migration: older WSK installs symlinked ~/.zshrc into the stow dir.
  # Convert it back to a real file (dereferencing its contents) so we can
  # manage just our block.
  if [[ -L "$rc" ]]; then
    local deref; deref="$(readlink -f "$rc" 2>/dev/null || true)"
    rm "$rc"
    if [[ -n "$deref" && -f "$deref" && -s "$deref" ]]; then
      cp "$deref" "$rc"
    else
      # Symlink target missing or empty — recover from the most recent backup
      # that has real content so the user's original config is not lost.
      local recovered=""
      for bak in "${rc}.bak."*; do
        if [[ -s "$bak" ]]; then
          cp "$bak" "$rc"
          recovered="$bak"
          break
        fi
      done
      if [[ -n "$recovered" ]]; then
        log_warn "Broken symlink: restored ~/.zshrc from backup $recovered."
      else
        touch "$rc"
        log_warn "Broken symlink and no backup found — starting with empty ~/.zshrc."
      fi
    fi
    log_info "Converted symlinked ~/.zshrc to a managed-block file."
  fi

  [[ -e "$rc" ]] || touch "$rc"

  # First time we touch this file → keep a one-off backup of the original.
  # Skip the backup if the file is empty to avoid overwriting a useful backup
  # with an empty one.
  if ! grep -qF "$begin" "$rc" 2>/dev/null && [[ -s "$rc" ]]; then
    cp "$rc" "${rc}.bak.$(date +%Y%m%d-%H%M%S)"
  fi

  # Strip any existing managed block, then append a fresh one.
  local tmp; tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "$rc" > "$tmp"

  {
    printf '%s\n' "$begin"
    printf '# Managed by Work-Swift-Kit — edits between these markers are overwritten.\n'
    cat "$frag"
    printf '%s\n' "$end"
  } >> "$tmp"

  mv "$tmp" "$rc"
  log_success "Work-Swift-Kit block written to ~/.zshrc (existing config preserved)."
}

link_dotfiles() {
  log_info "Linking dotfiles via GNU Stow..."

  local targets=(
    "$HOME/.gitconfig"
    "$HOME/.gitignore_global"
    "$HOME/.ssh/config"
  )

  for acct in "${WSK_ACCOUNTS[@]}"; do
    targets+=("$HOME/.gitconfig-${acct}")
    local _fw; _fw=$(grep '^AI_FRAMEWORK=' "${WSK_DIR}/accounts/${acct}.env" 2>/dev/null | cut -d= -f2- || true)
    [[ "$_fw" != "gentle-ai" ]] && targets+=("$HOME/.claude-${acct}/CLAUDE.md")
  done

  for t in "${targets[@]}"; do
    backup_if_real "$t"
  done

  stow --restow --no-folding --dir="${WSK_DIR}" --target="$HOME" stow

  # ~/.zshrc is no longer stow-managed: splice a marked block instead so the
  # user's own ~/.zshrc is never replaced.
  inject_zshrc_block

  log_success "Dotfiles linked."
}
