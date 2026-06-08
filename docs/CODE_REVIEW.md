# NaiveProxy Server 代码审查报告

> 最后更新：v1.0.6（2026-06-08）

## 状态总览

| 类别 | v1.0.3 前 | v1.0.5 后 |
|------|-----------|-----------|
| 严重 BUG | 3 | **0** |
| 中等 BUG | 5 | **0** |
| 低优先级 | — | **0**（v1.0.6 终审已修复） |
| 孤立代码 | 6+ 函数 | **已清理 / 有意保留见下** |
| 内嵌 update 重复 | 370 行漂移风险 | **提取 `lib/update-core.sh` + sync 脚本** |
| env 明文/解析 | 无转义 | **`%q` 读写 + 向后兼容** |
| CI | 失败 | **全绿** |

## v1.0.6 终审修复

- 删除 `install-naive-server.sh` 内重复的 `generate_*_link`，统一调用 `lib/links.sh`
- `caddyfile_has_recommended_site` 校验所有绑定域名（含 `EXTRA_DOMAINS`）
- `vps-verify-checklist.sh` 从 `naive.env` 读取 `SERVICE_NAME`，避免硬编码 `caddy`
- `--extra-auth` 拒绝用户名含冒号

## 已修复项（v1.0.3 + v1.0.4）

### 严重

- `--extra-domain` 校验无效 → `validate_hostname()`
- 多域名 Caddyfile 结构误报 → 正则放宽
- 额外域名变更不重签 SAN 证书 → `should_issue_cert` 比较 `EXTRA_DOMAINS`

### 中等

- 多域名 HTTP 重定向缺失 → `http://${site_hosts}`
- `show_caddy_logs` 硬编码 `caddy.service` → `$SERVICE_NAME`
- purge 备份时间戳 → 操作时刻独立生成
- `--extra-auth` 密码含逗号 → 安装时拒绝
- `--enable-http3` 运维切换条件过严 → `naive_install_requested()`
- `read_env_value` 简单分割 → `lib/env.sh` `%q` + 裸转义 `eval` 兼容

### 优化

- 删除 `build_proxy_url`、`json_escape`、`yaml_double_quote`、`TIMESTAMP`
- `naive_all_domains` 委托 `build_all_domains_list`
- `service_exists` 统一为 `unit_exists` 包装
- 交互向导增加多域名/多账号
- `build-monolith.sh` 内联全部 lib 模块

## 有意保留（非 BUG）

| 项 | 说明 |
|----|------|
| `PASS` 存于 `naive.env` | Caddy `basic_auth` 需要明文；权限 `600` + `%q` |
| `USER` 作为 env 键名 | 历史兼容；主脚本用 `read_env_value`，update 脚本 `source` 后覆盖 shell `$USER` 影响有限 |
| 内嵌 `NAIVE_EMBEDDED_UPDATE_CORE` | curl 单文件 fallback；改 `lib/update-core.sh` 后跑 `sync-embedded-update-core.js` |
| fallback 块（`if NAIVE_LIB_LOADED`） | 单文件发布版由 `build-monolith.sh` 置 `if false` |
| `mask_secret` | 仅 Bats 测试 |
| `patch-update-script.js` | 一次性迁移工具，可保留在 `scripts/` |

## 模块结构

```
lib/
  common.sh      # 日志、mask_secret（测试）
  encoding.sh    # url_encode、caddyfile_quote、base64
  links.sh       # 客户端链接（生产环境唯一实现）
  validate.sh    # validate_hostname
  env.sh         # read_env_value、write_env_kv
  update-core.sh # update-caddy-naive 核心
```

## 维护清单

1. 修改 `lib/update-core.sh` → `node scripts/sync-embedded-update-core.js`
2. 发布前 → `bash scripts/build-monolith.sh`
3. 本地验证 → `bash scripts/verify-local.sh`
4. VPS 验证 → `sudo bash scripts/vps-verify-checklist.sh YOUR_DOMAIN`
