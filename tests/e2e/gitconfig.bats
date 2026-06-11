#!/usr/bin/env bats
# gitconfig.bats — WU-2
# Tests for render_gitconfig managed-section preservation.

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Helper: run render_gitconfig in an isolated subprocess
# ---------------------------------------------------------------------------
_run_gitconfig_iso() {
  local extra_setup="${1:-}"

  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'

    source '${WSK_DIR}/lib/log.sh'
    source '${WSK_DIR}/lib/ui.sh'

    ${extra_setup}

    source '${WSK_DIR}/templates/gitconfig.sh'

    render_gitconfig 2>&1
  " 2>&1
}

setup() {
  init_test_home
  export WSK_DIR
  export WSK_TEST_HOME
  # Ensure stow dir exists in sandbox
  mkdir -p "${WSK_DIR}/stow"
  # Seed a default account
  seed_account "work" "Work" "Jane" "jane@work.com" "janew" "$HOME/projects/work" "id_work"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ===========================================================================
# GC-1: WSK section renders between markers
# ===========================================================================

@test "GC-1: render_gitconfig creates file with WSK:BEGIN/END markers" {
  _run_gitconfig_iso "WSK_ACCOUNTS=(work)"

  local out="${WSK_DIR}/stow/.gitconfig"
  [[ -f "$out" ]]
  grep -qF '# WSK:BEGIN' "$out"
  grep -qF '# WSK:END' "$out"
}

# ===========================================================================
# GC-2: Content outside markers preserved on re-render
# ===========================================================================

@test "GC-2: content outside markers preserved on re-render" {
  local out="${WSK_DIR}/stow/.gitconfig"
  # Pre-populate with markers + external content
  cat > "$out" <<'EOF'
[credential]
  helper = osxkeychain

# WSK:BEGIN
[user]
  name = Old Name
# WSK:END
EOF

  _run_gitconfig_iso "WSK_ACCOUNTS=(work)"

  grep -qF '[credential]' "$out"
  grep -qF 'osxkeychain' "$out"
  # WSK managed section is updated
  grep -qF 'jane@work.com' "$out"
}

# ===========================================================================
# GC-3: gh credential block outside markers survives
# ===========================================================================

@test "GC-3: gh credential block outside markers survives re-render" {
  local out="${WSK_DIR}/stow/.gitconfig"
  cat > "$out" <<'EOF'
# WSK:BEGIN
[user]
  name = Old
# WSK:END

[credential "https://github.com"]
  helper = !/opt/homebrew/bin/gh auth git-credential
EOF

  _run_gitconfig_iso "WSK_ACCOUNTS=(work)"

  grep -qF 'gh auth git-credential' "$out"
}

# ===========================================================================
# GC-4: Legacy file without markers — backup + wrap
# ===========================================================================

@test "GC-4: legacy file without markers — backup created, content wrapped" {
  local out="${WSK_DIR}/stow/.gitconfig"
  cat > "$out" <<'EOF'
[user]
  name = Legacy User
  email = legacy@example.com
EOF

  _run_gitconfig_iso "WSK_ACCOUNTS=(work)"

  # Backup should exist
  local bak_count
  bak_count=$(ls "${WSK_DIR}/stow/.gitconfig.bak."* 2>/dev/null | wc -l || true)
  [[ "$bak_count" -ge 1 ]]

  # The rendered file now has markers
  grep -qF '# WSK:BEGIN' "$out"
  grep -qF '# WSK:END' "$out"
}

# ===========================================================================
# GC-5: Re-render is idempotent
# ===========================================================================

@test "GC-5: re-render is idempotent — content byte-identical after two runs" {
  _run_gitconfig_iso "WSK_ACCOUNTS=(work)"
  local out="${WSK_DIR}/stow/.gitconfig"
  local first_content
  first_content=$(cat "$out")

  _run_gitconfig_iso "WSK_ACCOUNTS=(work)"
  local second_content
  second_content=$(cat "$out")

  [[ "$first_content" == "$second_content" ]]
}

# ===========================================================================
# GC-7: Missing markers on second run — re-migrate cleanly
# ===========================================================================

@test "GC-7: markers absent after second run start — re-migrate cleanly" {
  # Simulate a state where somehow markers were removed
  local out="${WSK_DIR}/stow/.gitconfig"
  cat > "$out" <<'EOF'
[user]
  name = Someone
  email = someone@example.com
[credential]
  helper = osxkeychain
EOF

  _run_gitconfig_iso "WSK_ACCOUNTS=(work)"

  grep -qF '# WSK:BEGIN' "$out"
  grep -qF '# WSK:END' "$out"
  # External credential block preserved
  grep -qF '[credential]' "$out"
}
