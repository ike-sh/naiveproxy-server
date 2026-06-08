# NaiveProxy Server 代码审查报告

> 最后更新：v1.0.4（2026-06-08）

## 状态总览

| 类别 | v1.0.3 前 | v1.0.4 后 |
|------|-----------|-----------|
| 严重 BUG | 3 | **0**（已修复） |
| 中等 BUG | 5 | **0**（已修复） |
| 孤立代码 | 6+ 函数 | **已清理** |
| 内嵌 update 重复 | 370 行漂移风险 | **提取 `lib/update-core.sh`** |
| env 明文/解析 | 无转义 | **`%q` 读写 + 向后兼容** |

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
- `read_env_value` 简单分割 → `lib/env.sh` `%q` + 旧格式兼容

### 优化

- 删除 `build_proxy_url`、`json_escape`、`yaml_double_quote`、`TIMESTAMP`
- `naive_all_domains` 委托 `build_all_domains_list`
- `service_exists` 统一为 `unit_exists` 包装
- 交互向导增加多域名/多账号提示
- `build-monolith.sh` 内联全部 lib 模块

## 剩余设计取舍（非 BUG）

| 项 | 说明 |
|----|------|
| `PASS` 存于 `naive.env` | Caddy `basic_auth` 需要明文；文件权限 `600`，`%q` 防止特殊字符破坏格式 |
| update 脚本 `load_env_defaults` 仍 `source` env | 与 `%q` 格式兼容；`update_env_release_sha` 已改用 `%q` |
| 内嵌 `NAIVE_EMBEDDED_UPDATE_CORE` | curl 单文件版 fallback；修改后需 `sync-embedded-update-core.js` |
| `mask_secret` | 仅 Bats 测试使用 |

## 模块结构（v1.0.4）

```
lib/
  common.sh      # 日志、mask_secret（测试）
  encoding.sh    # url_encode、caddyfile_quote、base64
  links.sh       # 客户端链接生成（测试）+ build_all_domains_list
  validate.sh    # validate_hostname
  env.sh         # read_env_value、write_env_kv
  update-core.sh # update-caddy-naive 核心（单一维护点）
```

## 维护清单

1. 修改 `lib/update-core.sh` → 运行 `node scripts/sync-embedded-update-core.js`
2. 发布前 → `bash scripts/build-monolith.sh`
3. 本地验证 → `bash scripts/verify-local.sh`
