#!/usr/bin/env bash
set -euo pipefail

_naive_resolve_script_dir() {
  if [[ -n "${BASH_SOURCE[0]}" && "${BASH_SOURCE[0]}" != /dev/fd/* && -f "${BASH_SOURCE[0]}" ]]; then
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
  fi
}

NAIVE_SCRIPT_DIR="$(_naive_resolve_script_dir)"
if [[ -n "$NAIVE_SCRIPT_DIR" && -d "$NAIVE_SCRIPT_DIR/lib" ]]; then
  # shellcheck source=lib/common.sh
  source "$NAIVE_SCRIPT_DIR/lib/common.sh"
  # shellcheck source=lib/encoding.sh
  source "$NAIVE_SCRIPT_DIR/lib/encoding.sh"
  # shellcheck source=lib/links.sh
  source "$NAIVE_SCRIPT_DIR/lib/links.sh"
  source "$NAIVE_SCRIPT_DIR/lib/validate.sh"
  source "$NAIVE_SCRIPT_DIR/lib/env.sh"
fi

SCRIPT_NAME="NaiveProxy Server"
SCRIPT_VERSION="1.0.4"
SCRIPT_AUTHOR="ike-sh"
SCRIPT_GITHUB="https://github.com/ike-sh/naiveproxy-server"
BUILDER_REPO_DEFAULT="ike-sh/caddy-naive-builder"
BUILDER_GITHUB="https://github.com/ike-sh/caddy-naive-builder"

DEFAULT_REPO="$BUILDER_REPO_DEFAULT"
DEFAULT_INSTALL_BIN="/usr/local/bin/caddy"
DEFAULT_SERVICE_NAME="caddy"

CONFIG_DIR="/etc/caddy"
CADDYFILE="/etc/caddy/Caddyfile"
SITE_DIR="/var/www/naive"
DATA_DIR="/var/lib/caddy"
BACKUP_DIR="/var/backups/caddy-naive"
UPDATE_SCRIPT="/usr/local/bin/update-caddy-naive"
ENV_FILE="/etc/caddy/naive.env"
AUTO_UPDATE_SERVICE_FILE="/etc/systemd/system/caddy-naive-update.service"
AUTO_UPDATE_TIMER_FILE="/etc/systemd/system/caddy-naive-update.timer"
CERT_BASE_DIR="/etc/caddy/certs"
ACME_SH="/root/.acme.sh/acme.sh"

DOMAIN=""
EMAIL=""
AUTH_USER=""
AUTH_PASS=""
EXTRA_DOMAINS=""
EXTRA_AUTH_RAW=""
SITE_MODE="static"
UPSTREAM=""
UPSTREAM_BASE=""
UPSTREAM_HOST=""
REPO="$DEFAULT_REPO"
INSTALL_BIN="$DEFAULT_INSTALL_BIN"
SERVICE_NAME="$DEFAULT_SERVICE_NAME"
SERVICE_FILE="/etc/systemd/system/${DEFAULT_SERVICE_NAME}.service"
DETECTED_UNAME_M=""
TARGET_ARCH=""
ASSET_NAME=""
SHA_ASSET_NAME=""
CERT_MODE="acme-standalone"
CERT_FULLCHAIN=""
CERT_KEY=""
HTTP3="off"
PROBE_RESISTANCE="on"

AUTO_UPDATE=0
NO_START=0
INTERACTIVE=0
MENU_MODE=0
ACTION_STATUS=0
ACTION_CHECK_UPDATE=0
ACTION_UPDATE=0
ACTION_FORCE_UPDATE=0
ACTION_SHOW_CLIENT=0
ACTION_LOGS=0
ACTION_ISSUE_CERT=0
ACTION_TLS_DIAGNOSE=0
ACTION_CHANGE_USER=0
ACTION_CHANGE_PASS=0
ACTION_HTTP3_TOGGLE=0
ACTION_PROBE_TOGGLE=0
ACTION_PROXY_SELF_TEST=0
ACTION_FIX_STATIC_PERMS=0
ACTION_TEST_ARCH=0
SET_USER_VALUE=""
SET_PASS_VALUE=""
DO_UNINSTALL=0
DO_PURGE=0
LAST_BACKUP_PATH=""
TMP_DIR=""
DOWNLOADED_CADDY=""
DOWNLOADED_ARCHIVE_SHA256=""
DOWNLOADED_RELEASE_TAG=""
RECORDED_BUILDER_RELEASE_ARCH=""
RECORDED_BUILDER_RELEASE_ASSET=""
LAST_CADDYFILE_BACKUP_FOR_RESTORE=""

if [[ -z "${NAIVE_LIB_LOADED:-}" ]]; then
log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }
log_ok() { printf '[OK] %s\n' "$*"; }
die() { log_error "$*"; exit 1; }
fi

read_tty() {
  local __var="$1"
  local __input

  if [[ -t 0 && -r /dev/tty ]]; then
    IFS= read -r __input </dev/tty || return 1
  else
    IFS= read -r __input || return 1
  fi

  printf -v "$__var" '%s' "$__input"
}

read_tty_silent() {
  local __var="$1"
  local __input

  if [[ -t 0 && -r /dev/tty ]]; then
    IFS= read -r -s __input </dev/tty || return 1
  else
    IFS= read -r -s __input || return 1
  fi

  printf -v "$__var" '%s' "$__input"
}

clear_menu_screen() {
  if [[ -t 1 ]]; then
    clear 2>/dev/null || printf '\033c'
  fi
}

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

print_banner() {
  cat <<BANNER
${SCRIPT_NAME} 管理脚本
作者：${SCRIPT_AUTHOR}
GitHub：${SCRIPT_GITHUB}
Builder：${BUILDER_GITHUB}
BANNER
}

print_version() {
  cat <<VERSION
${SCRIPT_NAME} ${SCRIPT_VERSION}
Author: ${SCRIPT_AUTHOR}
GitHub: ${SCRIPT_GITHUB}
Builder: ${BUILDER_GITHUB}
VERSION
}

usage() {
  print_banner
  cat <<USAGE

用法：
  bash install-naive-server.sh --domain DOMAIN [options]
  bash install-naive-server.sh --menu
  bash install-naive-server.sh --interactive
  bash install-naive-server.sh --status
  bash install-naive-server.sh --check-update
  bash install-naive-server.sh --update
  bash install-naive-server.sh --uninstall
  bash install-naive-server.sh --purge

必填：
  --domain DOMAIN              部署域名，例如 example.com。

选项：
  --email EMAIL                Caddy 或 acme.sh 申请 ACME TLS 证书使用的邮箱。
  --user USER                  Basic Auth 用户名；不传则自动生成或复用。
  --pass PASS                  Basic Auth 密码；不传则自动生成或复用。
  --extra-domain DOMAIN        额外绑定域名，可重复指定；与主域名共享同一代理实例。
  --extra-auth USER:PASS       额外认证账号，可重复指定；格式 user:pass。
  --site-mode static|reverse   回落网站模式，默认 static。
  --upstream URL               reverse 模式必填。
  --cert-mode MODE             证书模式：caddy-auto、caddy-zerossl 或 acme-standalone，默认 acme-standalone。
  --http3 on|off               HTTP/3 开关，默认 off。
  --enable-http3               启用 HTTP/3，等价于 --http3 on。
  --disable-http3              关闭 HTTP/3，等价于 --http3 off。
  --no-probe-resistance        临时关闭 probe_resistance，仅建议排查时使用；无 --domain 时会修改当前安装配置。
  --enable-probe-resistance    重新开启 probe_resistance。
  --repo OWNER/REPO            GitHub Release 仓库，默认：${BUILDER_REPO_DEFAULT}。
  --install-bin PATH           Caddy 安装路径，默认：/usr/local/bin/caddy。
  --service-name NAME          systemd 服务名，默认：caddy。
  --menu                       进入主菜单。
  --interactive, -i            进入主菜单，不直接进入安装向导。
  --auto-update                安装并启用每日自动更新 timer。
  --no-start                   只写入文件，不启用或启动服务/timer。
  --version                    显示脚本版本、作者、GitHub 地址和 Builder 仓库地址。
  --status                     查看当前安装状态。
  --check-update               检测 GitHub Release 是否有新 Caddy naive 内核。
  --update                     更新 Caddy naive 内核。
  --force-update               强制重新安装 latest Caddy naive 内核。
  --issue-cert                 使用 acme.sh + ZeroSSL standalone 重新申请本地证书并切换 Caddyfile。
  --tls-diagnose               执行 SSL / 证书诊断。
  --show-client                查看当前配置和客户端链接。
  --change-user                交互式修改认证用户名。
  --change-pass                交互式修改认证密码。
  --set-user USER              非交互设置认证用户名。
  --set-pass PASS              非交互设置认证密码。
  --proxy-self-test            执行代理核心自检。
  --fix-static-perms           修复静态站目录权限并重启 Caddy。
  --logs                       查看 caddy 日志。
  --uninstall                  卸载服务和更新脚本，保留配置、站点和数据。
  --purge                      完全卸载服务、更新脚本、二进制、配置、站点和数据。
  --help                       显示帮助。

示例：
  bash install-naive-server.sh --domain example.com --email me@example.com --site-mode static --cert-mode acme-standalone
  bash install-naive-server.sh --domain example.com --email me@example.com --site-mode reverse --upstream https://www.example.org --cert-mode acme-standalone
  bash install-naive-server.sh --issue-cert
  bash install-naive-server.sh --tls-diagnose
  bash install-naive-server.sh --set-user newuser --set-pass 'newpassword'
USAGE
}

refresh_cert_paths() {
  if [[ -n "$DOMAIN" ]]; then
    CERT_FULLCHAIN="${CERT_BASE_DIR}/${DOMAIN}/fullchain.pem"
    CERT_KEY="${CERT_BASE_DIR}/${DOMAIN}/privkey.pem"
  fi
}

refresh_paths() {
  SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
  refresh_cert_paths
}

naive_all_domains() {
  if [[ -n "${NAIVE_LIB_LOADED:-}" ]] && declare -f build_all_domains_list >/dev/null 2>&1; then
    build_all_domains_list "$@"
    return 0
  fi
  local primary="$1"
  local extra="$2"
  local result="$primary"
  local item
  [[ -n "$primary" ]] || return 0
  [[ -n "$extra" ]] || { printf '%s' "$result"; return 0; }
  IFS=',' read -ra _naive_extra_domains <<< "$extra"
  for item in "${_naive_extra_domains[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ -n "$item" ]] || continue
    result+=" ${item}"
  done
  printf '%s' "$result"
}

naive_append_extra_domain() {
  local domain="$1"
  local item
  [[ -n "$domain" ]] || return 0
  validate_hostname "$domain" "额外域名"
  if [[ -n "$DOMAIN" && "$domain" == "$DOMAIN" ]]; then
    die "额外域名不能与主域名相同：${domain}"
  fi
  if [[ -n "$EXTRA_DOMAINS" ]]; then
    IFS=',' read -ra _naive_dup_check <<< "$EXTRA_DOMAINS"
    for item in "${_naive_dup_check[@]}"; do
      item="${item#"${item%%[![:space:]]*}"}"
      item="${item%"${item##*[![:space:]]}"}"
      [[ "$item" != "$domain" ]] || die "额外域名重复：${domain}"
    done
    EXTRA_DOMAINS+=",${domain}"
  else
    EXTRA_DOMAINS="$domain"
  fi
}

naive_append_extra_auth() {
  local pair="$1"
  local user pass
  [[ -n "$pair" ]] || return 0
  [[ "$pair" == *:* ]] || die "--extra-auth 格式应为 user:pass"
  user="${pair%%:*}"
  pass="${pair#*:}"
  [[ -n "$user" && -n "$pass" ]] || die "--extra-auth 格式应为 user:pass，用户名和密码均不能为空。"
  [[ "$pass" != *","* ]] || die "额外账号密码不能包含逗号（会与 EXTRA_AUTH 存储格式冲突）。"
  validate_auth_user_safe "$user"
  validate_credential_token "PASS" "$pass"
  if [[ -n "$EXTRA_AUTH_RAW" ]]; then
    EXTRA_AUTH_RAW+=",${user}:${pass}"
  else
    EXTRA_AUTH_RAW="${user}:${pass}"
  fi
}

if [[ -z "${NAIVE_LIB_LOADED:-}" ]]; then
url_encode() {
  local input="$1"
  local output="" char hex i
  local LC_ALL=C
  for ((i = 0; i < ${#input}; i++)); do
    char="${input:i:1}"
    case "$char" in
      [a-zA-Z0-9.~_-])
        output+="$char"
        ;;
      *)
        printf -v hex '%%%02X' "'$char"
        output+="$hex"
        ;;
    esac
  done

  printf '%s' "$output"
}

base64_no_wrap() {
  local input="$1"
  local encoded

  if encoded="$(printf '%s' "$input" | base64 -w 0 2>/dev/null)"; then
    :
  else
    encoded="$(printf '%s' "$input" | base64 | tr -d '\n')"
  fi

  while [[ "$encoded" == *= ]]; do
    encoded="${encoded%=}"
  done

  printf '%s' "$encoded"
}

caddyfile_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}
fi

generate_v2rayn_link() {
  local encoded_user encoded_pass encoded_name
  encoded_user="$(url_encode "$AUTH_USER")"
  encoded_pass="$(url_encode "$AUTH_PASS")"
  encoded_name="$(url_encode "naive-${DOMAIN}")"
  printf 'naive+https://%s:%s@%s:443?security=tls&sni=%s&insecure=0&allowInsecure=0&type=tcp&headerType=none#%s' \
    "$encoded_user" "$encoded_pass" "$DOMAIN" "$DOMAIN" "$encoded_name"
}

generate_shadowrocket_link() {
  local encoded_auth encoded_name
  encoded_auth="$(base64_no_wrap "${AUTH_USER}:${AUTH_PASS}@${DOMAIN}:443")"
  encoded_name="$(url_encode "n2")"
  printf 'http2://%s?peer=%s&uot=1#%s' "$encoded_auth" "$DOMAIN" "$encoded_name"
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    if [[ -t 0 ]]; then
      MENU_MODE=1
      refresh_paths
      return 0
    fi
    usage
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)
        shift
        [[ $# -gt 0 ]] || die "--domain 需要一个值。"
        DOMAIN="$1"
        ;;
      --email)
        shift
        [[ $# -gt 0 ]] || die "--email 需要一个值。"
        EMAIL="$1"
        ;;
      --user)
        shift
        [[ $# -gt 0 ]] || die "--user 需要一个值。"
        AUTH_USER="$1"
        ;;
      --pass)
        shift
        [[ $# -gt 0 ]] || die "--pass 需要一个值。"
        AUTH_PASS="$1"
        ;;
      --extra-domain)
        shift
        [[ $# -gt 0 ]] || die "--extra-domain 需要一个值。"
        naive_append_extra_domain "$1"
        ;;
      --extra-auth)
        shift
        [[ $# -gt 0 ]] || die "--extra-auth 需要一个值（格式 user:pass）。"
        naive_append_extra_auth "$1"
        ;;
      --site-mode)
        shift
        [[ $# -gt 0 ]] || die "--site-mode 需要一个值。"
        SITE_MODE="$1"
        ;;
      --upstream)
        shift
        [[ $# -gt 0 ]] || die "--upstream 需要一个值。"
        UPSTREAM="$1"
        ;;
      --cert-mode)
        shift
        [[ $# -gt 0 ]] || die "--cert-mode 需要一个值。"
        CERT_MODE="$1"
        ;;
      --http3)
        shift
        [[ $# -gt 0 ]] || die "--http3 需要一个值。"
        HTTP3="$1"
        ACTION_HTTP3_TOGGLE=1
        ;;
      --enable-http3)
        HTTP3="on"
        ACTION_HTTP3_TOGGLE=1
        ;;
      --disable-http3)
        HTTP3="off"
        ACTION_HTTP3_TOGGLE=1
        ;;
      --no-probe-resistance)
        PROBE_RESISTANCE="off"
        ACTION_PROBE_TOGGLE=1
        ;;
      --enable-probe-resistance)
        PROBE_RESISTANCE="on"
        ACTION_PROBE_TOGGLE=1
        ;;
      --repo)
        shift
        [[ $# -gt 0 ]] || die "--repo 需要一个值。"
        REPO="$1"
        ;;
      --install-bin)
        shift
        [[ $# -gt 0 ]] || die "--install-bin 需要一个值。"
        INSTALL_BIN="$1"
        ;;
      --service-name)
        shift
        [[ $# -gt 0 ]] || die "--service-name 需要一个值。"
        SERVICE_NAME="$1"
        ;;
      --menu)
        MENU_MODE=1
        ;;
      --interactive|-i)
        MENU_MODE=1
        ;;
      --auto-update)
        AUTO_UPDATE=1
        ;;
      --no-start)
        NO_START=1
        ;;
      --version)
        print_version
        exit 0
        ;;
      --status)
        ACTION_STATUS=1
        ;;
      --check-update)
        ACTION_CHECK_UPDATE=1
        ;;
      --update)
        ACTION_UPDATE=1
        ;;
      --force-update)
        ACTION_FORCE_UPDATE=1
        ;;
      --test-arch)
        ACTION_TEST_ARCH=1
        ;;
      --issue-cert)
        ACTION_ISSUE_CERT=1
        ;;
      --tls-diagnose)
        ACTION_TLS_DIAGNOSE=1
        ;;
      --show-client)
        ACTION_SHOW_CLIENT=1
        ;;
      --change-user)
        ACTION_CHANGE_USER=1
        ;;
      --change-pass)
        ACTION_CHANGE_PASS=1
        ;;
      --set-user)
        shift
        [[ $# -gt 0 ]] || die "--set-user 需要一个值。"
        SET_USER_VALUE="$1"
        ;;
      --set-pass)
        shift
        [[ $# -gt 0 ]] || die "--set-pass 需要一个值。"
        SET_PASS_VALUE="$1"
        ;;
      --proxy-self-test)
        ACTION_PROXY_SELF_TEST=1
        ;;
      --fix-static-perms)
        ACTION_FIX_STATIC_PERMS=1
        ;;
      --logs)
        ACTION_LOGS=1
        ;;
      --uninstall)
        DO_UNINSTALL=1
        ;;
      --purge)
        DO_PURGE=1
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "未知参数：$1"
        ;;
    esac
    shift
  done

  refresh_paths
}

prompt_text() {
  local var_name="$1"
  local label="$2"
  local required="$3"
  local example="${4:-}"
  local current input value prompt

  while true; do
    current="${!var_name}"
    if [[ -n "$current" ]]; then
      prompt="${label} [${current}]: "
    elif [[ -n "$example" ]]; then
      prompt="${label} (${example}): "
    else
      prompt="${label}: "
    fi

    printf '%s' "$prompt"
    read_tty input || die "输入已取消。"
    if [[ -z "$input" ]]; then
      value="$current"
    else
      value="$input"
    fi

    if [[ "$required" == "required" && -z "$value" ]]; then
      log_warn "${label} 不能为空。"
      continue
    fi

    printf -v "$var_name" '%s' "$value"
    return 0
  done
}

prompt_password() {
  local first second

  while true; do
    if [[ -n "$AUTH_PASS" ]]; then
      printf '认证密码 PASS [已提供，回车保留；输入新密码可覆盖]: '
    else
      printf '认证密码 PASS [回车自动生成强随机密码]: '
    fi

    read_tty_silent first || die "输入已取消。"
    printf '\n'

    if [[ -z "$first" ]]; then
      return 0
    fi

    printf '请再次输入认证密码 PASS: '
    read_tty_silent second || die "输入已取消。"
    printf '\n'

    if [[ "$first" == "$second" ]]; then
      AUTH_PASS="$first"
      return 0
    fi

    log_warn "两次输入的密码不一致，请重新输入。"
  done
}

prompt_site_mode() {
  local input default_label

  while true; do
    default_label="$SITE_MODE"
    printf '回落网站模式 SITE_MODE：\n'
    printf '  1) static  - 本地静态网页，最稳定，推荐\n'
    printf '              网站目录：%s\n' "$SITE_DIR"
    printf '              首页文件：%s/index.html\n' "$SITE_DIR"
    printf '              适合放一个普通首页 / 产品页 / 个人页\n'
    printf '  2) reverse - 反代一个正常网站作为回落站\n'
    printf '              示例：https://www.example.org\n'
    printf '              注意：第三方网站可能受 CSP、Cookie、跳转、Host 校验和合规影响\n'
    printf '              建议只反代自己有权使用的网站或普通公开静态站\n'
    printf '请选择 [1/2/static/reverse，回车默认 %s]: ' "$default_label"
    read_tty input || die "输入已取消。"

    case "$input" in
      "")
        [[ "$SITE_MODE" == "static" || "$SITE_MODE" == "reverse" ]] || SITE_MODE="static"
        return 0
        ;;
      1|static|STATIC)
        SITE_MODE="static"
        return 0
        ;;
      2|reverse|REVERSE)
        SITE_MODE="reverse"
        return 0
        ;;
      *)
        log_warn "请选择 static 或 reverse。"
        ;;
    esac
  done
}

prompt_cert_mode() {
  local input

  while true; do
    printf '请选择 HTTPS 证书模式：\n'
    printf '  1) caddy-auto\n'
    printf '     Caddy 自动申请证书，最简单，但部分机器可能 ACME 超时。\n'
    printf '  2) caddy-zerossl\n'
    printf '     Caddy 强制 ZeroSSL。\n'
    printf '  3) acme-standalone\n'
    printf '     使用 acme.sh + ZeroSSL standalone 先签证书，然后 Caddy 使用本地证书文件，推荐。\n'
    printf '默认：acme-standalone\n'
    printf '请选择 [1/2/3/caddy-auto/caddy-zerossl/acme-standalone，回车默认 %s]: ' "${CERT_MODE:-acme-standalone}"
    read_tty input || die "输入已取消。"

    case "$input" in
      "")
        [[ -n "$CERT_MODE" ]] || CERT_MODE="acme-standalone"
        return 0
        ;;
      1|caddy-auto)
        CERT_MODE="caddy-auto"
        return 0
        ;;
      2|caddy-zerossl)
        CERT_MODE="caddy-zerossl"
        return 0
        ;;
      3|acme-standalone)
        CERT_MODE="acme-standalone"
        return 0
        ;;
      *)
        log_warn "请选择 caddy-auto、caddy-zerossl 或 acme-standalone。"
        ;;
    esac
  done
}

prompt_http3_mode() {
  local input

  while true; do
    printf '是否启用 HTTP/3？\n'
    printf '  1) off - 关闭 HTTP/3，只使用 HTTP/1.1 + HTTP/2，推荐，最稳\n'
    printf '  2) on  - 开启 HTTP/3，需要 UDP 443 放行，实验功能\n'
    printf '请选择 [1/2/on/off，回车默认 %s]: ' "${HTTP3:-off}"
    read_tty input || die "输入已取消。"
    case "$input" in
      "")
        [[ "$HTTP3" == "on" || "$HTTP3" == "off" ]] || HTTP3="off"
        return 0
        ;;
      1|off|OFF)
        HTTP3="off"
        return 0
        ;;
      2|on|ON)
        HTTP3="on"
        return 0
        ;;
      *)
        log_warn "请选择 on 或 off。"
        ;;
    esac
  done
}

prompt_yes_no() {
  local question="$1"
  local default="$2"
  local input suffix normalized

  if [[ "$default" == "Y" ]]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi

  while true; do
    printf '%s %s ' "$question" "$suffix"
    read_tty input || die "输入已取消。"
    normalized="${input,,}"

    if [[ -z "$normalized" ]]; then
      if [[ "$default" == "Y" ]]; then
        return 0
      fi
      return 1
    fi

    case "$normalized" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) log_warn "请输入 y 或 n。" ;;
    esac
  done
}

print_install_summary() {
  local password_label upstream_label email_label start_label auto_update_label

  if [[ -n "$AUTH_PASS" ]]; then
    password_label="已填写，隐藏显示"
  else
    password_label="自动生成"
  fi

  email_label="${EMAIL:-未设置}"
  upstream_label="${UPSTREAM:-未设置}"
  if [[ "$AUTO_UPDATE" -eq 1 ]]; then
    auto_update_label="是"
  else
    auto_update_label="否"
  fi
  if [[ "$NO_START" -eq 1 ]]; then
    start_label="否"
  else
    start_label="是"
  fi

  cat <<SUMMARY

安装确认信息：
  部署域名：${DOMAIN}
  ACME 邮箱：${email_label}
  认证用户：${AUTH_USER:-自动生成}
  认证密码：${password_label}
  回落模式：${SITE_MODE}
  反代目标：${upstream_label}
  证书模式：${CERT_MODE}
  HTTP3：${HTTP3}
  自动更新：${auto_update_label}
  立即启动服务：${start_label}
SUMMARY
}

confirm_interactive_install() {
  local answer
  printf '\n确认开始安装？[y/N] '
  read_tty answer || die "输入已取消。"
  case "${answer,,}" in
    y|yes)
      return 0
      ;;
    *)
      printf '[WARN] 已取消安装。\n'
      exit 0
      ;;
  esac
}

prompt_interactive_extra_options() {
  local input
  if prompt_yes_no "是否添加额外绑定域名" "N"; then
    while true; do
      printf '额外域名（留空结束）：'
      read_tty input || break
      input="${input//$'\r'/}"
      [[ -n "$input" ]] || break
      naive_append_extra_domain "$input"
    done
  fi
  if prompt_yes_no "是否添加额外认证账号" "N"; then
    while true; do
      printf '额外账号 user:pass（留空结束）：'
      read_tty input || break
      input="${input//$'\r'/}"
      [[ -n "$input" ]] || break
      naive_append_extra_auth "$input"
    done
  fi
}

naive_install_requested() {
  [[ "$MENU_MODE" -eq 1 || "$INTERACTIVE" -eq 1 ]] && return 0
  [[ -z "$DOMAIN" ]] && return 1
  [[ -n "$EMAIL" ]] && return 0
  [[ "$CERT_MODE" == "caddy-auto" || "$CERT_MODE" == "caddy-zerossl" ]] && return 0
  return 1
}

run_interactive_wizard() {
  cat <<'TITLE'
NaiveProxy Server 一键部署向导

TITLE

  prompt_text DOMAIN "部署域名 DOMAIN" "required" "示例：proxy.example.com"
  prompt_interactive_extra_options
  prompt_text EMAIL "ACME 邮箱 EMAIL，可选" "optional"
  prompt_cert_mode
  if [[ "$CERT_MODE" == "acme-standalone" && -z "$EMAIL" ]]; then
    log_warn "acme-standalone 模式需要邮箱用于注册 ZeroSSL 账户。"
    prompt_text EMAIL "ACME 邮箱 EMAIL" "required" "示例：me@example.com"
  fi
  prompt_http3_mode
  prompt_text AUTH_USER "认证用户名 USER，可选" "optional"
  prompt_password
  prompt_site_mode

  if [[ "$SITE_MODE" == "reverse" ]]; then
    while true; do
      prompt_text UPSTREAM "upstream URL" "required" "示例：https://www.example.org"
      if [[ "$UPSTREAM" =~ ^https?:// ]]; then
        break
      fi
      log_warn "upstream URL 必须以 http:// 或 https:// 开头。"
      UPSTREAM=""
    done
  else
    UPSTREAM=""
  fi

  if prompt_yes_no "是否启用自动更新 auto-update" "N"; then
    AUTO_UPDATE=1
  else
    AUTO_UPDATE=0
  fi

  if prompt_yes_no "是否现在启动服务" "Y"; then
    NO_START=0
  else
    NO_START=1
  fi

  print_install_summary
  confirm_interactive_install
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "请使用 root 权限运行此脚本。"
  fi
}

require_supported_os() {
  [[ -r /etc/os-release ]] || die "无法检测系统：/etc/os-release 不存在。"
  # shellcheck disable=SC1091
  . /etc/os-release
  local id="${ID:-}"
  local like="${ID_LIKE:-}"
  case " ${id} ${like} " in
    *" debian "*|*" ubuntu "*) ;;
    *) die "仅支持 Debian / Ubuntu。" ;;
  esac
  command -v apt-get >/dev/null 2>&1 || die "需要 apt-get，但当前系统未找到。"
}

detect_arch() {
  local arch
  if [[ -n "${NAIVE_TEST_UNAME_M:-}" ]]; then
    arch="$NAIVE_TEST_UNAME_M"
  else
    arch="$(uname -m)"
  fi

  DETECTED_UNAME_M="$arch"
  case "$arch" in
    x86_64|amd64)
      TARGET_ARCH="linux-amd64"
      ;;
    aarch64|arm64)
      TARGET_ARCH="linux-arm64"
      ;;
    *)
      die "不支持的架构：${arch}。支持的架构：linux-amd64 / linux-arm64。"
      ;;
  esac
}

set_builder_assets() {
  [[ -n "$TARGET_ARCH" ]] || detect_arch
  ASSET_NAME="caddy-naive-${TARGET_ARCH}.tar.gz"
  SHA_ASSET_NAME="${ASSET_NAME}.sha256"
}

prepare_builder_assets() {
  detect_arch
  set_builder_assets
}

print_test_arch() {
  prepare_builder_assets
  printf '%s -> %s -> %s\n' "$DETECTED_UNAME_M" "$TARGET_ARCH" "$ASSET_NAME"
}

print_disk_cleanup_hint() {
  cat >&2 <<'HINT'
请释放磁盘空间后重试。可参考以下命令：
  df -h
  apt clean
  rm -rf /var/lib/apt/lists/*
  journalctl --vacuum-size=100M
HINT
}

check_root_free_space() {
  local df_output available

  if ! command -v df >/dev/null 2>&1; then
    log_warn "无法检查根分区可用空间：未找到 df 命令。"
    return 0
  fi

  if ! df_output="$(df -Pm / 2>/dev/null)"; then
    log_warn "无法检查根分区可用空间：df -Pm / 执行失败。"
    return 0
  fi

  if ! command -v awk >/dev/null 2>&1; then
    log_warn "无法解析根分区可用空间：未找到 awk 命令。"
    return 0
  fi

  available="$(awk 'NR == 2 { print $4 }' <<< "$df_output")"
  if [[ ! "$available" =~ ^[0-9]+$ ]]; then
    log_warn "无法从 df 输出解析根分区可用空间。"
    return 0
  fi

  if (( available < 300 )); then
    log_error "根分区可用空间不足 300MB。"
    print_disk_cleanup_hint
    exit 1
  fi

  log_info "根分区可用空间：${available}MB。"
}

install_dependencies() {
  local deps=(
    curl
    socat
    tar
    ca-certificates
    openssl
    libcap2-bin
    systemd
    coreutils
  )
  local apt_log

  log_info "正在使用 apt-get 安装基础依赖..."
  apt_log="$(mktemp)"
  if ! apt-get update >"$apt_log" 2>&1; then
    if grep -qi "No space left on device" "$apt_log"; then
      log_error "apt-get update 失败：No space left on device。"
      print_disk_cleanup_hint
    else
      log_error "apt-get update 失败："
      cat "$apt_log" >&2
    fi
    rm -f "$apt_log"
    exit 1
  fi
  rm -f "$apt_log"

  DEBIAN_FRONTEND=noninteractive apt-get install -y "${deps[@]}"
  log_ok "基础依赖已就绪。"
}

if [[ -z "${NAIVE_LIB_LOADED:-}" ]]; then
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
fi

validate_domain() {
  [[ -n "$DOMAIN" ]] || die "必须提供 --domain。"
  validate_hostname "$DOMAIN" "主域名"
  refresh_cert_paths
}

validate_common_args() {
  [[ "$SITE_MODE" == "static" || "$SITE_MODE" == "reverse" ]] || die "--site-mode 必须是 static 或 reverse。"
  [[ "$CERT_MODE" == "caddy-auto" || "$CERT_MODE" == "caddy-zerossl" || "$CERT_MODE" == "acme-standalone" ]] || die "--cert-mode 必须是 caddy-auto、caddy-zerossl 或 acme-standalone。"
  [[ "$HTTP3" == "on" || "$HTTP3" == "off" ]] || die "--http3 必须是 on 或 off。"
  [[ "$PROBE_RESISTANCE" == "on" || "$PROBE_RESISTANCE" == "off" ]] || die "PROBE_RESISTANCE 必须是 on 或 off。"
  [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--repo 必须是 OWNER/REPO 格式。"
  [[ "$INSTALL_BIN" == /* ]] || die "--install-bin 必须是绝对路径。"
  [[ "$INSTALL_BIN" != *[[:space:]]* ]] || die "--install-bin 不能包含空白字符。"
  [[ "$SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] || die "--service-name 包含不支持的字符。"
  if [[ -n "$EMAIL" ]]; then
    [[ "$EMAIL" != *[[:space:]]* ]] || die "--email 不能包含空白字符。"
  fi
  if [[ "$CERT_MODE" == "acme-standalone" ]]; then
    [[ -n "$EMAIL" ]] || die "--cert-mode acme-standalone 需要提供 --email，用于注册 ZeroSSL 账户。"
  fi
}

parse_upstream() {
  if [[ "$SITE_MODE" != "reverse" ]]; then
    if [[ -n "$UPSTREAM" ]]; then
      log_warn "--site-mode 为 static 时会忽略 --upstream。"
    fi
    return
  fi

  [[ -n "$UPSTREAM" ]] || die "--site-mode reverse 时必须提供 --upstream。"
  if [[ ! "$UPSTREAM" =~ ^(https?)://([^/?#]+) ]]; then
    die "--upstream 必须以 http:// 或 https:// 开头。"
  fi

  local scheme="${BASH_REMATCH[1]}"
  local authority="${BASH_REMATCH[2]}"
  [[ -n "$authority" ]] || die "无法解析 upstream host。"
  [[ "$authority" != *"@"* ]] || die "--upstream 不能包含 userinfo。"

  UPSTREAM_BASE="${scheme}://${authority}"
  if [[ "$authority" =~ ^\[([^]]+)\](:[0-9]+)?$ ]]; then
    UPSTREAM_HOST="${BASH_REMATCH[1]}"
  else
    UPSTREAM_HOST="${authority%%:*}"
  fi

  [[ -n "$UPSTREAM_HOST" ]] || die "无法解析 upstream host。"
  [[ "$UPSTREAM_HOST" =~ ^[A-Za-z0-9.-]+$ || "$UPSTREAM_HOST" =~ ^[0-9A-Fa-f:]+$ ]] || die "Upstream host 包含不支持的字符。"

  log_warn "反代第三方网站可能受 CSP、Cookie、登录、跳转和法律合规影响，建议只反代自己有权使用的网站或普通公开静态站点。"
}

if [[ -z "${NAIVE_LIB_LOADED:-}" ]]; then
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
fi

load_saved_install_info() {
  local value

  value="$(read_env_value DOMAIN || true)"
  [[ -n "$value" ]] && DOMAIN="$value"
  value="$(read_env_value EMAIL || true)"
  [[ -n "$value" ]] && EMAIL="$value"
  value="$(read_env_value USER || true)"
  [[ -n "$value" ]] && AUTH_USER="$value"
  value="$(read_env_value PASS || true)"
  [[ -n "$value" ]] && AUTH_PASS="$value"
  value="$(read_env_value EXTRA_DOMAINS || true)"
  [[ -n "$value" ]] && EXTRA_DOMAINS="$value"
  value="$(read_env_value EXTRA_AUTH || true)"
  [[ -n "$value" ]] && EXTRA_AUTH_RAW="$value"
  value="$(read_env_value SITE_MODE || true)"
  [[ -n "$value" ]] && SITE_MODE="$value"
  value="$(read_env_value UPSTREAM || true)"
  [[ -n "$value" ]] && UPSTREAM="$value"
  value="$(read_env_value REPO || true)"
  [[ -n "$value" ]] && REPO="$value"
  value="$(read_env_value INSTALL_BIN || true)"
  [[ -n "$value" ]] && INSTALL_BIN="$value"
  value="$(read_env_value SERVICE_NAME || true)"
  [[ -n "$value" ]] && SERVICE_NAME="$value"
  value="$(read_env_value CERT_MODE || true)"
  [[ -n "$value" ]] && CERT_MODE="$value"
  value="$(read_env_value CERT_FULLCHAIN || true)"
  [[ -n "$value" ]] && CERT_FULLCHAIN="$value"
  value="$(read_env_value CERT_KEY || true)"
  [[ -n "$value" ]] && CERT_KEY="$value"
  value="$(read_env_value HTTP3 || true)"
  [[ -n "$value" ]] && HTTP3="$value"
  value="$(read_env_value PROBE_RESISTANCE || true)"
  [[ -n "$value" ]] && PROBE_RESISTANCE="$value"
  value="$(read_env_value BUILDER_RELEASE_TAG || true)"
  [[ -n "$value" ]] && DOWNLOADED_RELEASE_TAG="$value"
  value="$(read_env_value BUILDER_RELEASE_ARCH || true)"
  [[ -n "$value" ]] && RECORDED_BUILDER_RELEASE_ARCH="$value"
  value="$(read_env_value BUILDER_RELEASE_ASSET || true)"
  [[ -n "$value" ]] && RECORDED_BUILDER_RELEASE_ASSET="$value"
  value="$(read_env_value BUILDER_RELEASE_SHA256 || true)"
  [[ -n "$value" ]] && DOWNLOADED_ARCHIVE_SHA256="$value"
  refresh_paths
  if [[ -n "$DOMAIN" && ( -z "$CERT_FULLCHAIN" || -z "$CERT_KEY" ) ]]; then
    refresh_cert_paths
  fi
}

validate_credential_token() {
  local name="$1"
  local value="$2"
  [[ -n "$value" ]] || die "${name} 不能为空。"
  if [[ ! "$value" =~ ^[A-Za-z0-9._:/@+-]+$ ]]; then
    die "${name} 只能包含 A-Z、a-z、0-9、点号、下划线、冒号、斜杠、@、加号和连字符。"
  fi
}

validate_auth_user_safe() {
  local value="$1"
  [[ -n "$value" ]] || die "认证用户名不能为空。"
  [[ "$value" =~ ^[A-Za-z0-9_.-]+$ ]] || die "认证用户名只能包含 A-Z、a-z、0-9、下划线、连字符和点号。"
}

prepare_credentials() {
  local existing_user existing_pass
  existing_user="$(read_env_value USER || true)"
  existing_pass="$(read_env_value PASS || true)"

  if [[ -z "$AUTH_USER" ]]; then
    if [[ "$INTERACTIVE" -eq 0 && -n "$existing_user" ]]; then
      AUTH_USER="$existing_user"
      log_info "复用 $ENV_FILE 中已有的 Basic Auth 用户名。"
    else
      AUTH_USER="user$(openssl rand -hex 4)"
      log_info "已生成 Basic Auth 用户名。"
    fi
  fi

  if [[ -z "$AUTH_PASS" ]]; then
    if [[ "$INTERACTIVE" -eq 0 && -n "$existing_pass" ]]; then
      AUTH_PASS="$existing_pass"
      log_info "复用 $ENV_FILE 中已有的 Basic Auth 密码。"
    else
      AUTH_PASS="$(openssl rand -hex 24)"
      log_info "已生成强随机 Basic Auth 密码。"
    fi
  fi

  validate_auth_user_safe "$AUTH_USER"
  validate_credential_token "PASS" "$AUTH_PASS"
}

backup_file() {
  local path="$1"
  LAST_BACKUP_PATH=""
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 0
  fi

  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR" 2>/dev/null || true

  local base dest backup_ts
  backup_ts="$(date +%Y%m%d_%H%M%S)"
  base="$(basename "$path")"
  dest="${BACKUP_DIR}/${base}.${backup_ts}.bak"
  if [[ -e "$dest" || -L "$dest" ]]; then
    dest="${dest}.$$"
  fi

  cp -a "$path" "$dest"
  chmod go-rwx "$dest" 2>/dev/null || true
  LAST_BACKUP_PATH="$dest"
  log_info "已备份 $path -> $dest"
}

check_dns() {
  if getent ahosts "$DOMAIN" >/dev/null 2>&1; then
    log_ok "DNS 解析成功：$DOMAIN"
  else
    log_warn "$DOMAIN DNS 解析失败。继续执行，但 ACME 证书申请可能失败。"
  fi
  log_info "请确认 ${DOMAIN} 的 A/AAAA 记录指向本机，并且云安全组放行 TCP 80/443。"
}

port_listeners() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -H -ltnp "sport = :${port}" 2>/dev/null || true
    return 0
  fi

  local port_hex inodes inode fd target pid comm
  printf -v port_hex '%04X' "$port"
  inodes="$(
    awk -v p="$port_hex" '
      tolower($2) ~ ":" tolower(p) "$" && $4 == "0A" { print $10 }
    ' /proc/net/tcp /proc/net/tcp6 2>/dev/null | sort -u
  )"
  [[ -n "$inodes" ]] || return 0

  while IFS= read -r inode; do
    [[ -n "$inode" ]] || continue
    for fd in /proc/[0-9]*/fd/*; do
      target="$(readlink "$fd" 2>/dev/null || true)"
      [[ "$target" == "socket:[${inode}]" ]] || continue
      pid="${fd#/proc/}"
      pid="${pid%%/*}"
      comm="$(tr -d '\0' < "/proc/${pid}/comm" 2>/dev/null || printf 'unknown')"
      printf 'LISTEN *:%s users:(("%s",pid=%s))\n' "$port" "$comm" "$pid"
    done
  done <<< "$inodes" | sort -u
}

extract_pid_from_listener() {
  local line="$1"
  if [[ "$line" =~ pid=([0-9]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

check_ports_available() {
  local managed_pid=""
  managed_pid="$(systemctl show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || true)"
  [[ "$managed_pid" == "0" ]] && managed_pid=""

  local conflict=0 port listeners unmanaged line pid
  for port in 80 443; do
    listeners="$(port_listeners "$port")"
    [[ -n "$listeners" ]] || continue

    unmanaged=""
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      pid="$(extract_pid_from_listener "$line")"
      if [[ -n "$managed_pid" && -n "$pid" && "$pid" == "$managed_pid" ]]; then
        continue
      fi
      unmanaged+="${line}"$'\n'
    done <<< "$listeners"

    if [[ -n "$unmanaged" ]]; then
      log_error "TCP ${port} 端口已被占用："
      printf '%s' "$unmanaged" >&2
      conflict=1
    else
      log_info "TCP ${port} 端口当前由本脚本管理的 ${SERVICE_NAME} 服务占用，按重复安装处理。"
    fi
  done

  if [[ "$conflict" -ne 0 ]]; then
    die "请先停止冲突服务后重试。本脚本不会自动修改 nginx/apache 或防火墙规则。"
  fi
}

ensure_caddy_user_and_dirs() {
  if ! getent group caddy >/dev/null 2>&1; then
    groupadd --system caddy
    log_ok "已创建系统组：caddy。"
  fi

  if ! id -u caddy >/dev/null 2>&1; then
    useradd --system \
      --gid caddy \
      --home-dir "$DATA_DIR" \
      --shell /usr/sbin/nologin \
      caddy
    log_ok "已创建系统用户：caddy。"
  fi

  mkdir -p "$CONFIG_DIR" "$SITE_DIR" "$DATA_DIR" "$BACKUP_DIR"
  chown root:caddy "$CONFIG_DIR"
  chmod 755 "$CONFIG_DIR"
  chown -R caddy:caddy "$SITE_DIR" "$DATA_DIR"
  chmod 750 "$DATA_DIR"
  chmod 755 "$SITE_DIR"
  chmod 700 "$BACKUP_DIR"
  log_ok "目录和权限已准备就绪。"
}

verify_sha256() {
  local dir="$1"
  local archive="${dir}/${ASSET_NAME}"
  local sha_file="${dir}/${SHA_ASSET_NAME}"
  local expected actual

  if (cd "$dir" && sha256sum -c "$SHA_ASSET_NAME" >/dev/null 2>&1); then
    expected="$(awk '{print $1; exit}' "$sha_file")"
    DOWNLOADED_ARCHIVE_SHA256="$expected"
    log_ok "SHA256 校验通过。"
    return 0
  fi

  expected="$(awk '{print $1; exit}' "$sha_file")"
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [[ -n "$expected" ]] || die "SHA256 文件为空或无效。"
  if [[ "$expected" != "$actual" ]]; then
    die "SHA256 校验失败。"
  fi
  DOWNLOADED_ARCHIVE_SHA256="$expected"
  log_ok "SHA256 校验通过。"
}

download_release_asset() {
  local url="$1"
  local output="$2"
  local asset="$3"

  if curl -fL --retry 3 --connect-timeout 20 -o "$output" "$url"; then
    return 0
  fi

  if [[ "$TARGET_ARCH" == "linux-arm64" ]]; then
    die "当前 Release 缺少 ${asset}，请先确认 caddy-naive-builder 最新 Release 已发布 arm64 资产。"
  fi
  die "下载 Release 资产失败：${asset}"
}

download_release_caddy() {
  prepare_builder_assets
  check_root_free_space
  TMP_DIR="$(mktemp -d)"
  local archive_url sha_url extract_dir caddy_path
  DOWNLOADED_RELEASE_TAG="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null || true)"
  DOWNLOADED_RELEASE_TAG="${DOWNLOADED_RELEASE_TAG##*/}"
  archive_url="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"
  sha_url="https://github.com/${REPO}/releases/latest/download/${SHA_ASSET_NAME}"
  log_info "正在下载 $archive_url"
  download_release_asset "$archive_url" "${TMP_DIR}/${ASSET_NAME}" "$ASSET_NAME"
  log_info "正在下载 $sha_url"
  download_release_asset "$sha_url" "${TMP_DIR}/${SHA_ASSET_NAME}" "$SHA_ASSET_NAME"

  verify_sha256 "$TMP_DIR"

  extract_dir="${TMP_DIR}/extract"
  mkdir -p "$extract_dir"
  tar -xzf "${TMP_DIR}/${ASSET_NAME}" -C "$extract_dir"

  caddy_path="$(find "$extract_dir" -type f -name caddy | head -n 1)"
  [[ -n "$caddy_path" ]] || die "压缩包中未找到 caddy 二进制。"
  chmod +x "$caddy_path"
  [[ -x "$caddy_path" ]] || die "解压出的 caddy 二进制不可执行。"
  DOWNLOADED_CADDY="$caddy_path"
  log_ok "Caddy 二进制已解压。"
}

show_caddy_version_and_check_modules() {
  local version modules
  version="$("$INSTALL_BIN" version 2>&1)"
  log_info "Caddy 版本：$version"

  modules="$("$INSTALL_BIN" list-modules 2>&1)"
  if ! grep -Eiq 'forward_proxy|forwardproxy' <<< "$modules"; then
    log_error "已安装的 Caddy list-modules 未检测到 forward_proxy/forwardproxy。"
    printf '%s\n' "$modules" >&2
    return 1
  fi
  log_ok "已检测到 forward_proxy 模块。"
}

install_caddy_binary() {
  [[ -n "$DOWNLOADED_CADDY" ]] || die "内部错误：下载的 caddy 路径为空。"
  mkdir -p "$(dirname "$INSTALL_BIN")"

  local previous_backup=""
  backup_file "$INSTALL_BIN"
  previous_backup="$LAST_BACKUP_PATH"

  install -m 0755 "$DOWNLOADED_CADDY" "$INSTALL_BIN"
  if command -v setcap >/dev/null 2>&1; then
    setcap cap_net_bind_service=+ep "$INSTALL_BIN" || log_warn "setcap 失败；systemd AmbientCapabilities 通常仍可允许绑定 80/443。"
  fi

  if ! show_caddy_version_and_check_modules; then
    if [[ -n "$previous_backup" ]]; then
      cp -a "$previous_backup" "$INSTALL_BIN"
      log_warn "已从 $previous_backup 恢复旧 Caddy 二进制。"
    fi
    die "Caddy 二进制校验失败。"
  fi
}

write_static_site() {
  [[ "$SITE_MODE" == "static" ]] || return 0

  backup_file "${SITE_DIR}/index.html"
  cat > "${SITE_DIR}/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Welcome</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #f6f7f9;
      --text: #18202a;
      --muted: #667085;
      --panel: #ffffff;
      --line: #d9dee7;
      --accent: #2563eb;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #111827;
        --text: #f9fafb;
        --muted: #a7b0c0;
        --panel: #172033;
        --line: #2b3548;
        --accent: #60a5fa;
      }
    }
    * {
      box-sizing: border-box;
    }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
    }
    main {
      width: min(960px, calc(100% - 32px));
      margin: 0 auto;
      padding: 64px 0;
    }
    header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 24px;
      padding-bottom: 36px;
      border-bottom: 1px solid var(--line);
    }
    .brand {
      font-weight: 700;
      letter-spacing: 0;
    }
    nav {
      display: flex;
      gap: 18px;
      flex-wrap: wrap;
    }
    a {
      color: var(--accent);
      text-decoration: none;
    }
    a:hover {
      text-decoration: underline;
    }
    section {
      padding: 48px 0;
    }
    h1 {
      margin: 0 0 18px;
      font-size: clamp(2.25rem, 6vw, 4.5rem);
      line-height: 1.05;
      letter-spacing: 0;
    }
    p {
      max-width: 680px;
      margin: 0 0 18px;
      color: var(--muted);
      font-size: 1.05rem;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 16px;
      margin-top: 30px;
    }
    .item {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 22px;
    }
    .item h2 {
      margin: 0 0 8px;
      font-size: 1rem;
      letter-spacing: 0;
    }
    footer {
      border-top: 1px solid var(--line);
      padding-top: 24px;
      color: var(--muted);
      font-size: 0.95rem;
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div class="brand">Home</div>
      <nav aria-label="Main navigation">
        <a href="#notes">Notes</a>
        <a href="#work">Work</a>
        <a href="#contact">Contact</a>
      </nav>
    </header>
    <section>
      <h1>Welcome</h1>
      <p>A quiet place for updates, useful links, and small notes. Thanks for stopping by.</p>
      <div class="grid">
        <article class="item" id="notes">
          <h2>Notes</h2>
          <p>Short writing, reading lists, and things worth remembering.</p>
        </article>
        <article class="item" id="work">
          <h2>Work</h2>
          <p>Selected projects, experiments, and practical references.</p>
        </article>
        <article class="item" id="contact">
          <h2>Contact</h2>
          <p>For questions or collaboration, please reach out through the usual channels.</p>
        </article>
      </div>
    </section>
    <footer>© <span id="year"></span> Home</footer>
  </main>
  <script>
    document.getElementById('year').textContent = new Date().getFullYear();
  </script>
</body>
</html>
HTML

  backup_file "${SITE_DIR}/robots.txt"
  cat > "${SITE_DIR}/robots.txt" <<'ROBOTS'
User-agent: *
Disallow:
ROBOTS

  fix_static_site_permissions
  log_ok "静态回落站点已生成。"
}

