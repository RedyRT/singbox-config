# sing-box Configuration Schema Reference (1.14.4)

> Authoritative docs: https://sing-box.sagernet.org/configuration/
> Target: stable 1.14.4. Check version badges in the rolling documentation and confirm uncertain fields against https://github.com/SagerNet/sing-box/tree/v1.14.4/option.

## Target Configuration

| Field / behavior | 1.14.4 policy |
|------------------|---------------|
| Default template | `config-1.14.4-tun-realip.json`; optional `config-1.14.4-tun-fakeip.json` |
| DNS cache isolation | Automatic per transport; omit deprecated `independent_cache` |
| Persistent DNS cache | `cache_file.store_dns: true`; omit deprecated `store_rdrc` / `rdrc_timeout` |
| Optimistic cache | `dns.optimistic: true` or an object with `enabled` and `timeout` |
| RealIP domain recovery | `dns.reverse_mapping: true`; explicitly route overseas DNS queries to remote DNS |
| FakeIP persistence | `cache_file.store_fakeip: true` in the FakeIP variant |
| Hosts fallback | `preferred_by: "hosts"` |
| Remote downloads | Explicit `http_client` or `http_clients` / `route.default_http_client`; omit `download_detour` |
| DNS response matching | Top-level `evaluate`, then `match_response` and a final action |
| TUN DNS | `dns_mode: "hijack"`; supported `stack: "mixed"` |

Do not import 1.15-only fields such as cache-file `buffer_size`/`flush_interval`, TUN `multi_queue`, DNS `dns_server_address`/`dns_search_domain`, or TLS `certificate_sha256`. The stack deprecation in the rolling website starts in 1.15, not this target.

## DNS Servers

Each server has `type`, `tag`, and type-specific fields. All remote servers support **Dial Fields**.

| Type | Default Port | Key Fields |
|------|-------------|------------|
| `udp` | 53 | `server`, `server_port` |
| `tcp` | 53 | `server`, `server_port` |
| `tls` | 853 | `server`, `server_port`, `tls` |
| `https` | 443 | `server`, `server_port`, `path` (/dns-query), `headers`, `tls` |
| `h3` | 443 | `server`, `server_port`, `path`, `headers`, `tls` |
| `quic` | 853 | `server`, `server_port`, `tls` |
| `local` | - | `prefer_go`, `neighbor_domain` — uses system resolver |
| `fakeip` | - | `inet4_range` (example: 198.18.0.0/15), `inet6_range` (example: 2001:2::/48); configure the desired ranges explicitly |
| `dhcp` | - | `interface` |
| `hosts` | - | `path` (default /etc/hosts), `predefined` (domain→IP map) |
| `tailscale` | - | `endpoint` (tag of Tailscale endpoint) |
| `resolved` | - | `service` (tag of resolved service) |

## DNS Rules

Values within a field match with OR. Related destination fields form an OR group, as do port fields and source-address fields; those groups and other fields combine with AND. Use `"type": "logical"` with `"mode": "and"|"or"` for explicit combinations.

### Query Match Fields
`inbound`, `ip_version`, `query_type` (A/AAAA/HTTPS/etc), `query_client_subnet`, `query_dnssec`, `network`, `protocol`, `domain`, `domain_suffix`, `domain_keyword`, `domain_regex`, `source_ip_cidr`, `source_ip_is_private`, `source_mac_address`, `source_hostname`, `port`, `port_range`, `process_name`, `process_path`, `package_name`, `package_name_regex`, `clash_mode`, `network_type`, `wifi_ssid`, `rule_set`, `preferred_by`, `invert`

### Response Matching

Use a preceding top-level `evaluate` action and `match_response: true` for the latest untagged response, or `match_response: "tag"` for a tagged evaluation. Match with `ip_cidr`, `ip_is_private`, `ip_accept_any`, `response_rcode`, `response_answer`, `response_ns`, or `response_extra`.

