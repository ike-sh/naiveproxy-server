#!/usr/bin/env bash
set -euo pipefail

ASSET_NAME="caddy-naive-linux-amd64.tar.gz"
SHA_ASSET_NAME="caddy-naive-linux-amd64.tar.gz.sha256"

SCRIPT_NAME="NaiveProxy Server"
SCRIPT_VERSION="0.2.0"
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
CLIENT_CONFIG="/root/naive-client-config.json"
NODE_LINK_FILE="/root/naive-node-link.txt"
ENV_FILE="/etc/caddy/naive.env"
AUTO_UPDATE_SERVICE_FILE="/etc/systemd/system/caddy-naive-update.service"
AUTO_UPDATE_TIMER_FILE="/etc/systemd/system/caddy-naive-update.timer"

DOMAIN=""
EMAIL=""
AUTH_USER=""
AUTH_PASS=""
SITE_MODE="static"
UPSTREAM=""
UPSTREAM_BASE=""
UPSTREAM_HOST=""
REPO="$DEFAULT_REPO"
INSTALL_BIN="$DEFAULT_INSTALL_BIN"
SERVICE_NAME="$DEFAULT_SERVICE_NAME"
SERVICE_FILE="/etc/systemd/system/${DEFAULT_SERVICE_NAME}.service"

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
DO_UNINSTALL=0
DO_PURGE=0
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LAST_BACKUP_PATH=""
TMP_DIR=""
DOWNLOADED_CADDY=""
DOWNLOADED_ARCHIVE_SHA256=""
DOWNLOADED_RELEASE_TAG=""

log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }
log_ok() { printf '[OK] %s\n' "$*"; }
die() { log_error "$*"; exit 1; }

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
作者：${SCRIPT_AUTHOR}
GitHub：${SCRIPT_GITHUB}
Builder 仓库：${BUILDER_GITHUB}
默认 Builder Release：${BUILDER_REPO_DEFAULT}
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
  --email EMAIL                Caddy 申请 ACME TLS 证书使用的邮箱。
  --user USER                  Basic Auth 用户名；不传则自动生成或复用。
  --pass PASS                  Basic Auth 密码；不传则自动生成或复用。
  --site-mode static|reverse   回落网站模式，默认 static。
  --upstream URL               reverse 模式必填。
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
  --show-client                显示客户端配置。
  --logs                       查看 caddy 日志。
  --uninstall                  卸载服务和更新脚本，保留配置、站点和数据。
  --purge                      完全卸载服务、更新脚本、二进制、配置、站点和数据。
  --help                       显示帮助。

示例：
  bash install-naive-server.sh --domain example.com --email me@example.com --site-mode static
  bash install-naive-server.sh --domain example.com --site-mode reverse --upstream https://www.example.org
USAGE
}

refresh_paths() {
  SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
}

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

build_proxy_url() {
  local encoded_user encoded_pass
  encoded_user="$(url_encode "$AUTH_USER")"
  encoded_pass="$(url_encode "$AUTH_PASS")"
  printf 'https://%s:%s@%s' "$encoded_user" "$encoded_pass" "$DOMAIN"
}

