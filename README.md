# NaiveProxy Server

作者：ike-sh  
GitHub：https://github.com/ike-sh/naiveproxy-server  
Builder 仓库：https://github.com/ike-sh/caddy-naive-builder

这是一个 Debian/Ubuntu `linux-amd64` 服务器上的 NaiveProxy 服务端一键管理脚本。脚本直接下载 Builder Release 里的 Caddy naive 二进制，不安装 Go，不安装 xcaddy，也不在服务器本地编译 Caddy。

Release 资产名称固定为：

- `caddy-naive-linux-amd64.tar.gz`
- `caddy-naive-linux-amd64.tar.gz.sha256`

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
```

兼容交互参数：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh) --interactive
```

`--interactive` / `-i` 现在也是进入主菜单。只有在主菜单选择 `1. 一键安装 / 重新配置` 后，才会进入安装配置向导。菜单项执行失败会显示错误并返回菜单，不会直接退出到 shell。

## 主菜单

```text
NaiveProxy Server 管理菜单
作者：ike-sh
GitHub：https://github.com/ike-sh/naiveproxy-server
Builder：https://github.com/ike-sh/caddy-naive-builder
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

推荐证书模式是 `acme-standalone`：先使用 `acme.sh + ZeroSSL standalone` 签发证书，再让 Caddy 使用本地证书文件，稳定性最好。

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

## 证书模式

```bash
--cert-mode caddy-auto|caddy-zerossl|acme-standalone
```

- `caddy-auto`：Caddy 自动申请证书，最简单，但部分机器访问 Let's Encrypt / ZeroSSL 可能超时。
- `caddy-zerossl`：Caddy 强制 ZeroSSL。
- `acme-standalone`：推荐默认模式，先用 `acme.sh + ZeroSSL standalone` 签发证书，再写入本地证书 Caddyfile。

本地证书路径：

```text
/etc/caddy/certs/DOMAIN/fullchain.pem
/etc/caddy/certs/DOMAIN/privkey.pem
```

如果出现 `ERR_SSL_PROTOCOL_ERROR`，优先运行：

```bash
bash install-naive-server.sh --tls-diagnose
bash install-naive-server.sh --issue-cert
```

安装 / 重新配置时，如果域名没变且本地证书存在、非空、未过期并且剩余有效期大于 15 天，脚本会复用现有证书，不会频繁重新签发。

## 推荐 Caddyfile 结构

脚本会生成推荐 NaiveProxy 结构：

- `:443, DOMAIN`
- `:443` 必须在 `DOMAIN` 前面
- `forward_proxy` 在 `route` 内，且位于 `file_server` / `reverse_proxy` 前
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

站点块会使用 `:443, DOMAIN`，并把 `forward_proxy` 放在 `route` 内：

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

安装成功后不会在 `/root` 生成客户端配置文件。脚本会直接输出：

- 当前服务端配置
- v2rayN / sing-box 链接
- Shadowrocket / 小火箭链接

查看当前配置：

```bash
bash install-naive-server.sh --show-client
```

或在主菜单选择：

```text
8. 查看当前配置 / 客户端链接
```

输出示例：

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

NaiveProxy 没有像 VLESS 那样统一的 `vless://` 分享标准。这里输出的是 Naive HTTPS 代理地址和 Shadowrocket HTTP2 分享链接。

## 客户端重点

v2rayN / sing-box：

- 类型：Naive
- UDP over TCP：On（必须开启）
- QUIC：Off
- TLS：tls
- SNI：填域名
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

修改用户名 / 密码会备份 `/etc/caddy/naive.env` 和 `/etc/caddy/Caddyfile`，重新生成 Caddyfile，执行 validate，并重启 Caddy。失败时会恢复备份。

## 回落网站

`static`：本地静态 HTML，最稳定。

```text
网站目录：/var/www/naive
首页文件：/var/www/naive/index.html
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

## 更新内核

手动更新：

```bash
update-caddy-naive
```

或：

```bash
bash install-naive-server.sh --update
bash install-naive-server.sh --force-update
```

更新脚本只替换 Caddy naive 二进制、校验模块、validate 当前 Caddyfile，并重启 Caddy。它不会覆盖 Caddyfile，不会重写证书，不会生成客户端配置文件。

检测更新不会只比较 `caddy version`。脚本会比较 Builder Release tag 和 latest 资产 sha256；即使 Caddy 版本号不变，只要 Builder Release 产物更新，也能检测到。

## 状态与诊断

查看状态：

```bash
bash install-naive-server.sh --status
systemctl status caddy
journalctl -u caddy -e --no-pager
```

代理核心自检：

```bash
bash install-naive-server.sh --proxy-self-test
```

临时关闭 `probe_resistance` 仅建议用于诊断，排查后请重新开启：

```bash
bash install-naive-server.sh --no-probe-resistance
bash install-naive-server.sh --enable-probe-resistance
```

SSL / 证书诊断：

```bash
bash install-naive-server.sh --tls-diagnose
```

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

## 常见问题

证书申请失败：

- 确认域名 A/AAAA 记录指向本机。
- 确认云安全组放行 TCP 80/443。
- 优先使用 `--cert-mode acme-standalone`。
- 运行 `bash install-naive-server.sh --tls-diagnose`。

80/443 被占用：

- 脚本不会自动修改 nginx/apache。
- 停止冲突服务后重新运行安装。

域名没有解析到服务器：

- `getent ahosts DOMAIN`
- DNS 未生效时证书申请可能失败。

Caddyfile validate 失败：

- 检查 `/etc/caddy/Caddyfile`。
- 确认 Caddy 二进制包含 `forward_proxy` 模块。

Release 下载失败：

- 检查服务器是否可以访问 GitHub。
- 检查仓库是否存在对应 Release 资产。

list-modules 检查不到 `forward_proxy`：

- 当前 Caddy 二进制不是 Builder Release 产物。
- 重新运行安装或执行 `update-caddy-naive`。

能测延迟但无法使用：

- UDP over TCP 是否开启。
- QUIC 是否关闭。
- Caddyfile 是否是 `:443, DOMAIN` 推荐结构。
- 是否误用普通 HTTPS / HTTP1 配置。
- 是否使用 IPv6 DNS 导致 unreachable。
- SNI 是否为域名。
- 跳过证书验证是否为 false。

磁盘不足：

```bash
df -h
apt clean
rm -rf /var/lib/apt/lists/*
journalctl --vacuum-size=100M
```