Legacy address filters without `match_response`, DNS rule-action `strategy`, and `rule_set_ip_cidr_accept_empty` are deprecated. Combining them with `query_type`, `ip_version`, or new response-matching features can fail at startup. This does not deprecate global `dns.strategy` or resolver/route-resolve strategy.

### DNS Rule Actions
- `"action": "route"` — route to `server` (required); options include `disable_cache`, `disable_optimistic_cache`, `rewrite_ttl`, `timeout`, `client_subnet`, `remove_client_subnet`, and `speculative`.
- `"action": "route-options"` — set query options without terminating matching; supports the cache, TTL, timeout, and subnet options above.
- `"action": "reject"` — returns REFUSED by default, or `method: "drop"` discards the request. Unless `no_drop: true`, repeated rejects can temporarily switch to dropping after 50 triggers in 30 seconds.
- `"action": "predefined"` — returns a predefined response: `rcode` (NOERROR/NXDOMAIN/SERVFAIL/REFUSED), `answer`/`ns`/`extra` (DNS record text)
- `"action": "evaluate"` — sends a query to `server`, optionally tags its response with `tag`, and continues rule matching. Only allowed at the top level.
- `"action": "respond"` — returns an evaluated response; requires a preceding top-level evaluation.
- `race: true` on route/respond/reject/predefined rules requires response matching and allows pending evaluations to compete; `speculative` can send a subsequent query while races are pending. Keep ordinary sequential rules unless the user needs advanced DNS racing.

## Route Rules

### Match Fields
`inbound`, `ip_version`, `network` (tcp/udp/icmp), `protocol`, `client`, `domain`, `domain_suffix`, `domain_keyword`, `domain_regex`, `source_ip_cidr`, `source_ip_is_private`, `ip_cidr`, `ip_is_private`, `source_port`, `port`, `port_range`, `process_name`, `process_path`, `process_path_regex`, `package_name`, `user`, `user_id`, `clash_mode`, `network_type`, `network_is_expensive`, `wifi_ssid`, `wifi_bssid`, `rule_set`, `rule_set_ip_cidr_match_source`, `invert`

### Final Actions
- `"action": "route"` — `outbound` (required) + route-options fields
- `"action": "reject"` — `method`: `default` (RST/ICMP) or `drop`
- `"action": "hijack-dns"` — redirect DNS to sing-box DNS module (no fields)
- `"action": "bypass"` — kernel-level bypass (Linux auto_redirect pre-match); outside pre-match, routes to the specified outbound or skips the rule when none is set.

### Non-Final Actions (processing continues to next rule)
- `"action": "sniff"` — protocol detection. `sniffer` (list), `timeout` (300ms)
- `"action": "resolve"` — DNS resolve. `server`, `strategy`, `disable_cache`, `disable_optimistic_cache`, `rewrite_ttl`, `timeout`, `client_subnet`
- `"action": "route-options"` — set options: `override_address`, `override_port`, `udp_connect`, `udp_timeout`, `tls_fragment`, `tls_record_fragment`

## TUN Inbound

```json
{
  "type": "tun",
  "tag": "tun-in",
  "address": ["172.19.0.1/30"],
  "mtu": 9000,
  "auto_route": true,
  "dns_mode": "hijack",
  "strict_route": true,
  "stack": "mixed",
  "platform": {
    "http_proxy": {
      "enabled": true,
      "server": "127.0.0.1",
      "server_port": 2080,
      "bypass_domain": [],
      "match_domain": []
    }
  }
}
```

Key fields:
- `address`: TUN interface addresses (IPv4/IPv6 prefixes)
- `auto_route`: Points the system default route to the TUN interface so that all traffic enters TUN. Linux implements this through iproute2 policy routing (table 2022), while macOS uses the system routing table. **You must also configure `route.auto_detect_interface` or `route.default_interface` to prevent routing loops.**
- `strict_route`: Meaning varies by platform:
  - **Linux**: Adds UNREACHABLE rules for address families not configured on TUN (e.g. no IPv6 address configured → IPv6 traffic immediately produces an error rather than leaking to the physical interface). When neither strict_route nor auto_redirect is enabled, ICMP does not go through TUN. When auto_redirect is enabled, this also controls whether `SO_BINDTODEVICE` traffic is redirected.
  - **Windows**: Prevents DNS leaks caused by Windows multihomed DNS resolution behavior.
  - **macOS/mobile**: No special effect (VPN mode itself already captures all traffic).
