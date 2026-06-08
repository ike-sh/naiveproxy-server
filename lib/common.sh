#!/usr/bin/env bash
# NaiveProxy Server — shared logging and helpers

export NAIVE_LIB_LOADED=1

log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }
log_ok() { printf '[OK] %s\n' "$*"; }
die() { log_error "$*"; exit 1; }

mask_secret() {
  local value="$1"
  local visible="${2:-4}"
  local len="${#value}"
  if (( len <= visible )); then
    printf '****'
    return 0
  fi
  printf '%s****' "${value:0:visible}"
}