fix_static_site_permissions() {
  if [[ -d "$SITE_DIR" ]]; then
    chown -R caddy:caddy "$SITE_DIR" 2>/dev/null || true
    find "$SITE_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
    find "$SITE_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true
  fi
}

write_caddyfile_content() {
  local output_path="$1"
  local tls_mode="${2:-$CERT_MODE}"
  local auth_user_caddy auth_pass_caddy site_hosts extra_pair extra_user extra_pass
  local -a extra_auth_pairs=()
  auth_user_caddy="$(caddyfile_quote "$AUTH_USER")"
  auth_pass_caddy="$(caddyfile_quote "$AUTH_PASS")"
  site_hosts="$(naive_all_domains "$DOMAIN" "$EXTRA_DOMAINS")"
  if [[ -n "$EXTRA_AUTH_RAW" ]]; then
    IFS=',' read -ra extra_auth_pairs <<< "$EXTRA_AUTH_RAW"
  fi

  if [[ "$tls_mode" == "acme-standalone" ]]; then
    if [[ ! -s "$CERT_FULLCHAIN" || ! -s "$CERT_KEY" ]]; then
      die "本地证书文件不存在或为空，拒绝写入本地证书 Caddyfile：${CERT_FULLCHAIN} / ${CERT_KEY}"
    fi
  fi

  {
    printf '{\n'
    printf '  order forward_proxy before file_server\n'
    printf '  order forward_proxy before reverse_proxy\n'
    if [[ "$tls_mode" == "caddy-zerossl" ]]; then
      printf '  acme_ca https://acme.zerossl.com/v2/DV90\n'
    fi
    printf '  admin off\n'
    printf '  servers {\n'
    if [[ "$HTTP3" == "on" ]]; then
      printf '    protocols h1 h2 h3\n'
    else
      printf '    protocols h1 h2\n'
    fi
    printf '  }\n'
    printf '}\n\n'
    printf 'http://%s {\n' "$site_hosts"
    printf '  redir https://{host}{uri} permanent\n'
    printf '}\n\n'
    printf ':443, %s {\n' "$site_hosts"
    printf '  encode zstd gzip\n\n'
    if [[ "$tls_mode" == "acme-standalone" ]]; then
      printf '  tls %s %s\n\n' "$CERT_FULLCHAIN" "$CERT_KEY"
    elif [[ -n "$EMAIL" ]]; then
      printf '  tls %s\n\n' "$EMAIL"
    fi
    printf '  route {\n'
    printf '    forward_proxy {\n'
    printf '      basic_auth %s %s\n' "$auth_user_caddy" "$auth_pass_caddy"
    for extra_pair in "${extra_auth_pairs[@]}"; do
      extra_pair="${extra_pair#"${extra_pair%%[![:space:]]*}"}"
      extra_pair="${extra_pair%"${extra_pair##*[![:space:]]}"}"
      [[ -n "$extra_pair" && "$extra_pair" == *:* ]] || continue
      extra_user="${extra_pair%%:*}"
      extra_pass="${extra_pair#*:}"
      printf '      basic_auth %s %s\n' "$(caddyfile_quote "$extra_user")" "$(caddyfile_quote "$extra_pass")"
    done
    printf '      hide_ip\n'
    printf '      hide_via\n'
    if [[ "$PROBE_RESISTANCE" == "on" ]]; then
      printf '      probe_resistance\n'
    fi
    printf '    }\n\n'

    if [[ "$SITE_MODE" == "static" ]]; then
      printf '    root * %s\n' "$SITE_DIR"
      printf '    file_server\n'
    else
      printf '    reverse_proxy %s {\n' "$UPSTREAM_BASE"
      printf '      header_up Host %s\n' "$UPSTREAM_HOST"
      printf '      header_up X-Forwarded-Host {host}\n'
      printf '      header_up X-Forwarded-Proto {scheme}\n'
      printf '      transport http {\n'
      printf '        tls_server_name %s\n' "$UPSTREAM_HOST"
      printf '      }\n'
      printf '    }\n'
    fi
    printf '  }\n'
    printf '}\n'
  } > "$output_path"
}

validate_caddyfile() {
  local config_path="${1:-$CADDYFILE}"
  local output_file
  [[ -f "$config_path" ]] || die "未找到 Caddyfile：$config_path"
  output_file="$(mktemp)"
  if "$INSTALL_BIN" validate --config "$config_path" >"$output_file" 2>&1; then
    rm -f "$output_file"
    log_ok "Caddyfile 校验通过：$config_path"
    return 0
  fi

  log_error "Caddyfile 校验失败："
  cat "$output_file" >&2
  rm -f "$output_file"
  return 1
}

write_and_validate_caddyfile() {
  local tls_mode="${1:-$CERT_MODE}"
  local caddyfile_backup=""
  local tmp_caddyfile

  backup_file "$CADDYFILE"
  caddyfile_backup="$LAST_BACKUP_PATH"
  LAST_CADDYFILE_BACKUP_FOR_RESTORE="$caddyfile_backup"

  tmp_caddyfile="$(mktemp /tmp/Caddyfile.XXXXXX)"
  write_caddyfile_content "$tmp_caddyfile" "$tls_mode"
  "$INSTALL_BIN" fmt --overwrite "$tmp_caddyfile" >/dev/null 2>&1 || log_warn "Caddyfile fmt 失败，将继续 validate 详细检查。"

  if validate_caddyfile "$tmp_caddyfile"; then
    if ! mv -f "$tmp_caddyfile" "$CADDYFILE"; then
      rm -f "$tmp_caddyfile"
      restore_caddyfile_backup || true
      die "覆盖 Caddyfile 失败。"
    fi
    chmod 640 "$CADDYFILE"
    chown root:caddy "$CADDYFILE" 2>/dev/null || true
    return 0
  fi

  rm -f "$tmp_caddyfile"
  if [[ -n "$caddyfile_backup" ]]; then
    cp -a "$caddyfile_backup" "$CADDYFILE"
    log_warn "已从备份恢复旧 Caddyfile：$caddyfile_backup"
    die "Caddyfile 校验失败。备份位于：$caddyfile_backup"
  fi

  die "Caddyfile 校验失败，且没有可用的旧 Caddyfile 备份。"
}

restore_caddyfile_backup() {
  if [[ -n "$LAST_CADDYFILE_BACKUP_FOR_RESTORE" && -f "$LAST_CADDYFILE_BACKUP_FOR_RESTORE" ]]; then
    cp -a "$LAST_CADDYFILE_BACKUP_FOR_RESTORE" "$CADDYFILE"
    log_warn "已恢复 Caddyfile 备份：$LAST_CADDYFILE_BACKUP_FOR_RESTORE"
    return 0
  fi

  return 1
}

cert_files_ready() {
  [[ -s "$CERT_FULLCHAIN" && -s "$CERT_KEY" ]]
}

cert_exists() {
  refresh_cert_paths
  cert_files_ready
}

cert_days_left() {
  local end_date end_ts now_ts days
  refresh_cert_paths
  [[ -s "$CERT_FULLCHAIN" ]] || return 1
  command -v openssl >/dev/null 2>&1 || return 1
  end_date="$(openssl x509 -in "$CERT_FULLCHAIN" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')" || return 1
  [[ -n "$end_date" ]] || return 1

  if date -d "$end_date" +%s >/dev/null 2>&1; then
    end_ts="$(date -d "$end_date" +%s)"
  elif date -j -f "%b %e %T %Y %Z" "$end_date" +%s >/dev/null 2>&1; then
    end_ts="$(date -j -f "%b %e %T %Y %Z" "$end_date" +%s)"
  else
    return 1
  fi
  now_ts="$(date +%s)"
  days=$(( (end_ts - now_ts) / 86400 ))
  printf '%s\n' "$days"
}

should_issue_cert() {
  local old_domain old_extra days_left
  refresh_cert_paths
  old_domain="$(read_env_value DOMAIN || true)"
  old_extra="$(read_env_value EXTRA_DOMAINS || true)"

  if [[ -n "$old_domain" && "$old_domain" != "$DOMAIN" ]]; then
    log_warn "域名已变化，需要重新签发本地证书。"
    return 0
  fi

  if [[ "${old_extra:-}" != "${EXTRA_DOMAINS:-}" ]]; then
    log_warn "额外域名已变化，需要重新签发 SAN 证书。"
    return 0
  fi

  if ! cert_exists; then
    log_warn "本地证书文件缺失或为空，需要重新签发。"
    return 0
  fi

  if ! days_left="$(cert_days_left)"; then
    log_warn "无法解析本地证书有效期，需要重新签发。"
    return 0
  fi

  if (( days_left <= 15 )); then
    log_warn "本地证书剩余有效期不超过 15 天，需要重新签发。"
    return 0
  fi

  log_ok "已复用现有本地证书，剩余有效期约 ${days_left} 天。"
  return 1
}

write_caddyfile_local_cert() {
  refresh_cert_paths
  if ! cert_files_ready; then
    die "本地证书文件不存在或为空，不能写入本地证书 Caddyfile：${CERT_FULLCHAIN} / ${CERT_KEY}"
  fi

  write_and_validate_caddyfile "acme-standalone"
}

write_caddyfile_auto_zerossl() {
  write_and_validate_caddyfile "caddy-zerossl"
}

write_systemd_service() {
  backup_file "$SERVICE_FILE"
  cat > "$SERVICE_FILE" <<SERVICE
[Unit]
Description=Caddy Naive Server
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=${INSTALL_BIN} run --environ --config ${CADDYFILE}
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SERVICE
  chmod 644 "$SERVICE_FILE"
  log_ok "systemd service 已写入：$SERVICE_FILE"
}

install_acme_sh() {
  [[ -n "$EMAIL" ]] || die "acme.sh + ZeroSSL standalone 模式需要 EMAIL。"
  command -v curl >/dev/null 2>&1 || die "安装 acme.sh 需要 curl。"

  if [[ ! -x "$ACME_SH" ]]; then
    local installer
    installer="$(mktemp /tmp/acme-install.XXXXXX.sh)"
    log_info "正在安装 acme.sh..."
    if ! curl -fsSL --proto '=https' --tlsv1.2 https://get.acme.sh -o "$installer"; then
      rm -f "$installer"
      die "acme.sh 安装脚本下载失败。"
    fi
    chmod 700 "$installer"
    [[ -s "$installer" ]] || die "acme.sh 安装脚本为空。"
    if ! head -n 1 "$installer" | grep -q '^#!'; then
      rm -f "$installer"
      die "acme.sh 安装脚本格式异常，已中止。"
    fi
    sh "$installer" "email=${EMAIL}"
    rm -f "$installer"
  else
    log_info "已检测到 acme.sh：$ACME_SH"
  fi

  [[ -x "$ACME_SH" ]] || die "acme.sh 安装失败：$ACME_SH 不存在或不可执行。"
  "$ACME_SH" --set-default-ca --server zerossl
  "$ACME_SH" --register-account -m "$EMAIL" --server zerossl || true
  log_ok "acme.sh / ZeroSSL 已就绪。"
}

check_port80_for_acme_standalone() {
  local listeners line conflict=0
  listeners="$(port_listeners 80)"
  [[ -n "$listeners" ]] || return 0

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if grep -Eiq 'caddy|acme\.sh' <<< "$line"; then
      log_warn "80 端口当前由 Caddy/acme.sh 相关进程占用，acme.sh 会再次尝试停止 Caddy：$line"
      continue
    fi
    log_error "80 端口被非 Caddy/acme.sh 进程占用，无法使用 standalone 验证：$line"
    conflict=1
  done <<< "$listeners"

  [[ "$conflict" -eq 0 ]] || die "请先释放 80 端口后重试。"
}

issue_cert_with_acme_standalone() {
  local issue_backup=""
  local item
  local -a acme_domain_args=(-d "$DOMAIN")
  refresh_cert_paths
  [[ -n "$DOMAIN" ]] || die "缺少 DOMAIN，无法申请证书。"
  [[ -n "$EMAIL" ]] || die "缺少 EMAIL，无法注册 ZeroSSL 账户。"
  [[ -x "$ACME_SH" ]] || die "未找到 acme.sh：$ACME_SH"

  if [[ -n "$EXTRA_DOMAINS" ]]; then
    IFS=',' read -ra _naive_acme_extra <<< "$EXTRA_DOMAINS"
    for item in "${_naive_acme_extra[@]}"; do
      item="${item#"${item%%[![:space:]]*}"}"
      item="${item%"${item##*[![:space:]]}"}"
      [[ -n "$item" ]] || continue
      acme_domain_args+=(-d "$item")
    done
  fi

  backup_file "$CADDYFILE"
  issue_backup="$LAST_BACKUP_PATH"

  systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  sleep 2
  check_port80_for_acme_standalone

  log_info "正在使用 acme.sh + ZeroSSL standalone 申请证书：$(naive_all_domains "$DOMAIN" "$EXTRA_DOMAINS")"
  if ! "$ACME_SH" --issue \
    --server zerossl \
    "${acme_domain_args[@]}" \
    --standalone \
    --httpport 80 \
    --force \
    --pre-hook "systemctl stop ${SERVICE_NAME} || true" \
    --post-hook "systemctl start ${SERVICE_NAME} || true"; then
    if [[ -n "$issue_backup" && -f "$issue_backup" ]]; then
      cp -a "$issue_backup" "$CADDYFILE"
      log_warn "证书申请失败，已恢复申请前的 Caddyfile：$issue_backup"
      validate_caddyfile || true
      systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi
    die "acme.sh standalone 申请证书失败。"
  fi

  log_ok "acme.sh standalone 证书申请成功。"
}

install_local_cert() {
  refresh_cert_paths
  [[ -x "$ACME_SH" ]] || die "未找到 acme.sh：$ACME_SH"
  mkdir -p "${CERT_BASE_DIR}/${DOMAIN}"

  log_info "正在安装证书到 ${CERT_BASE_DIR}/${DOMAIN} ..."
  if ! "$ACME_SH" --install-cert -d "$DOMAIN" \
    --key-file "$CERT_KEY" \
    --fullchain-file "$CERT_FULLCHAIN" \
    --reloadcmd "systemctl restart ${SERVICE_NAME}"; then
    log_error "acme.sh 安装证书失败。"
    log_warn "正在恢复为 Caddy ZeroSSL 自动证书配置，避免服务引用不存在的证书文件。"
    write_caddyfile_auto_zerossl
    systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
    die "本地证书安装失败。"
  fi

  if ! cert_files_ready; then
    log_error "证书安装后仍未找到有效文件：${CERT_FULLCHAIN} / ${CERT_KEY}"
    log_warn "正在恢复为 Caddy ZeroSSL 自动证书配置，避免服务引用不存在的证书文件。"
    write_caddyfile_auto_zerossl
    systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
    die "本地证书文件不存在或为空。"
  fi

  chown -R caddy:caddy "$CERT_BASE_DIR" 2>/dev/null || true
  chmod 700 "${CERT_BASE_DIR}/${DOMAIN}" 2>/dev/null || true
  chmod 600 "$CERT_KEY" 2>/dev/null || true
  chmod 644 "$CERT_FULLCHAIN" 2>/dev/null || true
  log_ok "本地证书已安装。"
}

issue_local_cert_workflow() {
  install_acme_sh
  issue_cert_with_acme_standalone
  install_local_cert
  write_caddyfile_local_cert
}

_naive_cat_update_core() {
  local core_file="${NAIVE_SCRIPT_DIR}/lib/update-core.sh"
  if [[ -n "${NAIVE_SCRIPT_DIR:-}" && -f "$core_file" ]]; then
    cat "$core_file"
    return 0
  fi
  cat <<'NAIVE_EMBEDDED_UPDATE_CORE'

BACKUP_DIR="/var/backups/caddy-naive"
CADDYFILE="/etc/caddy/Caddyfile"
ENV_FILE="/etc/caddy/naive.env"
DETECTED_UNAME_M=""
TARGET_ARCH=""
ASSET_NAME=""
SHA_ASSET_NAME=""

log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }
log_ok() { printf '[OK] %s\n' "$*"; }
die() { log_error "$*"; exit 1; }

write_env_kv() {
  printf '%s=%q\n' "$1" "$2"
}

TMP_DIR=""
LAST_BACKUP_PATH=""
DOWNLOADED_CADDY=""
DOWNLOADED_ARCHIVE_SHA256=""
DOWNLOADED_RELEASE_TAG=""

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "更新脚本必须使用 root 权限运行。"
}

detect_arch() {
  local arch

  if [[ -n "${NAIVE_TEST_UNAME_M:-}" ]]; then
    arch="$NAIVE_TEST_UNAME_M"
  else
    arch="$(uname -m)"
  fi

  DETECTED_UNAME_M="$arch"
  case "$arch" in
    x86_64|amd64)
      TARGET_ARCH="linux-amd64"
      ;;
    aarch64|arm64)
      TARGET_ARCH="linux-arm64"
      ;;
    *)
      die "不支持的架构：${arch}。支持的架构：linux-amd64 / linux-arm64。"
      ;;
  esac
}

