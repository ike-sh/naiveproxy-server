# NaiveProxy 服务端一键部署脚本

这个项目提供一个生产可用的 Bash 一键部署脚本，用于在 Debian/Ubuntu 的 `linux-amd64` 服务器上部署 NaiveProxy 服务端。

脚本直接下载 GitHub Release 中已经编译好的 Caddy naive 二进制：

- `caddy-naive-linux-amd64.tar.gz`
- `caddy-naive-linux-amd64.tar.gz.sha256`

默认 Release 仓库：

https://github.com/ike-sh/caddy-naive-builder

脚本不会在服务器上安装 Go、不会安装 xcaddy，也不会在服务器本地编译 Caddy。

## 安装方式

交互式安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh)
```

显式进入交互式向导：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh) --interactive
```

无人值守参数式安装：

```bash
bash install-naive-server.sh --domain example.com --email me@example.com --site-mode static
```

运行规则：

- 无参数且在终端中运行：进入交互式向导。
- 使用 `--interactive` 或 `-i`：进入交互式向导。
- 带完整参数：直接无人值守安装。
- 管道或非 TTY 场景无参数：显示 usage 并以非 0 退出。
- `--help` 只显示帮助，不进入交互。
- `--uninstall` 和 `--purge` 不进入安装向导。

安装完成后，脚本会输出：

- NaiveProxy URL：`https://USER:PASS@example.com`
- 客户端配置文件：`/root/naive-client-config.json`
- 安装信息：`/etc/caddy/naive.env`

请妥善保存生成的用户名和密码。`naive.env` 与客户端配置文件权限会设置为 `600`。

## 反代模式

```bash
bash install-naive-server.sh --domain example.com --email me@example.com --site-mode reverse --upstream https://www.example.org
```

反代模式会把普通浏览器访问回落到 `--upstream` 指定的网站。脚本会从 upstream URL 解析 host，并在 Caddyfile 中设置 `header_up Host` 与 `tls_server_name`。

反代第三方网站可能受 CSP、Cookie、登录、跳转和法律合规影响，建议只反代自己有权使用的网站或普通公开静态站点。

## 自动更新

```bash
bash install-naive-server.sh --domain example.com --email me@example.com --site-mode static --auto-update
```

启用后会生成：

- `/etc/systemd/system/caddy-naive-update.service`
- `/etc/systemd/system/caddy-naive-update.timer`

timer 默认每天凌晨 `04:30` 执行一次，并带 `RandomizedDelaySec=1800` 随机延迟。

## 手动更新

```bash
update-caddy-naive
```

更新脚本会重新下载 latest Release、校验 SHA256、备份旧二进制、替换 Caddy、检查 `forward_proxy/forwardproxy` 模块、验证 Caddyfile，然后 reload 服务；reload 失败时会 restart。

可用环境变量覆盖：

```bash
REPO=owner/repo INSTALL_BIN=/usr/local/bin/caddy SERVICE_NAME=caddy update-caddy-naive
```

## 查看状态

```bash
systemctl status caddy
journalctl -u caddy -e --no-pager
```

如果使用了 `--service-name`，请把命令中的 `caddy` 替换成对应服务名。

## 客户端配置示例

```json
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://USER:PASS@example.com"
}
```

Naive 客户端连接地址格式：

```text
https://USER:PASS@DOMAIN
```

## 回落站点模式

`static`：生成本地静态 HTML 回落站，最稳定，默认推荐。

`reverse`：反代其他正常网站，更像真实站点，但可能受 CSP、Cookie、登录、跳转和合规影响。

## 卸载

卸载服务、自动更新 timer 和更新脚本，但保留 `/etc/caddy`、`/var/www/naive` 和 `/var/lib/caddy`：

```bash
bash install-naive-server.sh --uninstall
```

彻底清理服务、自动更新 timer、更新脚本、Caddy 二进制、配置目录、站点目录和数据目录：

```bash
bash install-naive-server.sh --purge
```

`--purge` 需要二次确认。

## 默认路径

- Caddy 二进制：`/usr/local/bin/caddy`
- Caddyfile：`/etc/caddy/Caddyfile`
- 网站目录：`/var/www/naive`
- Caddy 数据目录：`/var/lib/caddy`
- Caddy 配置目录：`/etc/caddy`
- 备份目录：`/var/backups/caddy-naive`
- systemd service：`/etc/systemd/system/caddy.service`
- 更新脚本：`/usr/local/bin/update-caddy-naive`
- 客户端配置：`/root/naive-client-config.json`
- 安装信息：`/etc/caddy/naive.env`

## 常见问题

### 证书申请失败

确认域名的 A/AAAA 记录已经指向当前服务器，并且云安全组、防火墙允许公网访问 TCP `80` 和 `443`。如果传入了 `--email`，请确认邮箱格式没有空格。

### 80/443 被占用

脚本会在启动前检查 TCP `80` 和 `443`。如果端口被 nginx、apache 或其他服务占用，脚本会输出占用进程并退出，不会自动修改 nginx/apache 或关闭系统防火墙。

### 域名没有解析到服务器

脚本会执行 `getent ahosts DOMAIN`。解析失败只会警告，不会强制退出，但 Caddy 后续申请 TLS 证书通常会失败。

### caddy validate 失败

脚本写入 Caddyfile 后会执行：

```bash
/usr/local/bin/caddy validate --config /etc/caddy/Caddyfile
```

如果两条 `order forward_proxy ...` 指令不被当前 Caddy 接受，脚本会自动改用等价的 `order forward_proxy first` 后再次校验。若仍失败，脚本不会启动服务，并会提示备份路径。

### Release 下载失败

确认服务器能访问 GitHub，并确认 Release 中存在以下资产：

- `caddy-naive-linux-amd64.tar.gz`
- `caddy-naive-linux-amd64.tar.gz.sha256`

也可以通过 `--repo OWNER/REPO` 指定其他 Release 仓库。

### 磁盘空间不足

脚本会在安装依赖前，以及下载和解压 Release 前检查根分区可用空间。根分区低于 `300MB` 时会直接退出。

可以先执行：

```bash
df -h
apt clean
rm -rf /var/lib/apt/lists/*
journalctl --vacuum-size=100M
```

如果 `apt-get update` 失败并出现 `No space left on device`，脚本会明确提示磁盘不足，不会继续往后安装。

### list-modules 检查不到 forward_proxy

说明下载到的 Caddy 二进制不包含 `klzgrad/forwardproxy` naive 插件，脚本会报错退出。请检查 Release 构建产物是否正确。

## 重要限制

- 仅支持 `linux-amd64`。
- `arm64/aarch64` 会明确报错并退出。
- 不会在服务器本地编译 Caddy。
- 不会安装 Go 或 xcaddy。
- 不会关闭系统防火墙。
- 不会自动修改 nginx/apache。
