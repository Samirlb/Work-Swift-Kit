# Node Toolchain Specification

## Purpose

Installs Node.js and pnpm once (global binaries) per OS, with correct paths for Intel macOS. Both functions MUST be idempotent.

## Requirements

### Requirement: Node Installation

The system MUST expose `install_node` which installs Node.js using the OS-appropriate method. Installation MUST be preceded by a `command -v node` idempotency check.

| OS | Method |
|----|--------|
| `macos` | `brew install node` |
| `linux` | `pkg_install node` (apt/dnf/pacman) |
| `windows` | Print instruction: "Install Node via winget: `winget install OpenJS.NodeJS`"; no command run |

#### Scenario: Node absent on macOS

- GIVEN `WSK_OS=macos`, `WSK_PKG_MGR=brew`, and `command -v node` fails
- WHEN `install_node` is called
- THEN `brew install node` is executed

#### Scenario: Node absent on Linux

- GIVEN `WSK_OS=linux` and `command -v node` fails
- WHEN `install_node` is called
- THEN `pkg_install node` is executed via the active pkg manager

#### Scenario: Node already present (idempotent)

- GIVEN `command -v node` succeeds
- WHEN `install_node` is called
- THEN no installer command is run
- AND a "node already installed" message is printed

#### Scenario: Windows — instruction only

- GIVEN `WSK_OS=windows`
- WHEN `install_node` is called
- THEN a manual install instruction is printed
- AND no installer is executed

---

### Requirement: pnpm Installation

The system MUST expose `install_pnpm` which installs pnpm using the OS-appropriate method. On `macos` (any architecture), `brew install pnpm` MUST always be used. The standalone `get.pnpm.io` curl script MUST NOT be used on macOS because it fails on Intel (darwin-x64).

| OS | Method |
|----|--------|
| `macos` | `brew install pnpm` (required; standalone script must not be used) |
| `linux` | `corepack enable pnpm` if corepack available, else `curl -fsSL https://get.pnpm.io/install.sh \| sh -` |
| `windows` | Print instruction: "Install pnpm via winget: `winget install pnpm.pnpm`" |

#### Scenario: pnpm absent on macOS (any architecture)

- GIVEN `WSK_OS=macos` and `command -v pnpm` fails
- WHEN `install_pnpm` is called
- THEN `brew install pnpm` is executed
- AND the curl/standalone script is NOT invoked

#### Scenario: pnpm absent on Linux with corepack available

- GIVEN `WSK_OS=linux`, `command -v pnpm` fails, and `command -v corepack` succeeds
- WHEN `install_pnpm` is called
- THEN `corepack enable pnpm` is executed

#### Scenario: pnpm absent on Linux without corepack

- GIVEN `WSK_OS=linux`, `command -v pnpm` fails, and `command -v corepack` fails
- WHEN `install_pnpm` is called
- THEN the curl installer `https://get.pnpm.io/install.sh` is piped to `sh`

#### Scenario: pnpm already present (idempotent)

- GIVEN `command -v pnpm` succeeds
- WHEN `install_pnpm` is called
- THEN no installer command is run

---

### Requirement: Install Order Enforcement

`install_pnpm` MUST verify Node is present (`command -v node`) before proceeding. If Node is absent, it MUST print an error and return non-zero without attempting pnpm installation.

#### Scenario: pnpm install blocked when Node absent

- GIVEN `command -v node` fails
- WHEN `install_pnpm` is called
- THEN an error message "Node.js is required before pnpm" is printed
- AND pnpm install is not attempted
- AND the function returns non-zero
