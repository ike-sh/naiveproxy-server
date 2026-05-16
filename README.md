# NaiveProxy Server

作者：ike-sh  
GitHub：https://github.com/ike-sh/naiveproxy-server  
Builder 仓库：https://github.com/ike-sh/caddy-naive-builder

这是一个 Debian/Ubuntu `linux-amd64` 服务器上的 NaiveProxy 服务端一键管理脚本。脚本直接下载 Builder Release 里的 Caddy naive 二进制，不安装 Go，不安装 xcaddy，也不在服务器本地编译 Caddy。

Release 资产名称固定为：

- `caddy-naive-linux-amd64.tar.gz`
- `caddy-naive-linux-amd64.tar.gz.sha256`

## 主菜单

无参数且在终端中运行时，会进入主菜单，不会直接安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh)
```

显式进入主菜单：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh) --menu
```

兼容交互参数：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh) --interactive
```

`--interactive` / `-i` 现在也是进入主菜单。只有在主菜单选择 `1. 一键安装 / 重新配置` 后，才会进入安装配置向导。

如果系统没有 `curl`：

```bash
apt update && apt install -y curl
```

也可以使用 `wget`：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh)
```

主菜单内容：

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
8. 显示客户端配置
9. 查看运行日志
10. 回落网站说明 / 配置位置
11. SSL / 证书诊断
12. 重新申请本地证书 acme.sh
0. 退出
```

菜单项执行失败会显示错误并返回菜单，不会直接退出到 shell。只有选择 `0. 退出` 或按 `Ctrl+C` 才会离开主菜单。

## 推荐证书模式

推荐使用：

```bash
--cert-mode acme-standalone
```

证书模式说明：

- `caddy-auto`：Caddy 自动申请证书，最简单，但部分机器访问 Let's Encrypt / ZeroSSL 可能超时。
- `caddy-zerossl`：Caddy 强制使用 ZeroSSL。
- `acme-standalone`：先用 `acme.sh + ZeroSSL standalone` 签发证书，再让 Caddy 使用本地证书文件，稳定性最好，当前默认推荐。

本地证书路径：

```text
/etc/caddy/certs/DOMAIN/fullchain.pem
/etc/caddy/certs/DOMAIN/privkey.pem
```

如果浏览器出现 `ERR_SSL_PROTOCOL_ERROR`，优先运行：

```bash
bash install-naive-server.sh --tls-diagnose
bash install-naive-server.sh --issue-cert
```

## 安装示例

交互安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh)
```

无人值守安装：

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

只写入文件、不启动服务：

```bash
bash install-naive-server.sh \
  --domain example.com \
  --email me@example.com \
  --site-mode static \
  --cert-mode acme-standalone \
  --no-start
```

带完整参数时会直接无人值守安装，不进入菜单。管道/非 TTY 场景无参数运行会显示 usage 并非 0 退出。

## 证书维护

重新申请本地证书：

```bash
bash install-naive-server.sh --issue-cert
```

证书诊断：

```bash
bash install-naive-server.sh --tls-diagnose
```

状态中会显示：

- `CERT_MODE`
- `CERT_FULLCHAIN`
- `CERT_KEY`
- 证书文件是否存在
- 证书 issuer / subject / 过期时间

## 回落站点模式

`static`：本地静态网页回落，最稳定，推荐。

- 站点目录：`/var/www/naive`
- 首页文件：`/var/www/naive/index.html`
- 适合放一个普通首页、产品页或个人页

手动上传 HTML/CSS/JS/图片后，推荐执行：

```bash
chown -R caddy:caddy /var/www/naive
find /var/www/naive -type d -exec chmod 755 {} \;
find /var/www/naive -type f -exec chmod 644 {} \;
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```

`reverse`：反代一个正常网站作为回落站。

- 输入 upstream，例如：`https://www.example.org`
- 脚本会生成 `reverse_proxy` 配置
- 第三方站可能受 CSP、Cookie、跳转、Host 校验和合规影响
- 建议只反代自己有权使用的网站或普通公开静态站

菜单 `10. 回落网站说明 / 配置位置` 会显示 Caddyfile、静态站目录、客户端配置、安装信息、更新脚本和证书路径。

## 客户端配置

安装成功后会输出 NaiveProxy 节点链接：

```text
https://USER:PASS@DOMAIN
```

NaiveProxy 没有像 VLESS 一样统一的 `vless://` 分享格式。这里提供的是 HTTPS 代理地址，适用于 `naive-client-config.json` 的 `proxy` 字段，也方便复制保存。

脚本会保存：

- `/root/naive-node-link.txt`
- `/root/naive-client-config.json`
- `/root/naive-shadowrocket.txt`
- `/root/naive-mihomo.yaml`
- `/root/naive-sing-box.json`
- `/etc/caddy/naive.env`