caddyfile_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
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
        [[ $# -gt 0 ]] || die "--domain requires a value."
        DOMAIN="$1"
        ;;
      --email)
        shift
        [[ $# -gt 0 ]] || die "--email requires a value."
        EMAIL="$1"
        ;;
      --user)
        shift
        [[ $# -gt 0 ]] || die "--user requires a value."
        AUTH_USER="$1"
        ;;
      --pass)
        shift
        [[ $# -gt 0 ]] || die "--pass requires a value."
        AUTH_PASS="$1"
        ;;
      --site-mode)
        shift
        [[ $# -gt 0 ]] || die "--site-mode requires a value."
        SITE_MODE="$1"
        ;;
      --upstream)
        shift
        [[ $# -gt 0 ]] || die "--upstream requires a value."
        UPSTREAM="$1"
        ;;
      --repo)
        shift
        [[ $# -gt 0 ]] || die "--repo requires a value."
        REPO="$1"
        ;;
      --install-bin)
        shift
        [[ $# -gt 0 ]] || die "--install-bin requires a value."
        INSTALL_BIN="$1"
        ;;
      --service-name)
        shift
        [[ $# -gt 0 ]] || die "--service-name requires a value."
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
      --show-client)
        ACTION_SHOW_CLIENT=1
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
        die "Unknown argument: $1"
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
    IFS= read -r input || die "Input cancelled."
    if [[ -z "$input" ]]; then
      value="$current"
    else
      value="$input"
    fi

    if [[ "$required" == "required" && -z "$value" ]]; then
      log_warn "${label} cannot be empty."
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

    IFS= read -r -s first || die "Input cancelled."
    printf '\n'

    if [[ -z "$first" ]]; then
      return 0
    fi

    printf '请再次输入认证密码 PASS: '
    IFS= read -r -s second || die "Input cancelled."
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
    IFS= read -r input || die "Input cancelled."

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
        log_warn "Please choose static or reverse."
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
    IFS= read -r input || die "Input cancelled."
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
      *) log_warn "Please answer y or n." ;;
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
  自动更新：${auto_update_label}
  立即启动服务：${start_label}
SUMMARY
}

confirm_interactive_install() {
  local answer
  printf '\n确认开始安装？[y/N] '
  IFS= read -r answer || die "Input cancelled."
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

run_interactive_wizard() {
  cat <<'TITLE'
NaiveProxy Server 一键部署向导

TITLE

  prompt_text DOMAIN "部署域名 DOMAIN" "required" "示例：proxy.example.com"
  prompt_text EMAIL "ACME 邮箱 EMAIL，可选" "optional"
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

require_amd64() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) ;;
    aarch64|arm64)
      die "当前 Release 只提供 linux-amd64，请不要继续安装。"
      ;;
    *)
      die "不支持的架构：${arch}。当前仅支持 linux-amd64。"
      ;;
  esac
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
    log_error "Root filesystem has less than 300MB free space."
    print_disk_cleanup_hint
    exit 1
  fi

  log_info "根分区可用空间：${available}MB。"
}

install_dependencies() {
  local deps=(
    curl
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

validate_domain() {
  [[ -n "$DOMAIN" ]] || die "必须提供 --domain。"
  [[ "$DOMAIN" != *"://"* ]] || die "--domain 必须是域名，不是 URL。"
  [[ "$DOMAIN" != *"/"* ]] || die "--domain 不能包含路径。"
  [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die "--domain 包含不支持的字符。"
  [[ "$DOMAIN" == *.* ]] || log_warn "域名不包含点号，公网 TLS 证书申请可能失败。"
}

validate_common_args() {
  [[ "$SITE_MODE" == "static" || "$SITE_MODE" == "reverse" ]] || die "--site-mode 必须是 static 或 reverse。"
  [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--repo 必须是 OWNER/REPO 格式。"
  [[ "$INSTALL_BIN" == /* ]] || die "--install-bin 必须是绝对路径。"
  [[ "$INSTALL_BIN" != *[[:space:]]* ]] || die "--install-bin 不能包含空白字符。"
  [[ "$SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] || die "--service-name 包含不支持的字符。"
  if [[ -n "$EMAIL" ]]; then
    [[ "$EMAIL" != *[[:space:]]* ]] || die "--email 不能包含空白字符。"
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

read_env_value() {
  local key="$1"
  local line value
  [[ -r "$ENV_FILE" ]] || return 0
  while IFS= read -r line; do
    [[ "$line" == "$key="* ]] || continue
    value="${line#*=}"
    printf '%s' "$value"
    return 0
  done < "$ENV_FILE"
}

load_saved_install_info() {
  local value

  value="$(read_env_value DOMAIN || true)"
  [[ -n "$value" ]] && DOMAIN="$value"
  value="$(read_env_value USER || true)"
  [[ -n "$value" ]] && AUTH_USER="$value"
  value="$(read_env_value PASS || true)"
  [[ -n "$value" ]] && AUTH_PASS="$value"
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

  refresh_paths
}

validate_credential_token() {
  local name="$1"
  local value="$2"
  [[ -n "$value" ]] || die "${name} 不能为空。"
  if [[ ! "$value" =~ ^[A-Za-z0-9._~:/@+-]+$ ]]; then
    die "${name} 只能包含 A-Z、a-z、0-9、点号、下划线、波浪线、冒号、斜杠、@、加号和连字符。"
  fi
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

  validate_credential_token "USER" "$AUTH_USER"
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

  local base dest
  base="$(basename "$path")"
  dest="${BACKUP_DIR}/${base}.${TIMESTAMP}.bak"
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
    log_ok "DNS lookup succeeded for $DOMAIN."
  else
    log_warn "$DOMAIN DNS 解析失败。继续执行，但 ACME 证书申请可能失败。"
  fi
  log_info "Ensure ${DOMAIN} A/AAAA records point to this server and cloud security groups allow TCP 80/443."
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
      log_error "TCP port ${port} is already occupied:"
      printf '%s' "$unmanaged" >&2
      conflict=1
    else
      log_info "TCP port ${port} is currently used by the managed ${SERVICE_NAME} service; continuing for repeat install."
    fi
  done

  if [[ "$conflict" -ne 0 ]]; then
    die "Please stop the conflicting service, then run this script again. This script will not modify nginx/apache or firewall rules."
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
  log_ok "Directories are ready."
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
  [[ -n "$expected" ]] || die "SHA256 file is empty or invalid."
  if [[ "$expected" != "$actual" ]]; then
    die "SHA256 校验失败。"
  fi
  DOWNLOADED_ARCHIVE_SHA256="$expected"
  log_ok "SHA256 校验通过。"
}

download_release_caddy() {
  check_root_free_space
  TMP_DIR="$(mktemp -d)"
  local archive_url sha_url extract_dir caddy_path
  DOWNLOADED_RELEASE_TAG="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null || true)"
  DOWNLOADED_RELEASE_TAG="${DOWNLOADED_RELEASE_TAG##*/}"
  archive_url="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"
  sha_url="https://github.com/${REPO}/releases/latest/download/${SHA_ASSET_NAME}"

  log_info "正在下载 $archive_url"
  curl -fL --retry 3 --connect-timeout 20 -o "${TMP_DIR}/${ASSET_NAME}" "$archive_url"
  log_info "正在下载 $sha_url"
  curl -fL --retry 3 --connect-timeout 20 -o "${TMP_DIR}/${SHA_ASSET_NAME}" "$sha_url"

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
  log_info "Caddy version: $version"

  modules="$("$INSTALL_BIN" list-modules 2>&1)"
  if ! grep -Eiq 'forward_proxy|forwardproxy' <<< "$modules"; then
    log_error "Installed Caddy does not report forward_proxy/forwardproxy in list-modules."
    printf '%s\n' "$modules" >&2
    return 1
  fi
  log_ok "已检测到 forward_proxy 模块。"
}

install_caddy_binary() {
  [[ -n "$DOWNLOADED_CADDY" ]] || die "Internal error: downloaded caddy path is empty."
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
  local order_mode="$1"
  local auth_user_caddy auth_pass_caddy
  auth_user_caddy="$(caddyfile_quote "$AUTH_USER")"
  auth_pass_caddy="$(caddyfile_quote "$AUTH_PASS")"
  {
    printf '{\n'
    if [[ "$order_mode" == "strict" ]]; then
      printf '  order forward_proxy before file_server\n'
      printf '  order forward_proxy before reverse_proxy\n'
    else
      printf '  order forward_proxy first\n'
    fi
    printf '  admin off\n'
    printf '}\n\n'
    printf '%s {\n' "$DOMAIN"
    printf '  encode zstd gzip\n'
    if [[ -n "$EMAIL" ]]; then
      printf '  tls %s\n' "$EMAIL"
    fi
    printf '\n'
    printf '  forward_proxy {\n'
    printf '    basic_auth %s %s\n' "$auth_user_caddy" "$auth_pass_caddy"
    printf '    hide_ip\n'
    printf '    hide_via\n'
    printf '    probe_resistance\n'
    printf '  }\n\n'

    if [[ "$SITE_MODE" == "static" ]]; then
      printf '  root * %s\n' "$SITE_DIR"
      printf '  file_server\n'
    else
      printf '  reverse_proxy %s {\n' "$UPSTREAM_BASE"
      printf '    header_up Host %s\n' "$UPSTREAM_HOST"
      printf '    header_up X-Forwarded-Host {host}\n'
      printf '    header_up X-Forwarded-Proto {scheme}\n'
      printf '    transport http {\n'
      printf '      tls_server_name %s\n' "$UPSTREAM_HOST"
      printf '    }\n'
      printf '  }\n'
    fi
    printf '}\n'
  } > "$CADDYFILE"

  chown root:caddy "$CADDYFILE"
  chmod 640 "$CADDYFILE"
}

validate_caddyfile() {
  local output_file
  output_file="$(mktemp)"
  if "$INSTALL_BIN" validate --config "$CADDYFILE" >"$output_file" 2>&1; then
    rm -f "$output_file"
    log_ok "Caddyfile 校验通过。"
    return 0
  fi

  log_error "Caddyfile 校验失败："
  cat "$output_file" >&2
  rm -f "$output_file"
  return 1
}

write_and_validate_caddyfile() {
  local caddyfile_backup=""
  backup_file "$CADDYFILE"
  caddyfile_backup="$LAST_BACKUP_PATH"

  write_caddyfile_content "strict"
  if validate_caddyfile; then
    return 0
  fi

  log_warn "正在改用等价的单条 order 指令重试：order forward_proxy first。"
  write_caddyfile_content "first"
  if validate_caddyfile; then
    return 0
  fi

  if [[ -n "$caddyfile_backup" ]]; then
    cp -a "$caddyfile_backup" "$CADDYFILE"
    log_warn "Restored previous Caddyfile from $caddyfile_backup."
    die "Caddyfile 校验失败。备份位于：$caddyfile_backup"
  fi

  rm -f "$CADDYFILE"
  die "Caddyfile 校验失败，且没有可用的旧 Caddyfile 备份。"
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
ExecReload=${INSTALL_BIN} reload --config ${CADDYFILE} --force
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

write_update_script() {
  backup_file "$UPDATE_SCRIPT"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n\n'
    printf 'DEFAULT_REPO=%q\n' "$REPO"
    printf 'DEFAULT_INSTALL_BIN=%q\n' "$INSTALL_BIN"
    printf 'DEFAULT_SERVICE_NAME=%q\n' "$SERVICE_NAME"
    cat <<'UPDATE_BODY'
ASSET_NAME="caddy-naive-linux-amd64.tar.gz"
SHA_ASSET_NAME="caddy-naive-linux-amd64.tar.gz.sha256"
BACKUP_DIR="/var/backups/caddy-naive"
CADDYFILE="/etc/caddy/Caddyfile"
ENV_FILE="/etc/caddy/naive.env"

log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }
log_ok() { printf '[OK] %s\n' "$*"; }
die() { log_error "$*"; exit 1; }

TMP_DIR=""
LAST_BACKUP_PATH=""
DOWNLOADED_ARCHIVE_SHA256=""
DOWNLOADED_RELEASE_TAG=""

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "This updater must be run as root."
}

require_amd64() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) ;;
    aarch64|arm64)
      die "当前 Release 只提供 linux-amd64，请不要继续安装。"
      ;;
    *)
      die "Unsupported architecture: ${arch}. Only linux-amd64 is supported."
      ;;
  esac
}

print_disk_cleanup_hint() {
  cat >&2 <<'HINT'
Please free disk space and try again. Useful commands:
  df -h
  apt clean
  rm -rf /var/lib/apt/lists/*
  journalctl --vacuum-size=100M
HINT
}

check_root_free_space() {
  local df_output available

  if ! command -v df >/dev/null 2>&1; then
    log_warn "Cannot check root filesystem free space: df command not found."
    return 0
  fi

  if ! df_output="$(df -Pm / 2>/dev/null)"; then
    log_warn "Cannot check root filesystem free space: df -Pm / failed."
    return 0
  fi

  if ! command -v awk >/dev/null 2>&1; then
    log_warn "Cannot parse root filesystem free space: awk command not found."
    return 0
  fi

  available="$(awk 'NR == 2 { print $4 }' <<< "$df_output")"
  if [[ ! "$available" =~ ^[0-9]+$ ]]; then
    log_warn "Cannot parse root filesystem free space from df output."
    return 0
  fi

  if (( available < 300 )); then
    log_error "Root filesystem has less than 300MB free space."
    print_disk_cleanup_hint
    exit 1
  fi

  log_info "Root filesystem free space: ${available}MB."
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
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
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
  log_info "Backed up $path -> $dest"
}

verify_sha256() {
  local dir="$1"
  local archive="${dir}/${ASSET_NAME}"
  local sha_file="${dir}/${SHA_ASSET_NAME}"
  local expected actual

  if (cd "$dir" && sha256sum -c "$SHA_ASSET_NAME" >/dev/null 2>&1); then
    expected="$(awk '{print $1; exit}' "$sha_file")"
    DOWNLOADED_ARCHIVE_SHA256="$expected"
    log_ok "SHA256 checksum verified."
    return 0
  fi

  expected="$(awk '{print $1; exit}' "$sha_file")"
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [[ -n "$expected" ]] || die "SHA256 file is empty or invalid."
  [[ "$expected" == "$actual" ]] || die "SHA256 verification failed."
  DOWNLOADED_ARCHIVE_SHA256="$expected"
  log_ok "SHA256 checksum verified."
}

download_release_caddy() {
  check_root_free_space
  TMP_DIR="$(mktemp -d)"
  local archive_url sha_url extract_dir caddy_path
  DOWNLOADED_RELEASE_TAG="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null || true)"
  DOWNLOADED_RELEASE_TAG="${DOWNLOADED_RELEASE_TAG##*/}"
  archive_url="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"
  sha_url="https://github.com/${REPO}/releases/latest/download/${SHA_ASSET_NAME}"

  log_info "Downloading $archive_url"
  curl -fL --retry 3 --connect-timeout 20 -o "${TMP_DIR}/${ASSET_NAME}" "$archive_url"
  log_info "Downloading $sha_url"
  curl -fL --retry 3 --connect-timeout 20 -o "${TMP_DIR}/${SHA_ASSET_NAME}" "$sha_url"

  verify_sha256 "$TMP_DIR"

  extract_dir="${TMP_DIR}/extract"
  mkdir -p "$extract_dir"
  tar -xzf "${TMP_DIR}/${ASSET_NAME}" -C "$extract_dir"
  caddy_path="$(find "$extract_dir" -type f -name caddy | head -n 1)"
  [[ -n "$caddy_path" ]] || die "The archive does not contain a caddy binary."
  chmod +x "$caddy_path"
  [[ -x "$caddy_path" ]] || die "Extracted caddy binary is not executable."
  DOWNLOADED_CADDY="$caddy_path"
}

show_caddy_version_and_check_modules() {
  local version modules
  version="$("$INSTALL_BIN" version 2>&1)"
  log_info "Caddy version: $version"

  modules="$("$INSTALL_BIN" list-modules 2>&1)"
  if ! grep -Eiq 'forward_proxy|forwardproxy' <<< "$modules"; then
    log_error "Installed Caddy does not report forward_proxy/forwardproxy in list-modules."
    printf '%s\n' "$modules" >&2
    return 1
  fi
  log_ok "forward_proxy module detected."
}

install_binary() {
  local previous_backup=""
  [[ -n "${DOWNLOADED_CADDY:-}" ]] || die "Internal error: downloaded caddy path is empty."
  mkdir -p "$(dirname "$INSTALL_BIN")"
  backup_file "$INSTALL_BIN"
  previous_backup="$LAST_BACKUP_PATH"

  install -m 0755 "$DOWNLOADED_CADDY" "$INSTALL_BIN"
  if command -v setcap >/dev/null 2>&1; then
    setcap cap_net_bind_service=+ep "$INSTALL_BIN" || log_warn "setcap failed; systemd AmbientCapabilities should still allow binding to 80/443."
  fi

  if ! show_caddy_version_and_check_modules; then
    if [[ -n "$previous_backup" ]]; then
      cp -a "$previous_backup" "$INSTALL_BIN"
      log_warn "Restored previous Caddy binary from $previous_backup."
    fi
    die "Caddy binary verification failed."
  fi
}

validate_caddyfile() {
  [[ -f "$CADDYFILE" ]] || die "Caddyfile not found: $CADDYFILE"
  "$INSTALL_BIN" validate --config "$CADDYFILE"
  log_ok "Caddyfile validation passed."
}

service_exists() {
  systemctl list-unit-files "${SERVICE_NAME}.service" --no-legend 2>/dev/null | grep -q . \
    || systemctl status "$SERVICE_NAME" >/dev/null 2>&1
}

reload_or_restart_service() {
  if ! service_exists; then
    log_warn "Service ${SERVICE_NAME} does not exist; binary updated only."
    return 0
  fi

  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    log_warn "Service ${SERVICE_NAME} exists but is not active; binary updated only."
    return 0
  fi

  if systemctl reload "$SERVICE_NAME"; then
    log_ok "Service ${SERVICE_NAME} reloaded."
    return 0
  fi

  log_warn "Reload failed; restarting ${SERVICE_NAME}."
  if ! systemctl restart "$SERVICE_NAME"; then
    log_error "Restart failed. If status shows a notify timeout, change Type=notify to Type=simple and retry."
    systemctl --no-pager --full status "$SERVICE_NAME" || true
    exit 1
  fi
  log_ok "Service ${SERVICE_NAME} restarted."
}

update_env_release_sha() {
  [[ -n "$DOWNLOADED_ARCHIVE_SHA256" ]] || return 0
  [[ -f "$ENV_FILE" ]] || return 0

  local tmp_file
  tmp_file="$(mktemp)"
  awk -F= '
    BEGIN { tag_done=0; builder_sha_done=0; release_sha_done=0 }
    $1 == "BUILDER_RELEASE_TAG" {
      print "BUILDER_RELEASE_TAG='"${DOWNLOADED_RELEASE_TAG}"'";
      tag_done=1;
      next
    }
    $1 == "BUILDER_RELEASE_SHA256" {
      print "BUILDER_RELEASE_SHA256='"${DOWNLOADED_ARCHIVE_SHA256}"'";
      builder_sha_done=1;
      next
    }
    $1 == "RELEASE_SHA256" {
      print "RELEASE_SHA256='"${DOWNLOADED_ARCHIVE_SHA256}"'";
      release_sha_done=1;
      next
    }
    { print }
    END {
      if (!tag_done) print "BUILDER_RELEASE_TAG='"${DOWNLOADED_RELEASE_TAG}"'";
      if (!builder_sha_done) print "BUILDER_RELEASE_SHA256='"${DOWNLOADED_ARCHIVE_SHA256}"'";
      if (!release_sha_done) print "RELEASE_SHA256='"${DOWNLOADED_ARCHIVE_SHA256}"'";
    }
  ' "$ENV_FILE" > "$tmp_file"
  install -m 600 "$tmp_file" "$ENV_FILE"
  rm -f "$tmp_file"
  log_ok "Updated ${ENV_FILE} release checksum."
}

main() {
  require_root
  require_amd64
  load_env_defaults
  require_command curl
  require_command tar
  require_command sha256sum
  require_command awk
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
  log_ok "Caddy naive binary update completed."
}

main "$@"
UPDATE_BODY
  } > "$UPDATE_SCRIPT"
  chmod 755 "$UPDATE_SCRIPT"
  log_ok "更新脚本已写入：$UPDATE_SCRIPT"
}

write_client_config() {
  local proxy_url
  proxy_url="$(build_proxy_url)"
  backup_file "$CLIENT_CONFIG"
  umask 077
  cat > "$CLIENT_CONFIG" <<JSON
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "${proxy_url}"
}
JSON
  chmod 600 "$CLIENT_CONFIG"
  log_ok "客户端 JSON 配置已写入：$CLIENT_CONFIG"
}

write_node_link_file() {
  local proxy_url
  proxy_url="$(build_proxy_url)"
  backup_file "$NODE_LINK_FILE"
  umask 077
  printf '%s\n' "$proxy_url" > "$NODE_LINK_FILE"
  chmod 600 "$NODE_LINK_FILE"
  log_ok "节点链接文件已写入：$NODE_LINK_FILE"
}

write_env_file() {
  backup_file "$ENV_FILE"
  umask 077
  cat > "$ENV_FILE" <<ENV
DOMAIN=${DOMAIN}
USER=${AUTH_USER}
PASS=${AUTH_PASS}
SITE_MODE=${SITE_MODE}
UPSTREAM=${UPSTREAM_BASE}
REPO=${REPO}
INSTALL_BIN=${INSTALL_BIN}
SERVICE_NAME=${SERVICE_NAME}
BUILDER_RELEASE_TAG=${DOWNLOADED_RELEASE_TAG}
BUILDER_RELEASE_SHA256=${DOWNLOADED_ARCHIVE_SHA256}
RELEASE_SHA256=${DOWNLOADED_ARCHIVE_SHA256}
INSTALLED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ENV
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
    log_warn "如果 systemd 状态显示 notify 超时，可编辑 ${SERVICE_FILE} 将 Type=notify 改为 Type=simple，然后执行：systemctl daemon-reload && systemctl restart ${SERVICE_NAME}"
    systemctl --no-pager --full status "$SERVICE_NAME" || true
    exit 1
  fi

  systemctl --no-pager --full status "$SERVICE_NAME"
  log_ok "服务 ${SERVICE_NAME} 正在运行。"
}

confirm_or_exit() {
  local expected="$1"
  local prompt="$2"
  local answer
  printf '%s\n' "$prompt"
  printf 'Type "%s" to continue: ' "$expected"
  read -r answer
  [[ "$answer" == "$expected" ]] || die "Cancelled."
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
    log_ok "Stopped and disabled $unit if it was active."
  fi
}

uninstall_service() {
  confirm_or_exit "uninstall" "This will stop and remove the service units and updater. It will keep /etc/caddy, /var/www/naive and /var/lib/caddy."

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
  log_ok "Uninstall completed. Config, site and data directories were kept."
}

purge_all() {
  local answer

  printf '确认完全卸载？[y/N] '
  IFS= read -r answer || die "Cancelled."
  case "${answer,,}" in
    y|yes) ;;
    *) die "Cancelled." ;;
  esac

  if [[ ! -f "$ENV_FILE" ]]; then
    log_warn "${ENV_FILE} 不存在，当前机器上可能存在非本脚本管理的 Caddy 配置。"
  fi

  printf '请输入 DELETE 确认完全删除：'
  IFS= read -r answer || die "Cancelled."
  [[ "$answer" == "DELETE" ]] || die "Cancelled."

  stop_disable_unit_if_present "${SERVICE_NAME}.service"
  stop_disable_unit_if_present "caddy.service"
  stop_disable_unit_if_present "caddy-naive-update.service"
  stop_disable_unit_if_present "caddy-naive-update.timer"

  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR" 2>/dev/null || true
  local purge_backup="${BACKUP_DIR}/purge.${TIMESTAMP}.tar.gz"
  if [[ -e "$CONFIG_DIR" || -e "$SITE_DIR" ]]; then
    tar -czf "$purge_backup" "$CONFIG_DIR" "$SITE_DIR" 2>/dev/null || log_warn "Could not create purge backup archive."
    [[ -s "$purge_backup" ]] && log_info "Created purge backup: $purge_backup"
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
  remove_file_with_backup "$CLIENT_CONFIG"
  remove_file_with_backup "$NODE_LINK_FILE"

  rm -rf "$CONFIG_DIR" "$SITE_DIR" "$DATA_DIR"
  rm -rf "$BACKUP_DIR"
  systemctl daemon-reload
  log_ok "Purge completed."
}

