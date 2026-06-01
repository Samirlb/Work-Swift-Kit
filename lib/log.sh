#!/usr/bin/env bash
set -euo pipefail

readonly _LOG_RED='\033[0;31m'
readonly _LOG_GREEN='\033[0;32m'
readonly _LOG_YELLOW='\033[0;33m'
readonly _LOG_BLUE='\033[0;34m'
readonly _LOG_RESET='\033[0m'

log_info() {
  printf "${_LOG_BLUE}[INFO]${_LOG_RESET} %s\n" "$*"
}

log_success() {
  printf "${_LOG_GREEN}[OK]${_LOG_RESET} %s\n" "$*"
}

log_warn() {
  printf "${_LOG_YELLOW}[WARN]${_LOG_RESET} %s\n" "$*" >&2
}

log_error() {
  printf "${_LOG_RED}[ERROR]${_LOG_RESET} %s\n" "$*" >&2
}

check_pass() { printf '  \033[38;5;42m✓\033[0m %s\n'  "$*"; }
check_fail() { printf '  \033[38;5;196m✗\033[0m %s\n' "$*"; }
check_warn() { printf '  \033[38;5;214m!\033[0m %s\n' "$*"; }
