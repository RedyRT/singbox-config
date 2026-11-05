# sing-box 1.14.4 Cookbook — How It Works and Configuration Patterns

> This document explains the **execution flow and interactions** of sing-box components; it is not a field reference (see config-schema.md for the field reference).

Target: [stable 1.14.4](https://github.com/SagerNet/sing-box/tree/v1.14.4). Consult the [official migration guide](https://sing-box.sagernet.org/migration/) and version badges when using the rolling documentation.

## 1. Connection Lifecycle: From TUN to the Destination

```
App initiates a connection (e.g. curl google.com)
  │
  ▼
① TUN captures IP packets → creates InboundContext (source IP/port, destination IP/port)
  │
  ▼
② matchRule() — main routing engine, iterates through route.rules in order
  │
   ├─ Looks up process information (process_name/path)
   ├─ FakeIP reverse lookup: is the destination IP in the fakeip store?
   │    Yes → restores metadata.Destination from IP to domain name, sets FakeIP=true
   ├─ RealIP reverse mapping: does the real destination IP have a DNS mapping?
   │    Yes → metadata.Domain = mapped domain name, for domain rule matching
  │
   ├─ Iterates through rules (first-final-action-wins):
   │    Rule 0: action=sniff → peeks at data, identifies protocol/domain, [does not stop; continues to the next rule]
   │    Rule 1: action=hijack-dns → matches? → hands off to DNS processing [stops]
   │    Rule 2: action=route → matches? → selects outbound [stops]
  │    Rule N: ...
  │
  ▼
③ Executes final action:
   hijack-dns → enters DNS routing (see Section 2)
   route      → sends the connection to the selected outbound
   reject     → returns RST/ICMP unreachable or silently drops
```

### Key Concepts

**Non-final actions (sniff/resolve/route-options) do not stop rule iteration.** They modify metadata and then continue matching the next rule. This means:

```
Rule 0: { "action": "sniff" }              ← identifies the domain google.com
Rule 1: { "domain": "google.com", ... }    ← can now match the domain
```

If sniff is placed after domain matching, the domain has not yet been identified and matching will fail. **Order determines everything.**

**Final actions (route/reject/hijack-dns) stop iteration immediately.** The first matching final action determines the fate of the connection; subsequent rules are not evaluated.

### When FakeIP Reverse Lookup Happens

FakeIP reverse lookup happens **before** rule iteration (the first step of matchRule). This means:
- The app connects to 198.18.0.32:443
- matchRule first checks the fakeip store → finds 198.18.0.32 = google.com
- metadata.Destination becomes google.com
- Subsequent rules match against the domain google.com rather than the IP

### When RealIP Reverse Mapping Happens

RealIP templates must set `dns.reverse_mapping: true`. After receiving a non-FakeIP A/AAAA response, the DNS router writes an in-memory `real IP -> domain` mapping with the DNS TTL. When a connection enters TUN, if the destination IP is not a FakeIP, the router checks `LookupReverseMapping()` and, on a hit, saves the domain to `metadata.Domain`; subsequent domain rules and sniff results jointly participate in matching.

The default 1.14.4 RealIP template combines `dns.reverse_mapping`, `dns.optimistic`, `store_dns`, and explicit HTTP clients for remote rule-set downloads.

RealIP gives applications real IPs and natural cache/debugging behavior. Shared IPs, expired mappings, ECH, and unsniffable traffic reduce domain attribution certainty. `reverse_mapping` does not prevent DNS poisoning; selected proxy domains need matching remote DNS rules. See `russia-dpi.md` for network filtering diagnostics.

## 2. DNS Query Flow

DNS queries have two entry points:

```
Entry A: hijack-dns (routing rule interception)
  App DNS query (UDP/TCP port 53) → routing rule match → hijack-dns → DNS routing

Entry B: domain_resolver (outbound domain resolution)
  Outbound needs to resolve a domain → directly calls the specified DNS server, [bypasses dns.rules]
```

### DNS Rule Matching

```
DNS query arrives
  │
  ▼
Iterates through dns.rules (matches in order; the first final action takes effect):
  │
   ├─ Match conditions: OR for fields of the same type, AND for fields of different types
   │   Example: domain_suffix=["cn","com.cn"] AND query_type=["A"]
   │   Meaning: (suffix is cn or com.cn) AND (query type is A)
  │
   ├─ Actions:
   │   route  → sends to the specified DNS server
    │   reject → returns REFUSED by default
  │
    ├─ evaluate → queries a server and saves a response; continues matching
    │   match_response + ip_accept_any/ip_cidr/ip_is_private/response_rcode
    │   → tests the evaluated response
    │   respond → returns that response; route → queries the selected server
  │
  ▼
No rule matches → uses the server specified by dns.final
```

### Hosts Fallback

Match domains actually provided by the hosts transport:

```json
{ "preferred_by": "hosts", "action": "route", "server": "hosts" }
```

### Explicit Response Matching

Evaluate first, then test and respond. This example falls back to remote DNS when the local response has no addresses:

```json
[
  { "action": "evaluate", "server": "local-dns" },
  { "match_response": true, "ip_accept_any": true, "action": "respond" },
  { "action": "route", "server": "remote-dns" }
]
```

This is not a poisoning detector: a poisoned address still satisfies `ip_accept_any`. Keep explicit remote DNS rules for known proxied domains. `evaluate` must be top-level; `match_response: true` refers to the latest untagged evaluation. Tagged evaluations use a string in `match_response`.

Do not mix legacy DNS address filters or DNS rule-action `strategy` with `query_type`/`ip_version` or response-matching features; such combinations can fail at startup.

### Cache Persistence and Isolation

1.14.4 keys DNS caches by transport automatically. Omit `independent_cache`. Use `experimental.cache_file.store_dns: true` instead of deprecated `store_rdrc` / `rdrc_timeout`.

`dns.optimistic: true` serves an expired cached response while refreshing it in the background, within the default `3d` window. It accepts an object such as `{"enabled": true, "timeout": "1h"}` and conflicts with `disable_cache` / `disable_expire`. DNS rule actions can set `disable_optimistic_cache` for selected queries.

## 3. How DNS Strategy (strategy) Works

Global `dns.strategy` controls address lookup preferences; `ipv4_only` requests IPv4, `ipv6_only` requests IPv6, and `prefer_ipv4` / `prefer_ipv6` order dual-stack results. Resolver and route `resolve` strategies remain supported.

Do not assume this alone filters every application DNS packet. For the bundled IPv4-only policy, put this rule first:

```json
{ "query_type": "AAAA", "action": "predefined", "rcode": "NOERROR" }
```

It returns a successful empty response for intercepted AAAA queries before hosts, Clash modes, or FakeIP rules. Remove it when enabling full IPv6 support. HTTPDNS and application-managed DoH are outside this rule's scope.

## 4. Complete FakeIP Lifecycle

```
① DNS query: google.com A?
   │
   ▼
② dns.rules matches the fakeip server
   │
   ▼
③ FakeIP generation:
   - Allocates IPs sequentially from inet4_range (198.18.0.0/15)
   - Stores a bidirectional mapping: 198.18.0.32 ↔ google.com
   - Persists to cache.db when store_fakeip=true
   │
   ▼
④ Returns 198.18.0.32 to the app
   │
   ▼
⑤ App connects to 198.18.0.32:443
   │
   ▼
⑥ TUN captures → matchRule():
   - Looks up the fakeip store: 198.18.0.32 → google.com
   - metadata.Destination = google.com (no longer an IP)
   - metadata.FakeIP = true
   │
   ▼
⑦ Routing rules match against the domain google.com
   │
   ▼
⑧ Outbound establishes a connection using the domain google.com
   (the proxy protocol sends the domain; the remote server resolves the real IP)
```

### FakeIP Step 7: Outbound Type Determines DNS Resolution (Verified Against Source Code)

After FakeIP reverse lookup restores the domain and routing rules select an outbound, the actual DNS resolution behavior varies by outbound type:

| Outbound type | DNS behavior |
|---------|---------|
| **proxy** (vless/vmess/trojan/ss/socks5/http) | Sends the domain unchanged to the remote proxy server. **No local DNS resolution.** |
| **direct** | Requires local resolution. Priority: 1) the outbound's `domain_resolver`, 2) `route.default_domain_resolver` (fallback), 3) the default DNS transport |