- `stack`: `system` (system stack), `gvisor` (userspace), `mixed` (system TCP + gvisor UDP; template default). Supported in 1.14.4.
- `dns_mode`: `disabled`, `native`, or `hijack`; defaults to `hijack` with `auto_route`, otherwise `disabled`.
- `dns_address`: Native interface DNS addresses. When unset, uses the next address after each configured TUN family and handles that destination as `hijack-dns`. When explicitly set, add DNS hijack rules for those addresses.
- `include_mac_address` / `exclude_mac_address`: Linux MAC filtering with `auto_route` and `auto_redirect`.
- `udp_mapping`, `udp_filtering`, `udp_nat_max`: Shared UDP NAT controls; see the official UDP NAT reference.
- `platform.http_proxy`: Sets the system HTTP proxy within TUN (VPN). Implemented through the Network Extension API (SFM/SFA/SFI), with no additional permissions required. See "TUN Platform Options" below for details.
- `auto_redirect`: nftables redirect (Linux, better than auto_route for servers). Recommended to always enable on Linux; it performs better than tproxy and avoids conflicts between TUN and Docker bridges.

## Mixed Inbound

```json
{
  "type": "mixed",
  "tag": "mixed-in",
  "listen": "127.0.0.1",
  "listen_port": 2080,
  "users": [{"username": "", "password": ""}],
  "set_system_proxy": false
}
```

Combined HTTP + SOCKS5 proxy. Platform implementations of `set_system_proxy`:
- **macOS**: Calls `networksetup` to set web/secure web/SOCKS proxies (a regular user is sufficient; root is not required; monitors network interface changes and updates automatically)
- **Windows**: Sets the system proxy through the WinINet API
- **Linux (GNOME/KDE)**: Sets it through `gsettings` (GNOME) or `kwriteconfig5/6` (KDE). When running as root, the `SUDO_USER` environment variable is required to switch to the actual user for execution. Servers without a desktop environment are not supported.
- **Android**: Requires root, system (adb), or rish privileges; sets it through `settings put global http_proxy`
- **Other platforms**: Not supported

## Outbound Types

### Proxy Protocols (Summary)
| Type | Key Fields | Notes |
|------|-----------|-------|
| `vless` | `server`, `server_port`, `uuid`, `flow`, `tls`, `transport` | `flow: "xtls-rprx-vision"` for XTLS |
| `vmess` | `server`, `server_port`, `uuid`, `security`, `tls`, `transport` | `alter_id`, `packet_encoding` |
| `shadowsocks` | `server`, `server_port`, `method`, `password` | `plugin`, `multiplex` |
| `trojan` | `server`, `server_port`, `password`, `tls`, `transport` | `multiplex` |
| `hysteria2` | `server`, `server_port`, `password`, `tls` | `obfs`, `up_mbps`, `down_mbps` |
| `hysteria` | `server`, `server_port`, `auth_string`, `tls` | legacy; prefer hysteria2 |
| `tuic` | `server`, `server_port`, `uuid`, `password`, `tls` | `congestion_control` |
| `shadowtls` | `server`, `server_port`, `version`, `password`, `tls` | must chain via `detour` |
| `anytls` | `server`, `server_port`, `password`, `tls` | outbound does not require `padding_scheme` |
| `http` | `server`, `server_port` | `username`, `password`, `tls` |
| `socks` | `server`, `server_port` | `version`, `username`, `password` |
| `ssh` | `server`, `server_port`, `user` | `private_key`, `password` |

### Proxy Protocol Details

