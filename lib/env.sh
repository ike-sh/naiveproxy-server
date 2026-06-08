#!/usr/bin/env bash
# NaiveProxy Server — naive.env read/write with bash %q quoting

read_env_value() {
  local key="$1" line _nev
  # ENV_FILE is set by the caller (install / test harness).
  # shellcheck disable=SC2154
  [[ -r "${ENV_FILE:-}" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "${key}="* ]] || continue
    _nev="${line#*=}"
    if [[ "$_nev" =~ ^[A-Za-z0-9._:@+-]+$ ]]; then
      printf '%s' "$_nev"
    else
      # bash %q may emit bare escapes (e.g. p@ss:w0rd\,ok); eval restores the value
      # shellcheck disable=SC2292
      eval "_nev=${_nev}"
      printf '%s' "$_nev"
    fi
    return 0
  done < "$ENV_FILE"
}

write_env_kv() {
  printf '%s=%q\n' "$1" "$2"
}