**Key implications:**
- In the bundled selective FakeIP variant, `dns.final: "local-dns"` handles all unmatched domains, including address queries. Selected non-address queries use `remote-dns`.
- Real DNS resolution for a direct outbound is controlled by `route.default_domain_resolver`, **not** `dns.final`
- A proxy outbound performs no local DNS resolution at all — the proxy server handles resolution

### FakeIP Cache Pitfalls

`store_fakeip: true` persists mappings. If you **change DNS rules to make a domain bypass fakeip**, the old fakeip mapping still exists:
- Query arrives → dns.rules matches the new rule → resolves via local-dns → returns a real IP ✓
- But if the app cached the old fakeip address and connects directly to it → TUN can still find the mapping in the fakeip store → still follows the fakeip path

**Solution:** After changing fakeip-related rules, you must clear the SFM cache and restart the VPN.

### Choosing Between RealIP and FakeIP Templates

| Template | Advantages | Trade-offs |
|------|------|------|
| RealIP template (compatibility first) | Applications receive real IPs; browser Local Network Access, Service Workers, system caches, and packet-capture debugging behave more intuitively; suitable for most TUN and browser scenarios. | Domain recovery relies on TTL-based `dns.reverse_mapping` mappings and sniffing, and may be less certain than FakeIP with shared CDN IPs, ECH, non-TLS traffic, or traffic that cannot be sniffed. |
| FakeIP template (split-routing certainty first) | Assigns a fake IP to each domain during DNS resolution, allowing more certain reverse lookup back to the domain during connection handling; suitable for scenarios requiring strong domain-based split routing where RealIP reverse mapping/sniffing is not stable enough. | May trigger browser Local Network Access; fake IPs may contaminate Service Worker/browser caches; missing mappings produce `missing fakeip record`; old mappings may remain after rule changes; IP semantics in ping/traceroute/logs are distorted. |

