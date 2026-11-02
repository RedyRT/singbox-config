# Russia Rule-Sets and Selective Routing (1.14.4)

Official schema: https://sing-box.sagernet.org/configuration/rule-set/

## Sources and Defaults

Use [Runet Freedom's release files](https://github.com/runetfreedom/russia-v2ray-rules-dat/tree/release/sing-box/rule-set-geosite). Its [README](https://github.com/runetfreedom/russia-v2ray-rules-dat) describes `ru-blocked` as community.antifilter.download plus re:filter, updated every six hours. These are community lists, not a guarantee of blocking on every Russian ISP.

Base URL:

```text
https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/
```

| Filename | Local tag | Default use |
|----------|-----------|-------------|
| `geosite-ru-blocked.srs` | `geosite-ru-blocked` | Proxy selected blocked domains |
| `geosite-category-ads-all.srs` | `geosite-ads` | Reject ads |
| `geosite-youtube.srs` | `geosite-youtube` | Optional service override |
| `geosite-discord.srs` | `geosite-discord` | Optional service override |

Do not substitute `ru-blocked-all`, broad hosting IP/ASN ranges, or a country list by default. Shared infrastructure can route unrelated traffic through the proxy. Domain lists can miss new blocks, application IP connections, and service dependencies; add measured exceptions as needed.

## Downloads and Bootstrap

```json
{
  "http_clients": [{ "tag": "rule-set-proxy", "detour": "proxy" }],
  "route": {
    "default_http_client": "rule-set-proxy",
    "default_domain_resolver": "local-dns"
  }
}
```

This fragment assumes the template's `proxy` outbound and local DNS server. Set remote lists to `update_interval: "6h"`. Omit deprecated `download_detour`. Bootstrap must work before proxied DNS and list downloads: use a reachable local resolver or a verified server IP supplied by the operator. Keep TLS server name unchanged when using an IP. Cached rule-sets or a verified `initial_path` can seed startup when downloads are unavailable; an empty list silently defeats selective coverage.

## Rule Mode Policy

After sniffing and DNS hijack: private addresses connect directly, Clash mode overrides apply, ads are rejected, then blocked domains use `blocked-services`. Unmatched traffic uses `route.final: "direct"`. DNS mirrors the selected domains, with `dns.final: "local-dns"`. Global/Direct modes override selection but retain earlier private routing and AAAA/hosts handling.

## Custom Direct Exception

Place both rules before blocked-domain rules (and before ad rejection if intentionally overriding an ad entry):

```json
{ "domain_suffix": ["example.com"], "action": "route", "server": "local-dns" }
```

```json
{ "domain_suffix": ["example.com"], "action": "route", "outbound": "direct" }
```

## Custom Proxy Domain

Add a traffic rule before the direct fallback and a matching DNS rule:

```json
{ "domain_suffix": ["example.com"], "action": "route", "outbound": "proxy" }
```

```json
{ "domain_suffix": ["example.com"], "action": "route", "server": "remote-dns" }
```

For selective FakeIP, insert this before the remote DNS rule, retaining that rule for non-address queries:

```json
{ "domain_suffix": ["example.com"], "query_type": ["A", "AAAA"], "action": "route", "server": "fakeip-dns" }
```

Keep AAAA suppression first for IPv4-only configurations. FakeIP cannot answer HTTPS/SVCB, TXT, or MX queries. Without a leading dot, `domain_suffix` covers the domain and its subdomains.

For an optional service list, declare its remote rule-set and reference the same tag in DNS and traffic rules. Do not assume its domains are absent from `ru-blocked`; check membership if accuracy matters. Add dedicated selectors only when the user needs separate service egress.
