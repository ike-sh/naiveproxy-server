#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  # shellcheck source=../../lib/common.sh
  source "$SCRIPT_DIR/lib/common.sh"
  # shellcheck source=../../lib/encoding.sh
  source "$SCRIPT_DIR/lib/encoding.sh"
}

@test "url_encode encodes special characters" {
  run url_encode "user@name"
  [ "$status" -eq 0 ]
  [ "$output" = "user%40name" ]
}

@test "url_encode preserves safe characters" {
  run url_encode "User-1.test_ok"
  [ "$status" -eq 0 ]
  [ "$output" = "User-1.test_ok" ]
}

@test "caddyfile_quote escapes quotes" {
  run caddyfile_quote 'say "hi"'
  [ "$status" -eq 0 ]
  [ "$output" = '"say \"hi\""' ]
}

@test "mask_secret hides tail" {
  run mask_secret "abcdefghij" 4
  [ "$status" -eq 0 ]
  [ "$output" = "abcd****" ]
}
