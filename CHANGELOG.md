# Changelog

All notable changes to [naiveproxy-server](https://github.com/ike-sh/naiveproxy-server) are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.4] - 2026-06-08

### Added

- `lib/env.sh`：`naive.env` 使用 bash `%q` 安全读写
- `lib/update-core.sh`：更新脚本核心逻辑独立模块，消除 370 行内嵌重复
- 交互向导支持额外域名 / 额外账号配置
- `tests/bats/env.bats` 环境文件读写测试
- `scripts/sync-embedded-update-core.js`：同步内嵌 update-core 到单文件发布版

### Changed

- `write_update_script` 优先 `cat lib/update-core.sh`，curl 单文件版内嵌 fallback
- `--enable-http3` / probe 切换：已安装环境下不再要求 CLI 不传 `--domain`
- 合并 `service_exists` → `unit_exists` 统一 systemd 检测
- `build-monolith.sh` 内联 `env.sh`

### Fixed

- 遗留审查项全部落地（env 转义、向导多域名、HTTP3 运维切换等）
- `update_env_release_sha` 改用 `%q` 写入，与 `write_env_file` 一致

## [1.0.3] - 2026-06-08

### Fixed

- `--extra-domain` 误调用 `validate_domain` 导致未校验额外域名、参数顺序敏感
- 多域名场景下 `caddyfile_has_recommended_site` 误报结构异常
- 额外域名变更后 `should_issue_cert` 未触发 SAN 证书重签
- 多域名 HTTP→HTTPS 重定向仅覆盖主域名
- `show_caddy_logs` 硬编码 `caddy.service` 忽略自定义 `SERVICE_NAME`
- `purge` 备份使用脚本启动时间戳而非操作时刻
- `--extra-auth` 密码含逗号时解析错误（现明确拒绝）

### Removed

- 孤立函数：`build_proxy_url`、`json_escape`、`yaml_double_quote`
- 未使用的全局变量 `TIMESTAMP`

## [1.0.2] - 2026-06-08

### Added

- `--extra-domain`：额外绑定域名，可重复指定，共享同一代理实例
- `--extra-auth USER:PASS`：额外 Basic Auth 账号，可重复指定
- `lib/` 模块化：`common.sh`、`encoding.sh`、`links.sh`
- Bats 单元测试（`tests/bats/`）
- GitHub Actions CI：ShellCheck、Bats、架构映射检测
- GitHub Actions Release：打 tag 自动构建 `dist/install-naive-server.sh` 并发布
- `DEPLOY.md` 部署指南
- `docs/ARCHITECTURE.md` 架构与流程图
- `docs/CODE_REVIEW.md` 代码审查报告
- `scripts/build-monolith.sh` 单文件合并构建脚本
- `scripts/verify-local.sh` 本地验证脚本

### Changed

- 版本号升至 1.0.2
- Caddyfile 站点块支持 `:443, DOMAIN extra1 extra2` 多域名格式
- `acme-standalone` 证书申请支持 SAN（多 `-d` 参数）
- `naive.env` 新增 `EXTRA_DOMAINS`、`EXTRA_AUTH` 字段
- 状态/客户端配置输出显示额外域名信息

### Fixed

- `backup_file` 每次备份使用独立时间戳，避免同次运行覆盖
- acme.sh 安装：强制 HTTPS、临时文件权限、shebang 格式校验

### Release Assets

- [v1.0.2 install-naive-server.sh](https://github.com/ike-sh/naiveproxy-server/releases/download/v1.0.2/install-naive-server.sh)（curl 单文件安装）

## [1.0.1] - 2026-06-07

### Added

- `linux-arm64` 架构支持（`aarch64` / `arm64`）
- arm64 Builder Release 资产检测与友好报错

## [1.0.0] - 2026-06-06

### Added

- 初始稳定版发布
- 一键安装 / 交互式管理菜单
- 三种证书模式：`acme-standalone`、`caddy-auto`、`caddy-zerossl`
- 静态站 / 反代回落模式
- Caddy naive 内核自动更新
- 代理核心自检、SSL 诊断、认证管理
- HTTP3 开关、probe_resistance 控制

[1.0.4]: https://github.com/ike-sh/naiveproxy-server/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/ike-sh/naiveproxy-server/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/ike-sh/naiveproxy-server/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/ike-sh/naiveproxy-server/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/ike-sh/naiveproxy-server/releases/tag/v1.0.0
