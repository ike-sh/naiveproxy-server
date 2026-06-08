# NaiveProxy Server 架构说明

> 项目：[ike-sh/naiveproxy-server](https://github.com/ike-sh/naiveproxy-server) v1.0.1  
> 核心：单文件 Bash 管理脚本 + 预编译 Caddy naive 二进制

## 系统概览

```mermaid
flowchart TB
  subgraph Client["客户端"]
    V2N[v2rayN / sing-box]
    SR[Shadowrocket]
  end

  subgraph Server["Debian/Ubuntu 服务器"]
    Script["install-naive-server.sh"]
    Caddy["Caddy + forward_proxy 模块"]
    Static["/var/www/naive 回落站"]
    Certs["/etc/caddy/certs"]
    Env["/etc/caddy/naive.env"]
    Updater["update-caddy-naive"]
    Timer["caddy-naive-update.timer"]
  end

  subgraph External["外部依赖"]
    GH["GitHub Releases\ncaddy-naive-builder"]
    ZS["ZeroSSL / acme.sh"]
  end

  Script -->|下载安装| Caddy
  Script -->|写入| Env
  Script -->|生成| Certs
  Script -->|部署| Updater
  Updater --> Timer
  Updater -->|拉取 latest| GH
  Script -->|签发证书| ZS
  Caddy --> Static
  Caddy --> Certs
  V2N -->|HTTPS + HTTP/2 + Naive| Caddy
  SR -->|HTTP/2 + uot=1| Caddy
```

## 安装流程

```mermaid
sequenceDiagram
  participant U as 管理员
  participant S as install-naive-server.sh
  participant GH as caddy-naive-builder
  participant AC as acme.sh
  participant C as Caddy systemd

  U->>S: bash install-naive-server.sh --domain ...
  S->>S: detect_arch / validate / check_ports
  S->>GH: 下载 caddy-naive-{arch}.tar.gz + sha256
  S->>S: verify_sha256 / install_caddy_binary
  S->>S: write_static_site / write_caddyfile

  alt cert-mode = acme-standalone
    S->>C: 临时 ZeroSSL 自动配置
    S->>AC: standalone 申请证书
    AC-->>S: fullchain.pem + privkey.pem
    S->>S: write_caddyfile_local_cert
  else caddy-auto / caddy-zerossl
    S->>S: write_and_validate_caddyfile
  end

  S->>S: write_systemd_service / write_env_file
  S->>C: systemctl start caddy
  S-->>U: 输出客户端链接
```

## 目录与职责

| 路径 | 职责 |
|------|------|
| `install-naive-server.sh` | 主入口：安装、菜单、诊断、卸载 |
| `lib/` | 可测试工具函数（编码、链接生成等） |
| `/usr/local/bin/caddy` | 含 `forward_proxy` 的 Caddy 二进制 |
| `/usr/local/bin/update-caddy-naive` | 内核热更新（不覆盖业务配置） |
| `/etc/caddy/Caddyfile` | 站点 + 代理核心配置 |
| `/etc/caddy/naive.env` | 安装元数据（域名、认证、Release 信息） |
| `/etc/caddy/certs/DOMAIN/` | 本地证书（acme-standalone 模式） |
| `/var/www/naive/` | 静态回落网站根目录 |

## Caddyfile 推荐结构

```mermaid
flowchart TD
  A["全局块: order forward_proxy / protocols h1 h2"] --> B["http://DOMAIN → 301 HTTPS"]
  B --> C[":443, DOMAIN { ... }"]
  C --> D["route {"]
  D --> E["forward_proxy { basic_auth / probe_resistance }"]
  E --> F["file_server 或 reverse_proxy"]
```

关键约束：

- `:443, DOMAIN` 中 `:443` 必须在域名前
- `forward_proxy` 必须在 `route` 内，且位于 `file_server` / `reverse_proxy` 之前
- 默认 `probe_resistance` 开启，不记录访问日志

## 更新流程

```mermaid
flowchart LR
  A[detect_update] --> B{Release tag/sha256 变化?}
  B -->|否| C[无需更新]
  B -->|是| D[download_release_caddy]
  D --> E[verify_sha256]
  E --> F[备份旧二进制]
  F --> G[validate Caddyfile]
  G --> H[systemctl restart caddy]
  H --> I[刷新 naive.env Release 字段]
```

更新脚本**不会**覆盖：`Caddyfile`、证书、用户名密码、站点模式。

## 证书模式对比

| 模式 | 机制 | 适用场景 |
|------|------|----------|
| `acme-standalone`（推荐） | acme.sh + ZeroSSL standalone | 稳定性最好，需放行 TCP 80 |
| `caddy-auto` | Caddy 内置 ACME | 最简单，部分网络可能超时 |
| `caddy-zerossl` | Caddy 强制 ZeroSSL | 介于两者之间 |

证书复用：域名未变、证书有效且剩余 > 15 天时跳过重新签发。

## 模块划分（lib/）

| 模块 | 函数 |
|------|------|
| `lib/common.sh` | 日志、die、常量 |
| `lib/encoding.sh` | url_encode、caddyfile_quote、base64 |
| `lib/links.sh` | v2rayN / Shadowrocket 链接生成 |

主脚本在本地克隆时 `source lib/*.sh`；通过 `curl \| bash` 安装时使用合并后的单文件版本。
