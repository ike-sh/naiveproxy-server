# NaiveProxy Server 部署指南

> 仓库：[https://github.com/ike-sh/naiveproxy-server](https://github.com/ike-sh/naiveproxy-server)

## 前置条件

| 项 | 要求 |
|----|------|
| 系统 | Debian / Ubuntu（`linux-amd64` 或 `linux-arm64`） |
| 权限 | root |
| 网络 | 可访问 GitHub Releases |
| 域名 | A/AAAA 记录指向服务器公网 IP |
| 端口 | TCP 80、443 放行（HTTP3 另需 UDP 443） |
| Cloudflare | 记录设为「仅 DNS」，关闭代理云朵 |

## 快速部署（推荐）

安装包直链（当前稳定版 [v1.0.5](https://github.com/ike-sh/naiveproxy-server/releases/tag/v1.0.5)）：

```text
https://github.com/ike-sh/naiveproxy-server/releases/download/v1.0.5/install-naive-server.sh
```

### 1. 一键安装

```bash
curl -fsSL https://github.com/ike-sh/naiveproxy-server/releases/download/v1.0.5/install-naive-server.sh | sudo bash -s -- \
  --domain proxy.example.com \
  --email admin@example.com \
  --site-mode static \
  --cert-mode acme-standalone \
  --auto-update
```

### 2. 交互式菜单

```bash
curl -fsSL https://github.com/ike-sh/naiveproxy-server/releases/download/v1.0.5/install-naive-server.sh | sudo bash
```

选择 `1. 一键安装 / 重新配置`，按向导填写。

### 3. 查看客户端配置

```bash
bash install-naive-server.sh --show-client
```

## 部署模式

### 静态回落站（推荐）

流量伪装为普通网站，最稳定。

```bash
bash install-naive-server.sh \
  --domain proxy.example.com \
  --email admin@example.com \
  --site-mode static \
  --cert-mode acme-standalone
```

自定义页面：编辑 `/var/www/naive/index.html`，然后：

```bash
bash install-naive-server.sh --fix-static-perms
```

### 反代回落

反代到外部网站，更像真实站点。

```bash
bash install-naive-server.sh \
  --domain proxy.example.com \
  --email admin@example.com \
  --site-mode reverse \
  --upstream https://www.example.org \
  --cert-mode acme-standalone
```

## 多域名部署

v1.0.2+ 支持额外域名绑定到同一代理实例：

```bash
bash install-naive-server.sh \
  --domain proxy.example.com \
  --extra-domain www.proxy.example.com \
  --extra-domain backup.example.com \
  --email admin@example.com \
  --cert-mode acme-standalone
```

额外用户（多账号）：

```bash
bash install-naive-server.sh \
  --domain proxy.example.com \
  --email admin@example.com \
  --extra-auth friend:SecurePass123 \
  --cert-mode acme-standalone
```

> 每个额外域名需要有效 DNS 记录；acme-standalone 会为所有域名申请 SAN 证书。

## 证书模式选择

| 模式 | 命令参数 | 说明 |
|------|----------|------|
| acme-standalone | `--cert-mode acme-standalone` | **默认推荐**，acme.sh + ZeroSSL |
| caddy-auto | `--cert-mode caddy-auto` | Caddy 自动 ACME |
| caddy-zerossl | `--cert-mode caddy-zerossl` | Caddy 强制 ZeroSSL |

证书路径：

```text
/etc/caddy/certs/DOMAIN/fullchain.pem
/etc/caddy/certs/DOMAIN/privkey.pem
```

重新签发：

```bash
bash install-naive-server.sh --issue-cert
```

诊断：

```bash
bash install-naive-server.sh --tls-diagnose
```

## 客户端配置

### v2rayN / sing-box

| 字段 | 值 |
|------|-----|
| 类型 | Naive |
| 地址 | 你的域名 |
| 端口 | 443 |
| UDP over TCP | **On（必须）** |
| QUIC | Off |
| TLS | tls |
| SNI | 域名 |
| 跳过证书验证 | false |

链接格式：

```text
naive+https://USER:PASS@DOMAIN:443?security=tls&sni=DOMAIN&insecure=0&allowInsecure=0&type=tcp&headerType=none#NAME
```

### Shadowrocket

| 字段 | 值 |
|------|-----|
| 类型 | HTTP2 |
| UDP over TCP | 开启 |

链接必须含 `uot=1`。

## 运维命令

```bash
# 状态
bash install-naive-server.sh --status

# 代理自检
bash install-naive-server.sh --proxy-self-test

# 日志
bash install-naive-server.sh --logs

# 检测/更新内核
bash install-naive-server.sh --check-update
bash install-naive-server.sh --update

# 修改认证
bash install-naive-server.sh --set-user newuser --set-pass newpass

# HTTP3（默认关闭，推荐保持关闭）
bash install-naive-server.sh --enable-http3
bash install-naive-server.sh --disable-http3
```

## 云厂商安全组

| 协议 | 端口 | 用途 |
|------|------|------|
| TCP | 80 | ACME 验证 |
| TCP | 443 | HTTPS / Naive 代理 |
| UDP | 443 | 仅 HTTP3 开启时需要 |

## 故障排查

### 能测延迟但无法上网

1. 客户端 **UDP over TCP** 是否开启
2. QUIC 是否关闭
3. Caddyfile 是否为 `:443, DOMAIN` 推荐结构
4. 客户端类型是否为 Naive/HTTP2（非普通 HTTP 代理）

```bash
bash install-naive-server.sh --proxy-self-test
bash install-naive-server.sh --status
```

### SSL 失败

```bash
bash install-naive-server.sh --tls-diagnose
bash install-naive-server.sh --issue-cert
```

检查：TCP 80/443 占用、DNS 指向、系统时间、Cloudflare 代理状态。

### 从 Git 克隆开发部署

```bash
git clone https://github.com/ike-sh/naiveproxy-server.git
cd naiveproxy-server
sudo bash install-naive-server.sh --menu
```

## 卸载

```bash
# 保留配置
bash install-naive-server.sh --uninstall

# 完全删除（需输入 DELETE 确认）
bash install-naive-server.sh --purge
```