set_builder_assets() {
  [[ -n "$TARGET_ARCH" ]] || detect_arch
  ASSET_NAME="caddy-naive-${TARGET_ARCH}.tar.gz"
  SHA_ASSET_NAME="${ASSET_NAME}.sha256"
}

prepare_builder_assets() {
  detect_arch
  set_builder_assets
}

print_test_arch() {
  prepare_builder_assets
  printf '%s -> %s -> %s\n' "$DETECTED_UNAME_M" "$TARGET_ARCH" "$ASSET_NAME"
}

print_disk_cleanup_hint() {
  cat >&2 <<'HINT'
请释放磁盘空间后重试。可参考以下命令：
  df -h
  apt clean
  rm -rf /var/lib/apt/lists/*
  journalctl --vacuum-size=100M
HINT
}

check_root_free_space() {
  local df_output available

  if ! command -v df >/dev/null 2>&1; then
    log_warn "无法检查根分区可用空间：未找到 df 命令。"
    return 0
  fi

  if ! df_output="$(df -Pm / 2>/dev/null)"; then
    log_warn "无法检查根分区可用空间：df -Pm / 执行失败。"
    return 0
  fi

  if ! command -v awk >/dev/null 2>&1; then
    log_warn "无法解析根分区可用空间：未找到 awk 命令。"
    return 0
  fi

  available="$(awk 'NR == 2 { print $4 }' <<< "$df_output")"
  if [[ ! "$available" =~ ^[0-9]+$ ]]; then
    log_warn "无法从 df 输出解析根分区可用空间。"
    return 0
  fi

  if (( available < 300 )); then
    log_error "根分区可用空间不足 300MB。"
    print_disk_cleanup_hint
    exit 1
  fi

  log_info "根分区可用空间：${available}MB。"
}

load_env_defaults() {
  local override_repo="${REPO-}"
  local override_install_bin="${INSTALL_BIN-}"
  local override_service_name="${SERVICE_NAME-}"

  REPO="$DEFAULT_REPO"
  INSTALL_BIN="$DEFAULT_INSTALL_BIN"
  SERVICE_NAME="$DEFAULT_SERVICE_NAME"

  if [[ -r "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
  fi

  REPO="${override_repo:-${REPO:-$DEFAULT_REPO}}"
  INSTALL_BIN="${override_install_bin:-${INSTALL_BIN:-$DEFAULT_INSTALL_BIN}}"
  SERVICE_NAME="${override_service_name:-${SERVICE_NAME:-$DEFAULT_SERVICE_NAME}}"
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "缺少必需命令：$cmd"
}

backup_file() {
  local path="$1"
  LAST_BACKUP_PATH=""
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 0
  fi

  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR" 2>/dev/null || true

  local base dest timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"
  base="$(basename "$path")"
  dest="${BACKUP_DIR}/${base}.${timestamp}.bak"
  if [[ -e "$dest" || -L "$dest" ]]; then
    dest="${dest}.$$"
  fi

  cp -a "$path" "$dest"
  chmod go-rwx "$dest" 2>/dev/null || true
  LAST_BACKUP_PATH="$dest"
  log_info "已备份 $path -> $dest"
}

verify_sha256() {
  local dir="$1"
  local archive="${dir}/${ASSET_NAME}"
  local sha_file="${dir}/${SHA_ASSET_NAME}"
  local expected actual

  if (cd "$dir" && sha256sum -c "$SHA_ASSET_NAME" >/dev/null 2>&1); then
    expected="$(awk '{print $1; exit}' "$sha_file")"
    DOWNLOADED_ARCHIVE_SHA256="$expected"
    log_ok "SHA256 校验通过。"
    return 0
  fi

  expected="$(awk '{print $1; exit}' "$sha_file")"
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [[ -n "$expected" ]] || die "SHA256 文件为空或无效。"
  [[ "$expected" == "$actual" ]] || die "SHA256 校验失败。"
  DOWNLOADED_ARCHIVE_SHA256="$expected"
  log_ok "SHA256 校验通过。"
}

download_release_asset() {
  local url="$1"
  local output="$2"
  local asset="$3"

  if curl -fL --retry 3 --connect-timeout 20 -o "$output" "$url"; then
    return 0
  fi

  if [[ "$TARGET_ARCH" == "linux-arm64" ]]; then
    die "当前 Release 缺少 ${asset}，请先确认 caddy-naive-builder 最新 Release 已发布 arm64 资产。"
  fi
  die "下载 Release 资产失败：${asset}"
}

download_release_caddy() {
  prepare_builder_assets
  check_root_free_space
  TMP_DIR="$(mktemp -d)"
  local archive_url sha_url extract_dir caddy_path
  DOWNLOADED_RELEASE_TAG="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null || true)"
  DOWNLOADED_RELEASE_TAG="${DOWNLOADED_RELEASE_TAG##*/}"
  archive_url="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"
  sha_url="https://github.com/${REPO}/releases/latest/download/${SHA_ASSET_NAME}"
  log_info "正在下载 $archive_url"
  download_release_asset "$archive_url" "${TMP_DIR}/${ASSET_NAME}" "$ASSET_NAME"
  log_info "正在下载 $sha_url"
  download_release_asset "$sha_url" "${TMP_DIR}/${SHA_ASSET_NAME}" "$SHA_ASSET_NAME"

  verify_sha256 "$TMP_DIR"

  extract_dir="${TMP_DIR}/extract"
  mkdir -p "$extract_dir"
  tar -xzf "${TMP_DIR}/${ASSET_NAME}" -C "$extract_dir"
  caddy_path="$(find "$extract_dir" -type f -name caddy | head -n 1)"
  [[ -n "$caddy_path" ]] || die "压缩包中未找到 caddy 二进制。"
  chmod +x "$caddy_path"
  [[ -x "$caddy_path" ]] || die "解压出的 caddy 二进制不可执行。"
  DOWNLOADED_CADDY="$caddy_path"
  log_ok "Caddy 二进制已解压。"
}

