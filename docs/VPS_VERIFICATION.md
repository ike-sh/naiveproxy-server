# VPS 部署验证清单（10 项必检）

[![CI](https://github.com/ike-sh/naiveproxy-server/actions/workflows/ci.yml/badge.svg)](https://github.com/ike-sh/naiveproxy-server/actions/workflows/ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/ike-sh/naiveproxy-server?label=stable)](https://github.com/ike-sh/naiveproxy-server/releases/latest)

> 当前推荐版本：**[v1.0.5](https://github.com/ike-sh/naiveproxy-server/releases/tag/v1.0.5)** · 适用全新 Debian/Ubuntu VPS

## 安装命令

```bash
curl -fsSL https://github.com/ike-sh/naiveproxy-server/releases/download/v1.0.5/install-naive-server.sh | sudo bash -s -- \
  --domain YOUR_DOMAIN \
  --email YOUR_EMAIL \
  --site-mode static \
  --cert-mode acme-standalone \
  --auto-update
```

安装完成后保存客户端链接：

```bash
bash install-naive-server.sh --show-client
```

## 半自动验证脚本（推荐）

在 VPS 上以 **root** 运行（已克隆仓库时）：

```bash
sudo bash scripts/vps-verify-checklist.sh YOUR_DOMAIN
```

未克隆仓库时，可先下载脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/scripts/vps-verify-checklist.sh \
  | sudo bash -s -- YOUR_DOMAIN
```

脚本自动覆盖 **#1 #3 #5 #7 #10** 及部分 **#4 #6**；**#2 #8 #9** 仍需人工确认。

## 必检清单

| # | 检查项 | 命令 | 通过标准 |
|---|--------|------|----------|
| 1 | DNS 解析 | `dig +short YOUR_DOMAIN` | 返回 VPS 公网 IP |
| 2 | 安装完成 | 安装脚本输出 / `--show-client` | 显示客户端链接，无 ERROR |
| 3 | 服务状态 | `bash install-naive-server.sh --status` | Caddy **active**，forward_proxy 已检测 |
| 4 | Caddyfile 结构 | 同上 | `:443, DOMAIN` 推荐结构 **OK** |
| 5 | HTTPS 回落 | `curl -4I https://YOUR_DOMAIN` | HTTP/2 200 或 301 |
| 6 | 证书有效 | `--status` / `--proxy-self-test` 中 openssl | 未过期，issuer 正常 |
| 7 | 代理自检 | `bash install-naive-server.sh --proxy-self-test` | Caddy active + forward_proxy OK |
| 8 | v2rayN 延迟 | 导入 Naive 节点（**UDP over TCP On**） | 有延迟数值 |
| 9 | v2rayN 连通 | 代理模式下访问外网 | 可正常上网 |
| 10 | 重启恢复 | `systemctl restart caddy && sleep 5 && curl -4I https://YOUR_DOMAIN` | HTTPS 恢复正常 |

## 逐项操作指引

### #1 DNS

```bash
dig +short YOUR_DOMAIN
curl -4 https://api.ipify.org   # 对比 VPS 公网 IP
```

Cloudflare 记录须为**灰云**（仅 DNS），否则 ACME 与直连探测可能失败。

### #3–#4 状态与结构

```bash
bash install-naive-server.sh --status
```

关注：`active (running)`、`forward_proxy`、`推荐 NaiveProxy 结构` 无 WARN。

### #5 HTTPS

```bash
curl -4I https://YOUR_DOMAIN
```

期望首行含 `HTTP/2 200` 或 `301`。

### #7 代理自检

```bash
bash install-naive-server.sh --proxy-self-test
```

若 curl 支持 `--proxy-http2`，脚本会尝试本机 HTTP2 代理探测。

### #8–#9 客户端（必做）

| 参数 | 值 |
|------|-----|
| 类型 | Naive（v2rayN）/ HTTP2（Shadowrocket） |
| UDP over TCP | **On**（必须） |
| QUIC | Off |
| SNI | 你的域名 |
| 跳过证书验证 | false |

### #10 重启

```bash
systemctl restart caddy    # 或自定义 SERVICE_NAME
sleep 5
curl -4I https://YOUR_DOMAIN
```

## 失败速查

| 现象 | 处理 |
|------|------|
| 能测延迟不能上网 | 确认 UDP over TCP 已开启 |
| 证书失败 | `--tls-diagnose`，检查 DNS / TCP 80 / Cloudflare 灰云 |
| 结构警告 | 菜单 `1. 一键安装 / 重新配置` |
| env 密码含特殊字符乱码 | 升级至 v1.0.5+（`%q` 读写修复） |

**10 项全部通过 = 部署验证合格**