**Hysteria2:**
```json
{
  "type": "hysteria2",
  "tag": "hy2-out",
  "server": "example.com",
  "server_port": 443,
  "password": "your-password",
  "obfs": { "type": "salamander", "password": "obfs-password" },
  "up_mbps": 100, "down_mbps": 200,
  "tls": { "enabled": true, "server_name": "example.com" }
}
```
- `server_ports` ([]string): port hopping, e.g. `["1000:2000", "3000"]`
- `hop_interval` (Duration): port hop interval, default `30s`

**TUIC:**
```json
{
  "type": "tuic",
  "tag": "tuic-out",
  "server": "example.com",
  "server_port": 443,
  "uuid": "your-uuid",
  "password": "your-password",
  "congestion_control": "bbr",
  "udp_relay_mode": "native",
  "zero_rtt_handshake": true,
  "tls": { "enabled": true, "server_name": "example.com", "alpn": ["h3"] }
}
```
- `congestion_control`: `cubic` (default), `bbr`, `new_reno`
- `udp_relay_mode`: `native` (default), `quic`

**ShadowTLS:**
```json
{
  "type": "shadowtls",
  "tag": "st-out",
  "server": "example.com",
  "server_port": 443,
  "version": 3,
  "password": "your-password",
  "tls": { "enabled": true, "server_name": "www.microsoft.com", "utls": { "enabled": true, "fingerprint": "chrome" } }
}
```
ShadowTLS wraps another protocol. Chain with inner outbound:
```json
{ "type": "shadowsocks", "tag": "ss-inner", "method": "2022-blake3-aes-128-gcm", "password": "...", "detour": "st-out", "udp_over_tcp": { "enabled": true } }
```

**AnyTLS:**
```json
{
  "type": "anytls",
  "tag": "anytls-out",
  "server": "example.com",
  "server_port": 443,
  "password": "your-password",
  "tls": { "enabled": true, "server_name": "example.com" },
  "idle_session_check_interval": "30s",
  "idle_session_timeout": "2m",
  "min_idle_session": 2
}
```

### Special Outbounds
| Type | Fields | Notes |
|------|--------|-------|
| `direct` | - | Direct connection, supports Dial Fields |
| `selector` | `outbounds` (required), `default`, `interrupt_exist_connections` | Manual switch (Clash API) |
| `urltest` | `outbounds` (required), `url`, `interval`, `tolerance`, `idle_timeout` | Auto-select by latency |
| `block` | - | Still available; use `"action": "reject"` for ordinary rule blocking, reserve `type: "block"` for selector blocking choices |

### Endpoints (not outbounds — separate `endpoints` array)

**WireGuard:**
```json
{
  "type": "wireguard",
  "tag": "wg-ep",
  "address": ["10.0.0.2/32"],
  "private_key": "your-private-key",
  "peers": [{
    "address": "wg.example.com",
    "port": 51820,
    "public_key": "peer-public-key",
    "pre_shared_key": "optional",
    "allowed_ips": ["0.0.0.0/0"]
  }],
  "mtu": 1408,
  "workers": 2
}
```
Goes in top-level `"endpoints": [...]`, not `"outbounds"`. Routable as outbound by tag.

## Dial Fields (shared by outbounds + DNS servers)

- `detour`: Upstream outbound tag (other dial fields are ignored when enabled)
- `domain_resolver`: DNS server tag or an object with `server`, `strategy`, and optional cache, TTL, subnet, and query-timeout options.
- `bind_interface`: Network interface to bind
- `inet4_bind_address` / `inet6_bind_address`: IPv4/IPv6 address to bind
- `routing_mark`: Linux netfilter routing mark (supports integers and hexadecimal strings such as `"0x1234"`)
- `reuse_addr`: Reuse the listening address
- `netns`: Network namespace (Linux only)
- `connect_timeout`: Connection timeout (Duration)
- `tcp_fast_open`: Enable TFO (bool)
- `tcp_multi_path`: Enable MPTCP (bool)
- `disable_tcp_keep_alive`: Disable TCP Keep-Alive
- `tcp_keep_alive`: Initial Keep-Alive period (default `5m`)
- `tcp_keep_alive_interval`: Keep-Alive interval (default `75s`)
- `udp_fragment`: Enable UDP fragmentation
- `network_strategy`: `default`, `hybrid`, `fallback` (1.11.0+, mutually exclusive with `bind_interface`)
- `network_type` / `fallback_network_type`: `wifi`, `cellular`, `ethernet`, `other` (1.11.0+)
- `fallback_delay`: Delay before trying fallback network (default `300ms`)