show_caddy_version_and_check_modules() {
  local version modules
  version="$("$INSTALL_BIN" version 2>&1)"
  log_info "Caddy 版本：$version"

  modules="$("$INSTALL_BIN" list-modules 2>&1)"
  if ! grep -Eiq 'forward_proxy|forwardproxy' <<< "$modules"; then
    log_error "已安装的 Caddy list-modules 未检测到 forward_proxy/forwardproxy。"
    printf '%s\n' "$modules" >&2
    return 1
  fi
  log_ok "已检测到 forward_proxy 模块。"
}

install_binary() {
  local previous_backup=""
  [[ -n "${DOWNLOADED_CADDY:-}" ]] || die "内部错误：下载的 caddy 路径为空。"
  mkdir -p "$(dirname "$INSTALL_BIN")"
  backup_file "$INSTALL_BIN"
  previous_backup="$LAST_BACKUP_PATH"

  install -m 0755 "$DOWNLOADED_CADDY" "$INSTALL_BIN"
  if command -v setcap >/dev/null 2>&1; then
    setcap cap_net_bind_service=+ep "$INSTALL_BIN" || log_warn "setcap 失败；systemd AmbientCapabilities 通常仍可允许绑定 80/443。"
  fi

  if ! show_caddy_version_and_check_modules; then
    if [[ -n "$previous_backup" ]]; then
      cp -a "$previous_backup" "$INSTALL_BIN"
      log_warn "已从 $previous_backup 恢复旧 Caddy 二进制。"
    fi
    die "Caddy 二进制校验失败。"
  fi
}