show_current_status() {
  load_saved_install_info

  cat <<STATUS
[INFO] 当前配置
  部署域名：${DOMAIN:-未设置}
  认证用户：${AUTH_USER:-未设置}
  回落模式：${SITE_MODE:-未设置}
  反代目标：${UPSTREAM:-未设置}
  Builder 仓库：${REPO}
  Caddy 二进制：${INSTALL_BIN}
  服务名：${SERVICE_NAME}
STATUS

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

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --no-pager --full status "$SERVICE_NAME" || true
    if systemctl is-enabled --quiet caddy-naive-update.timer 2>/dev/null; then
      log_ok "自动更新 timer 已启用。"
    else
      log_warn "自动更新 timer 未启用。"
    fi
  else
    log_warn "当前环境没有 systemctl。"
  fi
}

show_client_config() {
  local found=0
  local proxy_url=""
  load_saved_install_info

  if [[ -n "$DOMAIN" && -n "$AUTH_USER" && -n "$AUTH_PASS" ]]; then
    proxy_url="$(build_proxy_url)"
    found=1
    cat <<URL
[INFO] NaiveProxy 节点链接：
  ${proxy_url}
URL
  fi

  if [[ -f "$NODE_LINK_FILE" ]]; then
    found=1
    if [[ -r "$NODE_LINK_FILE" ]]; then
      cat <<CONFIG
[INFO] 节点链接文件：${NODE_LINK_FILE}
CONFIG
      cat "$NODE_LINK_FILE"
      printf '\n'
    else
      printf '[WARN] 节点链接文件存在但不可读：%s\n' "$NODE_LINK_FILE"
    fi
  fi

  if [[ -f "$CLIENT_CONFIG" ]]; then
    found=1
    if [[ -r "$CLIENT_CONFIG" ]]; then
      cat <<CONFIG
[INFO] 客户端 JSON 配置：${CLIENT_CONFIG}
CONFIG
      cat "$CLIENT_CONFIG"
      printf '\n'
    else
      printf '[WARN] 客户端配置存在但不可读：%s\n' "$CLIENT_CONFIG"
    fi
  fi

  if [[ -f "$ENV_FILE" && -z "$proxy_url" ]]; then
    found=1
    printf '[WARN] %s 存在，但 DOMAIN/USER/PASS 不完整或不可读。\n' "$ENV_FILE"
  fi

  if [[ "$found" -eq 0 ]]; then
    printf '[WARN] 尚未安装或未找到客户端配置。\n'
  fi
}

