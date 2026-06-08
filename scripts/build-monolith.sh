#!/usr/bin/env bash
# 将 lib/ 内联到 install-naive-server.sh，生成 curl 安装可用的单文件发布版。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/install-naive-server.sh"
DIST_DIR="${ROOT}/dist"
OUT="${DIST_DIR}/install-naive-server.sh"

[[ -f "$SRC" ]] || { echo "[ERROR] 未找到 $SRC" >&2; exit 1; }
mkdir -p "$DIST_DIR"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# 复制主脚本，移除 source lib/ 块
awk '
  /^NAIVE_SCRIPT_DIR=/ { skip=1; next }
  skip && /^fi$/ { skip=0; next }
  skip { next }
  { print }
' "$SRC" > "$TMP"

# 构建内联库内容
INLINE="$(mktemp)"
{
  echo '# NAIVE_LIB_INLINE_START'
  for lib in common.sh encoding.sh links.sh validate.sh env.sh; do
    echo "# --- lib/${lib} ---"
    awk '!/^#!/ && $0 != "NAIVE_LIB_LOADED=1" { print }' "${ROOT}/lib/${lib}"
    echo
  done
  echo 'NAIVE_LIB_LOADED=1'
  echo '# NAIVE_LIB_INLINE_END'
} > "$INLINE"

# 在 set -euo pipefail 后插入内联库
awk -v inline="$INLINE" '
  { print }
  /^set -euo pipefail$/ {
    while ((getline line < inline) > 0) print line
    close(inline)
  }
' "$TMP" > "$OUT"

# 禁用主脚本中所有 lib fallback 块（log / encoding / env / validate）
sed -i 's/^if \[\[ -z "\${NAIVE_LIB_LOADED:-}" \]\]; then$/if false; then/g' "$OUT" 2>/dev/null \
  || sed -i '' 's/^if \[\[ -z "\${NAIVE_LIB_LOADED:-}" \]\]; then$/if false; then/g' "$OUT"

chmod +x "$OUT"
echo "[OK] $OUT"
echo "     校验: bash dist/install-naive-server.sh --version"
