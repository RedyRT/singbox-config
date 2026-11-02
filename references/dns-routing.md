# DNS, RealIP, FakeIP, and IPv6 (1.14.4)

Sources: [DNS](https://sing-box.sagernet.org/configuration/dns/), [DNS rule actions](https://sing-box.sagernet.org/configuration/dns/rule_action/), [TUN](https://sing-box.sagernet.org/configuration/inbound/tun/), and [migration](https://sing-box.sagernet.org/migration/). Check feature version badges against 1.14.4.

## DNS hijack

Use `dns_mode: "hijack"` with `auto_route: true`. With `dns_address` unset, the next address after the TUN address is used and traffic to it is handled as `hijack-dns`. An explicit `dns_address` requires matching DNS hijack rules. Keep the routing rules below to intercept other port-53 DNS traffic too.

The first two route rules in TUN templates must be:

```json
{ "action": "sniff" },
{
  "type": "logical",
  "mode": "or",
  "rules": [{ "protocol": "dns" }, { "port": 53 }],
  "action": "hijack-dns"
}
```

Without `sniff` first, protocol detection has not yet run. Using only `"protocol": "dns"` misses some UDP DNS traffic; combine it with `port: 53` for reliable capture.

## RealIP Templates

RealIP templates use real DNS responses. With `dns.reverse_mapping: true`, the DNS router stores non-FakeIP A/AAAA responses in an in-memory `real IP -> domain` mapping according to their TTL. When a connection enters routing, FakeIP is checked first; on a miss, reverse mapping is checked and combined with sniffing to support domain-rule matching.

The stable 1.14.4 RealIP template is the default. It uses `dns.reverse_mapping`, `dns.optimistic`, `store_dns`, explicit HTTP clients, and hosts-aware DNS rules.

`reverse_mapping` does not validate or correct DNS responses. A poisoned answer produces a poisoned mapping. Route selected blocked domains to proxied remote DNS, matching the domain lists in traffic routing; unmatched domains intentionally use local DNS.

Advantages:

- Applications receive real IP addresses.
- Browser behavior, system caches, packet captures, and logs retain natural semantics.
- Suitable for most TUN and browser scenarios.

Trade-offs:

- Multiple domains may share a real IP address.
- Mappings expire according to TTL.
- ECH, non-TLS traffic, and traffic that cannot be sniffed reduce domain-attribution certainty.

## FakeIP Templates

FakeIP templates return fake IP addresses during DNS resolution and maintain a dedicated `fake IP <-> domain` mapping. When a connection enters routing, if the destination IP is within the fake IP range, routing can look up the domain directly.

Advantages:

- More deterministic domain recovery at connection time.
- Can reduce application-side DNS waiting because A/AAAA queries immediately return fake IP addresses.

Trade-offs:

- May trigger browser Local Network Access checks.
- May contaminate Service Worker / browser caches.
- Missing mappings cause `missing fakeip record`.
- Old mappings may persist after rule changes.
- IP semantics in ping/traceroute/logs become misleading.

FakeIP does not eliminate real resolution: proxy outbounds usually pass the domain to the remote proxy for resolution; direct outbounds still need local resolution. For DNS latency alone, prioritize `dns.optimistic`, `store_dns`, simpler rules, or a browser-specific mixed/socks/http inbound.

`dns.optimistic: true` uses a `3d` stale-cache window. An object such as `{"enabled": true, "timeout": "1h"}` customizes it. It conflicts with `disable_cache` and `disable_expire`; individual DNS rule actions can disable optimistic caching. Persist the full DNS cache with `store_dns`, and omit deprecated `independent_cache`, `store_rdrc`, and `rdrc_timeout`.

## FakeIP Lifecycle

1. An application queries A/AAAA records for `example.com`.
2. A DNS rule selects `fakeip-dns`.
3. The FakeIP transport returns a fake IP without a real DNS query.
4. The application connects to the fake IP.
5. The router detects that the destination is in the fake IP range and looks up the domain.
6. Routing rules match the domain and select an outbound.
7. Only at the outbound stage does the outbound type determine whether real resolution is needed.

| Outbound type | DNS behavior |
|----------|----------|
| proxy | Usually sends the domain to the remote proxy without local resolution |
| direct | Must resolve locally using outbound `domain_resolver` or route `default_domain_resolver` |
| socks4 | The protocol does not support FQDNs; local resolution is required |

## Default DNS Rule Structure

RealIP template defaults:

- The IPv4-only AAAA-suppression rule runs first, then hosts-aware matching with `preferred_by: "hosts"`.
- Clash Direct uses local DNS; Global uses remote DNS. Ads are rejected in Rule mode.
- `geosite-ru-blocked` uses `remote-dns` (DoH through `proxy`).
- `dns.final` is `local-dns` and `route.final` is `direct`.

FakeIP template defaults:

- Only `geosite-ru-blocked` address queries use `fakeip-dns`; the earlier AAAA rule means only A reaches it by default.
- Selected non-address queries use `remote-dns`; unmatched queries use real local DNS.
- `experimental.cache_file.store_fakeip: true` must be enabled.

DNS does not follow `blocked-services` selector changes. Selecting direct traffic still leaves the configured DNS policy in place. Full direct exceptions need both DNS and route rules before the blocked-domain rules. Flush application DNS caches and reconnect when testing policy changes.

## Default IPv6 Strategy

Use IPv4-only by default:

```json
"strategy": "ipv4_only"
```

Also put this explicit rule first in `dns.rules` to suppress intercepted application AAAA queries, including before Clash mode and FakeIP rules:

```json
{ "query_type": "AAAA", "action": "predefined", "rcode": "NOERROR" }
```

Global strategy remains a lookup preference; do not rely on it as a universal filter for raw DNS exchanges. Do not use deprecated DNS rule-action `strategy` alongside `query_type`/`ip_version` or modern response matching. For address-based response filtering, evaluate a response first and use `match_response`.

Unless the user confirms that IPv6 works on the actual network and requests full IPv6 TUN support, do not assign an IPv6 address to the TUN inbound:

```json
"address": "172.19.0.1/30"
```

Do not use this on networks without working IPv6:

```json
"address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"]
```

Reason: assigning an IPv6 address to TUN makes the system consider IPv6 available. Applications such as WeChat may obtain IPv6 addresses through HTTPDNS, bypass the sing-box DNS module, and then connect to the raw IPv6 address, causing `no route to host` and unreliable IPv4 fallback.

| Network environment | TUN addresses | Behavior |
|----------|----------|------|
| IPv4 only | IPv4 only | IPv4 is captured; IPv6 fallback depends on application and platform behavior |
| IPv4 + IPv6 | IPv4 only | IPv4 is captured; IPv6 may bypass TUN or be blocked by platform strict-routing behavior |
| IPv4 + IPv6 | IPv4 + IPv6 | Both IPv4 and IPv6 pass through TUN |

For full dual-stack support, remove the AAAA-suppression rule, choose a dual-stack DNS strategy, add a TUN IPv6 address, and add an explicit FakeIP IPv6 range (for example `2001:2::/48`) if using FakeIP.