unit_exists() {
  local unit="$1"
  systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q . \
    || systemctl status "$unit" >/dev/null 2>&1
}

show_caddy_logs() {
  if ! command -v systemctl >/dev/null 2>&1 || ! command -v journalctl >/dev/null 2>&1; then
    printf '[WARN] journalctl 或 systemctl 不存在，无法查看日志。\n'
    return 0
  fi

  if unit_exists "caddy.service"; then
    journalctl -u caddy -e --no-pager
  else
    printf '[WARN] caddy.service 不存在，可能尚未安装。\n'
  fi
}

fetch_latest_release_tag() {
  local latest_url
  latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
  printf '%s\n' "${latest_url##*/}"
}

fetch_latest_archive_sha() {
  curl -fsSL "https://github.com/${REPO}/releases/latest/download/${SHA_ASSET_NAME}" | awk '{print $1; exit}'
}

detect_update() {
  load_saved_install_info
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

  [[ -n "$latest_sha" ]] || die "无法获取 ${REPO} 的最新 Release 校验值。"

  if [[ -x "$INSTALL_BIN" ]]; then
    current_version="$("$INSTALL_BIN" version 2>&1 || true)"
  else
    current_version="未安装"
  fi

  cat <<STATUS
[INFO] 更新检测
  Builder 仓库：${REPO}
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
  [[ -x "$UPDATE_SCRIPT" ]] || die "未找到更新脚本：$UPDATE_SCRIPT。请先运行安装 / 重新配置。"
  if [[ "$force" -eq 1 ]]; then
    log_info "正在从 ${REPO} 强制重新安装 latest Caddy naive 内核。"
  fi
  "$UPDATE_SCRIPT"
}

