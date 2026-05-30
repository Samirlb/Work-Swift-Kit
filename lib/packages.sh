#!/usr/bin/env bash
set -euo pipefail

install_packages() {
  # label:binary — package name for the installer; binary name for idempotency (command -v).
  # pkg_install receives the BINARY name so command -v guard works correctly.
  # Where label == binary, only one token is needed; split on ':' when they differ.
  local pkg_pairs=(
    git:git
    gh:gh
    fzf:fzf
    ripgrep:rg
    bat:bat
    eza:eza
    fd:fd
    sd:sd
    starship:starship
    zoxide:zoxide
    jq:jq
    tree:tree
  )

  log_info "Installing base packages..."
  local label binary
  for pair in "${pkg_pairs[@]}"; do
    label="${pair%%:*}"
    binary="${pair#*:}"
    # pkg_install uses the binary for command -v idempotency check and the same
    # value as the install target. When binary != package name (e.g. ripgrep/rg)
    # we pre-check with command -v binary; if absent, install the label.
    if command -v "$binary" &>/dev/null; then
      log_info "$label already installed, skipping."
    else
      pkg_install "$label"
    fi
  done
}
