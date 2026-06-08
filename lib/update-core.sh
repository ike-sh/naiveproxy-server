#!/usr/bin/env bash
# NaiveProxy Server — Caddy naive 内核更新核心逻辑

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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
