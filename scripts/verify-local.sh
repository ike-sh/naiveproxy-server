#!/usr/bin/env bash
# 本地开发验证：ShellCheck + Bats（需在 Linux / WSL / Git Bash 环境运行）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Architecture mapping"
bash install-naive-server.sh --test-arch
NAIVE_TEST_UNAME_M=x86_64 bash install-naive-server.sh --test-arch | grep -q linux-amd64
NAIVE_TEST_UNAME_M=aarch64 bash install-naive-server.sh --test-arch | grep -q linux-arm64

if command -v shellcheck >/dev/null 2>&1; then
  echo "==> ShellCheck"
  shellcheck -x install-naive-server.sh lib/*.sh
else
  echo "[WARN] shellcheck 未安装，跳过"
fi

if command -v bats >/dev/null 2>&1; then
  echo "==> Bats"
  bats tests/bats/
else
  echo "[WARN] bats 未安装，跳过"
fi

echo "[OK] 本地验证完成"
