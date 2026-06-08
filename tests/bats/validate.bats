#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  source "$SCRIPT_DIR/lib/common.sh"
  source "$SCRIPT_DIR/lib/validate.sh"
}

@test "validate_hostname accepts normal domain" {
  run validate_hostname "proxy.example.com" "测试域名"
  [ "$status" -eq 0 ]
}

@test "validate_hostname rejects URL" {
  run validate_hostname "https://evil.com" "测试域名"
  [ "$status" -eq 1 ]
}

@test "validate_hostname rejects comma" {
  run validate_hostname "a,b.com" "测试域名"
  [ "$status" -eq 1 ]
}
