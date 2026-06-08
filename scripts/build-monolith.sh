#!/usr/bin/env bash
# 将 lib/ 内联到 install-naive-server.sh，生成 curl 安装可用的单文件发布版。
# 开发时在仓库根目录直接运行 install-naive-server.sh（自动 source lib/）。
# 发布前运行本脚本，输出 dist/install-naive-server.sh。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/install-naive-server.sh"
DIST_DIR="${ROOT}/dist"
OUT="${DIST_DIR}/install-naive-server.sh"
MARKER_START='# NAIVE_LIB_INLINE_START'
MARKER_END='# NAIVE_LIB_INLINE_END'

[[ -f "$SRC" ]] || { echo "[ERROR] 未找到 $SRC" >&2; exit 1; }

mkdir -p "$DIST_DIR"

python3 - "$SRC" "$OUT" "$ROOT" "$MARKER_START" "$MARKER_END" <<'PY'
import sys
from pathlib import Path

src_path, out_path, root, start_marker, end_marker = sys.argv[1:6]
root = Path(root)
src = Path(src_path).read_text(encoding="utf-8")

libs = []
for name in ("common.sh", "encoding.sh", "links.sh"):
    p = root / "lib" / name
    if not p.exists():
        print(f"[ERROR] missing {p}", file=sys.stderr)
        sys.exit(1)
    body = p.read_text(encoding="utf-8")
    body = "\n".join(
        line for line in body.splitlines()
        if not line.strip().startswith("#!/") and line.strip() != "NAIVE_LIB_LOADED=1"
    )
    libs.append(f"# --- lib/{name} ---\n{body.strip()}\n")

inline_block = start_marker + "\n" + "\n".join(libs) + end_marker + "\n"

# 移除运行时 source lib/ 块（发布版不需要外部 lib 目录）
import re
src = re.sub(
    r'NAIVE_SCRIPT_DIR="\$\(_naive_resolve_script_dir\)"\n'
    r'if \[\[ -n "\$NAIVE_SCRIPT_DIR" && -d "\$NAIVE_SCRIPT_DIR/lib" \]\]; then\n'
    r'(?:.*\n)*?'
    r'fi\n\n',
    '',
    src,
    count=1,
)

# 在 set -euo pipefail 之后插入内联库
needle = "set -euo pipefail\n"
if needle not in src:
    print("[ERROR] cannot find set -euo pipefail", file=sys.stderr)
    sys.exit(1)
src = src.replace(needle, needle + "\n" + inline_block, 1)

# 发布版始终定义 NAIVE_LIB_LOADED，跳过主脚本中的 fallback 块
src = src.replace(
    'if [[ -z "${NAIVE_LIB_LOADED:-}" ]]; then\nlog_info()',
    'NAIVE_LIB_LOADED=1\nif false; then\nlog_info()',
    1,
)

Path(out_path).write_text(src, encoding="utf-8")
print(f"[OK] wrote {out_path}")
PY

chmod +x "$OUT"
echo "[OK] dist/install-naive-server.sh 已生成（curl 发布用）"
echo "     校验: bash dist/install-naive-server.sh --version"
