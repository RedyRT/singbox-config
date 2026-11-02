# sing-box Cookbook — How It Works and Configuration Patterns

> This document explains the **execution flow and interactions** of sing-box components; it is not a field reference (see config-schema.md for the field reference).

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

1.13 already supports `dns.reverse_mapping`, so the 1.13 RealIP TUN template can serve as a stable default. The RealIP enhancements in 1.14 are `dns.optimistic`, `store_dns`, and new HTTP client and DNS rule capabilities, rather than the introduction of RealIP itself.

The advantage of RealIP is that applications receive real IPs, giving browsers, system caches, and debugging tools natural semantics; its weaknesses are that one real IP may correspond to multiple domains, mappings expire with their TTL, and ECH, non-TLS traffic, and traffic that cannot be sniffed reduce the certainty of domain attribution. `reverse_mapping` does not prevent DNS poisoning; protection against poisoning relies on DNS rules sending proxied/overseas domains to remote DNS.

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
   │   reject → returns NXDOMAIN
  │
   ├─ Response filtering (A/AAAA/HTTPS only):
   │   ip_accept_any: accepts if the response contains any IP
   │   ip_cidr: accepts only if the response IP is within the specified CIDR range
   │   ip_is_private: accepts only if the response IP is a private address
  │
   │   ↳ If the response does not satisfy the filter → skips this rule and continues matching the next
  │
  ▼
No rule matches → uses the server specified by dns.final
```

### What ip_accept_any Really Means

**It is a response filter, not a query filter.** Execution order:

1. The query is sent to the hosts server
2. hosts returns a response (which may contain IPs or be empty)
3. `ip_accept_any` checks: does the response contain any IP?
   - Yes → accepts the response; the rule matches
   - No → the rule does not match; **continues to the next rule**

This implements the "check hosts first, fall through if not found" pattern:
```json
{ "ip_accept_any": true, "action": "route", "server": "hosts" }
```

### RDRC (Rejected DNS Response Cache)

RDRC caches rejection results from DNS response filters (`ip_cidr`, `ip_is_private`, `ip_accept_any`).

Workflow:
1. A DNS query for `google.com` matches the `alidns` (domestic Chinese DNS) rule
2. alidns returns a poisoned IP (such as `203.0.113.1`)
3. The rule's response filter (such as a non-matching `ip_cidr` or an empty result for `ip_accept_any`) rejects the response
4. RDRC caches: `alidns + google.com + A → rejected`
5. The next time a `google.com` query arrives, the alidns rule is skipped directly without sending an actual DNS request
6. Matching continues with the next rule (such as fakeip or google-dns)

**Why this matters:** In the hosts fallthrough pattern (`ip_accept_any`), hosts returns empty results for most domains → every query must ask hosts first before falling through. Once RDRC caches the empty results, subsequent queries skip the hosts rule directly.

`store_rdrc: true` persists RDRC to cache.db so it survives restarts. `rdrc_timeout` defaults to 7 days.

### What independent_cache Does

- `false` (default): a global cache, shared across DNS servers for the same domain
- `true`: a separate cache for each DNS server

Why split-routing scenarios require `true`: if google.com is first resolved by alidns (returning a poisoned IP), google-dns will also hit that poisoned result once cached. Independent caches prevent cross-contamination.

## 3. How DNS Strategy (strategy) Works

strategy filters in **both the query and response phases**:

| Strategy | Query phase | Response phase |
|------|---------|---------|
| `ipv4_only` | Receives an AAAA query → immediately returns an empty successful response | Returns only A records |
| `ipv6_only` | Receives an A query → immediately returns an empty successful response | Returns only AAAA records |
| `prefer_ipv4` | Queries both types | Places A records first |
| `prefer_ipv6` | Queries both types | Places AAAA records first |

`ipv4_only` does not "discard AAAA responses"; it never sends AAAA queries in the first place, so no IPv6 addresses are produced at all.

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
- `dns.final` (such as google-dns) is rarely used in fakeip scenarios — it only handles non-A/AAAA queries (MX, TXT, SRV)
- Real DNS resolution for a direct outbound is controlled by `route.default_domain_resolver`, **not** `dns.final`
- A proxy outbound performs no local DNS resolution at all — the proxy server handles resolution

### FakeIP Cache Pitfalls

`store_fakeip: true` persists mappings. If you **change DNS rules to make a domain bypass fakeip**, the old fakeip mapping still exists:
- Query arrives → dns.rules matches the new rule → resolves via alidns → returns a real IP ✓
- But if the app cached the old fakeip address and connects directly to it → TUN can still find the mapping in the fakeip store → still follows the fakeip path

**Solution:** After changing fakeip-related rules, you must clear the SFM cache and restart the VPN.

### Choosing Between RealIP and FakeIP Templates

| Template | Advantages | Trade-offs |
|------|------|------|
| RealIP template (compatibility first) | Applications receive real IPs; browser Local Network Access, Service Workers, system caches, and packet-capture debugging behave more intuitively; suitable for most TUN and browser scenarios. | Domain recovery relies on TTL-based `dns.reverse_mapping` mappings and sniffing, and may be less certain than FakeIP with shared CDN IPs, ECH, non-TLS traffic, or traffic that cannot be sniffed. |
| FakeIP template (split-routing certainty first) | Assigns a fake IP to each domain during DNS resolution, allowing more certain reverse lookup back to the domain during connection handling; suitable for scenarios requiring strong domain-based split routing where RealIP reverse mapping/sniffing is not stable enough. | May trigger browser Local Network Access; fake IPs may contaminate Service Worker/browser caches; missing mappings produce `missing fakeip record`; old mappings may remain after rule changes; IP semantics in ping/traceroute/logs are distorted. |

FakeIP can reduce application-side DNS waiting because the FakeIP transport returns fake IPs directly for A/AAAA without performing real DNS queries. But real resolution has not disappeared: proxy outbounds usually delegate resolution to the remote end, while direct outbounds still require local resolution. If the main concern is simply DNS latency, prefer `dns.optimistic`, `store_dns`, and caching strategies in 1.14; in 1.13, prefer ordinary DNS cache, simplified rules, or a browser-specific mixed/socks/http inbound. Choose FakeIP only when certainty of domain recovery during connection handling is also needed.

If LNA, Service Worker, or cache contamination issues have already appeared in browser scenarios, prefer RealIP TUN or provide a separate mixed/socks/http inbound for the browser, allowing it to pass domain names to the proxy chain rather than continuing to rely on FakeIP.

## 5. Routing Rule Matching Logic

### Rules for Combining Conditions

Within a single rule: **AND for fields of different types, OR for fields of the same type**

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

Another example (anti-leak blocking domestic Chinese apps):
```
❌ Incorrect:
  Rule: reject UDP 443             ← WeChat QUIC is blocked here
  Rule: geosite-cn → direct        ← WeChat never reaches this rule