FakeIP can reduce application-side DNS waiting because it answers address queries without real resolution. Real resolution still occurs at the remote proxy or the direct outbound. For DNS latency alone, prefer `dns.optimistic`, `store_dns`, simpler rules, or a browser-specific mixed/socks/http inbound. Choose FakeIP when deterministic domain recovery is also needed.

If LNA, Service Worker, or cache contamination issues have already appeared in browser scenarios, prefer RealIP TUN or provide a separate mixed/socks/http inbound for the browser, allowing it to pass domain names to the proxy chain rather than continuing to rely on FakeIP.

## 5. Routing Rule Matching Logic

### Rules for Combining Conditions

Within a field, values use OR. Related destination fields (domain/IP), port fields, source-address fields, and source-port fields form OR groups; those groups and other fields combine with AND. Use logical rules for explicit combinations.

```json
{
  "domain_suffix": [".google.com", ".youtube.com"],  ← OR: matches either suffix
  "port": [80, 443],                                  ← OR: matches either port
  "network": "tcp",                                    ← AND: must be TCP
  "action": "route", "outbound": "proxy"
}
```
Meaning: `(google.com OR youtube.com) AND (port 80 OR 443) AND (TCP)` → proxy

### logical Rules

Use `"type": "logical"` for more complex combinations:

```json
{
  "type": "logical",
  "mode": "or",      // OR between sub-rules (can also be "and")
  "rules": [
    { "protocol": "dns" },
    { "port": 53 }
  ],
  "action": "hijack-dns"
}
```

### Rule Ordering Pitfalls

Routing rules **short-circuit in order**. Common mistakes:

```
❌ Incorrect order:
  Rule: ip_is_private → direct     ← 172.19.0.2 (TUN gateway) matches!
  Rule: port 53 → hijack-dns      ← never reached

✅ Correct order:
  Rule: action=sniff               ← sniff the protocol first
  Rule: port 53 OR protocol dns → hijack-dns  ← handle DNS first
  Rule: ip_is_private → direct     ← only other private IPs go direct
```

Another example (global blocking breaks ordinary direct traffic):
```
❌ Incorrect:
  Rule: reject UDP 443             ← ordinary QUIC is blocked here
  Fallback: direct                 ← connection never reaches fallback

✅ Correct: do not reject UDP 443 globally; scope any workaround to the affected service
```