menu_update_caddy_kernel() {
  load_saved_install_info
  if [[ ! -f "$ENV_FILE" || ! -x "$INSTALL_BIN" || ! -x "$UPDATE_SCRIPT" ]]; then
    printf '[WARN] 当前尚未安装或更新脚本不存在。\n'
    printf '[INFO] 请先选择 1. 一键安装 / 重新配置。\n'
    printf '[INFO] 如果只是想查看 GitHub 最新版本，请选择 3. 检测更新。\n'
    return 0
  fi

  update_caddy_kernel 0
}

toggle_auto_update() {
  require_root
  load_saved_install_info
  command -v systemctl >/dev/null 2>&1 || die "systemctl is required."

  if systemctl is-enabled --quiet caddy-naive-update.timer 2>/dev/null || systemctl is-active --quiet caddy-naive-update.timer 2>/dev/null; then
    if prompt_yes_no "自动更新当前已启用，是否关闭？" "N"; then
      systemctl disable --now caddy-naive-update.timer
      log_ok "Auto-update timer disabled."
    else
      log_warn "No changes made."
    fi
    return 0
  fi

  if prompt_yes_no "自动更新当前未启用，是否启用？" "Y"; then
    write_update_script
    NO_START=0
    write_auto_update_units
  else
    log_warn "No changes made."
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
  IFS= read -r _ || true
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
  local builder_tag builder_sha installed=0
  load_saved_install_info
  builder_tag="$(read_env_value BUILDER_RELEASE_TAG || true)"
  builder_sha="$(read_env_value BUILDER_RELEASE_SHA256 || true)"

  cat <<INFO
[INFO] 配置位置
  Caddyfile: ${CADDYFILE}
  Static web root: ${SITE_DIR}
  Static index: ${SITE_DIR}/index.html
  Client config: ${CLIENT_CONFIG}
  Node link: ${NODE_LINK_FILE}
  Install env: ${ENV_FILE}
  Updater: ${UPDATE_SCRIPT}
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
  systemctl reload ${SERVICE_NAME}
INFO

  if [[ -f "$ENV_FILE" ]]; then
    installed=1
    cat <<INFO

[INFO] 当前安装信息
  DOMAIN: ${DOMAIN:-not set}
  SITE_MODE: ${SITE_MODE:-not set}
  UPSTREAM: ${UPSTREAM:-未设置}
  REPO: ${REPO:-not set}
  INSTALL_BIN: ${INSTALL_BIN:-not set}
  BUILDER_RELEASE_TAG: ${builder_tag:-未记录}
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
  systemctl reload ${SERVICE_NAME}
INFO
      ;;
    reverse)
      cat <<INFO

