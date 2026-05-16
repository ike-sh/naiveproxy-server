# NaiveProxy Server

作者：ike-sh  
GitHub：https://github.com/ike-sh/naiveproxy-server  
Builder 仓库：https://github.com/ike-sh/caddy-naive-builder

这是一个 Debian/Ubuntu `linux-amd64` 服务器上的 NaiveProxy 服务端一键管理脚本。脚本直接下载 Builder Release 里的 Caddy naive 二进制，不安装 Go，不安装 xcaddy，也不在服务器本地编译 Caddy。

Release 资产名固定为：

- `caddy-naive-linux-amd64.tar.gz`
- `caddy-naive-linux-amd64.tar.gz.sha256`

## 主菜单

无参数运行会进入主菜单，不会直接安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh)
```

显式主菜单：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh) --menu
```

兼容交互参数：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/naiveproxy-server/main/install-naive-server.sh) --interactive
```

`--interactive` / `-i` 现在也是进入主菜单。只有在主菜单选择 `1. 一键安装 / 重新配置` 后，才会进入安装配置向导。

主菜单内容：

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
8. 显示客户端配置
9. 查看运行日志
0. 退出
```

## 无人值守安装

带完整参数时会直接安装，不进入菜单：

```bash
bash install-naive-server.sh --domain example.com --email me@example.com --site-mode static --auto-update
```

反代模式：

```bash
bash install-naive-server.sh --domain example.com --email me@example.com --site-mode reverse --upstream https://www.example.org
```

`static`：生成本地静态 HTML 回落站，最稳定。  
`reverse`：反代其他正常网站，更像真实站点，但可能受 CSP、Cookie、登录、跳转和合规影响。

## 常用命令

```bash
bash install-naive-server.sh --help
bash install-naive-server.sh --version
bash install-naive-server.sh --status
bash install-naive-server.sh --check-update
bash install-naive-server.sh --update
bash install-naive-server.sh --force-update
bash install-naive-server.sh --show-client
bash install-naive-server.sh --logs
```

手动更新已安装的内核：

```bash
update-caddy-naive
```

查看服务：

```bash
systemctl status caddy
journalctl -u caddy -e --no-pager
```

## 客户端配置

安装成功后会保存：

- `/root/naive-client-config.json`
- `/etc/caddy/naive.env`

示例：

```json
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://USER:PASS@example.com"
}
```

连接地址格式：

```text
https://USER:PASS@DOMAIN
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

执行前需要二次确认。

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

## 故障排查

证书申请失败：确认域名 A/AAAA 记录指向当前服务器，云安全组和防火墙放行 TCP `80` 和 `443`。

端口被占用：脚本会检查 TCP `80` 和 `443`，发现 nginx、apache 或其他服务占用时会退出，不会自动修改这些服务。

磁盘空间不足：脚本会在安装依赖前、下载和解压 Release 前检查根分区可用空间，低于 `300MB` 会退出。可先执行：

```bash
df -h
apt clean
rm -rf /var/lib/apt/lists/*
journalctl --vacuum-size=100M
```

Release 下载失败：确认服务器能访问 GitHub，并确认 Builder Release 中存在固定资产名。

`list-modules` 检查不到 `forward_proxy`：说明下载到的 Caddy 二进制不包含 `klzgrad/forwardproxy` naive 插件，请检查 Builder Release 构建产物。

## 限制

- 仅支持 `linux-amd64`
- `arm64/aarch64` 会明确报错并退出
- 不会在服务器本地编译 Caddy
- 不会安装 Go 或 xcaddy
- 不会关闭系统防火墙
- 不会自动修改 nginx/apache