## Multiplex (smux/h2mux)

Multiplexes multiple connections over a single TCP stream. Supported by: shadowsocks, vmess, vless, trojan.

```json
{
  "type": "vless",
  "multiplex": {
    "enabled": true,
    "protocol": "h2mux",
    "max_connections": 4,
    "min_streams": 4,
    "max_streams": 0,
    "padding": true,
    "brutal": { "enabled": true, "up_mbps": 50, "down_mbps": 100 }
  }
}
```
- `protocol`: `smux`, `yamux`, `h2mux` (default `h2mux`)
- `brutal`: TCP Brutal congestion control (requires server support)
- `padding`: randomize packet sizes to resist traffic analysis
- `max_connections` and `max_streams` are mutually exclusive; `min_streams` and `max_streams` are mutually exclusive

## UDP over TCP

Wrap UDP in TCP for protocols/networks that don't support UDP. Supported by: shadowsocks, socks.

```json
{ "udp_over_tcp": { "enabled": true, "version": 2 } }
```

## TLS Options (outbound)

```json
{
  "enabled": true,
  "server_name": "example.com",
  "insecure": false,
  "alpn": ["h2", "http/1.1"],
  "min_version": "1.2",
  "utls": { "enabled": true, "fingerprint": "chrome" },
  "reality": { "enabled": true, "public_key": "...", "short_id": "..." },
  "handshake_timeout": "15s"
}
```

### ECH (Encrypted Client Hello)
Encrypts SNI to prevent middlebox detection. Two modes:
- **Static config**: `config` is a PEM-format ECH configuration line array; alternatively use `config_path: "ech.pem"` to read a PEM file.
- **DNS query**: enable ECH and omit both static fields; query HTTPS records for `server_name`, optionally overriding the queried domain with `query_server_name`.

### TLS Fragment
Splits TLS ClientHello into small fragments to bypass DPI:
- `"fragment": true` on TLS options: fragment the TLS handshake
- `"fragment_fallback_delay"`: fallback wait when the segmentation delay cannot be detected automatically (default `"500ms"`)
- `"record_fragment": true`: also fragment TLS records (more aggressive)
- **`fragment` and `record_fragment` are mutually exclusive** and cannot be enabled simultaneously

Can also be set per-route via route-options action:
```json
{ "action": "route-options", "tls_fragment": true, "tls_fragment_fallback_delay": "500ms" }
```
Note: In route-options, `tls_fragment` is a bool (not an object), and `tls_record_fragment` is also a bool. These two are also mutually exclusive.

The default TLS engine is `go`. Native `apple` / `windows` engines have platform and feature restrictions; use the default engine for Reality/uTLS/ECH/fragmentation. `handshake_timeout` defaults to `15s`. Optional `spoof` / `spoof_method` require supported desktop platforms and elevated privileges; consult the official TLS reference when requested.

### uTLS Fingerprints
Available: `chrome`, `firefox`, `edge`, `safari`, `360`, `qq`, `ios`, `android`, `random`, `randomized`

## V2Ray Transport Options

| Type | Key Fields |
|------|-----------|
| `http` | `host` ([]string), `path`, `method`, `headers`, `idle_timeout`, `ping_timeout` |
| `ws` | `path`, `headers`, `max_early_data`, `early_data_header_name` |
| `grpc` | `service_name`, `idle_timeout`, `ping_timeout`, `permit_without_stream` |
| `httpupgrade` | `host`, `path`, `headers` |
| `quic` | (no additional fields, requires QUIC TLS) |

## Rule-Set

1.14.4 remote rule-set:

