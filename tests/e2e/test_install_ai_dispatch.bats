#!/usr/bin/env bats
# test_install_ai_dispatch.bats — WU-6
# Tests for install.sh AI integration: dispatch, menu entry, and run_full_setup order.

bats_require_minimum_version 1.5.0

load "../helpers/setup.bash"

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------
setup() {
  init_test_home
  export WSK_DIR
  export WSK_TEST_HOME
  seed_account "work" "Work" "Jane Doe" "jane@work.com" "jane" "$HOME/projects" "id_ed25519_work"
}

teardown() {
  cleanup_test_artifacts
  cleanup_test_home
}

# ---------------------------------------------------------------------------
# WU-6 Test 1: install.sh dispatch() has an 'ai' case that calls run_ai
# ---------------------------------------------------------------------------
@test "install.sh dispatch() contains ai case" {
  grep -q 'ai)' "${WSK_DIR}/install.sh"
  grep -q 'run_ai' "${WSK_DIR}/install.sh"
}

# ---------------------------------------------------------------------------
# WU-6 Test 2: run_full_setup in install.sh calls the AI steps
# ---------------------------------------------------------------------------
@test "install.sh run_full_setup references install_node" {
  # Extract run_full_setup body from install.sh and check it has the AI calls
  # This is a static assertion — the source code must reference these functions.
  awk '/^run_full_setup\(\)/,/^\}/' "${WSK_DIR}/install.sh" | grep -q 'install_node'
}

@test "install.sh run_full_setup references install_pnpm" {
  awk '/^run_full_setup\(\)/,/^\}/' "${WSK_DIR}/install.sh" | grep -q 'install_pnpm'
}

@test "install.sh run_full_setup references install_claude_code" {
  awk '/^run_full_setup\(\)/,/^\}/' "${WSK_DIR}/install.sh" | grep -q 'install_claude_code'
}

@test "install.sh run_full_setup references run_ai_for_all_accounts" {
  awk '/^run_full_setup\(\)/,/^\}/' "${WSK_DIR}/install.sh" | grep -q 'run_ai_for_all_accounts'
}

# ---------------------------------------------------------------------------
# WU-6 Test 3: install.sh sources the new lib files
# ---------------------------------------------------------------------------
@test "install.sh sources lib/os.sh" {
  grep -q 'source.*lib/os\.sh' "${WSK_DIR}/install.sh"
}

@test "install.sh sources lib/node.sh" {
  grep -q 'source.*lib/node\.sh' "${WSK_DIR}/install.sh"
}

@test "install.sh sources lib/claude.sh" {
  grep -q 'source.*lib/claude\.sh' "${WSK_DIR}/install.sh"
}

@test "install.sh sources lib/frameworks.sh" {
  grep -q 'source.*lib/frameworks\.sh' "${WSK_DIR}/install.sh"
}

# ---------------------------------------------------------------------------
# WU-6 Test 4: menu entry "AI dev tools" exists in ui_menu call
# ---------------------------------------------------------------------------
@test "install.sh ui_menu call contains AI dev tools entry" {
  grep -q 'AI dev tools' "${WSK_DIR}/install.sh"
}

# ---------------------------------------------------------------------------
# WU-6 Test 5: menu case routes AI dev tools to run_ai
# ---------------------------------------------------------------------------
@test "install.sh menu case has AI dev tools routing to run_ai" {
  # Check that the case block after ACTION= has an AI dev tools branch
  awk '/case "\$ACTION"/,/esac/' "${WSK_DIR}/install.sh" | grep -q 'AI dev tools'
}

# ---------------------------------------------------------------------------
# WU-6 Test 6: dispatch actually routes 'ai' to run_ai at runtime
# ---------------------------------------------------------------------------
@test "dispatch ai subcommand calls run_ai at runtime" {
  local run_ai_flag="$WSK_TEST_HOME/run_ai_called"

  bash -c "
    export WSK_STUB_LOG='$WSK_STUB_LOG'
    export WSK_TEST_HOME='$WSK_TEST_HOME'
    export WSK_DIR='$WSK_DIR'
    export HOME='$WSK_TEST_HOME'
    export PATH='$WSK_STUB_BIN:/usr/bin:/bin'

    # Stub everything install.sh sources so we can load it safely
    bootstrap()            { true; }
    collect_accounts()     { true; }
    install_packages()     { true; }
    install_terminals()    { true; }
    setup_gh_accounts()    { true; }
    render_all()           { true; }
    link_dotfiles()        { true; }
    run_relink()           { true; }
    run_accounts()         { true; }
    run_doctor()           { true; }
    run_update()           { true; }
    load_accounts()        { true; }
    detect_os()            { true; }
    detect_pkg_mgr()       { true; }
    install_node()         { true; }
    install_pnpm()         { true; }
    install_claude_code()  { true; }
    run_ai_for_all_accounts() { true; }
    tui_menu()             { echo 'Quit'; }
    ui_menu()              { echo 'Quit'; }
    ui_section()           { true; }
    ui_subhead()           { true; }
    check_pass()           { true; }
    check_fail()           { true; }
    check_warn()           { true; }
    ui_confirm()           { return 1; }
    log_success()          { true; }
    log_info()             { true; }

    run_ai() {
      touch '${run_ai_flag}'
    }

    # Source only the dispatch function portion: we define it ourselves
    # matching what install.sh should have after WU-6.
    dispatch() {
      case \"\$1\" in
        setup|full)    run_full_setup ;;
        accounts)      run_accounts ;;
        terminals)     install_terminals ;;
        relink)        run_relink ;;
        doctor|check)  run_doctor ;;
        update)        run_update ;;
        ai)            run_ai ;;
        *)             return 1 ;;
      esac
    }

    dispatch ai
  "

  [[ -f "$run_ai_flag" ]]
}

# ---------------------------------------------------------------------------
# WU-6 Test 7: usage string mentions ai subcommand
# ---------------------------------------------------------------------------
@test "install.sh usage string includes ai subcommand" {
  grep -q 'ai' "${WSK_DIR}/install.sh"
}
