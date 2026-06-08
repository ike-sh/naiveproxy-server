#!/usr/bin/env bash
# NaiveProxy Server — client link generators
# Requires: lib/encoding.sh

generate_v2rayn_link() {
  local user="$1"
  local pass="$2"
  local domain="$3"
  local name="${4:-$domain}"
  local encoded_user encoded_pass
  encoded_user="$(url_encode "$user")"
  encoded_pass="$(url_encode "$pass")"
  printf 'naive+https://%s:%s@%s:443?security=tls&sni=%s&insecure=0&allowInsecure=0&type=tcp&headerType=none#%s' \
    "$encoded_user" "$encoded_pass" "$domain" "$domain" "$name"
}

generate_shadowrocket_link() {
  local user="$1"
  local pass="$2"
  local domain="$3"
  local name="${4:-n2}"
  local encoded_auth
  encoded_auth="$(base64_no_wrap "${user}:${pass}@${domain}:443")"
  encoded_auth="${encoded_auth%%=}"
  printf 'http2://%s?peer=%s&uot=1#%s' "$encoded_auth" "$domain" "$name"
}

build_all_domains_list() {
  local primary="$1"
  local extra="$2"
  local result="$primary"
  local item
  if [[ -z "$extra" ]]; then
    printf '%s' "$result"
    return 0
  fi
  IFS=',' read -ra _extra_arr <<< "$extra"
  for item in "${_extra_arr[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ -n "$item" ]] || continue
    result+=" ${item}"
  done
  printf '%s' "$result"
}