validate_caddyfile() {
  local output_file
  [[ -f "$CADDYFILE" ]] || die "未找到 Caddyfile：$CADDYFILE"
  output_file="$(mktemp)"
  if "$INSTALL_BIN" validate --config "$CADDYFILE" >"$output_file" 2>&1; then
    rm -f "$output_file"
    log_ok "Caddyfile 校验通过：$CADDYFILE"
    return 0
  fi
  log_error "Caddyfile 校验失败："
  cat "$output_file" >&2
  rm -f "$output_file"
  return 1
}

unit_exists() {
  local unit="$1"
  systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q . \
    || systemctl status "$unit" >/dev/null 2>&1
}

service_exists() {
  unit_exists "${SERVICE_NAME}.service"
}

reload_or_restart_service() {
  if ! service_exists; then
    log_warn "服务 ${SERVICE_NAME} 不存在；仅更新二进制。"
    return 0
  fi

  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    log_warn "服务 ${SERVICE_NAME} 存在但未运行；仅更新二进制。"
    return 0
  fi

  log_info "Caddy admin 已关闭，更新后使用 restart 应用新二进制。"
  if ! systemctl restart "$SERVICE_NAME"; then
    log_error "重启失败。如果状态显示 notify 超时，可将 Type=notify 改为 Type=simple 后重试。"
    systemctl --no-pager --full status "$SERVICE_NAME" || true
    exit 1
  fi
  log_ok "服务 ${SERVICE_NAME} 已重启。"
}

update_env_release_sha() {
  [[ -n "$DOWNLOADED_ARCHIVE_SHA256" ]] || return 0
  [[ -f "$ENV_FILE" ]] || return 0

  local tmp_file line key updated_at release_url
  local tag_done=0 arch_done=0 asset_done=0 sha_done=0 url_done=0 updated_done=0

  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  release_url="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"
  tmp_file="$(mktemp)"
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      key="${line%%=*}"
      case "$key" in
        BUILDER_RELEASE_TAG)
          write_env_kv BUILDER_RELEASE_TAG "$DOWNLOADED_RELEASE_TAG"
          tag_done=1
          continue
          ;;
        BUILDER_RELEASE_ARCH)
          write_env_kv BUILDER_RELEASE_ARCH "$TARGET_ARCH"
          arch_done=1
          continue
          ;;
        BUILDER_RELEASE_ASSET)
          write_env_kv BUILDER_RELEASE_ASSET "$ASSET_NAME"
          asset_done=1
          continue
          ;;
        BUILDER_RELEASE_SHA256)
          write_env_kv BUILDER_RELEASE_SHA256 "$DOWNLOADED_ARCHIVE_SHA256"
          sha_done=1
          continue
          ;;
        BUILDER_RELEASE_URL)
          write_env_kv BUILDER_RELEASE_URL "$release_url"
          url_done=1
          continue
          ;;
        UPDATED_AT)
          write_env_kv UPDATED_AT "$updated_at"
          updated_done=1
          continue
          ;;
      esac
      printf '%s\n' "$line"
    done < "$ENV_FILE"
    (( tag_done )) || write_env_kv BUILDER_RELEASE_TAG "$DOWNLOADED_RELEASE_TAG"
    (( arch_done )) || write_env_kv BUILDER_RELEASE_ARCH "$TARGET_ARCH"
    (( asset_done )) || write_env_kv BUILDER_RELEASE_ASSET "$ASSET_NAME"
    (( sha_done )) || write_env_kv BUILDER_RELEASE_SHA256 "$DOWNLOADED_ARCHIVE_SHA256"
    (( url_done )) || write_env_kv BUILDER_RELEASE_URL "$release_url"
    (( updated_done )) || write_env_kv UPDATED_AT "$updated_at"
  } > "$tmp_file"
  install -m 600 "$tmp_file" "$ENV_FILE"
  rm -f "$tmp_file"
  log_ok "已更新 ${ENV_FILE} 中的 Release 校验值。"
}

main() {
  require_root
  load_env_defaults
  prepare_builder_assets
  require_command curl
  require_command tar
  require_command sha256sum
  require_command mktemp
  require_command find
  require_command install
  require_command systemctl

  check_root_free_space
  download_release_caddy
  install_binary
  validate_caddyfile
  update_env_release_sha
  reload_or_restart_service
  log_ok "Caddy naive 内核更新完成。"
}

main "$@"

NAIVE_EMBEDDED_UPDATE_CORE
}

write_update_script() {
  backup_file "$UPDATE_SCRIPT"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n\n'
    printf 'DEFAULT_REPO=%q\n' "$REPO"
    printf 'DEFAULT_INSTALL_BIN=%q\n' "$INSTALL_BIN"
    printf 'DEFAULT_SERVICE_NAME=%q\n' "$SERVICE_NAME"
    _naive_cat_update_core
  } > "$UPDATE_SCRIPT"
  chmod 755 "$UPDATE_SCRIPT"
  log_ok "更新脚本已写入：$UPDATE_SCRIPT"
}

write_env_file() {
  local tmp_env installed_at
  backup_file "$ENV_FILE"
  umask 077
  tmp_env="$(mktemp /tmp/naive.env.XXXXXX)"
  installed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    write_env_kv DOMAIN "$DOMAIN"
    write_env_kv EMAIL "$EMAIL"
    write_env_kv USER "$AUTH_USER"
    write_env_kv PASS "$AUTH_PASS"
    write_env_kv EXTRA_DOMAINS "$EXTRA_DOMAINS"
    write_env_kv EXTRA_AUTH "$EXTRA_AUTH_RAW"
    write_env_kv SITE_MODE "$SITE_MODE"
    write_env_kv UPSTREAM "$UPSTREAM_BASE"
    write_env_kv REPO "$REPO"
    write_env_kv INSTALL_BIN "$INSTALL_BIN"
    write_env_kv SERVICE_NAME "$SERVICE_NAME"
    write_env_kv CERT_MODE "$CERT_MODE"
    write_env_kv CERT_FULLCHAIN "$CERT_FULLCHAIN"
    write_env_kv CERT_KEY "$CERT_KEY"
    write_env_kv HTTP3 "$HTTP3"
    write_env_kv PROBE_RESISTANCE "$PROBE_RESISTANCE"
    write_env_kv BUILDER_RELEASE_TAG "$DOWNLOADED_RELEASE_TAG"
    write_env_kv BUILDER_RELEASE_ARCH "$TARGET_ARCH"
    write_env_kv BUILDER_RELEASE_ASSET "$ASSET_NAME"
    write_env_kv BUILDER_RELEASE_SHA256 "$DOWNLOADED_ARCHIVE_SHA256"
    write_env_kv BUILDER_RELEASE_URL "https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"
    write_env_kv RELEASE_SHA256 "$DOWNLOADED_ARCHIVE_SHA256"
    write_env_kv INSTALLED_AT "$installed_at"
  } > "$tmp_env"
  if ! mv -f "$tmp_env" "$ENV_FILE"; then
    rm -f "$tmp_env"
    log_error "覆盖安装信息失败：$ENV_FILE"
    return 1
  fi
  chmod 600 "$ENV_FILE"
  log_ok "安装信息已写入：$ENV_FILE"
}

write_auto_update_units() {
  backup_file "$AUTO_UPDATE_SERVICE_FILE"
  cat > "$AUTO_UPDATE_SERVICE_FILE" <<SERVICE
[Unit]
Description=Update Caddy Naive binary
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=-${ENV_FILE}
ExecStart=${UPDATE_SCRIPT}
SERVICE
  chmod 644 "$AUTO_UPDATE_SERVICE_FILE"

  backup_file "$AUTO_UPDATE_TIMER_FILE"
  cat > "$AUTO_UPDATE_TIMER_FILE" <<'TIMER'
[Unit]
Description=Daily Caddy Naive binary update

[Timer]
OnCalendar=*-*-* 04:30:00
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
TIMER
  chmod 644 "$AUTO_UPDATE_TIMER_FILE"

  systemctl daemon-reload
  if [[ "$NO_START" -eq 1 ]]; then
    log_warn "已指定 --no-start；自动更新 timer 文件已写入但未启用。"
  else
    systemctl enable --now caddy-naive-update.timer
    log_ok "自动更新 timer 已启用。"
  fi
}