```json
{
  "type": "remote",
  "tag": "geosite-cn",
  "format": "binary",
  "url": "https://testingcf.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-cn.srs",
  "http_client": "rule-set-direct",
  "update_interval": "1d"
}
```

Formats: `source` (JSON, larger) or `binary` (SRS, smaller+faster).
Types: `remote` (URL download), `local` (file path), `inline` (embedded rules).
Define top-level `http_clients` plus `route.default_http_client`, or a per-rule-set HTTP client. Avoid the deprecated implicit default and `download_detour`.

```json
{
  "http_clients": [{ "tag": "rule-set-direct", "detour": "direct" }],
  "route": { "default_http_client": "rule-set-direct" }
}
```

HTTP clients accept a shared tag or an inline object. Default engine is `go`, default HTTP version is `2`; versions `1` and `3` are also supported. `initial_path` supplies initial remote rule-set content when no cache is available. Multiple rule-set tags can share a definition using a `{tag}` placeholder in the URL/path.

## Experimental

### Cache File
1.14.4 RealIP:

```json
{
  "enabled": true,
  "store_dns": true
}
```

1.14.4 FakeIP:

```json
{
  "enabled": true,
  "store_dns": true,
  "store_fakeip": true
}
```

- `store_fakeip`: Persists fakeip mappings so they are not lost after a restart (otherwise, "missing fakeip record" is reported)
- `store_dns`: DNS cache persistence. Combined with `dns.optimistic`, it can reduce latency for repeated queries.
- Omit deprecated `store_rdrc` and `rdrc_timeout`.
- `cache_id`: Isolates cache data between multiple configurations

### Clash API
```json
{
  "external_controller": "127.0.0.1:9090",
  "external_ui": "ui",
  "secret": "",
  "default_mode": "Rule"
}
```

## Route Top-Level Fields

```json
{
  "route": {
    "rules": [],
    "rule_set": [],
    "final": "proxy",
    "auto_detect_interface": true,
    "default_domain_resolver": "local-dns",
    "default_http_client": "rule-set-direct"
  }
}
```

- `final`: Default outbound when no rule matches
- `auto_detect_interface`: Bind to default interface (prevents TUN routing loops)
- `default_domain_resolver`: DNS server for resolving domain-based outbound addresses
- `default_http_client`: Default HTTP client tag or inline HTTP client for remote rule-set downloads

## DNS Top-Level Fields

1.14.4 RealIP (server definitions and rules omitted here):

```json
{
  "dns": {
    "servers": [],
    "rules": [],
    "final": "alidns",
    "strategy": "ipv4_only",
    "reverse_mapping": true,
    "optimistic": true
  }
}
```

- `final`: Default DNS server when no rule matches
- `strategy`: `prefer_ipv4`, `prefer_ipv6`, `ipv4_only`, `ipv6_only`
- `reverse_mapping`: Store real DNS A/AAAA answers as TTL-bound IP→domain mappings; required by RealIP TUN templates that rely on domain rules after DNS hijack. It does not prevent DNS pollution; route overseas/proxy domains to remote DNS with DNS rules.
- `optimistic`: Serves expired responses while refreshing in the background, within a timeout window. `true` uses `3d`; alternatively use `{"enabled": true, "timeout": "3d"}`. Conflicts with `disable_cache` and `disable_expire`.
- `timeout`: Default DNS query timeout, `10s`; overridable by DNS rule actions and `domain_resolver.timeout`.
- For IPv4-only application DNS, put `{"query_type":"AAAA","action":"predefined","rcode":"NOERROR"}` before other DNS rules. Do not treat global lookup strategy as a universal raw-query filter.

## Route-Options Action Fields

