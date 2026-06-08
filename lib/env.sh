#!/usr/bin/env bash
# NaiveProxy Server — naive.env read/write with bash %q quoting

read_env_value() {
  local key="$1" line _nev
  [[ -r "$ENV_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "${key}="* ]] || continue
    _nev="${line#*=}"
    if [[ "$_nev" =~ ^\' || "$_nev" =~ ^\" || "$_nev" == *\$\'* ]]; then
      eval "_nev=${_nev}"
      printf '%s' "$_nev"
    else
      printf '%s' "$_nev"
    fi
    return 0
  done < "$ENV_FILE"
}

write_env_kv() {
  printf '%s=%q\n' "$1" "$2"
}