start_or_reload_service() {
  systemctl daemon-reload
  if [[ "$NO_START" -eq 1 ]]; then
    log_warn "已指定 --no-start；未启用或启动 ${SERVICE_NAME}。"
    return 0
  fi

  systemctl enable "$SERVICE_NAME"
  if ! systemctl restart "$SERVICE_NAME"; then
    log_error "启动 ${SERVICE_NAME} 失败。"
    if restore_caddyfile_backup; then
      log_warn "正在使用恢复后的 Caddyfile 重新校验并尝试启动。"
      validate_caddyfile || true
      systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi
    log_warn "如果 systemd 状态显示 notify 超时，可编辑 ${SERVICE_FILE} 将 Type=notify 改为 Type=simple，然后执行：systemctl daemon-reload && systemctl restart ${SERVICE_NAME}"
    return 1
  fi

  systemctl is-active "$SERVICE_NAME" || true
  systemctl is-enabled "$SERVICE_NAME" || true
  log_ok "服务 ${SERVICE_NAME} 正在运行。"
}

check_https_after_start() {
  [[ "$NO_START" -eq 0 ]] || return 0
  [[ -n "$DOMAIN" ]] || return 0

  if command -v curl >/dev/null 2>&1; then
    if curl -4I "https://${DOMAIN}" --connect-timeout 5 --max-time 20; then
      log_ok "HTTPS 已可用：https://${DOMAIN}"
    else
      log_warn "HTTPS 检测未通过，请确认 DNS、80/443 放行以及证书状态。"
    fi
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl s_client -connect "${DOMAIN}:443" -servername "$DOMAIN" </dev/null 2>/dev/null | grep -E 'subject=|issuer=|Verify return code' || true
  fi
}

confirm_or_exit() {
  local expected="$1"
  local prompt="$2"
  local answer
  printf '%s\n' "$prompt"
  printf '请输入 "%s" 继续：' "$expected"
  read_tty answer
  [[ "$answer" == "$expected" ]] || die "已取消。"
}

remove_file_with_backup() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    backup_file "$path"
    rm -f "$path"
    log_ok "已删除 $path。"
  fi
}

stop_disable_unit_if_present() {
  local unit="$1"
  if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q . || systemctl status "$unit" >/dev/null 2>&1; then
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
    log_ok "已停止并禁用 $unit（如果它处于活动状态）。"
  fi
}

uninstall_service() {
  confirm_or_exit "uninstall" "这将停止并删除服务单元和更新脚本，但保留 /etc/caddy、/var/www/naive 和 /var/lib/caddy。"

  stop_disable_unit_if_present "${SERVICE_NAME}.service"
  stop_disable_unit_if_present "caddy.service"
  stop_disable_unit_if_present "caddy-naive-update.service"
  stop_disable_unit_if_present "caddy-naive-update.timer"

  remove_file_with_backup "$SERVICE_FILE"
  if [[ "$SERVICE_FILE" != "/etc/systemd/system/caddy.service" ]]; then
    remove_file_with_backup "/etc/systemd/system/caddy.service"
  fi
  remove_file_with_backup "$AUTO_UPDATE_SERVICE_FILE"
  remove_file_with_backup "$AUTO_UPDATE_TIMER_FILE"
  remove_file_with_backup "$UPDATE_SCRIPT"

  systemctl daemon-reload
  log_ok "卸载完成。配置、站点和数据目录已保留。"
}

purge_all() {
  local answer

  printf '确认完全卸载？[y/N] '
  read_tty answer || die "已取消。"
  case "${answer,,}" in
    y|yes) ;;
    *) die "已取消。" ;;
  esac

  if [[ ! -f "$ENV_FILE" ]]; then
    log_warn "${ENV_FILE} 不存在，当前机器上可能存在非本脚本管理的 Caddy 配置。"
  fi

  printf '请输入 DELETE 确认完全删除：'
  read_tty answer || die "已取消。"
  [[ "$answer" == "DELETE" ]] || die "已取消。"

  stop_disable_unit_if_present "${SERVICE_NAME}.service"
  stop_disable_unit_if_present "caddy.service"
  stop_disable_unit_if_present "caddy-naive-update.service"
  stop_disable_unit_if_present "caddy-naive-update.timer"

  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR" 2>/dev/null || true
  local purge_backup purge_ts
  purge_ts="$(date +%Y%m%d_%H%M%S)"
  purge_backup="${BACKUP_DIR}/purge.${purge_ts}.tar.gz"
  if [[ -e "$CONFIG_DIR" || -e "$SITE_DIR" ]]; then
    tar -czf "$purge_backup" "$CONFIG_DIR" "$SITE_DIR" 2>/dev/null || log_warn "无法创建彻底卸载前的备份压缩包。"
    [[ -s "$purge_backup" ]] && log_info "已创建彻底卸载前备份：$purge_backup"
  fi

  remove_file_with_backup "$SERVICE_FILE"
  if [[ "$SERVICE_FILE" != "/etc/systemd/system/caddy.service" ]]; then
    remove_file_with_backup "/etc/systemd/system/caddy.service"
  fi
  remove_file_with_backup "$AUTO_UPDATE_SERVICE_FILE"
  remove_file_with_backup "$AUTO_UPDATE_TIMER_FILE"
  remove_file_with_backup "$UPDATE_SCRIPT"
  remove_file_with_backup "$INSTALL_BIN"
  if [[ "$INSTALL_BIN" != "/usr/local/bin/caddy" ]]; then
    remove_file_with_backup "/usr/local/bin/caddy"
  fi
  rm -rf "$CONFIG_DIR" "$SITE_DIR" "$DATA_DIR"
  rm -rf "$BACKUP_DIR"
  systemctl daemon-reload
  log_ok "彻底卸载完成。"
}

caddyfile_has_recommended_site() {
  [[ -n "$DOMAIN" && -f "$CADDYFILE" ]] || return 1
  grep -Eq "^[[:space:]]*:443,[[:space:]]*.*${DOMAIN//./\\.}.*\\{" "$CADDYFILE"
}

caddyfile_has_domain_only_site() {
  [[ -n "$DOMAIN" && -f "$CADDYFILE" ]] || return 1
  grep -Eq "^[[:space:]]*${DOMAIN//./\\.}[[:space:]]*\\{" "$CADDYFILE"
}

caddyfile_has_route_forward_proxy() {
  [[ -f "$CADDYFILE" ]] || return 1
  awk '
    /^[[:space:]]*route[[:space:]]*\{/ { in_route=1 }
    in_route && /^[[:space:]]*forward_proxy[[:space:]]*\{/ { found=1 }
    END { exit found ? 0 : 1 }
  ' "$CADDYFILE"
}

print_port_listen_status() {
  if ! command -v ss >/dev/null 2>&1; then
    log_warn "未找到 ss，无法显示端口监听状态。"
    return 0
  fi

  printf '\n[INFO] TCP 80/443 监听状态：\n'
  ss -lntp 2>/dev/null | grep -E ':(80|443)\b' || true
  printf '\n[INFO] UDP 443 监听状态：\n'
  ss -lnup 2>/dev/null | grep -E ':443\b' || true
}

show_current_status() {
  local release_arch release_asset release_sha
  load_saved_install_info
  prepare_builder_assets
  release_arch="${RECORDED_BUILDER_RELEASE_ARCH:-$TARGET_ARCH}"
  release_asset="${RECORDED_BUILDER_RELEASE_ASSET:-$ASSET_NAME}"
  release_sha="${DOWNLOADED_ARCHIVE_SHA256:-$(read_env_value RELEASE_SHA256 || true)}"

  cat <<STATUS
[INFO] 当前配置
  部署域名：${DOMAIN:-未设置}
  额外域名：${EXTRA_DOMAINS:-无}
  认证用户：${AUTH_USER:-未设置}
  额外账号：$([[ -n "${EXTRA_AUTH_RAW:-}" ]] && echo "已配置" || echo "无")
  回落模式：${SITE_MODE:-未设置}
  反代目标：${UPSTREAM:-未设置}
  证书模式：${CERT_MODE:-未设置}
  HTTP3：${HTTP3:-off}
  probe_resistance：${PROBE_RESISTANCE:-on}
  证书文件：${CERT_FULLCHAIN:-未设置}
  私钥文件：${CERT_KEY:-未设置}
  Builder 仓库：${REPO}
  当前系统架构：${DETECTED_UNAME_M}
  当前 Release 架构：${release_arch}
  当前 Release asset：${release_asset}
  当前 Caddy naive sha256：${release_sha:-未记录}
  Caddy 二进制：${INSTALL_BIN}
  服务名：${SERVICE_NAME}
  更新脚本：${UPDATE_SCRIPT}
STATUS

  if [[ "$HTTP3" == "on" ]]; then
    log_warn "HTTP/3 需要云安全组和系统防火墙放行 UDP 443；客户端也要明确选择 HTTP3/QUIC。默认推荐仍是 HTTP2 + UDP over TCP。"
  fi

  if [[ -x "$INSTALL_BIN" ]]; then
    "$INSTALL_BIN" version || true
    if "$INSTALL_BIN" list-modules 2>/dev/null | grep -Eiq 'forward_proxy|forwardproxy'; then
      log_ok "已检测到 forward_proxy 模块。"
    else
      log_warn "list-modules 未检测到 forward_proxy 模块。"
    fi
  else
    log_warn "未找到 Caddy 二进制或不可执行：$INSTALL_BIN"
  fi

  if [[ -f "$CADDYFILE" ]]; then
    if caddyfile_has_recommended_site; then
      log_ok "Caddyfile 已使用推荐站点结构：:443, DOMAIN。"
    else
      log_warn "当前 Caddyfile 不是推荐 NaiveProxy 结构，可能导致能测延迟但无法使用。建议重新运行安装 / 重新配置。"
    fi
    if caddyfile_has_domain_only_site && ! caddyfile_has_recommended_site; then
      log_warn "检测到 DOMAIN { } 形式站点块；推荐结构应为 :443, DOMAIN { }，且 :443 位于域名前。"
    fi
    if caddyfile_has_route_forward_proxy; then
      log_ok "Caddyfile 包含 route { forward_proxy { 推荐结构。"
    else
      log_warn "Caddyfile 未检测到 route { forward_proxy { 推荐结构。"
    fi
    if grep -Fq "probe_resistance" "$CADDYFILE"; then
      log_ok "probe_resistance 已启用。"
    else
      log_warn "probe_resistance 未启用。"
    fi
  else
    log_warn "未找到 Caddyfile：$CADDYFILE"
  fi

  if [[ -n "$CERT_FULLCHAIN" ]]; then
    if [[ -s "$CERT_FULLCHAIN" ]]; then
      log_ok "证书文件存在：$CERT_FULLCHAIN"
      if command -v openssl >/dev/null 2>&1; then
        openssl x509 -in "$CERT_FULLCHAIN" -noout -issuer -enddate -subject || true
      fi
    else
      log_warn "证书文件不存在或为空：$CERT_FULLCHAIN"
    fi
  fi

  if [[ -n "$CERT_KEY" ]]; then
    if [[ -s "$CERT_KEY" ]]; then
      log_ok "私钥文件存在：$CERT_KEY"
    else
      log_warn "私钥文件不存在或为空：$CERT_KEY"
    fi
  fi

  if command -v systemctl >/dev/null 2>&1; then
    printf '\n[INFO] systemd 状态：\n'
    printf '  active: '
    systemctl is-active "$SERVICE_NAME" || true
    printf '  enabled: '
    systemctl is-enabled "$SERVICE_NAME" || true
    if systemctl is-enabled --quiet caddy-naive-update.timer 2>/dev/null; then
      log_ok "自动更新 timer 已启用。"
    else
      log_warn "自动更新 timer 未启用。"
    fi
  else
    log_warn "当前环境没有 systemctl。"
  fi

  if [[ -x "$UPDATE_SCRIPT" ]]; then
    log_ok "更新脚本存在：$UPDATE_SCRIPT"
  else
    log_warn "更新脚本不存在或不可执行：$UPDATE_SCRIPT"
  fi

  print_port_listen_status
  if command -v ss >/dev/null 2>&1; then
    if [[ "$HTTP3" == "off" ]]; then
      if ss -lnup 2>/dev/null | grep -qE ':443\b'; then
        log_warn "HTTP3=off 但 UDP 443 正在监听，请检查 Caddyfile 或其他进程。"
      else
        log_info "HTTP3=off，UDP 443 未监听是正常状态。"
      fi
    elif [[ "$HTTP3" == "on" ]] && ! ss -lnup 2>/dev/null | grep -qE ':443\b'; then
      log_warn "HTTP3=on 但 UDP 443 未监听，请确认 Caddy 配置和防火墙。"
    fi
  fi
}

print_current_client_config() {
  local v2rayn_link shadowrocket_link
  load_saved_install_info

  if [[ ! -f "$ENV_FILE" ]]; then
    log_warn "尚未安装：未找到 ${ENV_FILE}。"
    return 0
  fi

  if [[ -z "$DOMAIN" || -z "$AUTH_USER" || -z "$AUTH_PASS" ]]; then
    log_warn "${ENV_FILE} 中 DOMAIN/USER/PASS 不完整，无法生成客户端链接。"
    return 0
  fi

  v2rayn_link="$(generate_v2rayn_link)"
  shadowrocket_link="$(generate_shadowrocket_link)"

  cat <<CONFIG
当前服务端配置：
  地址：${DOMAIN}
  额外域名：${EXTRA_DOMAINS:-无}
  端口：443
  用户名：${AUTH_USER}
  密码：${AUTH_PASS}
  UDP over TCP：On（必须开启）
  TLS：tls
  SNI：${DOMAIN}
  跳过证书验证：false
  HTTP3：${HTTP3}
  probe_resistance：${PROBE_RESISTANCE}

v2rayN / sing-box 链接：
  ${v2rayn_link}

Shadowrocket / 小火箭链接：
  ${shadowrocket_link}

重要提示：
  UDP over TCP 必须开启，否则可能只能测延迟但无法使用。
  QUIC 关闭。
  ALPN 不需要填写。
  v2rayN / sing-box GUI 请选择 Naive 类型。
  Shadowrocket 请选择 HTTP2 类型。
  HTTP3 只有在你明确开启并放行 UDP 443 时再测试。
CONFIG
}

show_client_config() {
  print_current_client_config
}

load_auth_change_context() {
  require_root
  load_saved_install_info
  [[ -f "$ENV_FILE" ]] || die "尚未安装：未找到 ${ENV_FILE}。"
  [[ -n "$DOMAIN" ]] || die "${ENV_FILE} 中缺少 DOMAIN。"
  [[ -n "$AUTH_USER" ]] || die "${ENV_FILE} 中缺少 USER。"
  [[ -n "$AUTH_PASS" ]] || die "${ENV_FILE} 中缺少 PASS。"
  [[ -x "$INSTALL_BIN" ]] || die "未找到 Caddy 二进制：$INSTALL_BIN。"
  command -v systemctl >/dev/null 2>&1 || die "当前环境没有 systemctl，无法重启服务。"
  validate_domain
  validate_common_args
  parse_upstream
}

apply_auth_change() {
  local env_backup=""
  backup_file "$ENV_FILE"
  env_backup="$LAST_BACKUP_PATH"

  write_and_validate_caddyfile "$CERT_MODE"

  if ! write_env_file; then
    log_error "写入 ${ENV_FILE} 失败，正在恢复旧 Caddyfile 和安装信息。"
    restore_caddyfile_backup || true
    if [[ -n "$env_backup" && -f "$env_backup" ]]; then
      cp -a "$env_backup" "$ENV_FILE"
      chmod 600 "$ENV_FILE" 2>/dev/null || true
    fi
    systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
    die "认证信息修改失败。"
  fi

  if ! systemctl restart "$SERVICE_NAME"; then
    log_error "重启 ${SERVICE_NAME} 失败，正在恢复旧 Caddyfile 和安装信息。"
    restore_caddyfile_backup || true
    if [[ -n "$env_backup" && -f "$env_backup" ]]; then
      cp -a "$env_backup" "$ENV_FILE"
      chmod 600 "$ENV_FILE" 2>/dev/null || true
    fi
    validate_caddyfile || true
    systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
    [[ -n "$env_backup" ]] && log_warn "安装信息已从备份恢复：$env_backup"
    die "认证信息修改失败，已尝试恢复原服务。"
  fi

  log_ok "认证信息已更新，${SERVICE_NAME} 已重启。"
  print_current_client_config
}

apply_runtime_config_change() {
  local description="${1:-配置已更新}"
  local env_backup=""
  backup_file "$ENV_FILE"
  env_backup="$LAST_BACKUP_PATH"

  write_and_validate_caddyfile "$CERT_MODE"

  if ! write_env_file; then
    log_error "写入 ${ENV_FILE} 失败，正在恢复旧 Caddyfile 和安装信息。"
    restore_caddyfile_backup || true
    if [[ -n "$env_backup" && -f "$env_backup" ]]; then
      cp -a "$env_backup" "$ENV_FILE"
      chmod 600 "$ENV_FILE" 2>/dev/null || true
    fi
    systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
    die "配置修改失败。"
  fi

  if ! systemctl restart "$SERVICE_NAME"; then
    log_error "重启 ${SERVICE_NAME} 失败，正在恢复旧 Caddyfile 和安装信息。"
    restore_caddyfile_backup || true
    if [[ -n "$env_backup" && -f "$env_backup" ]]; then
      cp -a "$env_backup" "$ENV_FILE"
      chmod 600 "$ENV_FILE" 2>/dev/null || true
    fi
    validate_caddyfile || true
    systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
    die "配置修改失败，已尝试恢复原服务。"
  fi

  log_ok "${description}，${SERVICE_NAME} 已重启。"
}

change_auth_user_interactive() {
  local new_user
  load_auth_change_context
  printf '当前用户名：%s\n' "$AUTH_USER"
  while true; do
    printf '请输入新用户名：'
    read_tty new_user || die "输入已取消。"
    if [[ -z "$new_user" ]]; then
      log_warn "用户名不能为空。"
      continue
    fi
    if [[ ! "$new_user" =~ ^[A-Za-z0-9_.-]+$ ]]; then
      log_warn "用户名只能包含 A-Z、a-z、0-9、下划线、连字符和点号。"
      continue
    fi
    break
  done

  AUTH_USER="$new_user"
  apply_auth_change
}

change_auth_pass_interactive() {
  local choice first second
  load_auth_change_context

  while true; do
    printf '请选择修改密码方式：\n'
    printf '  1) 自动生成强随机密码\n'
    printf '  2) 手动输入新密码\n'
    printf '请选择 [1/2]: '
    read_tty choice || die "输入已取消。"
    case "$choice" in
      1)
        AUTH_PASS="$(openssl rand -hex 24)"
        log_info "已生成新的强随机密码。"
        break
        ;;
      2)
        while true; do
          printf '请输入新密码：'
          read_tty_silent first || die "输入已取消。"
          printf '\n'
          [[ -n "$first" ]] || { log_warn "密码不能为空。"; continue; }
          printf '请再次输入新密码：'
          read_tty_silent second || die "输入已取消。"
          printf '\n'
          if [[ "$first" != "$second" ]]; then
            log_warn "两次输入的密码不一致，请重新输入。"
            continue
          fi
          AUTH_PASS="$first"
          validate_credential_token "PASS" "$AUTH_PASS"
          break
        done
        break
        ;;
      *)
        log_warn "请选择 1 或 2。"
        ;;
    esac
  done

  validate_credential_token "PASS" "$AUTH_PASS"
  apply_auth_change
}

