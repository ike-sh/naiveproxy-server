#!/usr/bin/env bash
set -euo pipefail

ASSET_NAME="caddy-naive-linux-amd64.tar.gz"
SHA_ASSET_NAME="caddy-naive-linux-amd64.tar.gz.sha256"

DEFAULT_REPO="ike-sh/caddy-naive-builder"
DEFAULT_INSTALL_BIN="/usr/local/bin/caddy"
DEFAULT_SERVICE_NAME="caddy"

CONFIG_DIR="/etc/caddy"
CADDYFILE="/etc/caddy/Caddyfile"
SITE_DIR="/var/www/naive"
DATA_DIR="/var/lib/caddy"
BACKUP_DIR="/var/backups/caddy-naive"
UPDATE_SCRIPT="/usr/local/bin/update-caddy-naive"
CLIENT_CONFIG="/root/naive-client-config.json"
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
DO_UNINSTALL=0
DO_PURGE=0
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LAST_BACKUP_PATH=""
TMP_DIR=""
DOWNLOADED_CADDY=""

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

usage() {
  cat <<'USAGE'
Usage:
  bash install-naive-server.sh --domain DOMAIN [options]
  bash install-naive-server.sh --interactive
  bash install-naive-server.sh --uninstall
  bash install-naive-server.sh --purge

Required:
  --domain DOMAIN              Deployment domain, for example example.com.

Options:
  --email EMAIL                Email for Caddy ACME TLS registration.
  --user USER                  Basic Auth username. Generated or reused if omitted.
  --pass PASS                  Basic Auth password. Generated or reused if omitted.
  --site-mode static|reverse   Fallback website mode. Default: static.
  --upstream URL               Required when --site-mode reverse.
  --repo OWNER/REPO            GitHub Release repo. Default: ike-sh/caddy-naive-builder.
  --install-bin PATH           Caddy install path. Default: /usr/local/bin/caddy.
  --service-name NAME          systemd service name. Default: caddy.
  --interactive, -i            Run the interactive installation wizard.
  --auto-update                Install and enable a daily systemd update timer.
  --no-start                   Write files only; do not enable or start services/timers.
  --uninstall                  Uninstall service units and updater; keep config/site/data.
  --purge                      Remove service, updater, binary, config, site and data.
  --help                       Show this help.

Examples:
  bash install-naive-server.sh --domain example.com --email me@example.com --site-mode static
  bash install-naive-server.sh --domain example.com --site-mode reverse --upstream https://www.example.org
USAGE
}

refresh_paths() {
  SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    if [[ -t 0 ]]; then
      INTERACTIVE=1
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
      --interactive|-i)
        INTERACTIVE=1
        ;;
      --auto-update)
        AUTO_UPDATE=1
        ;;
      --no-start)
        NO_START=1
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
    printf '回落网站模式 SITE_MODE [%s]\n' "$default_label"
    printf '  1) static，本地静态页面，推荐\n'
    printf '  2) reverse，反代其他网站\n'
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
    password_label="provided, hidden"
  else
    password_label="auto-generate"
  fi

  email_label="${EMAIL:-not set}"
  upstream_label="${UPSTREAM:-not set}"
  if [[ "$AUTO_UPDATE" -eq 1 ]]; then
    auto_update_label="yes"
  else
    auto_update_label="no"
  fi
  if [[ "$NO_START" -eq 1 ]]; then
    start_label="no"
  else
    start_label="yes"
  fi

  cat <<SUMMARY

Installation summary:
  Domain: ${DOMAIN}
  Email: ${email_label}
  User: ${AUTH_USER:-auto-generate}
  Password: ${password_label}
  Site mode: ${SITE_MODE}
  Upstream: ${upstream_label}
  Auto update: ${auto_update_label}
  Start service now: ${start_label}
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
      log_warn "Installation cancelled."
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
      log_warn "upstream URL must start with http:// or https://."
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
    die "This script must be run as root."
  fi
}

