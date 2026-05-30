# OS Abstraction Specification

## Purpose

Provides cross-OS detection and a unified `pkg_install` router so all installers call one function instead of hard-coding `brew`.

## Requirements

### Requirement: OS Detection

The system MUST expose `detect_os` which sets `WSK_OS` to one of: `macos`, `linux`, or `windows`. On Windows (Git Bash / WSL / MSYSTEM env), `WSK_OS=windows` MUST be set and no package installations MUST be attempted; a human-readable instruction MUST be printed instead.

#### Scenario: macOS detected

- GIVEN `uname -s` returns `Darwin`
- WHEN `detect_os` is called
- THEN `WSK_OS` is set to `macos`

#### Scenario: Linux detected

- GIVEN `uname -s` returns `Linux` and `MSYSTEM` is unset
- WHEN `detect_os` is called
- THEN `WSK_OS` is set to `linux`

#### Scenario: Windows environment detected

- GIVEN `MSYSTEM` is set (Git Bash) OR `/proc/version` contains `microsoft` (WSL)
- WHEN `detect_os` is called
- THEN `WSK_OS` is set to `windows`
- AND no package-manager commands are run

---

### Requirement: Package Manager Detection

The system MUST expose `detect_pkg_mgr` which sets `WSK_PKG_MGR` to one of: `brew`, `apt`, `dnf`, `pacman`, or `winget`. Detection MUST be based on which binary is present in PATH, checked in that priority order.

#### Scenario: Homebrew present (macOS)

- GIVEN `WSK_OS=macos` and `brew` is in PATH
- WHEN `detect_pkg_mgr` is called
- THEN `WSK_PKG_MGR` is set to `brew`

#### Scenario: apt present (Debian/Ubuntu)

- GIVEN `WSK_OS=linux` and `apt-get` is in PATH
- WHEN `detect_pkg_mgr` is called
- THEN `WSK_PKG_MGR` is set to `apt`

#### Scenario: No recognized package manager

- GIVEN no recognized package manager binary is in PATH
- WHEN `detect_pkg_mgr` is called
- THEN a warning is printed and the function returns non-zero

---

### Requirement: pkg_install Router

The system MUST expose `pkg_install <package>` which delegates to the correct installer for the current `WSK_PKG_MGR`. On Windows it MUST print instructions and return without executing any installer.

#### Scenario: Installs via brew on macOS

- GIVEN `WSK_PKG_MGR=brew`
- WHEN `pkg_install git` is called
- THEN `brew install git` is executed

#### Scenario: Installs via apt on Linux

- GIVEN `WSK_PKG_MGR=apt`
- WHEN `pkg_install git` is called
- THEN `sudo apt-get install -y git` is executed

#### Scenario: Windows prints instruction only

- GIVEN `WSK_OS=windows`
- WHEN `pkg_install git` is called
- THEN a message like "Please install git manually via winget or the Microsoft Store" is printed
- AND no shell installer command is executed

---

### Requirement: pkg_install Idempotency

`pkg_install` MUST skip installation when the target binary is already present in PATH, using `command -v <package>` as the guard. A `check_pass`-style message MUST be printed indicating it was already installed.

#### Scenario: Package already installed

- GIVEN `command -v git` succeeds
- WHEN `pkg_install git` is called
- THEN no package-manager command is invoked
- AND a "already installed" message is printed

#### Scenario: Package absent — install proceeds

- GIVEN `command -v git` fails
- WHEN `pkg_install git` is called
- THEN the appropriate installer command is executed

---

### Requirement: CI Coverage on macOS and Linux

The `pkg_install` router MUST be exercised by bats tests on both macOS and Ubuntu CI runners with mocked installers. Tests MUST stub `brew`, `apt-get`, `dnf`, and `pacman` via `tests/helpers/setup.bash`.

#### Scenario: Mocked brew invoked on macOS runner

- GIVEN `WSK_PKG_MGR=brew` and `brew` is stubbed in `tests/helpers/setup.bash`
- WHEN a bats test calls `pkg_install somepackage`
- THEN the stub records the invocation and the test asserts it was called

#### Scenario: Mocked apt-get invoked on Linux runner

- GIVEN `WSK_PKG_MGR=apt` and `apt-get` is stubbed
- WHEN a bats test calls `pkg_install somepackage`
- THEN the apt-get stub records the invocation