[INFO] 当前使用反代回落。
  Upstream: ${UPSTREAM:-未设置}
如需修改，建议重新运行菜单 1 重新配置。
INFO
      ;;
    *)
      log_warn "未知回落模式：${SITE_MODE:-not set}"
      ;;
  esac
}

print_management_menu() {
  cat <<MENU
${SCRIPT_NAME} 管理菜单
作者：${SCRIPT_AUTHOR}
GitHub：${SCRIPT_GITHUB}
Builder：${BUILDER_GITHUB}
-------------------------------------------------
1. 一键安装 / 重新配置
2. 查看当前状态
3. 检测更新
4. 更新 Caddy naive 内核
5. 自动更新管理
6. 卸载服务，保留配置
7. 完全卸载所有文件
8. 显示客户端配置
9. 查看运行日志
10. 回落网站说明 / 配置位置
0. 退出
MENU
}

run_management_menu() {
  local choice

  while true; do
    printf '\n'
    print_management_menu
    printf '\n请选择：'
    IFS= read -r choice || exit 0

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
  local proxy_url
  proxy_url="$(build_proxy_url)"
  cat <<EOF

[OK] 安装完成。

NaiveProxy 节点链接：
  ${proxy_url}

节点链接文件：
  ${NODE_LINK_FILE}

客户端 JSON 配置：
  ${CLIENT_CONFIG}

配置内容：
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "${proxy_url}"
}

