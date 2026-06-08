#!/usr/bin/env bash
# NaiveProxy Server — encoding and quoting helpers

url_encode() {
  local raw="$1"
  local i c hex
  for ((i = 0; i < ${#raw}; i++)); do
    c="${raw:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
      *) printf -v hex '%%%02X' "'$c"; printf '%s' "$hex" ;;
    esac
  done
}

base64_no_wrap() {
  local input="$1"
  if command -v base64 >/dev/null 2>&1; then
    printf '%s' "$input" | base64 -w 0 2>/dev/null || printf '%s' "$input" | base64
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$input" | openssl base64 -A
    return 0
  fi
  die "缺少 base64 或 openssl，无法生成 Shadowrocket 链接。"
}

caddyfile_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}
