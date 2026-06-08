# NaiveProxy Server 1.0.2

作者：ike-sh  
GitHub：https://github.com/ike-sh/naiveproxy-server  
Builder 仓库：https://github.com/ike-sh/caddy-naive-builder

这是一个面向 Debian/Ubuntu `linux-amd64` / `linux-arm64` 服务器的 NaiveProxy 服务端一键管理脚本。脚本会根据 `uname -m` 自动选择 Builder Release 里的 Caddy naive 二进制，不安装 Go，不安装 xcaddy，也不在服务器本地编译 Caddy。

**文档**：详细部署见 [DEPLOY.md](DEPLOY.md)，架构说明见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## v1.0.2 更新

- 支持 `--extra-domain` / `--extra-auth` 多域名与多账号
- `lib/` 模块化拆分，配套 Bats 单元测试与 GitHub Actions CI
- 备份时间戳独立生成，acme.sh 安装增加 HTTPS 与格式校验

当前支持的 Release 资产：

- `caddy-naive-linux-amd64.tar.gz`
- `caddy-naive-linux-amd64.tar.gz.sha256`
- `caddy-naive-linux-arm64.tar.gz`
- `caddy-naive-linux-arm64.tar.gz.sha256`

架构映射：

- `x86_64` / `amd64` -> `linux-amd64`
- `aarch64` / `arm64` -> `linux-arm64`

## 推荐安装

无参数且在终端中运行时会进入主菜单：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh)
```

如果系统没有 `curl`：

```bash
apt update && apt install -y curl
```

也可以使用 `wget`：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh)
```

显式进入主菜单：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh) --menu
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh) --interactive
```

`--interactive` / `-i` 也是进入主菜单。只有在主菜单选择 `1. 一键安装 / 重新配置` 后，才会进入安装向导。菜单项执行失败会显示错误并返回菜单，不会直接退出到 shell。

## 主菜单

```text
NaiveProxy Server 管理菜单
-------------------------------------------------
1. 一键安装 / 重新配置
2. 查看当前状态
3. 检测更新
4. 更新 Caddy naive 内核
5. 自动更新管理
6. 卸载服务，保留配置
7. 完全卸载所有文件
8. 查看当前配置 / 客户端链接
9. 查看运行日志
10. 回落网站说明 / 配置位置
11. SSL / 证书诊断
12. 重新申请本地证书 acme.sh
13. 认证信息管理
14. HTTP3 开启 / 关闭
15. 代理核心自检
16. 修复静态站权限
0. 退出
```

## 无人值守安装

推荐证书模式是 `acme-standalone`：

```bash
bash install-naive-server.sh \
  --domain example.com \
  --email me@example.com \
  --site-mode static \
  --cert-mode acme-standalone \
  --auto-update
```

反代模式：

```bash
bash install-naive-server.sh \
  --domain example.com \
  --email me@example.com \
  --site-mode reverse \
  --upstream https://www.example.org \
  --cert-mode acme-standalone
```

带完整参数时会直接无人值守安装，不进入菜单。管道 / 非 TTY 场景无参数运行会显示 usage 并非 0 退出。

### 多域名 / 多账号

```bash
bash install-naive-server.sh \
  --domain proxy.example.com \
  --extra-domain www.proxy.example.com \
  --extra-auth friend:SecurePass123 \
  --email me@example.com \
  --cert-mode acme-standalone