set_auth_credentials_cli() {
  load_auth_change_context
  if [[ -n "$SET_USER_VALUE" ]]; then
    validate_auth_user_safe "$SET_USER_VALUE"
    AUTH_USER="$SET_USER_VALUE"
  fi
  if [[ -n "$SET_PASS_VALUE" ]]; then
    AUTH_PASS="$SET_PASS_VALUE"
    validate_credential_token "PASS" "$AUTH_PASS"
  fi
  [[ -n "$SET_USER_VALUE" || -n "$SET_PASS_VALUE" ]] || die "未提供 --set-user 或 --set-pass。"
  apply_auth_change
}

auth_management_menu() {
  local choice

  while true; do
    cat <<'MENU'
认证信息管理
-------------------------------------------------
1. 修改用户名
2. 修改密码
0. 返回
MENU
    printf '请选择：'
    read_tty choice || return 0
    case "$choice" in
      1)
        change_auth_user_interactive
        return 0
        ;;
      2)
        change_auth_pass_interactive
        return 0
        ;;
      0)
        return 0
        ;;
      *)
        log_warn "无效选择。"
        ;;
    esac
  done
}

load_runtime_config_context() {
  require_root
  load_saved_install_info
  [[ -f "$ENV_FILE" ]] || die "尚未安装：未找到 ${ENV_FILE}。"
  [[ -n "$DOMAIN" ]] || die "${ENV_FILE} 中缺少 DOMAIN。"
  [[ -n "$AUTH_USER" && -n "$AUTH_PASS" ]] || die "${ENV_FILE} 中缺少 USER/PASS。"
  [[ -x "$INSTALL_BIN" ]] || die "未找到 Caddy 二进制：$INSTALL_BIN。"
  command -v systemctl >/dev/null 2>&1 || die "当前环境没有 systemctl，无法重启服务。"
  validate_domain
  validate_common_args
  parse_upstream
}

set_http3_config() {
  local new_value="$1"
  load_runtime_config_context
  [[ "$new_value" == "on" || "$new_value" == "off" ]] || die "HTTP3 必须是 on 或 off。"
  HTTP3="$new_value"
  apply_runtime_config_change "HTTP3 已切换为 ${HTTP3}"
  if [[ "$HTTP3" == "on" ]]; then
    log_warn "HTTP/3 需要云安全组和系统防火墙放行 UDP 443。默认推荐仍是 HTTP2 + UDP over TCP。"
  else
    log_info "HTTP3=off 时 UDP 443 未监听是正常状态。"
  fi
  print_port_listen_status
}

set_probe_resistance_config() {
  local new_value="$1"
  load_runtime_config_context
  [[ "$new_value" == "on" || "$new_value" == "off" ]] || die "probe_resistance 必须是 on 或 off。"
  PROBE_RESISTANCE="$new_value"
  apply_runtime_config_change "probe_resistance 已切换为 ${PROBE_RESISTANCE}"
  if [[ "$PROBE_RESISTANCE" == "off" ]]; then
    log_warn "probe_resistance 已关闭。此模式仅建议临时诊断使用，排查完成后请执行 --enable-probe-resistance 重新开启。"
  else
    log_ok "probe_resistance 已开启。"
  fi
}

http3_management_menu() {
  local choice
  cat <<'MENU'
HTTP3 开启 / 关闭
-------------------------------------------------
1. 开启 HTTP3
2. 关闭 HTTP3
0. 返回
MENU
  printf '请选择：'
  read_tty choice || return 0
  case "$choice" in
    1) set_http3_config "on" ;;
    2) set_http3_config "off" ;;
    0) return 0 ;;
    *) log_warn "无效选择。" ;;
  esac
}

fix_static_site_permissions_menu() {
  require_root
  load_saved_install_info
  fix_static_site_permissions
  log_ok "静态站权限已修复。"
  if [[ -x "$INSTALL_BIN" && -f "$CADDYFILE" ]]; then
    validate_caddyfile || die "Caddyfile 校验失败，未重启服务。"
  fi
  if command -v systemctl >/dev/null 2>&1 && service_exists; then
    systemctl restart "$SERVICE_NAME" || die "重启 ${SERVICE_NAME} 失败。"
    log_ok "服务 ${SERVICE_NAME} 已重启。"
  fi
}

proxy_self_test() {
  load_saved_install_info
  if [[ ! -f "$ENV_FILE" || -z "$DOMAIN" || -z "$AUTH_USER" || -z "$AUTH_PASS" ]]; then
    log_warn "尚未安装或 ${ENV_FILE} 中 DOMAIN/USER/PASS 不完整。"
    return 0
  fi

  cat <<INFO
[INFO] 代理核心自检
  部署域名：${DOMAIN}
  认证用户：${AUTH_USER}
  HTTP3：${HTTP3}
INFO

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet "$SERVICE_NAME"; then
      log_ok "Caddy 服务是 active。"
    else
      log_warn "Caddy 服务当前不是 active。"
    fi
  fi

  if [[ -x "$INSTALL_BIN" ]]; then
    "$INSTALL_BIN" version || true
    if "$INSTALL_BIN" list-modules 2>/dev/null | grep -Eiq 'forward_proxy|forwardproxy'; then
      log_ok "已检测到 forward_proxy 模块。"
    else
      log_warn "list-modules 未检测到 forward_proxy 模块。"
    fi
  else
    log_warn "未找到 Caddy 二进制或不可执行：$INSTALL_BIN"
  fi

  refresh_cert_paths
  if [[ -s "$CERT_FULLCHAIN" ]]; then
    log_ok "证书文件存在：$CERT_FULLCHAIN"
    if command -v openssl >/dev/null 2>&1; then
      openssl x509 -in "$CERT_FULLCHAIN" -noout -subject -issuer -enddate || true
    fi
  else
    log_warn "证书文件不存在或为空：${CERT_FULLCHAIN:-未设置}"
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -4I "https://${DOMAIN}" --connect-timeout 5 --max-time 20 || log_warn "HTTPS 探测失败。"
  else
    log_warn "未找到 curl，跳过 HTTPS / proxy 自检。"
    return 0
  fi

  if [[ -f "$CADDYFILE" ]]; then
    local caddyfile_ok=1
    caddyfile_has_recommended_site || caddyfile_ok=0
    caddyfile_has_route_forward_proxy || caddyfile_ok=0
    if [[ "$caddyfile_ok" -eq 1 ]]; then
      log_ok "Caddyfile 使用推荐 NaiveProxy 结构。"
    else
      log_warn "当前 Caddyfile 不是推荐 NaiveProxy 结构，可能导致能测延迟但无法使用。建议重新运行安装 / 重新配置。"
    fi
    if caddyfile_has_domain_only_site && ! caddyfile_has_recommended_site; then
      log_warn "检测到 DOMAIN { } 形式站点块；推荐结构应为 :443, DOMAIN { }，且 :443 位于域名前。"
    fi
  fi

  if curl --help all 2>/dev/null | grep -q -- '--proxy-http2'; then
    local encoded_user encoded_pass curl_log
    encoded_user="$(url_encode "$AUTH_USER")"
    encoded_pass="$(url_encode "$AUTH_PASS")"
    curl_log="$(mktemp)"
    curl -v --proxy-http2 \
      --resolve "${DOMAIN}:443:127.0.0.1" \
      --proxy "https://${encoded_user}:${encoded_pass}@${DOMAIN}:443" \
      "https://cp.cloudflare.com/generate_204" >"$curl_log" 2>&1 || true
    cat "$curl_log"
    if grep -Eiq 'HTTP/1\.1 200 Connection established|CONNECT .* 200|record overflow|wrong version number' "$curl_log"; then
      log_warn "如果出现普通 HTTP/1.1 CONNECT 200 后 TLS record overflow，通常说明测试走的是普通 HTTPS/HTTP1 代理路径，不是最终 NaiveProxy 客户端路径。"
      log_warn "请重点检查客户端是否选择 Naive/HTTP2 类型，并开启 UDP over TCP。"
    fi
    rm -f "$curl_log"
  else
    log_warn "当前 curl 不支持 --proxy-http2。普通 curl --proxy 默认可能走 HTTP/1.1 CONNECT，只能验证 TLS/认证/CONNECT，不代表 NaiveProxy 客户端最终可用。"
    log_warn "如果看到普通 HTTP/1.1 CONNECT 200 后 TLS record overflow，通常说明测试走的是普通 HTTPS/HTTP1 代理路径，不是最终 NaiveProxy 客户端路径。"
    log_warn "请使用 v2rayN / sing-box Naive 类型或 Shadowrocket HTTP2，且必须开启 UDP over TCP。"
  fi
}

unit_exists() {
  local unit="$1"
  systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q . \
    || systemctl status "$unit" >/dev/null 2>&1
}

service_exists() {
  unit_exists "${SERVICE_NAME}.service"
}

show_caddy_logs() {
  load_saved_install_info
  if ! command -v systemctl >/dev/null 2>&1 || ! command -v journalctl >/dev/null 2>&1; then
    printf '[WARN] journalctl 或 systemctl 不存在，无法查看日志。\n'
    return 0
  fi

  if unit_exists "${SERVICE_NAME}.service"; then
    journalctl -u "$SERVICE_NAME" -e --no-pager
  else
    printf '[WARN] %s.service 不存在，可能尚未安装。\n' "$SERVICE_NAME"
  fi
}

tls_diagnose() {
  load_saved_install_info
  refresh_cert_paths

  cat <<INFO
[INFO] SSL / 证书诊断
  部署域名：${DOMAIN:-未设置}
  证书模式：${CERT_MODE:-未设置}
  证书文件：${CERT_FULLCHAIN:-未设置}
  私钥文件：${CERT_KEY:-未设置}
  Caddyfile：${CADDYFILE}
  服务名：${SERVICE_NAME}
INFO

  if [[ -z "$DOMAIN" ]]; then
    log_warn "未读取到 DOMAIN。请先安装或检查 ${ENV_FILE}。"
    return 0
  fi

  if getent ahosts "$DOMAIN" >/dev/null 2>&1; then
    log_ok "DNS 可解析：$DOMAIN"
    getent ahosts "$DOMAIN" | head -n 5 || true
  else
    log_warn "DNS 无法解析：$DOMAIN"
  fi

  printf '\n[INFO] 端口监听：\n'
  port_listeners 80 || true
  port_listeners 443 || true

  if command -v systemctl >/dev/null 2>&1; then
    printf '\n[INFO] systemd 状态：\n'
    systemctl is-active "$SERVICE_NAME" || true
    systemctl is-enabled "$SERVICE_NAME" || true
  fi

  if [[ -s "$CERT_FULLCHAIN" ]]; then
    log_ok "证书文件存在：$CERT_FULLCHAIN"
    if command -v openssl >/dev/null 2>&1; then
      openssl x509 -in "$CERT_FULLCHAIN" -noout -issuer -enddate -subject || true
    fi
  else
    log_warn "证书文件不存在或为空：$CERT_FULLCHAIN"
  fi

  if [[ -s "$CERT_KEY" ]]; then
    log_ok "私钥文件存在：$CERT_KEY"
  else
    log_warn "私钥文件不存在或为空：$CERT_KEY"
  fi

  if command -v curl >/dev/null 2>&1; then
    printf '\n[INFO] HTTPS 探测：\n'
    curl -4I "https://${DOMAIN}" --connect-timeout 5 --max-time 20 || true
  fi

  if command -v openssl >/dev/null 2>&1; then
    printf '\n[INFO] 远端证书链：\n'
    openssl s_client -connect "${DOMAIN}:443" -servername "$DOMAIN" </dev/null 2>/dev/null | grep -E 'subject=|issuer=|Verify return code' || true
  fi
}

issue_cert_from_saved_config() {
  local env_backup=""
  require_root
  require_supported_os
  prepare_builder_assets
  load_saved_install_info
  [[ -f "$ENV_FILE" ]] || die "未找到安装信息：$ENV_FILE。请先运行安装 / 重新配置。"
  [[ -n "$DOMAIN" ]] || die "${ENV_FILE} 中缺少 DOMAIN。"
  [[ -n "$EMAIL" ]] || die "${ENV_FILE} 中缺少 EMAIL，acme.sh ZeroSSL 注册需要邮箱。"
  [[ -n "$AUTH_USER" && -n "$AUTH_PASS" ]] || die "${ENV_FILE} 中缺少 USER/PASS。"
  [[ -x "$INSTALL_BIN" ]] || die "未找到 Caddy 二进制：$INSTALL_BIN。请先运行安装 / 重新配置。"

  validate_domain
  SITE_MODE="${SITE_MODE:-static}"
  CERT_MODE="acme-standalone"
  validate_common_args
  parse_upstream
  check_root_free_space
  install_dependencies
  ensure_caddy_user_and_dirs
  issue_local_cert_workflow
  if ! write_env_file; then
    log_error "写入 ${ENV_FILE} 失败，正在恢复旧 Caddyfile 和安装信息。"
    restore_caddyfile_backup || true
    die "本地证书重新申请失败。"
  fi
  env_backup="$LAST_BACKUP_PATH"
  if ! start_or_reload_service; then
    if [[ -n "$env_backup" && -f "$env_backup" ]]; then
      cp -a "$env_backup" "$ENV_FILE"
      chmod 600 "$ENV_FILE" 2>/dev/null || true
      log_warn "安装信息已从备份恢复：$env_backup"
    fi
    die "本地证书重新申请失败，已尝试恢复原服务。"
  fi
  check_https_after_start
  log_ok "本地证书重新申请完成。"
}