Non-final action that sets per-connection options without selecting an outbound:
```json
{
  "action": "route-options",
  "override_address": "1.2.3.4",
  "override_port": 443,
  "network_strategy": "hybrid",
  "fallback_delay": 300,
  "udp_disable_domain_unmapping": false,
  "udp_connect": true,
  "udp_timeout": "5m",
  "tls_fragment": true,
  "tls_fragment_fallback_delay": "500ms"
}
```
- `tls_fragment` and `tls_record_fragment` are **bool** values and are **mutually exclusive**
- `tls_fragment_fallback_delay`: Fallback wait when segmentation timing cannot be detected (default `500ms`)
- `fallback_delay` in route-options is an integer in milliseconds in the 1.14.4 option schema, unlike the duration-valued dial field.
- `udp_disable_domain_unmapping`: Do not send mapped domain names in UDP responses
- `udp_timeout`: Connection timeout (default 10s for DNS/NTP/STUN, 30s for QUIC/DTLS)

## NTP

```json
{
  "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m",
    "write_to_system": false
  }
}
```
Useful for TLS certificate validation when system clock is unreliable (embedded devices).

## Certificate

```json
{
  "certificate": {
    "store": "system",
    "certificate": [],
    "certificate_path": []
  }
}
```
- `store`: `system` (default), `mozilla`, `chrome`, `none`
- Custom CA certificates for self-signed proxy servers

## TUN Platform Options

### platform.http_proxy (GUI clients only)

`platform` contains platform-specific settings provided by GUI clients (SFM/SFA/SFI), primarily consumed by the GUI client's PlatformInterface. Command-line `sing-box run` should not rely on this block taking effect.

Sets the system HTTP proxy within TUN (VPN) through the Network Extension / VPN API. Unlike `set_system_proxy` on a mixed inbound — this does not call `networksetup`, but uses APIs within the VPN tunnel (Apple: `NEProxySettings`).

```json
{
  "type": "tun",
  "platform": {
    "http_proxy": {
      "enabled": true,
      "server": "127.0.0.1",
      "server_port": 2080,
      "bypass_domain": ["localhost", "internal.corp.com"],
      "match_domain": ["specific-app.com"]
    }
  }
}
```

| Field | Description |
|------|------|
| `enabled` | Enable the system HTTP proxy (default `false`) |
| `server` | Proxy server address (usually `127.0.0.1`, requires a listening mixed inbound) |
| `server_port` | Proxy server port |
| `bypass_domain` | Domains that bypass the proxy. **Apple platforms match suffixes** (`example.com` matches `api.example.com`) |
| `match_domain` | Domains that use the proxy. **Supported only by Apple GUI clients**; ignored on other platforms |

**Note:** HTTP and HTTPS use the same proxy server (in the Apple implementation, `httpServer` and `httpsServer` point to the same address).

### macOS TUN Permission Model

| Method | Permissions | Description |
|------|------|------|
| **SFM GUI client** | No root required (Network Extension) | Apple developer entitlement `packet-tunnel-provider`; the system kernel creates the TUN device |
| **SFM.System standalone mode** | No root required (System Extension) | Requires the user to approve installation in System Settings; runs outside the app sandbox |
| **Command-line `sing-box run`** | Requires **sudo** | Creates the utun device directly through the `com.apple.net.utun_control` socket |

### Android Per-App Proxy

```json
{
  "type": "tun",
  "include_package": ["com.android.chrome"]
}
```
- `include_package` / `exclude_package`: Android per-app proxy (package names)
- Choose inclusion or exclusion mode rather than configuring both.
- `include_uid` / `exclude_uid` / `include_uid_range` / `exclude_uid_range`: Linux UID-based filtering
- `route_address` / `route_exclude_address`: IP-based split tunneling

## Official References

- https://sing-box.sagernet.org/migration/
- https://sing-box.sagernet.org/configuration/dns/
- https://sing-box.sagernet.org/configuration/dns/rule/
- https://sing-box.sagernet.org/configuration/dns/rule_action/
- https://sing-box.sagernet.org/configuration/inbound/tun/
- https://sing-box.sagernet.org/configuration/shared/http-client/
- https://sing-box.sagernet.org/configuration/experimental/cache-file/
- https://sing-box.sagernet.org/configuration/shared/tls/
- https://sing-box.sagernet.org/configuration/endpoint/wireguard/