## 6. auto_route / strict_route / auto_detect_interface

### What auto_route Actually Does

`auto_route` points the system default route to the TUN interface, sending all traffic into TUN:

- **Linux**: Creates iproute2 policy routing rules (default table 2022, rule priorities starting at 9000), directing matching traffic to the TUN routing table
- **macOS (command line)**: Adds routes through the system routing table (using subnet splitting to avoid overwriting the default route)
- **macOS/iOS/Android (graphical clients)**: Configured through the Network Extension / VpnService API, with routing managed by the system

`auto_route` only handles routing; it **does not prevent loops**. It must be used with `route.auto_detect_interface` or `route.default_interface`.

### What strict_route Means

`strict_route` varies by platform:

**Linux:**
- Adds `UNREACHABLE` rules for address families **not configured** on TUN (such as when no IPv6 address is configured) → traffic for that protocol family fails immediately rather than leaking to a real interface
- When neither `strict_route` nor `auto_redirect` is enabled, all ICMP traffic bypasses TUN
- With `auto_redirect` enabled, `strict_route` also controls whether `SO_BINDTODEVICE` traffic (such as Docker) is redirected into sing-box

**Windows:**
- Prevents DNS leaks caused by Windows multihomed DNS resolution (Windows queries DNS on all network interfaces simultaneously by default)

**macOS/mobile:**
- No special effect (VPN mode itself already captures all traffic)

### auto_detect_interface Loop Prevention Mechanism

`auto_detect_interface` itself **does not prevent loops**. What it does is:

1. Monitors changes to the system's default network interface
2. Automatically binds an outbound to the detected default interface when no interface is explicitly bound

**How loop prevention actually works:**
- The TUN interface receives traffic (through the routing table)
- Outbound traffic is bound to a **physical interface** (such as en0), bypassing TUN
- Traffic on the physical interface is not routed back into TUN

If `auto_detect_interface: false`, the outbound does not bind to an interface, and outgoing traffic may be sent back to TUN by the routing table → infinite loop.

### auto_redirect (Recommended on Linux)

`auto_redirect` builds on `auto_route`, using nftables for more efficient traffic redirection:
- Better performance than tproxy
- Avoids conflicts between TUN and Docker bridges
- Supports automatic compatibility with OpenWrt fw4
- Recommended to always enable on Linux

## 7. domain_resolver vs dns.rules

These are two completely independent DNS resolution paths:

| | dns.rules | domain_resolver |
|---|---|---|
| Trigger | DNS queries intercepted by hijack-dns | Outbound resolving a server domain |
| Rules | Full matching through dns.rules | Uses the specified DNS server directly, **bypassing dns.rules** |
| Use cases | App DNS queries | Proxy node address resolution, rule-set URL resolution |
| Configuration | `dns.rules` | `domain_resolver` on the outbound or `default_domain_resolver` on route |

An explicit `default_domain_resolver: "local-dns"` resolves proxy node domains independently of DNS split rules. This avoids requiring a connected proxy to resolve its own hostname.

## 8. Choosing a TUN Stack

| Stack | TCP | UDP | Compatibility | Performance |
|---|---|---|---|---|
| `system` | System stack | System stack | Platform-dependent | High |
| `gvisor` | Userspace TCP | Userspace UDP | Complete, but may have edge-case issues | Medium |
| `mixed` | System TCP | gvisor UDP | **Recommended** | High |

`mixed` uses the system TCP stack and gVisor UDP stack and remains the template default for 1.14.4. Do not apply the 1.15 stack migration to this release.

## 9. Common Configuration Patterns

### Pattern A: Hosts-Aware Matching
```json
{ "preferred_by": "hosts", "action": "route", "server": "hosts" }
```

### Pattern B: Selective DNS for Blocked Domains

RealIP templates use real DNS split routing by default:

```json
{ "rule_set": "geosite-ru-blocked", "action": "route", "server": "remote-dns" }
```

FakeIP templates insert an address-query rule before remote DNS for the same selected domains:

```json
[
  { "rule_set": "geosite-ru-blocked", "query_type": ["A","AAAA"], "action": "route", "server": "fakeip-dns" },
  { "rule_set": "geosite-ru-blocked", "action": "route", "server": "remote-dns" }
]
```
Both variants use `dns.final: "local-dns"`. Keep AAAA suppression, hosts, Clash overrides, and ad rejection before these rules. FakeIP must not catch unmatched domains or non-address queries.

### Pattern C: "Direct Connections by Domain"
Requires both DNS and routing rules before the blocked-domain rules. In FakeIP templates, put the DNS exception before selective FakeIP too:
```json
// dns.rules: real resolution
{ "domain_suffix": ["example.com"], "server": "local-dns" }
// route.rules: direct connection
{ "domain_suffix": ["example.com"], "outbound": "direct" }
```

### Pattern D: "Split Routing by Service"
```json
// outbounds: one selector per service
{ "type": "selector", "tag": "google", "outbounds": ["proxy","direct"] }
// route.rules: service → corresponding selector
{ "rule_set": "geosite-google", "outbound": "google" }
```
Users can switch each service independently between proxy and direct connections through a Clash API dashboard.

Declare the service rule-set and add a matching DNS rule; otherwise domains absent from `ru-blocked` still use local DNS:

```json
{ "rule_set": "geosite-google", "action": "route", "server": "remote-dns" }
```

In FakeIP mode, optionally precede that rule with a service-scoped address rule:

```json
{ "rule_set": "geosite-google", "query_type": ["A", "AAAA"], "action": "route", "server": "fakeip-dns" }
```

Keep the remote rule for non-address queries and AAAA suppression first. Service overrides precede existing blocked-domain rules in both DNS and routing. Selector changes do not automatically change DNS; a full direct exception requires paired local-DNS/direct rules.

## 10. HTTPDNS and TUN IPv6 Pitfalls

### Problem

Apps such as WeChat use HTTPDNS (obtaining IP addresses through HTTP requests) instead of standard DNS. HTTPDNS responses are inside the HTTP payload, completely invisible to sing-box's DNS module. Therefore, `dns.strategy: "ipv4_only"` cannot prevent these apps from obtaining IPv6 addresses.

### The Fatal Impact of a TUN IPv6 Address

When an IPv6 address is configured on TUN, the system creates IPv6 routes and apps consider IPv6 available:
- WeChat obtains an IPv6 address for `wx.qlogo.cn` through HTTPDNS
- The app connects over IPv6 → enters TUN → direct outbound → physical network adapter has no IPv6 → failure
- The app sees a valid IPv6 route (pointing to TUN) and keeps retrying instead of falling back to IPv4 (Happy Eyeballs fails)

**WeChat works normally without TUN** because: the system has no IPv6 route → the kernel immediately returns `ENETUNREACH` → the app instantly falls back to IPv4 through Happy Eyeballs.

### Fix

Remove the IPv6 address from TUN, keeping only IPv4:
```json
"address": "172.19.0.1/30"
```

Keep `dns.strategy: "ipv4_only"` and the explicit AAAA-suppression DNS rule. Neither can control addresses obtained through HTTPDNS.

## 11. Proxy Chains (Chained Outbounds / Detour)

Use the `detour` field to chain multiple outbounds. The inner outbound sends traffic through the outer outbound's tunnel.

```
App → sing-box → ShadowTLS (outer) → Shadowsocks (inner) → destination
```

```json
// Outer: ShadowTLS camouflage
{
  "type": "shadowtls", "tag": "st-out",
  "server": "example.com", "server_port": 443,
  "version": 3, "password": "st-password",
  "tls": { "enabled": true, "server_name": "www.microsoft.com", "utls": { "enabled": true, "fingerprint": "chrome" } }
}
// Inner: Shadowsocks through the ShadowTLS tunnel
{
  "type": "shadowsocks", "tag": "ss-out",
  "server": "127.0.0.1", "server_port": 0,
  "method": "2022-blake3-aes-128-gcm", "password": "ss-password",
  "detour": "st-out",
  "udp_over_tcp": { "enabled": true }
}
```