说明：
  NaiveProxy 没有像 VLESS 一样统一的 vless:// 分享标准。
  这里输出的是 NaiveProxy HTTPS 代理地址，适用于 naive-client-config.json 的 proxy 字段，也方便复制保存。

请妥善保存用户名和密码。以下文件仅 root 可读：
  ${ENV_FILE}
  ${CLIENT_CONFIG}
  ${NODE_LINK_FILE}

查看状态：
  systemctl status ${SERVICE_NAME}
  journalctl -u ${SERVICE_NAME} -e --no-pager
EOF

  if [[ "$SITE_MODE" == "static" ]]; then
    cat <<EOF

静态回落站点：
  网站目录：${SITE_DIR}
  首页文件：${SITE_DIR}/index.html

自定义静态网页：
  nano ${SITE_DIR}/index.html
  chown -R caddy:caddy ${SITE_DIR}
  find ${SITE_DIR} -type d -exec chmod 755 {} \;
  find ${SITE_DIR} -type f -exec chmod 644 {} \;
  systemctl reload ${SERVICE_NAME}
EOF
  elif [[ "$SITE_MODE" == "reverse" ]]; then
    cat <<EOF

反代回落站点：
  反代目标：${UPSTREAM_BASE}
  目标主机：${UPSTREAM_HOST}

