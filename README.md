# singbox-config

[English](README.en.md)

`singbox-config` 是一个用于生成、迁移和排查 sing-box 客户端配置的 Codex skill。它聚焦客户端场景，包括 TUN/VPN、system proxy、SFM/SFA/SFI 图形客户端、命令行 `sing-box run`、DNS 分流、远程规则集、Clash API selector，以及常见代理节点转换。

## 版本策略

生成配置前按版本号倒序选择目标版本：

| 版本 | 默认状态 | 模板 |
| --- | --- | --- |
| `1.14` | 可选 | `references/templates/config-1.14-tun-realip.json` 或 `references/templates/config-1.14-tun-fakeip.json` |
| `1.13` | 默认 | `references/templates/config-1.13-tun.json` |

截至 2026-07-01，默认版本为 `1.13`。当 1.14 成为默认稳定版本时，只需要更新版本表和默认模板指向。

## 1.14 TUN 模板

- `RealIP 模板（兼容性优先）`：默认选择。应用拿真实 IP，浏览器、系统缓存和调试工具语义更自然；通过 DNS hijack、`dns.reverse_mapping: true` 和 sniff 支持多出口域名分流。
- `FakeIP 模板（分流确定性优先）`：用于需要更确定地从连接 IP 恢复域名的场景。它可能降低应用侧 DNS 等待，但不是首选 DNS 延迟优化方案；使用前需要接受浏览器 LNA、Service Worker/缓存污染、映射缺失和调试失真等副作用。

## 文件结构

- `SKILL.md`：skill 入口说明和执行规则。
- `references/config-schema.md`：配置字段参考和版本兼容矩阵。
- `references/cookbook.md`：RealIP/FakeIP、DNS、路由和 TUN 机制说明。
- `references/template.json`：当前默认模板，现等价于 `references/templates/config-1.13-tun.json`。
- `references/templates/`：版本化配置模板。

## 验证

模板应至少通过 JSON 语法检查：

```bash
jq empty references/template.json references/templates/*.json
```

改动版本字段时，还应检查：

- 1.13 模板不得包含 `optimistic`、`store_dns`、`http_client`、`preferred_by`。
- 1.14 模板不得包含 `independent_cache`、`store_rdrc`、`download_detour`。
- 1.14 RealIP 模板必须包含 `dns.reverse_mapping: true`，且不得包含 FakeIP DNS server 或 `store_fakeip`。
- 1.14 FakeIP 模板必须包含 FakeIP DNS server、A/AAAA FakeIP 规则和 `cache_file.store_fakeip: true`。

## 范围

本 skill 只覆盖 sing-box 客户端配置。不覆盖服务端 inbound、服务端 TLS/ACME/Reality、透明代理网关服务端部署等场景。
