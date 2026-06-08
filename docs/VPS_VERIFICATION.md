# VPS 部署验证清单

> 适用于 v1.0.2，在全新 Debian/Ubuntu VPS 上验证安装与代理可用性。

## 前置检查

| # | 检查项 | 命令 / 方法 | 预期 |
|---|--------|-------------|------|
| 1 | 系统架构 | `uname -m` | `x86_64` 或 `aarch64` |
| 2 | root 权限 | `id -u` | `0` |
| 3 | 磁盘空间 | `df -h /` | 可用 ≥ 1GB |
| 4 | 系统时间 | `timedatectl` | 同步正确 |
| 5 | DNS A 记录 | `dig +short YOUR_DOMAIN` | 返回 VPS 公网 IP |
| 6 | TCP 80 可达 | 外部 `curl -I http://YOUR_DOMAIN` | 可连接（安装前可能 000） |
| 7 | TCP 443 可达 | 外部 `nc -zv YOUR_DOMAIN 443` | 端口开放 |
| 8 | Cloudflare | 控制台 DNS | 仅 DNS，灰云关闭 |

## 安装验证

### 方式 A：Release 单文件（推荐）

```bash
bash <(curl -fsSL https://github.com/ike-sh/naiveproxy-server/releases/download/v1.0.2/install-naive-server.sh) \
  --domain YOUR_DOMAIN \
  --email YOUR_EMAIL \
  --site-mode static \
  --cert-mode acme-standalone \
  --auto-update
```

### 方式 B：多域名

```bash
bash <(curl -fsSL https://github.com/ike-sh/naiveproxy-server/releases/download/v1.0.2/install-naive-server.sh) \
  --domain proxy.example.com \
  --extra-domain www.proxy.example.com \
  --email YOUR_EMAIL \
  --cert-mode acme-standalone
```

### 安装后检查

| # | 检查项 | 命令 | 预期 |
|---|--------|------|------|
| 9 | 脚本版本 | `bash install-naive-server.sh --version` | `1.0.2` |
| 10 | 服务状态 | `bash install-naive-server.sh --status` | Caddy active，forward_proxy 已检测 |
| 11 | Caddyfile 结构 | 同上输出 | `:443, DOMAIN` 推荐结构 OK |
| 12 | 证书有效 | 同上 openssl 输出 | 未过期 |
| 13 | HTTPS 回落站 | `curl -4I https://YOUR_DOMAIN` | `HTTP/2 200` 或 `301` |
| 14 | 端口监听 | `ss -lntp \| grep -E ':80\|:443'` | caddy 监听 80/443 |
| 15 | env 权限 | `ls -la /etc/caddy/naive.env` | `-rw-------` (600) |

## 代理功能验证

| # | 检查项 | 命令 / 操作 | 预期 |
|---|--------|-------------|------|
| 16 | 代理自检 | `bash install-naive-server.sh --proxy-self-test` | Caddy active，forward_proxy OK |
| 17 | 客户端链接 | `bash install-naive-server.sh --show-client` | 输出 v2rayN + Shadowrocket 链接 |
| 18 | v2rayN 延迟 | 导入 Naive 节点，测延迟 | 有延迟数值 |
| 19 | v2rayN 连通 | 开启 UDP over TCP，访问网站 | 可正常上网 |
| 20 | Shadowrocket | HTTP2 类型 + uot=1 | 可正常上网 |

### v2rayN / sing-box 必检参数

- [ ] 类型：**Naive**（非 HTTP/SOCKS）
- [ ] UDP over TCP：**On**
- [ ] QUIC：**Off**
- [ ] SNI：填写域名
- [ ] 跳过证书验证：**false**

## 故障场景回归

| # | 场景 | 验证方法 | 预期 |
|---|------|----------|------|
| 21 | 认证修改 | `--set-user test --set-pass test1234` | 服务重启，新凭据可用 |
| 22 | 内核更新检测 | `--check-update` | 正常输出，无报错 |
| 23 | 日志查看 | `--logs` | journalctl 有 caddy 输出 |
| 24 | TLS 诊断 | `--tls-diagnose` | 证书链信息正常 |
| 25 | 静态站权限 | `--fix-static-perms` | 无报错，服务重启 |

## 性能与稳定性（可选）

| # | 检查项 | 方法 | 参考 |
|---|--------|------|------|
| 26 | 内存占用 | `ps aux \| grep caddy` | 通常 < 100MB |
| 27 | 重启恢复 | `systemctl restart caddy` | 30s 内恢复 HTTPS |
| 28 | 开机自启 | `systemctl is-enabled caddy` | `enabled` |
| 29 | 自动更新 timer | `systemctl is-enabled caddy-naive-update.timer` | `enabled`（若安装时开启） |
| 30 | 长时间运行 | 运行 24h 后 `--proxy-self-test` | 仍全部 OK |

## 常见问题速查

| 现象 | 排查 |
|------|------|
| 能测延迟不能上网 | 检查 UDP over TCP、客户端类型 Naive/HTTP2 |
| 证书申请失败 | `--tls-diagnose`，确认 80 端口、DNS、Cloudflare 灰云 |
| Caddyfile 结构警告 | 重新运行菜单 `1. 一键安装 / 重新配置` |
| arm64 下载 404 | 检查 caddy-naive-builder Release 是否有 arm64 资产 |

## 验证完成标准

全部必检项（#1–#20）通过，即可认为 v1.0.2 VPS 部署验证合格。
