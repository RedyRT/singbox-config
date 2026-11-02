# Node Conversion Reference (sing-box 1.14.4)

Target [1.14.4](https://github.com/SagerNet/sing-box/tree/v1.14.4). Use the [official outbound documentation](https://sing-box.sagernet.org/configuration/outbound/) and check version badges before adding fields from rolling docs.

Use this file when converting Clash YAML, V2Ray share information, or manually supplied protocol parameters to sing-box outbounds.

## Common Field Mappings

| Clash / Common field | sing-box |
|------------------|----------|
| `server` / `port` | `"server"` / `"server_port"` |
| `tls: true` | `"tls": { "enabled": true }` |
| `servername` / `sni` | `"tls.server_name"` |
| `skip-cert-verify: true` | `"tls.insecure": true` |
| `client-fingerprint` | `"tls.utls": { "enabled": true, "fingerprint": "..." }` |
| `reality-opts.public-key` | `"tls.reality.public_key"` |
| `reality-opts.short-id` | `"tls.reality.short_id"` |
| `network: ws` | `"transport": { "type": "ws" }` |
| `network: grpc` | `"transport": { "type": "grpc" }` |
| `network: h2` | `"transport": { "type": "http" }` |
| `ws-opts.path` | `"transport.path"` |
| `ws-opts.headers.Host` | `"transport.headers": { "Host": ["..."] }` |
| `grpc-opts.grpc-service-name` | `"transport.service_name"` |

Server addresses specified as IP addresses do not need `domain_resolver`.

## VLESS

```json
{
  "type": "vless",
  "tag": "node",
  "server": "example.com",
  "server_port": 443,
  "uuid": "uuid",
  "flow": "xtls-rprx-vision",
  "tls": {
    "enabled": true,
    "server_name": "example.com",
    "utls": { "enabled": true, "fingerprint": "chrome" },
    "reality": { "enabled": true, "public_key": "...", "short_id": "..." }
  }
}
```

## VMess

```json
{
  "type": "vmess",
  "tag": "node",
  "server": "example.com",
  "server_port": 443,
  "uuid": "uuid",
  "security": "auto",
  "tls": { "enabled": true, "server_name": "example.com" },
  "transport": {
    "type": "ws",
    "path": "/path",
    "headers": { "Host": ["example.com"] }
  }
}
```

Clash `cipher` maps to sing-box `security`. `alter_id` defaults to 0; a nonzero value indicates a legacy pre-AEAD configuration.

## Shadowsocks

```json
{
  "type": "shadowsocks",
  "tag": "node",
  "server": "example.com",
  "server_port": 8388,
  "method": "2022-blake3-aes-128-gcm",
  "password": "password"
}
```

Clash `plugin: obfs` maps to `"plugin": "obfs-local"` and `"plugin_opts": "obfs=http;obfs-host=..."`.

## Trojan

```json
{
  "type": "trojan",
  "tag": "node",
  "server": "example.com",
  "server_port": 443,
  "password": "password",
  "tls": { "enabled": true, "server_name": "example.com" }
}
```

## Hysteria2

```json
{
  "type": "hysteria2",
  "tag": "node",
  "server": "example.com",
  "server_port": 443,
  "password": "password",
  "up_mbps": 100,
  "down_mbps": 200,
  "obfs": { "type": "salamander", "password": "password" },
  "tls": { "enabled": true, "server_name": "example.com" }
}
```

Clash `auth` maps to sing-box `password`.

## TUIC

```json
{
  "type": "tuic",
  "tag": "node",
  "server": "example.com",
  "server_port": 443,
  "uuid": "uuid",
  "password": "password",
  "congestion_control": "bbr",
  "udp_relay_mode": "native",
  "tls": { "enabled": true, "server_name": "example.com", "alpn": ["h3"] }
}
```

## ShadowTLS + Shadowsocks

```json
{
  "type": "shadowtls",
  "tag": "st",
  "server": "example.com",
  "server_port": 443,
  "version": 3,
  "password": "st-password",
  "tls": {
    "enabled": true,
    "server_name": "www.microsoft.com",
    "utls": { "enabled": true, "fingerprint": "chrome" }
  }
},
{
  "type": "shadowsocks",
  "tag": "ss-via-st",
  "method": "2022-blake3-aes-128-gcm",
  "password": "ss-password",
  "detour": "st",
  "udp_over_tcp": { "enabled": true }
}
```

## AnyTLS

```json
{
  "type": "anytls",
  "tag": "node",
  "server": "example.com",
  "server_port": 443,
  "password": "password",
  "tls": { "enabled": true, "server_name": "example.com" }
}
```

A standard AnyTLS outbound requires at least `server`, `server_port`, `password`, and `tls`. `padding_scheme` applies to inbound/user-related scenarios and is not a required field for a standard outbound.

1.14.4 also supports optional `client_metadata` and idle-session controls. Preserve these if supplied by the user; do not invent server credentials or metadata.

## Conversion Checks

- Replace every placeholder in the selected template and update selector/URLTest member tags consistently.
- Preserve TLS/SNI, transport, authentication, and detour semantics; do not add unrelated transport features.
- For a domain-based proxy server, use a bootstrap `domain_resolver` or the route default that does not depend on the proxy being connected.
- Prefer `action: "reject"` / `hijack-dns` for old special-outbound rules, typed DNS servers, and explicit HTTP clients when importing a full legacy configuration.
- Run `sing-box check -c config.json` with version 1.14.4 after conversion. A valid schema does not prove server reachability or credential correctness.
