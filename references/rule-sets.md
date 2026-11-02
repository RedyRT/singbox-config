# Rule-Sets and Custom Split Routing

## URL Conventions

`raw.githubusercontent.com` is unreliable in China. Use the jsdelivr CDN by default:

```text
https://testingcf.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-{name}.srs
https://testingcf.jsdelivr.net/gh/SagerNet/sing-geoip@rule-set/geoip-{code}.srs
```

URL filenames for `@cn` variant tags use `@`, for example `geosite-apple@cn.srs`. `fastly.jsdelivr.net` can serve as a fallback CDN.

v1.13 remote rule-sets can use `download_detour`. v1.14 templates use `http_clients` + `route.default_http_client` or per-rule-set `http_client`.

## Common Tags

**Geosite**:

- China: `geosite-cn`, `geosite-geolocation-cn`
- Broad overseas coverage: `geosite-geolocation-!cn`
- Google: `geosite-google`, `geosite-google@cn`, `geosite-youtube`, `geosite-google-gemini`
- Microsoft: `geosite-microsoft`, `geosite-microsoft@cn`, `geosite-github`, `geosite-github-copilot`
- Apple: `geosite-apple`, `geosite-apple@cn`, `geosite-apple-intelligence`
- AI: `geosite-openai`, `geosite-anthropic`, `geosite-jetbrains-ai`, `geosite-category-ai-chat-!cn`, `geosite-xai`
- Steam: `geosite-steam`, `geosite-steam@cn`
- Social: `geosite-telegram`, `geosite-discord`
- Streaming: `geosite-netflix`, `geosite-spotify`
- Ads: `geosite-category-ads-all`

**Geoip**: Country/region codes, such as `geoip-cn`, `geoip-us`, `geoip-jp`, and `geoip-sg`.

Do not infer `geosite-cn` membership from a site's language, brand, or TLD; verify the rule-set source when accuracy is needed.

## Built-In Template Defaults

Default rules do not require online lookup; use the template's existing structure:

- Reject ads.
- Connect directly to domestic domains/IPs.
- Proxy common overseas domains.
- Service selectors for AI/Google/Apple/Microsoft/Steam/Telegram and others.

## Proxying Common Overseas Sites

When the user wants common overseas sites to always use the proxy, prefer:

```json
{
  "rule_set": "geosite-geolocation-!cn",
  "action": "route",
  "outbound": "proxy"
}
```

Place this rule before `geosite-cn` / `geoip-cn -> direct`.

## Direct Connections for Custom Domains

Add both DNS and route rules before the CN/proxy fallbacks:

```json
{ "domain_suffix": ["example.com"], "action": "route", "server": "local-dns" }
```

```json
{ "domain_suffix": ["example.com"], "action": "route", "outbound": "direct" }
```

Without a leading `.`, `domain_suffix` matches the domain itself and all its subdomains.

## Proxying Custom Domains

By default, add a route rule before `geosite-cn` / `geoip-cn` and `final`:

```json
{ "domain_suffix": ["example.com"], "action": "route", "outbound": "proxy" }
```

For RealIP templates with a domestic DNS server as `dns.final`, also add a remote DNS rule:

```json
{ "domain_suffix": ["example.com"], "action": "route", "server": "google-dns" }
```

In FakeIP templates, use the following only when explicitly requested by the user:

```json
{ "domain_suffix": ["example.com"], "action": "route", "server": "fakeip-dns" }
```

## Custom-Rule Lookup Strategy

Look up rules online only when the user explicitly requests custom rules, service egress, country/region egress, or rule-sets. Prefer official or trusted rule-set sources.

If no suitable rule-set is found:

- For domain requirements, use explicit `domain` / `domain_suffix` / `domain_regex` rules.
- For country/region IP requirements, use `geoip-{code}` or explicit `ip_cidr` rules.
- For service-egress requirements without an existing selector, create the corresponding selector or reuse `proxy`, and explain this in the summary.