For this ShadowTLS wrapping pattern, the outer outbound determines the physical server connection. Do not generalize that to all detours: a normal proxy-to-proxy chain still needs the inner proxy's actual server address and port, which the upstream proxy connects to.

## 12. Multiplexing (Multiplex / Mux)

Combines multiple connections into a single underlying TCP connection to reduce handshake overhead, with optional traffic padding.

```json
{
  "type": "vless",
  "multiplex": {
    "enabled": true,
    "protocol": "h2mux",
    "max_connections": 4,
    "min_streams": 4,
    "padding": true,
    "brutal": { "enabled": true, "up_mbps": 50, "down_mbps": 100 }
  }
}
```

- `h2mux` is recommended (HTTP/2 multiplexing); `smux` has better compatibility but lower efficiency
- `brutal` enables TCP Brutal congestion control (the server must also support and enable brutal)
- `padding: true` adds random bytes to resist traffic analysis
- **Note:** The server must also enable multiplex; otherwise, connections fail

## 13. TLS Fragmentation (Anti-DPI)

Splits TLS ClientHello into small fragments to bypass DPI (deep packet inspection).

### Method A: Global TLS Options
```json
{
  "tls": {
    "enabled": true,
    "fragment": true,
    "fragment_fallback_delay": "500ms"
  }
}
```

### Method B: Per Routing Rule (route-options)
```json
{
  "rule_set": "geosite-ru-blocked",
  "action": "route-options",
  "tls_fragment": true,
  "tls_fragment_fallback_delay": "500ms"
}
```

`tls_fragment` is a boolean, not an object. `fragment_fallback_delay` is the wait used when segmentation timing cannot be detected, not a retry timeout. TLS `fragment` and `record_fragment` are mutually exclusive; route `tls_fragment` and `tls_record_fragment` are also mutually exclusive. Choose one method, preferably record fragmentation first as advised by the official documentation.

## 14. Android Per-App Proxying

Use `include_package` / `exclude_package` to control which apps use TUN:

```json
{
  "type": "tun",
  "include_package": [
    "com.google.android.youtube",
    "org.telegram.messenger"
  ]
}
```

Or exclusion mode (proxy all apps except those specified):
```json
{
  "type": "tun",
  "exclude_package": [
    "com.tencent.mm",
    "com.tencent.mobileqq"
  ]
}
```

**Do not use include and exclude together.** Usually, `exclude_package` is more practical — proxy everything by default and exclude apps that do not need it.

## 15. Network Strategy (Mobile WiFi/Cellular Switching)

`network_strategy` controls outbound behavior in multi-network environments (such as WiFi + cellular on a phone):

```json
{
  "route": {
    "default_network_strategy": "hybrid",
    "default_network_type": ["wifi"],
    "default_fallback_network_type": ["cellular"],
    "default_fallback_delay": "100ms"
  }
}
```

| Strategy | Behavior |
|------|------|
| `default` | Uses only the default network interface |
| `hybrid` | Tries all available networks simultaneously and uses the fastest |
| `fallback` | Tries the preferred network first, then falls back to the alternative after a timeout |

You can also set `network_strategy`, `network_type`, and `fallback_network_type` in an individual outbound's dial fields.

## 16. Conditional Routing by WiFi SSID

Switch behavior based on the name of the currently connected WiFi network:

```json
{
  "wifi_ssid": ["HomeWiFi", "OfficeWiFi"],
  "action": "route",
  "outbound": "direct"
}
```

Use case: connect directly on office/home WiFi and use a proxy on other WiFi networks. Can be combined with DNS rules.

## 17. ECH (Encrypted Client Hello)

ECH encrypts the SNI in the TLS handshake, preventing intermediate devices from detecting the destination domain.

```json
{
  "tls": {
    "enabled": true,
    "server_name": "example.com",
    "ech": {
      "enabled": true
    }
  }
}
```

Three configuration modes:
1. **Automatic DNS query** (recommended): set only `"enabled": true`; sing-box automatically queries DNS HTTPS records to obtain the ECH configuration
2. **Manual configuration**: `config` contains PEM-format ECH configuration lines
3. **File path**: `"config_path": "path/to/ech.pem"`

**Note:** ECH requires server-side support. CDNs such as CloudFlare generally support it.