fetch_latest_release_tag() {
  local latest_url
  latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
  printf '%s\n' "${latest_url##*/}"
}

fetch_latest_archive_sha() {
  [[ -n "$SHA_ASSET_NAME" ]] || prepare_builder_assets
  curl -fsSL "https://github.com/${REPO}/releases/latest/download/${SHA_ASSET_NAME}" | awk '{print $1; exit}'
}

detect_update() {
  load_saved_install_info
  prepare_builder_assets
  if ! command -v curl >/dev/null 2>&1; then
    log_warn "检测更新需要 curl。"
    return 0
  fi
  if ! command -v awk >/dev/null 2>&1; then
    log_warn "检测更新需要 awk。"
    return 0
  fi

  local latest_tag latest_sha current_tag current_sha legacy_sha current_version
  latest_tag="$(fetch_latest_release_tag || true)"
  latest_sha="$(fetch_latest_archive_sha || true)"
  current_tag="$(read_env_value BUILDER_RELEASE_TAG || true)"
  current_sha="$(read_env_value BUILDER_RELEASE_SHA256 || true)"
  legacy_sha="$(read_env_value RELEASE_SHA256 || true)"
  [[ -n "$current_sha" ]] || current_sha="$legacy_sha"

  [[ -n "$latest_sha" ]] || die "无法获取 ${REPO} 的最新 Release 校验值：${SHA_ASSET_NAME}。"

  if [[ -x "$INSTALL_BIN" ]]; then
    current_version="$("$INSTALL_BIN" version 2>&1 || true)"
  else
    current_version="未安装"
  fi

  cat <<STATUS
[INFO] 更新检测
  Builder 仓库：${REPO}
  当前系统架构：${DETECTED_UNAME_M}
  当前检测架构：${TARGET_ARCH}
  当前检测资产：${ASSET_NAME}
  已记录 Builder Release Tag：${current_tag:-未记录}
  最新 Release：${latest_tag:-未知}
  当前 Caddy：${current_version}
  已记录 Builder 资产 sha256：${current_sha:-未记录}
  最新资产 sha256：${latest_sha}
STATUS

  if [[ -n "$current_sha" && "$current_sha" == "$latest_sha" && ( -z "$latest_tag" || -z "$current_tag" || "$current_tag" == "$latest_tag" ) ]]; then
    log_ok "当前已是最新版本。"
  else
    log_warn "发现可用更新。可选择菜单 4 更新 Caddy naive 内核。"
  fi
}

update_caddy_kernel() {
  local force="${1:-0}"
  require_root
  load_saved_install_info
  prepare_builder_assets
  write_update_script
  [[ -x "$UPDATE_SCRIPT" ]] || die "未找到更新脚本：$UPDATE_SCRIPT。请先运行安装 / 重新配置。"
  if [[ "$force" -eq 1 ]]; then
    log_info "正在从 ${REPO} 强制重新安装 latest Caddy naive 内核：${ASSET_NAME}。"
  else
    log_info "正在从 ${REPO} 更新 Caddy naive 内核：${ASSET_NAME}。"
  fi
  "$UPDATE_SCRIPT"
}

menu_update_caddy_kernel() {
  load_saved_install_info
  if [[ ! -f "$ENV_FILE" || ! -x "$INSTALL_BIN" ]]; then
    printf '[WARN] 当前尚未安装完整 NaiveProxy Server。\n'
    printf '[INFO] 请先选择 1. 一键安装 / 重新配置。\n'
    printf '[INFO] 如果只是想查看 GitHub 最新版本，请选择 3. 检测更新。\n'
    return 0
  fi

  update_caddy_kernel 0
}

toggle_auto_update() {
  require_root
  load_saved_install_info
  command -v systemctl >/dev/null 2>&1 || die "缺少 systemctl，无法管理自动更新。"

  if systemctl is-enabled --quiet caddy-naive-update.timer 2>/dev/null || systemctl is-active --quiet caddy-naive-update.timer 2>/dev/null; then
    if prompt_yes_no "自动更新当前已启用，是否关闭？" "N"; then
      systemctl disable --now caddy-naive-update.timer
      log_ok "自动更新 timer 已关闭。"
    else
      log_warn "未做任何更改。"
    fi
    return 0
  fi

  if prompt_yes_no "自动更新当前未启用，是否启用？" "Y"; then
    write_update_script
    NO_START=0
    write_auto_update_units
  else
    log_warn "未做任何更改。"
  fi
}

menu_manage_auto_update() {
  load_saved_install_info
  if [[ ! -f "$ENV_FILE" || ! -x "$UPDATE_SCRIPT" || ! -f "$SERVICE_FILE" ]]; then
    printf '[WARN] 当前尚未安装完整 NaiveProxy Server。\n'
    printf '[INFO] 请先选择 1. 一键安装 / 重新配置。\n'
    return 0
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    log_warn "systemctl 不存在，无法管理自动更新。"
    return 0
  fi

  toggle_auto_update
}

pause_for_menu() {
  local _
  printf '\n按 Enter 返回菜单...'
  read_tty _ || true
}

run_menu_action() {
  local action="$1"
  shift || true

  set +e
  (
    set -e
    "$action" "$@"
  )
  local rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    log_warn "操作未完成，退出码：$rc"
  fi

  pause_for_menu
}

menu_install_or_reconfigure() {
  require_root
  load_saved_install_info
  INTERACTIVE=1
  run_interactive_wizard
  run_install_flow
}

menu_uninstall_service() {
  require_root
  load_saved_install_info
  uninstall_service
}

menu_purge_all() {
  require_root
  load_saved_install_info
  purge_all
}

show_fallback_info() {
  local builder_tag builder_arch builder_asset builder_sha installed=0
  load_saved_install_info
  builder_tag="$(read_env_value BUILDER_RELEASE_TAG || true)"
  builder_arch="$(read_env_value BUILDER_RELEASE_ARCH || true)"
  builder_asset="$(read_env_value BUILDER_RELEASE_ASSET || true)"
  builder_sha="$(read_env_value BUILDER_RELEASE_SHA256 || true)"

  cat <<INFO
[INFO] 配置位置
  Caddyfile: ${CADDYFILE}
  Install env: ${ENV_FILE}
  Static web root: ${SITE_DIR}
  Static index: ${SITE_DIR}/index.html
  Cert dir: ${CERT_BASE_DIR}/${DOMAIN:-DOMAIN}
  Updater: ${UPDATE_SCRIPT}
  Cert fullchain: ${CERT_FULLCHAIN:-${CERT_BASE_DIR}/DOMAIN/fullchain.pem}
  Cert key: ${CERT_KEY:-${CERT_BASE_DIR}/DOMAIN/privkey.pem}
INFO

  cat <<INFO

[INFO] 静态网页目录：
  ${SITE_DIR}

[INFO] 首页文件：
  ${SITE_DIR}/index.html

[INFO] 手动上传 HTML/CSS/JS/图片后建议执行：
  chown -R caddy:caddy ${SITE_DIR}
  find ${SITE_DIR} -type d -exec chmod 755 {} \;
  find ${SITE_DIR} -type f -exec chmod 644 {} \;
  ${INSTALL_BIN} validate --config ${CADDYFILE}
  systemctl restart ${SERVICE_NAME}
INFO

  if [[ -f "$ENV_FILE" ]]; then
    installed=1
    cat <<INFO

[INFO] 当前安装信息
  DOMAIN: ${DOMAIN:-未设置}
  SITE_MODE: ${SITE_MODE:-未设置}
  UPSTREAM: ${UPSTREAM:-未设置}
  REPO: ${REPO:-未设置}
  INSTALL_BIN: ${INSTALL_BIN:-未设置}
  CERT_MODE: ${CERT_MODE:-未记录}
  HTTP3: ${HTTP3:-off}
  PROBE_RESISTANCE: ${PROBE_RESISTANCE:-on}
  CERT_FULLCHAIN: ${CERT_FULLCHAIN:-未记录}
  CERT_KEY: ${CERT_KEY:-未记录}
  BUILDER_RELEASE_TAG: ${builder_tag:-未记录}
  BUILDER_RELEASE_ARCH: ${builder_arch:-未记录}
  BUILDER_RELEASE_ASSET: ${builder_asset:-未记录}
  BUILDER_RELEASE_SHA256: ${builder_sha:-未记录}
INFO
  fi

  if [[ "$installed" -eq 0 ]]; then
    printf '[WARN] 当前未检测到安装信息。你可以先选择 1 安装。\n'
    return 0
  fi

  case "$SITE_MODE" in
    static)
      cat <<INFO

[INFO] 当前使用本地静态网页回落。你可以修改：
  ${SITE_DIR}/index.html
修改后执行：
  chown -R caddy:caddy ${SITE_DIR}
  find ${SITE_DIR} -type d -exec chmod 755 {} \;
  find ${SITE_DIR} -type f -exec chmod 644 {} \;
  ${INSTALL_BIN} validate --config ${CADDYFILE}
  systemctl restart ${SERVICE_NAME}
INFO
      ;;
    reverse)
      cat <<INFO

[INFO] 当前使用反代回落。
  反代目标: ${UPSTREAM:-未设置}
如需修改，建议重新运行菜单 1 重新配置。
INFO
      ;;
    *)
      log_warn "未知回落模式：${SITE_MODE:-未设置}"
      ;;
  esac
}

print_management_menu() {
  cat <<MENU
${SCRIPT_NAME} 管理菜单
-------------------------------------------------
1. 一键安装 / 重新配置
2. 查看当前状态
3. 检测更新
4. 更新 Caddy naive 内核
5. 自动更新管理
6. 卸载服务，保留配置
7. 完全卸载所有文件
8. 查看当前配置 / 客户端链接
9. 查看运行日志
10. 回落网站说明 / 配置位置
11. SSL / 证书诊断
12. 重新申请本地证书 acme.sh
13. 认证信息管理
14. HTTP3 开启 / 关闭
15. 代理核心自检
16. 修复静态站权限
0. 退出
MENU
}

run_management_menu() {
  local choice

  while true; do
    clear_menu_screen
    printf '\n'
    print_management_menu
    printf '\n请选择：'
    read_tty choice || exit 0
    choice="${choice//$'\r'/}"

    case "$choice" in
      1)
        run_menu_action menu_install_or_reconfigure
        ;;
      2)
        run_menu_action show_current_status
        ;;
      3)
        run_menu_action detect_update
        ;;
      4)
        run_menu_action menu_update_caddy_kernel
        ;;
      5)
        run_menu_action menu_manage_auto_update
        ;;
      6)
        run_menu_action menu_uninstall_service
        ;;
      7)
        run_menu_action menu_purge_all
        ;;
      8)
        run_menu_action show_client_config
        ;;
      9)
        run_menu_action show_caddy_logs
        ;;
      10)
        run_menu_action show_fallback_info
        ;;
      11)
        run_menu_action tls_diagnose
        ;;
      12)
        run_menu_action issue_cert_from_saved_config
        ;;
      13)
        run_menu_action auth_management_menu
        ;;
      14)
        run_menu_action http3_management_menu
        ;;
      15)
        run_menu_action proxy_self_test
        ;;
      16)
        run_menu_action fix_static_site_permissions_menu
        ;;
      0)
        exit 0
        ;;
      *)
        log_warn "无效选择。"
        pause_for_menu
        ;;
    esac
  done
}

print_success() {
  log_ok "安装完成。"
  print_current_client_config
}

run_install_flow() {
  local issue_needed=0
  local env_backup=""
  require_root
  require_supported_os
  prepare_builder_assets
  validate_domain
  validate_common_args
  parse_upstream
  check_root_free_space
  install_dependencies
  prepare_credentials
  check_dns
  check_ports_available
  ensure_caddy_user_and_dirs
  download_release_caddy
  install_caddy_binary
  write_static_site

  if [[ "$CERT_MODE" == "acme-standalone" ]]; then
    if [[ "$NO_START" -eq 1 ]]; then
      if should_issue_cert; then
        log_warn "已指定 --no-start，无法执行 acme.sh standalone 申请证书；将暂时写入 Caddy ZeroSSL 自动证书配置。"
        write_caddyfile_auto_zerossl
      else
        write_caddyfile_local_cert
      fi
    else
      if should_issue_cert; then
        issue_needed=1
        write_caddyfile_auto_zerossl
      else
        write_caddyfile_local_cert
      fi
    fi
  else
    write_and_validate_caddyfile "$CERT_MODE"
  fi

  write_systemd_service
  write_update_script

  if [[ "$CERT_MODE" == "acme-standalone" && "$NO_START" -eq 0 && "$issue_needed" -eq 1 ]]; then
    systemctl daemon-reload
    issue_local_cert_workflow
  fi

  if ! write_env_file; then
    log_error "写入 ${ENV_FILE} 失败，正在恢复旧 Caddyfile。"
    restore_caddyfile_backup || true
    die "安装信息写入失败。"
  fi
  env_backup="$LAST_BACKUP_PATH"

  if [[ "$AUTO_UPDATE" -eq 1 ]]; then
    write_auto_update_units
  fi

  if ! start_or_reload_service; then
    if [[ -n "$env_backup" && -f "$env_backup" ]]; then
      cp -a "$env_backup" "$ENV_FILE"
      chmod 600 "$ENV_FILE" 2>/dev/null || true
      log_warn "安装信息已从备份恢复：$env_backup"
    fi
    die "安装 / 重新配置失败，已尝试恢复原服务。"
  fi
  check_https_after_start
  print_success
}

main() {
  parse_args "$@"

  if [[ "$ACTION_TEST_ARCH" -eq 1 ]]; then
    print_test_arch
    exit 0
  fi

  if [[ "$DO_PURGE" -eq 1 ]]; then
    require_root
    load_saved_install_info
    purge_all
    exit 0
  fi

  if [[ "$DO_UNINSTALL" -eq 1 ]]; then
    require_root
    load_saved_install_info
    uninstall_service
    exit 0
  fi

  if [[ "$ACTION_STATUS" -eq 1 || "$ACTION_CHECK_UPDATE" -eq 1 || "$ACTION_UPDATE" -eq 1 || "$ACTION_FORCE_UPDATE" -eq 1 || "$ACTION_SHOW_CLIENT" -eq 1 || "$ACTION_LOGS" -eq 1 || "$ACTION_ISSUE_CERT" -eq 1 || "$ACTION_TLS_DIAGNOSE" -eq 1 || "$ACTION_CHANGE_USER" -eq 1 || "$ACTION_CHANGE_PASS" -eq 1 || "$ACTION_PROXY_SELF_TEST" -eq 1 || "$ACTION_FIX_STATIC_PERMS" -eq 1 || ( "$ACTION_HTTP3_TOGGLE" -eq 1 && ! naive_install_requested ) || ( "$ACTION_PROBE_TOGGLE" -eq 1 && ! naive_install_requested ) || -n "$SET_USER_VALUE" || -n "$SET_PASS_VALUE" ]]; then
    [[ "$ACTION_STATUS" -eq 1 ]] && show_current_status
    [[ "$ACTION_CHECK_UPDATE" -eq 1 ]] && detect_update
    [[ "$ACTION_UPDATE" -eq 1 ]] && update_caddy_kernel 0
    [[ "$ACTION_FORCE_UPDATE" -eq 1 ]] && update_caddy_kernel 1
    [[ "$ACTION_ISSUE_CERT" -eq 1 ]] && issue_cert_from_saved_config
    [[ "$ACTION_TLS_DIAGNOSE" -eq 1 ]] && tls_diagnose
    [[ "$ACTION_CHANGE_USER" -eq 1 ]] && change_auth_user_interactive
    [[ "$ACTION_CHANGE_PASS" -eq 1 ]] && change_auth_pass_interactive
    [[ "$ACTION_PROXY_SELF_TEST" -eq 1 ]] && proxy_self_test
    [[ "$ACTION_FIX_STATIC_PERMS" -eq 1 ]] && fix_static_site_permissions_menu
    [[ "$ACTION_HTTP3_TOGGLE" -eq 1 ]] && set_http3_config "$HTTP3"
    [[ "$ACTION_PROBE_TOGGLE" -eq 1 ]] && set_probe_resistance_config "$PROBE_RESISTANCE"
    if [[ -n "$SET_USER_VALUE" || -n "$SET_PASS_VALUE" ]]; then
      set_auth_credentials_cli
    fi
    [[ "$ACTION_SHOW_CLIENT" -eq 1 ]] && show_client_config
    [[ "$ACTION_LOGS" -eq 1 ]] && show_caddy_logs
    exit 0
  fi

  if [[ "$MENU_MODE" -eq 1 ]]; then
    run_management_menu
    exit 0
  fi

  run_install_flow
}

main "$@"