修改反代目标：
  重新运行脚本并选择 1. 一键安装 / 重新配置
  或谨慎编辑 ${CADDYFILE} 后执行：
  ${INSTALL_BIN} validate --config ${CADDYFILE}
  systemctl reload ${SERVICE_NAME}
EOF
  fi
}

run_install_flow() {
  require_root
  require_supported_os
  require_amd64
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
  write_and_validate_caddyfile
  write_systemd_service
  write_update_script
  write_env_file
  write_client_config
  write_node_link_file

  if [[ "$AUTO_UPDATE" -eq 1 ]]; then
    write_auto_update_units
  fi

  start_or_reload_service
  print_success
}

main() {
  parse_args "$@"

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

  if [[ "$ACTION_STATUS" -eq 1 || "$ACTION_CHECK_UPDATE" -eq 1 || "$ACTION_UPDATE" -eq 1 || "$ACTION_FORCE_UPDATE" -eq 1 || "$ACTION_SHOW_CLIENT" -eq 1 || "$ACTION_LOGS" -eq 1 ]]; then
    [[ "$ACTION_STATUS" -eq 1 ]] && show_current_status
    [[ "$ACTION_CHECK_UPDATE" -eq 1 ]] && detect_update
    [[ "$ACTION_UPDATE" -eq 1 ]] && update_caddy_kernel 0
    [[ "$ACTION_FORCE_UPDATE" -eq 1 ]] && update_caddy_kernel 1
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
