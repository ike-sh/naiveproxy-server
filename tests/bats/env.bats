#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  source "$SCRIPT_DIR/lib/common.sh"
  source "$SCRIPT_DIR/lib/env.sh"
  ENV_FILE="$(mktemp)"
  export ENV_FILE
}

teardown() {
  rm -f "$ENV_FILE"
}

@test "write_env_kv and read_env_value roundtrip special chars" {
  write_env_kv PASS 'p@ss:w0rd,ok' >> "$ENV_FILE"
  run read_env_value PASS
  [ "$status" -eq 0 ]
  [ "$output" = 'p@ss:w0rd,ok' ]
}

@test "read_env_value supports legacy unquoted values" {
  printf 'USER=legacyuser\n' > "$ENV_FILE"
  run read_env_value USER
  [ "$status" -eq 0 ]
  [ "$output" = "legacyuser" ]
}