JSON 示例：

```json
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://USER:PASS@example.com"
}
```

显示客户端配置：

```bash
bash install-naive-server.sh --show-client
```

或在主菜单选择 `8. 显示客户端配置`。

## 常用命令

```bash
bash install-naive-server.sh --help
bash install-naive-server.sh --version
bash install-naive-server.sh --status
bash install-naive-server.sh --check-update
bash install-naive-server.sh --update
bash install-naive-server.sh --force-update
bash install-naive-server.sh --tls-diagnose
bash install-naive-server.sh --issue-cert
bash install-naive-server.sh --show-client
bash install-naive-server.sh --logs
```

手动更新已安装的 Caddy naive 内核：

```bash
update-caddy-naive
```

查看服务：

```bash
systemctl status caddy
journalctl -u caddy -e --no-pager
```

## 更新检测

检测更新不会只比较 `caddy version`。脚本会优先比较：

- 已安装时记录的 `BUILDER_RELEASE_TAG`
- 已安装时记录的 `BUILDER_RELEASE_SHA256`
- GitHub latest release tag
- latest asset sha256

这样即使 Caddy 版本号不变，但 forwardproxy naive 分支更新，也能通过 Release tag 或资产 sha256 发现变化。

## 卸载

卸载服务，保留配置：

```bash
bash install-naive-server.sh --uninstall
```

完全卸载所有文件：

```bash
bash install-naive-server.sh --purge
```

完全卸载会删除：

- `/etc/systemd/system/caddy.service`
- `/etc/systemd/system/caddy-naive-update.service`
- `/etc/systemd/system/caddy-naive-update.timer`
- `/usr/local/bin/update-caddy-naive`
- `/usr/local/bin/caddy`
- `/etc/caddy`
- `/var/www/naive`
- `/var/lib/caddy`
- `/var/backups/caddy-naive`
- `/root/naive-client-config.json`
- `/root/naive-node-link.txt`
- `/root/naive-shadowrocket.txt`
- `/root/naive-mihomo.yaml`
- `/root/naive-sing-box.json`

执行前需要二次确认。

## 默认路径

- Caddy 二进制：`/usr/local/bin/caddy`
- Caddyfile：`/etc/caddy/Caddyfile`
- 网站目录：`/var/www/naive`
- Caddy 数据目录：`/var/lib/caddy`
- Caddy 配置目录：`/etc/caddy`
- Caddy 证书目录：`/etc/caddy/certs`
- 备份目录：`/var/backups/caddy-naive`
- systemd service：`/etc/systemd/system/caddy.service`
- 更新脚本：`/usr/local/bin/update-caddy-naive`
- 客户端 JSON 配置：`/root/naive-client-config.json`
- 节点链接：`/root/naive-node-link.txt`
- 安装信息：`/etc/caddy/naive.env`

## 故障排查

证书申请失败：确认域名 A/AAAA 记录指向当前服务器，云安全组和防火墙放行 TCP `80` 和 `443`。推荐使用 `--tls-diagnose` 查看证书、端口、DNS 和 HTTPS 探测结果。

`ERR_SSL_PROTOCOL_ERROR`：优先执行 `bash install-naive-server.sh --tls-diagnose`，然后执行 `bash install-naive-server.sh --issue-cert` 重新签发本地证书。

80/443 被占用：脚本会检查 TCP `80` 和 `443`，发现 nginx、apache 或其他非托管服务占用时会退出，不会自动修改这些服务。

域名没有解析到服务器：`getent ahosts DOMAIN` 无结果时会警告。请检查 DNS 记录和 CDN/代理状态。

`caddy validate` 失败：脚本会恢复 Caddyfile 备份，避免写入无效配置后导致服务挂掉。可查看 `/var/backups/caddy-naive`。

Release 下载失败：确认服务器能访问 GitHub，并确认 Builder Release 中存在固定资产名。

`list-modules` 检查不到 `forward_proxy`：说明下载到的 Caddy 二进制不包含 `klzgrad/forwardproxy` naive 插件，请检查 Builder Release 构建产物。

磁盘空间不足：脚本会在安装依赖前、下载和解压 Release 前检查根分区可用空间，低于 `300MB` 会退出。可先执行：

```bash
df -h
apt clean
rm -rf /var/lib/apt/lists/*
journalctl --vacuum-size=100M
```

## 限制

- 仅支持 `linux-amd64`
- `arm64/aarch64` 会明确报错并退出
- 不会在服务器本地编译 Caddy
- 不会安装 Go 或 xcaddy
- 不会关闭系统防火墙
- 不会自动修改 nginx/apache