```

每个额外域名需有有效 DNS 记录；`acme-standalone` 会为所有域名申请 SAN 证书。

## 证书模式

```bash
--cert-mode caddy-auto|caddy-zerossl|acme-standalone
```

- `acme-standalone`：默认推荐。先用 `acme.sh + ZeroSSL standalone` 签发证书，再让 Caddy 使用本地证书文件，稳定性最好。
- `caddy-auto`：Caddy 自动申请证书，最简单，但部分机器访问 Let's Encrypt / ZeroSSL 可能超时。
- `caddy-zerossl`：Caddy 强制 ZeroSSL。

本地证书路径：

```text
/etc/caddy/certs/DOMAIN/fullchain.pem
/etc/caddy/certs/DOMAIN/privkey.pem
```

安装 / 重新配置时，如果域名没变且本地证书存在、非空、未过期并且剩余有效期大于 15 天，脚本会复用现有证书，不会频繁重新签发。

重新签发本地证书：

```bash
bash install-naive-server.sh --issue-cert
```

证书诊断：

```bash
bash install-naive-server.sh --tls-diagnose
```

## 推荐 Caddyfile 结构

脚本会固定生成推荐 NaiveProxy 结构：

- `:443, DOMAIN`
- `:443` 必须在 `DOMAIN` 前面
- `forward_proxy` 必须在 `route` 内，且位于 `file_server` / `reverse_proxy` 前
- `probe_resistance` 默认开启
- 不默认写入访问日志，避免记录代理访问细节

HTTP3 默认关闭时，全局块包含：

```caddyfile
servers {
  protocols h1 h2
}
```

开启 HTTP3 后包含：

```caddyfile
servers {
  protocols h1 h2 h3
}
```

静态站结构示例：

```caddyfile
:443, example.com {
  encode zstd gzip

  route {
    forward_proxy {
      basic_auth "USER" "PASS"
      hide_ip
      hide_via
      probe_resistance
    }

    root * /var/www/naive
    file_server
  }
}
```

## 客户端配置

安装成功后不会在 `/root` 生成客户端配置文件。脚本只会即时输出当前配置和两个链接，也可以随时查看：

```bash
bash install-naive-server.sh --show-client
```

输出内容包含：

```text
当前服务端配置：
  地址：docs.example.com
  端口：443
  用户名：user
  密码：pass
  UDP over TCP：On（必须开启）
  TLS：tls
  SNI：docs.example.com
  跳过证书验证：false
  HTTP3：off
  probe_resistance：on
