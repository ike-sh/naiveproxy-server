# NaiveProxy Server 代码审查报告

> 审查对象：`install-naive-server.sh` v1.0.1（3493 行）  
> 审查日期：2026-06-08

## 总体评价

脚本工程化程度较高：`set -euo pipefail`、备份回滚、sha256 校验、Caddyfile 先 validate 再覆盖、systemd 硬化配置（`ProtectSystem=full`、`NoNewPrivileges=true`）均体现生产意识。主要风险集中在**单文件体量过大**、**凭据明文存储**、**备份时间戳全局复用**三方面。

## 安全性

### 已做好的部分

| 项 | 说明 |
|----|------|
| 文件权限 | `naive.env` chmod 600；Caddyfile 640 root:caddy；证书私钥 600 |
| 备份目录 | `/var/backups/caddy-naive` chmod 700 |
| 凭据生成 | 默认 `openssl rand -hex 24` 强随机密码 |
| 用户名校验 | 仅允许 `A-Z a-z 0-9 _ - .` |
| 二进制完整性 | Release 资产强制 sha256 校验 |
| systemd 隔离 | caddy 以 `caddy` 用户运行，非 root |
| 彻底卸载 | 二次确认 + 输入 `DELETE` |

### 发现的问题与修复状态

| 严重度 | 问题 | 修复 |
|--------|------|------|
| 中 | `backup_file` 使用脚本启动时的全局 `TIMESTAMP`，同一次运行多次备份可能覆盖 | ✅ 改为每次备份独立时间戳 |
| 中 | `naive.env` 明文存储 `PASS` | ⚠️ 设计取舍（Caddy basic_auth 需要明文）；已文档化风险，建议限制文件 ACL |
| 低 | acme.sh 安装脚本从远程拉取无校验 | ✅ 增加 HTTPS 强制与安装后可执行性检查 |
| 低 | `proxy_self_test` 将认证信息传入 curl 命令行（/proc 可见） | 已知限制，仅本机诊断使用 |
| 信息 | `show_client_config` 明文输出密码 | 预期行为（用户需要配置客户端） |

### 建议后续改进

1. 考虑 `PASS` 使用 `secret-tool` 或独立权限文件，Caddyfile 生成时读取
2. `purge` 前备份 tar 应排除 `naive.env` 中的敏感字段或加密存储
3. 为 `write_update_script` 内嵌的 ~400 行重复代码提取共享库，减少漂移

## 健壮性

### 优点

- 端口占用检测（80/443）含 `/proc` 兜底
- Caddyfile 写入失败自动恢复备份
- 认证修改失败回滚 env + Caddyfile
- 证书申请失败恢复 Caddyfile 并重启服务
- 磁盘空间预检（< 300MB 拒绝）
- DNS 解析失败仅 warn 不阻断

### 风险点

| 项 | 说明 |
|----|------|
| 单文件 3493 行 | 维护成本高，已启动 `lib/` 拆分 |
| 更新脚本内嵌 | `write_update_script` 复制大量函数，与主脚本可能不同步 |
| `grep` 检测 Caddyfile 结构 | 正则匹配脆弱，复杂手工编辑可能误判 |
| 仅支持 Debian/Ubuntu | `require_supported_os` 明确限制，符合 README |

## 可维护性

### 函数统计

- 约 **156** 个函数/入口
- 主流程：`parse_args` → `main` → `run_install_flow` / `run_management_menu`
- 内嵌更新脚本：`write_update_script` 占 ~370 行

### 改进路线

1. ✅ `lib/` 提取纯函数（encoding、links、logging）
2. ✅ `tests/bats/` 覆盖可单测函数
3. ✅ GitHub Actions ShellCheck
4. 🔲 `build.sh` 合并 lib 为 curl 可用的单文件
5. 🔲 更新脚本改为 `source` 共享 lib

## 测试覆盖建议

| 优先级 | 场景 |
|--------|------|
| P0 | url_encode、caddyfile_quote、域名校验 |
| P0 | Caddyfile 推荐结构检测函数 |
| P1 | `--test-arch` 架构映射 |
| P1 | 客户端链接生成格式 |
| P2 | 完整安装流程（需 Docker CI） |

## 结论

脚本适合作为**个人/小团队 NaiveProxy 服务端一键部署工具**，安全基线良好。本次已修复备份时间戳与 acme 安装校验；模块化与 CI 测试已落地基础设施，建议下一版本完成 `build.sh` 单文件合并以兼顾 curl 安装与可维护性。
