# NaiveProxy Server v1.0.2

## 下载

| 文件 | 说明 |
|------|------|
| [install-naive-server.sh](https://github.com/ike-sh/naiveproxy-server/releases/download/v1.0.2/install-naive-server.sh) | curl 单文件安装（推荐） |

```bash
bash <(curl -fsSL https://github.com/ike-sh/naiveproxy-server/releases/download/v1.0.2/install-naive-server.sh) --menu
```

## 新功能

- **多域名**：`--extra-domain www.example.com`（可重复）
- **多账号**：`--extra-auth user:pass`（可重复）
- **文档**：`DEPLOY.md`、`docs/ARCHITECTURE.md`、`CHANGELOG.md`
- **CI/CD**：GitHub Actions 自动测试与 Release 构建

## 安全修复

- 备份文件独立时间戳
- acme.sh 安装 HTTPS + 格式校验

## 多域名安装示例

```bash
bash install-naive-server.sh \
  --domain proxy.example.com \
  --extra-domain www.proxy.example.com \
  --email me@example.com \
  --cert-mode acme-standalone
```

## 完整变更

见 [CHANGELOG.md](../CHANGELOG.md)

**Full Changelog**: https://github.com/ike-sh/naiveproxy-server/compare/v1.0.1...v1.0.2
