#!/usr/bin/env bash
# NaiveProxy Server — hostname and input validation

if [[ -z "${NAIVE_LIB_LOADED:-}" ]]; then
  # shellcheck source=common.sh disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

validate_hostname() {
  local name="$1"
  local label="${2:-域名}"
  [[ -n "$name" ]] || die "${label} 不能为空。"
  [[ "$name" != *"://"* ]] || die "${label} 必须是域名，不是 URL。"
  [[ "$name" != *"/"* ]] || die "${label} 不能包含路径。"
  [[ "$name" != *","* ]] || die "${label} 不能包含逗号。"
  [[ "$name" =~ ^[A-Za-z0-9.-]+$ ]] || die "${label} 包含不支持的字符：${name}"
  [[ "$name" == *.* ]] || log_warn "${label} 不包含点号，公网 TLS 证书申请可能失败：${name}"
}
