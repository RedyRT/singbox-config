# DNS, RealIP, FakeIP, and IPv6

## DNS hijack

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

1.13 already supports the `dns.reverse_mapping` required for RealIP, so 1.13 RealIP TUN can serve as the default stable template. 1.14 RealIP is an enhanced preview template, offering `dns.optimistic`, `store_dns`, HTTP clients, and new DNS rule capabilities.

`reverse_mapping` does not validate or correct DNS responses, nor prevent poisoning. If domestic DNS returns a poisoned IP for an overseas domain, it simply records that poisoned IP's mapping. To avoid DNS poisoning for overseas domains, RealIP templates must route explicitly proxied/overseas rule-sets to remote DNS in their DNS rules.

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

FakeIP does not eliminate real resolution: proxy outbounds usually pass the domain to the remote proxy for resolution; direct outbounds still need local resolution. If DNS latency is the only main concern, prioritize `dns.optimistic`, `store_dns`, and caching strategies in 1.14. Since 1.13 does not support these new fields, prefer ordinary DNS caching, simpler rules, or a browser-specific mixed/socks/http inbound.

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

- hosts takes priority.
- Domestic domains use `alidns`.
- Explicitly proxied domains use remote DNS.
- final defaults to domestic DNS.

FakeIP template defaults:

- Domestic domains use real domestic DNS.
- Other A/AAAA queries can use `fakeip-dns`.
- `experimental.cache_file.store_fakeip: true` must be enabled.

## Default IPv6 Strategy

Use IPv4-only by default:

```json
"strategy": "ipv4_only"
```

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
| IPv4 only | IPv4 only | All traffic passes through TUN; applications fall back to IPv4 natively |
| IPv4 + IPv6 | IPv4 only | IPv4 passes through TUN; IPv6 bypasses TUN |
| IPv4 + IPv6 | IPv4 + IPv6 | Both IPv4 and IPv6 pass through TUN |
