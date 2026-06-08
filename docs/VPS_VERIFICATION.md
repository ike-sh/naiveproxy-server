# VPS 部署验证清单（10 项必检）

> v1.0.2 · 全新 Debian/Ubuntu VPS

## 安装命令

```bash
bash <(curl -fsSL https://github.com/ike-sh/naiveproxy-server/releases/download/v1.0.2/install-naive-server.sh) \
  --domain YOUR_DOMAIN \
  --email YOUR_EMAIL \
  --site-mode static \
  --cert-mode acme-standalone \
  --auto-update
```

## 必检清单

| # | 检查项 | 命令 | 通过标准 |
|---|--------|------|----------|
| 1 | DNS 解析 | `dig +short YOUR_DOMAIN` | 返回 VPS 公网 IP |
| 2 | 安装完成 | 安装脚本输出 | 显示客户端链接，无 ERROR |
| 3 | 服务状态 | `bash install-naive-server.sh --status` | Caddy **active**，forward_proxy 已检测 |
| 4 | Caddyfile 结构 | 同上 | `:443, DOMAIN` 推荐结构 **OK** |
| 5 | HTTPS 回落 | `curl -4I https://YOUR_DOMAIN` | HTTP/2 200 或 301 |
| 6 | 证书有效 | `--status` 中 openssl 输出 | 未过期，issuer 正常 |
| 7 | 代理自检 | `bash install-naive-server.sh --proxy-self-test` | Caddy active + forward_proxy OK |
| 8 | v2rayN 延迟 | 导入 Naive 节点（**UDP over TCP On**） | 有延迟数值 |
| 9 | v2rayN 连通 | 代理模式下访问外网 | 可正常上网 |
| 10 | 重启恢复 | `systemctl restart caddy && sleep 5 && curl -4I https://YOUR_DOMAIN` | HTTPS 恢复正常 |

## 客户端参数（第 8–9 项必看）

- 类型：**Naive**（v2rayN）/ **HTTP2**（Shadowrocket）
- **UDP over TCP：On**（必须）
- QUIC：Off
- SNI：你的域名
- 跳过证书验证：false

## 失败速查

| 现象 | 处理 |
|------|------|
| 能测延迟不能上网 | 确认 UDP over TCP 已开启 |
| 证书失败 | `--tls-diagnose`，检查 DNS / TCP 80 / Cloudflare 灰云 |
| 结构警告 | 重新运行菜单 `1. 一键安装 / 重新配置` |

**10 项全部通过 = 部署验证合格**
