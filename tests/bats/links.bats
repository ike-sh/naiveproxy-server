#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  source "$SCRIPT_DIR/lib/common.sh"
  source "$SCRIPT_DIR/lib/encoding.sh"
  source "$SCRIPT_DIR/lib/links.sh"
}

@test "generate_v2rayn_link format" {
  run generate_v2rayn_link "user" "pass" "example.com" "test"
  [ "$status" -eq 0 ]
  [[ "$output" == naive+https://user:pass@example.com:443?* ]]
  [[ "$output" == *"#test" ]]
}

@test "generate_shadowrocket_link includes uot=1" {
  run generate_shadowrocket_link "user" "pass" "example.com"
  [ "$status" -eq 0 ]
  [[ "$output" == http2://* ]]
  [[ "$output" == *"uot=1"* ]]
  [[ "$output" == *"peer=example.com"* ]]
}

@test "build_all_domains_list merges primary and extra" {
  run build_all_domains_list "a.com" "b.com,c.com"
  [ "$status" -eq 0 ]
  [ "$output" = "a.com b.com c.com" ]
}

@test "build_all_domains_list primary only" {
  run build_all_domains_list "a.com" ""
  [ "$status" -eq 0 ]
  [ "$output" = "a.com" ]
}
