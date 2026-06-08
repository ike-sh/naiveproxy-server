#!/usr/bin/env bash
# VPS 部署验证助手 — 在已安装 NaiveProxy Server 的 Debian/Ubuntu 上以 root 运行
# 用法：sudo bash scripts/vps-verify-checklist.sh [DOMAIN]
# 未传 DOMAIN 时尝试从 /etc/caddy/naive.env 读取
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SCRIPT="${NAIVE_INSTALL_SCRIPT:-$ROOT/install-naive-server.sh}"
ENV_FILE="/etc/caddy/naive.env"
DOMAIN="${1:-}"
SERVICE_NAME="caddy"
PUBLIC_IP=""
PASS=0
FAIL=0
MANUAL=0

log_ok() { printf '[OK] %s\n' "$*"; ((PASS++)) || true; }
log_fail() { printf '[FAIL] %s\n' "$*" >&2; ((FAIL++)) || true; }
log_manual() { printf '[MANUAL] %s\n' "$*"; ((MANUAL++)) || true; }
log_info() { printf '[INFO] %s\n' "$*"; }

resolve_install_script() {
  if [[ -f "$INSTALL_SCRIPT" ]]; then
    return 0
  fi
  for candidate in \
    "$ROOT/install-naive-server.sh" \
    "/root/install-naive-server.sh" \
    "./install-naive-server.sh"; do
    if [[ -f "$candidate" ]]; then
      INSTALL_SCRIPT="$candidate"
      return 0
    fi
  done
  log_info "本地未找到 install-naive-server.sh，从 v1.0.6 Release 下载到 /tmp ..."
  curl -fsSL \
    "https://github.com/ike-sh/naiveproxy-server/releases/download/v1.0.6/install-naive-server.sh" \
    -o /tmp/install-naive-server.sh
  chmod +x /tmp/install-naive-server.sh
  INSTALL_SCRIPT="/tmp/install-naive-server.sh"
}

read_env_value_simple() {
  local key="$1" line _nev
  [[ -r "${ENV_FILE:-}" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "${key}="* ]] || continue
    _nev="${line#*=}"
    if [[ "$_nev" =~ ^[A-Za-z0-9._:@+-]+$ ]]; then
      printf '%s' "$_nev"
    else
      # shellcheck disable=SC2292
      eval "_nev=${_nev}"
      printf '%s' "$_nev"
    fi
    return 0
  done < "$ENV_FILE"
}

load_install_info_from_env() {
  [[ -r "$ENV_FILE" ]] || return 0
  [[ -n "$DOMAIN" ]] || DOMAIN="$(read_env_value_simple DOMAIN || true)"
  local svc
  svc="$(read_env_value_simple SERVICE_NAME || true)"
  [[ -n "$svc" ]] && SERVICE_NAME="$svc"
}

detect_public_ip() {
  if command -v curl >/dev/null 2>&1; then
    PUBLIC_IP="$(curl -fsS4 --connect-timeout 5 https://api.ipify.org 2>/dev/null || true)"
  fi
  [[ -n "$PUBLIC_IP" ]] || PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
}

check_dns() {
  log_info "=== #1 DNS 解析 ==="
  [[ -n "$DOMAIN" ]] || { log_fail "未设置 DOMAIN"; return; }
  if ! command -v dig >/dev/null 2>&1; then
    log_manual "#1 请安装 dnsutils 后执行：dig +short $DOMAIN"
    return
  fi
  local resolved
  resolved="$(dig +short "$DOMAIN" | tail -n1)"
  if [[ -z "$resolved" ]]; then
    log_fail "#1 $DOMAIN 无 A/AAAA 记录"
    return
  fi
  log_info "解析结果：$resolved（本机公网 IP：${PUBLIC_IP:-未知}）"
  if [[ -n "$PUBLIC_IP" && "$resolved" == "$PUBLIC_IP" ]]; then
    log_ok "#1 DNS 指向本机公网 IP"
  else
    log_manual "#1 请确认 $DOMAIN 解析到 VPS 公网 IP（当前解析 $resolved）"
  fi
}

check_status() {
  log_info "=== #3–#4 服务状态 & Caddyfile 结构 ==="
  if ! bash "$INSTALL_SCRIPT" --status; then
    log_fail "#3 --status 执行失败"
    return
  fi
  if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    log_ok "#3 服务 ${SERVICE_NAME} active"
  else
    log_fail "#3 服务 ${SERVICE_NAME} 未 active（请检查 systemctl status）"
  fi
  log_manual "#4 请在上文 --status 输出中确认「推荐结构 OK」"
}

check_https() {
  log_info "=== #5 HTTPS 回落 ==="
  [[ -n "$DOMAIN" ]] || { log_fail "#5 无 DOMAIN"; return; }
  if ! command -v curl >/dev/null 2>&1; then
    log_manual "#5 请安装 curl 后执行：curl -4I https://$DOMAIN"
    return
  fi
  if curl -fsS4I --connect-timeout 10 --max-time 20 "https://${DOMAIN}" | head -n1 | grep -qE 'HTTP/[12] (200|301|302)'; then
    log_ok "#5 HTTPS 回落正常"
  else
    log_fail "#5 HTTPS 探测失败：curl -4I https://$DOMAIN"
  fi
}

check_proxy_self_test() {
  log_info "=== #6–#7 证书 & 代理自检 ==="
  bash "$INSTALL_SCRIPT" --proxy-self-test || log_fail "#7 --proxy-self-test 返回非零"
  log_manual "#6 请在上文 openssl 输出中确认证书未过期"
}

check_restart() {
  log_info "=== #10 重启恢复 ==="
  if systemctl restart "$SERVICE_NAME"; then
    sleep 5
    if curl -fsS4I --connect-timeout 10 "https://${DOMAIN}" >/dev/null 2>&1; then
      log_ok "#10 重启后 HTTPS 正常"
    else
      log_fail "#10 重启后 HTTPS 探测失败"
    fi
  else
    log_fail "#10 systemctl restart ${SERVICE_NAME} 失败"
  fi
}

print_manual_items() {
  cat <<'MANUAL'

=== #2 #8 #9 需人工确认 ===
#2  安装过程应无 ERROR，并输出客户端链接（--show-client）
#8  v2rayN 导入 Naive 节点，UDP over TCP = On，应显示延迟
#9  v2rayN 代理模式下可访问外网

客户端参数：Naive / HTTP2 · UDP over TCP On · QUIC Off · SNI=域名 · 跳过证书验证=false
MANUAL
}

main() {
  [[ "${EUID:-0}" -eq 0 ]] || { log_fail "请使用 root 运行"; exit 1; }
  resolve_install_script
  load_install_info_from_env
  detect_public_ip
  log_info "使用脚本：$INSTALL_SCRIPT"
  log_info "验证域名：${DOMAIN:-（未设置）}"
  log_info "服务名：${SERVICE_NAME}"

  check_dns
  check_status
  check_https
  check_proxy_self_test
  check_restart
  print_manual_items

  printf '\n========== 汇总 ==========\n'
  printf '自动通过：%s  失败：%s  需人工：%s\n' "$PASS" "$FAIL" "$MANUAL"
  if [[ "$FAIL" -eq 0 ]]; then
    log_ok "自动项全部通过；完成 #2/#8/#9 人工项后即为部署合格"
    exit 0
  fi
  exit 1
}

main "$@"