require_supported_os() {
  [[ -r /etc/os-release ]] || die "Cannot detect OS: /etc/os-release is missing."
  # shellcheck disable=SC1091
  . /etc/os-release
  local id="${ID:-}"
  local like="${ID_LIKE:-}"
  case " ${id} ${like} " in
    *" debian "*|*" ubuntu "*) ;;
    *) die "Only Debian and Ubuntu are supported." ;;
  esac
  command -v apt-get >/dev/null 2>&1 || die "apt-get is required but was not found."
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

  log_info "Installing base dependencies with apt-get..."
  apt_log="$(mktemp)"
  if ! apt-get update >"$apt_log" 2>&1; then
    if grep -qi "No space left on device" "$apt_log"; then
      log_error "apt-get update failed: No space left on device."
      print_disk_cleanup_hint
    else
      log_error "apt-get update failed:"
      cat "$apt_log" >&2
    fi
    rm -f "$apt_log"
    exit 1
  fi
  rm -f "$apt_log"

  DEBIAN_FRONTEND=noninteractive apt-get install -y "${deps[@]}"
  log_ok "Dependencies are ready."
}

validate_domain() {
  [[ -n "$DOMAIN" ]] || die "--domain is required."
  [[ "$DOMAIN" != *"://"* ]] || die "--domain must be a hostname, not a URL."
  [[ "$DOMAIN" != *"/"* ]] || die "--domain must not contain a path."
  [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die "--domain contains unsupported characters."
  [[ "$DOMAIN" == *.* ]] || log_warn "Domain does not contain a dot; public TLS issuance may fail."
}

validate_common_args() {
  [[ "$SITE_MODE" == "static" || "$SITE_MODE" == "reverse" ]] || die "--site-mode must be static or reverse."
  [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--repo must look like OWNER/REPO."
  [[ "$INSTALL_BIN" == /* ]] || die "--install-bin must be an absolute path."
  [[ "$INSTALL_BIN" != *[[:space:]]* ]] || die "--install-bin must not contain whitespace."
  [[ "$SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] || die "--service-name contains unsupported characters."
  if [[ -n "$EMAIL" ]]; then
    [[ "$EMAIL" != *[[:space:]]* ]] || die "--email must not contain whitespace."
  fi
}

parse_upstream() {
  if [[ "$SITE_MODE" != "reverse" ]]; then
    if [[ -n "$UPSTREAM" ]]; then
      log_warn "--upstream is ignored when --site-mode is static."
    fi
    return
  fi

  [[ -n "$UPSTREAM" ]] || die "--upstream is required when --site-mode reverse."
  if [[ ! "$UPSTREAM" =~ ^(https?)://([^/?#]+) ]]; then
    die "--upstream must start with http:// or https://."
  fi

  local scheme="${BASH_REMATCH[1]}"
  local authority="${BASH_REMATCH[2]}"
  [[ -n "$authority" ]] || die "Cannot parse upstream host."
  [[ "$authority" != *"@"* ]] || die "--upstream must not contain userinfo."

  UPSTREAM_BASE="${scheme}://${authority}"
  if [[ "$authority" =~ ^\[([^]]+)\](:[0-9]+)?$ ]]; then
    UPSTREAM_HOST="${BASH_REMATCH[1]}"
  else
    UPSTREAM_HOST="${authority%%:*}"
  fi

  [[ -n "$UPSTREAM_HOST" ]] || die "Cannot parse upstream host."
  [[ "$UPSTREAM_HOST" =~ ^[A-Za-z0-9.-]+$ || "$UPSTREAM_HOST" =~ ^[0-9A-Fa-f:]+$ ]] || die "Upstream host contains unsupported characters."

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

validate_credential_token() {
  local name="$1"
  local value="$2"
  [[ -n "$value" ]] || die "${name} must not be empty."
  if [[ ! "$value" =~ ^[A-Za-z0-9._~-]+$ ]]; then
    die "${name} may only contain A-Z, a-z, 0-9, dot, underscore, tilde and hyphen. Avoid '/', '@', ':' and whitespace."
  fi
}

prepare_credentials() {
  local existing_user existing_pass
  existing_user="$(read_env_value USER || true)"
  existing_pass="$(read_env_value PASS || true)"

  if [[ -z "$AUTH_USER" ]]; then
    if [[ "$INTERACTIVE" -eq 0 && -n "$existing_user" ]]; then
      AUTH_USER="$existing_user"
      log_info "Reusing existing Basic Auth username from $ENV_FILE."
    else
      AUTH_USER="user$(openssl rand -hex 4)"
      log_info "Generated Basic Auth username."
    fi
  fi

  if [[ -z "$AUTH_PASS" ]]; then
    if [[ "$INTERACTIVE" -eq 0 && -n "$existing_pass" ]]; then
      AUTH_PASS="$existing_pass"
      log_info "Reusing existing Basic Auth password from $ENV_FILE."
    else
      AUTH_PASS="$(openssl rand -hex 24)"
      log_info "Generated strong random Basic Auth password."
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
  log_info "Backed up $path -> $dest"
}

check_dns() {
  if getent ahosts "$DOMAIN" >/dev/null 2>&1; then
    log_ok "DNS lookup succeeded for $DOMAIN."
  else
    log_warn "DNS lookup failed for $DOMAIN. Continue anyway, but ACME issuance may fail."
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
    log_ok "Created system group: caddy."
  fi

  if ! id -u caddy >/dev/null 2>&1; then
    useradd --system \
      --gid caddy \
      --home-dir "$DATA_DIR" \
      --shell /usr/sbin/nologin \
      caddy
    log_ok "Created system user: caddy."
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
    log_ok "SHA256 checksum verified."
    return 0
  fi

  expected="$(awk '{print $1; exit}' "$sha_file")"
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [[ -n "$expected" ]] || die "SHA256 file is empty or invalid."
  if [[ "$expected" != "$actual" ]]; then
    die "SHA256 verification failed."
  fi
  log_ok "SHA256 checksum verified."
}

download_release_caddy() {
  check_root_free_space
  TMP_DIR="$(mktemp -d)"
  local archive_url sha_url extract_dir caddy_path
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
  log_ok "Caddy binary extracted."
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

install_caddy_binary() {
  [[ -n "$DOWNLOADED_CADDY" ]] || die "Internal error: downloaded caddy path is empty."
  mkdir -p "$(dirname "$INSTALL_BIN")"

  local previous_backup=""
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

  chown -R caddy:caddy "$SITE_DIR"
  chmod 644 "${SITE_DIR}/index.html" "${SITE_DIR}/robots.txt"
  log_ok "Static fallback site generated."
}

write_caddyfile_content() {
  local order_mode="$1"
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
    printf '    basic_auth %s %s\n' "$AUTH_USER" "$AUTH_PASS"
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
    log_ok "Caddyfile validation passed."
    return 0
  fi

  log_error "Caddyfile validation failed:"
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

  log_warn "Retrying Caddyfile with equivalent single order directive: order forward_proxy first."
  write_caddyfile_content "first"
  if validate_caddyfile; then
    return 0
  fi

  if [[ -n "$caddyfile_backup" ]]; then
    cp -a "$caddyfile_backup" "$CADDYFILE"
    log_warn "Restored previous Caddyfile from $caddyfile_backup."
    die "Caddyfile validation failed. Backup is available at $caddyfile_backup."
  fi

  rm -f "$CADDYFILE"
  die "Caddyfile validation failed. No previous Caddyfile backup was available."
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
  log_ok "systemd service written to $SERVICE_FILE."
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
    log_ok "SHA256 checksum verified."
    return 0
  fi

  expected="$(awk '{print $1; exit}' "$sha_file")"
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [[ -n "$expected" ]] || die "SHA256 file is empty or invalid."
  [[ "$expected" == "$actual" ]] || die "SHA256 verification failed."
  log_ok "SHA256 checksum verified."
}

download_release_caddy() {
  TMP_DIR="$(mktemp -d)"
  local archive_url sha_url extract_dir caddy_path
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

main() {
  require_root
  require_amd64
  load_env_defaults
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
  reload_or_restart_service
  log_ok "Caddy naive binary update completed."
}

main "$@"
UPDATE_BODY
  } > "$UPDATE_SCRIPT"
  chmod 755 "$UPDATE_SCRIPT"
  log_ok "Updater written to $UPDATE_SCRIPT."
}

write_client_config() {
  backup_file "$CLIENT_CONFIG"
  umask 077
  cat > "$CLIENT_CONFIG" <<JSON
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://${AUTH_USER}:${AUTH_PASS}@${DOMAIN}"
}
JSON
  chmod 600 "$CLIENT_CONFIG"
  log_ok "Client config written to $CLIENT_CONFIG."
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
INSTALLED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ENV
  chmod 600 "$ENV_FILE"
  log_ok "Install information written to $ENV_FILE."
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
    log_warn "--no-start specified; auto-update timer files were written but not enabled."
  else
    systemctl enable --now caddy-naive-update.timer
    log_ok "Auto-update timer enabled."
  fi
}

start_or_reload_service() {
  systemctl daemon-reload
  if [[ "$NO_START" -eq 1 ]]; then
    log_warn "--no-start specified; ${SERVICE_NAME} was not enabled or started."
    return 0
  fi

  systemctl enable "$SERVICE_NAME"
  if ! systemctl restart "$SERVICE_NAME"; then
    log_error "Failed to start ${SERVICE_NAME}."
    log_warn "If systemd status shows a notify timeout, edit ${SERVICE_FILE} and change Type=notify to Type=simple, then run: systemctl daemon-reload && systemctl restart ${SERVICE_NAME}"
    systemctl --no-pager --full status "$SERVICE_NAME" || true
    exit 1
  fi

  systemctl --no-pager --full status "$SERVICE_NAME"
  log_ok "Service ${SERVICE_NAME} is running."
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
    log_ok "Removed $path."
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
  stop_disable_unit_if_present "caddy-naive-update.timer"

  remove_file_with_backup "$SERVICE_FILE"
  remove_file_with_backup "$AUTO_UPDATE_SERVICE_FILE"
  remove_file_with_backup "$AUTO_UPDATE_TIMER_FILE"
  remove_file_with_backup "$UPDATE_SCRIPT"

  systemctl daemon-reload
  log_ok "Uninstall completed. Config, site and data directories were kept."
}

purge_all() {
  confirm_or_exit "purge" "This will remove the service, updater, Caddy binary, /etc/caddy, /var/www/naive and /var/lib/caddy."
  confirm_or_exit "DELETE" "Second confirmation required. This action is destructive."

  stop_disable_unit_if_present "${SERVICE_NAME}.service"
  stop_disable_unit_if_present "caddy-naive-update.timer"

  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR" 2>/dev/null || true
  local purge_backup="${BACKUP_DIR}/purge.${TIMESTAMP}.tar.gz"
  if [[ -e "$CONFIG_DIR" || -e "$SITE_DIR" ]]; then
    tar -czf "$purge_backup" "$CONFIG_DIR" "$SITE_DIR" 2>/dev/null || log_warn "Could not create purge backup archive."
    [[ -s "$purge_backup" ]] && log_info "Created purge backup: $purge_backup"
  fi

  remove_file_with_backup "$SERVICE_FILE"
  remove_file_with_backup "$AUTO_UPDATE_SERVICE_FILE"
  remove_file_with_backup "$AUTO_UPDATE_TIMER_FILE"
  remove_file_with_backup "$UPDATE_SCRIPT"
  remove_file_with_backup "$INSTALL_BIN"

  rm -rf "$CONFIG_DIR" "$SITE_DIR" "$DATA_DIR"
  systemctl daemon-reload
  log_ok "Purge completed."
}

print_success() {
  local proxy_url="https://${AUTH_USER}:${AUTH_PASS}@${DOMAIN}"
  cat <<EOF

[OK] Installation completed.

NaiveProxy URL:
  ${proxy_url}

Client config saved to ${CLIENT_CONFIG}:
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "${proxy_url}"
}

Please save the username and password securely. They are stored only in root-readable files:
  ${ENV_FILE}
  ${CLIENT_CONFIG}

Check status:
  systemctl status ${SERVICE_NAME}
  journalctl -u ${SERVICE_NAME} -e --no-pager
EOF
}

main() {
  parse_args "$@"

  if [[ "$DO_PURGE" -eq 1 ]]; then
    require_root
    purge_all
    exit 0
  fi

  if [[ "$DO_UNINSTALL" -eq 1 ]]; then
    require_root
    uninstall_service
    exit 0
  fi

  if [[ "$INTERACTIVE" -eq 1 ]]; then
    run_interactive_wizard
  fi

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

  if [[ "$AUTO_UPDATE" -eq 1 ]]; then
    write_auto_update_units
  fi

  start_or_reload_service
  print_success
}

main "$@"
