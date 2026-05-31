# Delta for Bootstrap

## MODIFIED Requirements

### Requirement: OS Compatibility

`lib/bootstrap.sh` MUST support macOS and Linux. It MUST NOT hard-exit when `uname -s` is not `Darwin`. On Linux it MUST source `lib/os.sh`, call `detect_os` and `detect_pkg_mgr`, then proceed with installation. On Windows it MUST print manual setup instructions and exit cleanly (exit 0).
(Previously: bootstrap.sh called `exit 1` immediately if `uname -s != Darwin`.)

#### Scenario: macOS — bootstrap proceeds normally

- GIVEN `uname -s` returns `Darwin`
- WHEN `bootstrap` is called
- THEN `detect_os` sets `WSK_OS=macos`
- AND Homebrew install/prereqs continue as before

#### Scenario: Linux — bootstrap proceeds without Darwin guard

- GIVEN `uname -s` returns `Linux`
- WHEN `bootstrap` is called
- THEN no exit occurs due to OS check
- AND `detect_os` sets `WSK_OS=linux`
- AND `detect_pkg_mgr` sets `WSK_PKG_MGR` appropriately
- AND prerequisite packages are installed via `pkg_install`

#### Scenario: Windows — clean exit with instructions

- GIVEN `WSK_OS=windows`
- WHEN `bootstrap` is called
- THEN manual setup instructions are printed
- AND the script exits with code 0 (no crash)

---

### Requirement: pkg_install Used for Prereqs

`lib/bootstrap.sh` MUST install prerequisite tools (`gum`, `stow`, `fzf`, `gettext`) via `pkg_install` rather than hard-coded `brew install`. This allows the same bootstrap to function on Linux.
(Previously: bootstrap used direct `brew install` calls for all prereqs.)

#### Scenario: Prereqs installed via pkg_install on Linux

- GIVEN `WSK_OS=linux` and `WSK_PKG_MGR=apt`
- WHEN `bootstrap` installs prereqs
- THEN `pkg_install gum`, `pkg_install stow`, `pkg_install fzf`, `pkg_install gettext` are each called
- AND no direct `brew install` call is made