✅ Correct: do not reject UDP 443 globally, or move the CN rule earlier
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

This means that even if dns.rules contains complex split-routing logic, `default_domain_resolver: "alidns"` is completely unaffected by dns.rules when resolving proxy node domains.

## 8. Choosing a TUN Stack

| Stack | TCP | UDP | Compatibility | Performance |
|---|---|---|---|---|
| `system` | System TCP stack | Unsupported | Best TCP compatibility | High |
| `gvisor` | Userspace TCP | Userspace UDP | Complete, but may have edge-case issues | Medium |
| `mixed` | System TCP | gvisor UDP | **Recommended** | High |

`mixed` combines the advantages of both: TCP uses the system stack for compatibility, while UDP uses gvisor for support.

## 9. Common Configuration Patterns

### Pattern A: "Query First, Then Match" (hosts fallthrough)
```json
{ "ip_accept_any": true, "server": "hosts" }  // Use the result if found; otherwise continue
```

### Pattern B: "Split DNS Routing for Domestic Chinese and Overseas Domains"

RealIP templates use real DNS split routing by default:

```json
{ "rule_set": "geosite-cn", "server": "alidns" },
{ "rule_set": ["geosite-google", "geosite-geolocation-!cn"], "server": "google-dns" }
```

Only FakeIP templates use FakeIP as the fallback:

```json
{ "rule_set": "geosite-cn", "server": "alidns" },     // Domestic Chinese domains → domestic Chinese DNS
{ "query_type": ["A","AAAA"], "server": "fakeip-dns" } // Others → FakeIP
```
Order matters: geosite-cn must precede fakeip; otherwise, domestic Chinese domains will also be intercepted by fakeip.

### Pattern C: "Direct Connections by Domain"
Requires both DNS and routing rules, both before the CN/proxy fallback. In FakeIP templates, they must also precede the fakeip fallback:
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

Keep `dns.strategy: "ipv4_only"` (it works for standard DNS), but it does not solve the HTTPDNS problem.

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

`server`/`server_port` are ignored when `detour` is present; traffic goes directly into the outbound specified by detour. However, the fields must still be present (they can be set to arbitrary values).

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
    "fragment_fallback_delay": "500ms",
    "record_fragment": true
  }
}
```

### Method B: Per Routing Rule (route-options)
```json
{
  "rule_set": "geosite-geolocation-!cn",
  "action": "route-options",
  "tls_fragment": { "enabled": true, "size": "1:5", "delay": "0:5" }
}
```

`size` and `delay` use the `"min:max"` format (bytes/milliseconds), choosing a random value each time.

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
2. **Manual configuration**: `"config": ["base64-encoded-ECHConfigList"]`
3. **File path**: `"config_path": "path/to/ech.pem"`

**Note:** ECH requires server-side support. CDNs such as CloudFlare generally support it.