```

v2rayN / sing-box 链接格式：

```text
naive+https://USER:PASS@DOMAIN:443?security=tls&sni=DOMAIN&insecure=0&allowInsecure=0&type=tcp&headerType=none#NAME
```

Shadowrocket / 小火箭链接格式：

```text
http2://BASE64(USER:PASS@DOMAIN:443)?peer=DOMAIN&uot=1#n2
```

Shadowrocket 链接必须包含 `uot=1`。Base64 原文是 `USER:PASS@DOMAIN:443`，不换行，可以去掉末尾的 `=`。

## 客户端重点

v2rayN / sing-box：

- 类型：Naive
- UDP over TCP：On（必须开启）
- QUIC：Off
- TLS：tls
- SNI：填写域名
- 跳过证书验证：false
- ALPN：不需要填写

Shadowrocket：

- 类型选择 HTTP2
- UDP over TCP 开启
- 分享链接必须包含 `uot=1`

如果能测延迟但无法使用，优先检查 UDP over TCP 是否开启。

## HTTP3

HTTP3 默认关闭，推荐主路径是 HTTP2 + UDP over TCP。

开启：

```bash
bash install-naive-server.sh --enable-http3
```

关闭：

```bash
bash install-naive-server.sh --disable-http3
```

HTTP3 需要云安全组和系统防火墙放行 UDP 443，客户端也要明确选择 HTTP3/QUIC 才会使用。HTTP3 关闭时，UDP 443 未监听是正常状态。

## 认证管理

菜单方式：

```bash
bash install-naive-server.sh
```

选择：

```text
13. 认证信息管理
```

CLI：

```bash
bash install-naive-server.sh --change-user
bash install-naive-server.sh --change-pass
bash install-naive-server.sh --set-user newuser
bash install-naive-server.sh --set-pass newpass
bash install-naive-server.sh --set-user newuser --set-pass newpass
```

用户名只允许 `A-Z a-z 0-9 _ - .`。修改用户名 / 密码会备份 `/etc/caddy/naive.env` 和 `/etc/caddy/Caddyfile`，重新生成 Caddyfile，执行 validate，并重启 Caddy。失败时会恢复备份。`/etc/caddy/naive.env` 权限保持 `chmod 600`。

## 诊断

查看状态：

```bash
bash install-naive-server.sh --status
```

代理核心自检：

```bash
bash install-naive-server.sh --proxy-self-test
```

代理自检会检查 Caddy 服务、HTTPS、`forward_proxy` 模块、证书信息、推荐 Caddyfile 结构，并在 curl 支持 `--proxy-http2` 时尝试 HTTP2 proxy 探测。普通 `curl --proxy` 可能走 HTTP/1.1 CONNECT，只能验证 TLS/认证/CONNECT，不代表 NaiveProxy 客户端最终可用。

临时关闭 `probe_resistance` 仅建议用于诊断，排查完成后请重新开启：

```bash
bash install-naive-server.sh --no-probe-resistance
bash install-naive-server.sh --enable-probe-resistance
```

不建议默认启用 ASN/IP 黑洞，容易误伤正常用户。

## 回落网站

`static`：本地静态 HTML，最稳定。

```text
Caddyfile: /etc/caddy/Caddyfile
Install env: /etc/caddy/naive.env
Static web root: /var/www/naive
Static index: /var/www/naive/index.html
Cert dir: /etc/caddy/certs/DOMAIN
```

手动上传 HTML/CSS/JS/图片后建议执行：

```bash
chown -R caddy:caddy /var/www/naive
find /var/www/naive -type d -exec chmod 755 {} \;
find /var/www/naive -type f -exec chmod 644 {} \;
caddy validate --config /etc/caddy/Caddyfile
systemctl restart caddy
```

也可以在菜单选择：

```text
16. 修复静态站权限
```

`reverse`：反代其他正常网站，更像真实站点，但第三方站可能受 CSP、Cookie、跳转、Host 校验和合规影响。建议只反代自己有权使用的网站或普通公开静态站。

## 更新 Caddy Naive 内核

手动更新：

```bash
update-caddy-naive
```

或：

```bash
bash install-naive-server.sh --update
bash install-naive-server.sh --force-update
```

更新脚本只会下载 latest Caddy naive 二进制、校验 sha256、备份旧二进制、替换二进制、检查 `forward_proxy` 模块、validate 当前 Caddyfile，并 `systemctl restart caddy`。

它不会覆盖：

- `/etc/caddy/Caddyfile`
- `/etc/caddy/certs`

它不会重写整份 `/etc/caddy/naive.env` 或改变服务端账号、证书、站点模式等业务配置。更新成功后只会刷新 `naive.env` 中的：

- `BUILDER_RELEASE_TAG`
- `BUILDER_RELEASE_ARCH`
- `BUILDER_RELEASE_ASSET`
- `BUILDER_RELEASE_SHA256`
- `BUILDER_RELEASE_URL`
- `UPDATED_AT`

检测更新不会只比较 `caddy version`。脚本会根据当前 `uname -m` 选择对应资产，比较 Builder Release tag 和 latest 资产 sha256；即使 Caddy 版本号不变，只要 Builder Release 产物更新，也能检测到。

## 卸载

卸载服务，保留配置：

```bash
bash install-naive-server.sh --uninstall
```

完全卸载所有文件：

```bash
bash install-naive-server.sh --purge
```

完全卸载会二次确认，并删除服务、timer、更新脚本、Caddy 二进制、`/etc/caddy`、`/var/www/naive`、`/var/lib/caddy` 和备份目录。

## 故障排查

能测延迟但无法使用：

- UDP over TCP 是否开启。
- QUIC 是否关闭。
- Caddyfile 是否是 `:443, DOMAIN` 推荐结构。
- 是否误用普通 HTTPS / HTTP1 配置。
- 是否使用 IPv6 DNS 导致 unreachable。
- SNI 是否为域名。
- 跳过证书验证是否为 false。

SSL 失败：

- 运行 `bash install-naive-server.sh --tls-diagnose`。
- 运行 `bash install-naive-server.sh --issue-cert`。
- 检查 TCP 80/443 是否被占用。
- 检查 DNS A/AAAA 是否指向本机。
- 如果使用 Cloudflare，请确认记录是仅 DNS，不要开启代理云朵。
- 检查系统时间是否正确。

Caddyfile validate 失败：

- 检查 `/etc/caddy/Caddyfile`。
- 确认 Caddy 二进制包含 `forward_proxy` 模块。
- 重新运行菜单 `1. 一键安装 / 重新配置`。

Release 下载失败：

- 检查服务器是否可以访问 GitHub。
- 检查 Builder 仓库是否存在当前架构对应资产名。

arm64 下载 404：

- 先检查 https://github.com/ike-sh/caddy-naive-builder/releases/latest
- 确认是否存在 `caddy-naive-linux-arm64.tar.gz`。
- 确认是否存在 `caddy-naive-linux-arm64.tar.gz.sha256`。
- 如果不存在，需要先触发 caddy-naive-builder 的 GitHub Actions `force_rebuild`。

磁盘不足：

```bash
df -h
apt clean
rm -rf /var/lib/apt/lists/*
journalctl --vacuum-size=100M
```

## 限制

- 支持 `linux-amd64` 和 `linux-arm64`。
- 其他架构会明确报错退出，并显示检测到的 `uname -m`。
- 不安装 Go，不安装 xcaddy，不在服务器本地编译 Caddy。
- 不关闭系统防火墙。
- 不自动修改 nginx/apache。
