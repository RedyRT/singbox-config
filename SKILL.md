---
name: singbox-config
description: "Use when generating, modifying, migrating, or troubleshooting sing-box 1.14.4 client configurations, including SFM/SFA/SFI/CLI, TUN/VPN, system proxy, RealIP/FakeIP, DNS hijacking, split routing, remote rule-sets, Clash API selectors, per-app routing, TLS/ECH, proxy chains, or Clash/V2Ray node conversion. Covers client devices connecting to proxy servers, not server-side proxy hosting."
---

# sing-box 1.14.4 Client Configuration Generator

Generate sing-box **1.14.4** client configurations for Russia with selective routing: listed blocked domains use the proxy, and unmatched traffic connects directly. This is not a full-tunnel policy. Use local DNS for unmatched domains and proxied DoH for selected domains.

**Scope:** TUN/VPN, system proxy, manual mixed/socks/http, SFM/SFA/SFI GUI clients, and command-line `sing-box run`. Server-side proxy listeners, TLS/ACME/Reality hosting, and transparent gateway deployments are outside this skill's scope.

## Release and Source Policy

- Target **1.14.4 stable**, released 2026-10-24; documentation checked 2026-11-03.
- [Release](https://github.com/SagerNet/sing-box/releases/tag/v1.14.4), [official documentation](https://sing-box.sagernet.org/configuration/), [migration guide](https://sing-box.sagernet.org/migration/).
- The website is rolling documentation. Check each feature's version badge; do not generate features introduced after 1.14.4. Resolve ambiguities against the [v1.14.4 source](https://github.com/SagerNet/sing-box/tree/v1.14.4) and the matching binary.
- Generate only this target version; there is no version-selection wizard. Migrate older input configurations to this target.

## Reference Guide

Read only the references needed for the task:

| Task | Read |
|------|------|
| Generation flow, options, defaults, summary | `references/workflow.md` |
| TUN, system proxy, manual proxies, platform behavior | `references/network-modes.md` |
| DNS hijack, RealIP/FakeIP, caching, IPv6 | `references/dns-routing.md` |
| Clash/V2Ray node conversion | `references/node-conversion.md` |
| Rule-set URLs and custom split routing | `references/rule-sets.md` |
| Supported fields and compatibility | `references/config-schema.md` |
| Connection lifecycle and troubleshooting | `references/cookbook.md` |
| Russia DPI symptoms, network tests, and evidence limits | `references/russia-dpi.md` |
| 1.14.4 TUN RealIP (default) | `references/templates/config-1.14.4-tun-realip.json` |
| 1.14.4 TUN FakeIP | `references/templates/config-1.14.4-tun-fakeip.json` |

`references/template.json` must be identical to the versioned RealIP template.

## Generation Flow

Read `references/workflow.md` when generating a new configuration.

- Generation intent without nodes: ask which option to use.
- Nodes without an option: parse them and use **1.14.4 TUN RealIP** with built-in rules.
- Nodes and an option provided: do not ask again.
- Explicit routing requirements: enter the custom-rule flow.
- Existing configuration: ask only for information missing for the requested change.
- Unrecognized node format: ask only about the format or missing protocol fields.
- Unsupported transport: sing-box 1.14.4 cannot natively represent Xray XHTTP/splitHTTP. Request a supported server profile; never rename it to HTTP, discard required transport fields, or present a lossy conversion as runnable. See `references/node-conversion.md`.

Prefer structured selection controls when available and permitted; otherwise ask short text questions. Accept nodes, subscriptions, YAML, and JSON through ordinary chat input.

Present a summary before generation. When the user has explicitly requested generation, generate immediately after the summary without another confirmation.

## Defaults and Variants

| Option | Use |
|--------|-----|
| **1.14.4 TUN RealIP** | Default; real DNS responses, `reverse_mapping: true`, sniffing, compatibility first |
| **1.14.4 TUN FakeIP** | Explicit need for deterministic connection IP-to-domain recovery; requires persistent FakeIP mappings |
| **Custom (1.14.4)** | TUN/VPN, system proxy, or manual mixed/socks/http with user-selected rules |

- IPv4-only: `dns.strategy: "ipv4_only"`, an explicit empty `NOERROR` response for AAAA queries, and only an IPv4 TUN address.
- Enable Clash API, service selectors, `dns.optimistic`, and `cache_file.store_dns`.
- Enable `store_fakeip` only in the FakeIP variant.
- No platform package-name exclusions by default.
- Return JSON directly; write files only when requested.
- Replace the template's node placeholders and update every selector/URLTest reference to the actual node tags. Never present placeholder credentials as a runnable final configuration.

FakeIP is not the first choice for DNS latency alone. Prefer ordinary/optimistic caching and DNS persistence. `reverse_mapping` does not prevent DNS poisoning: selected proxy domains need remote DNS rules. The FakeIP variant assigns synthetic addresses only to selected blocked domains; other domains keep real responses.

## Mandatory Configuration Rules

### TUN DNS Handling and Routing Order

Use `dns_mode: "hijack"` with `auto_route: true`. Leave `dns_address` unset to use the address following the TUN address. Explicit DNS addresses require matching `hijack-dns` rules.

Keep the first two route rules:

```json
{ "action": "sniff" },
{
  "type": "logical",
  "mode": "or",
  "rules": [{ "protocol": "dns" }, { "port": 53 }],
  "action": "hijack-dns"
}
```

This catches DNS traffic before private-IP direct routing. Do not rely on `protocol: "dns"` alone. Retain `route.auto_detect_interface: true` to bind outbound traffic to the physical interface. `stack: "mixed"` is supported in this target release.

After private-IP direct routing, apply Clash modes, ad rejection, and blocked-domain routing. Do not globally reject STUN, DoT, or UDP 443/QUIC. Application-managed encrypted DNS may bypass domain policy; diagnose it per application.

### DNS and Migration

- Use typed DNS servers (`type`, `server`); legacy DNS server formats and the top-level `dns.fakeip` block are removed.
- Use the `hijack-dns` route action instead of the removed DNS outbound.
- Use `domain_resolver` / `route.default_domain_resolver` instead of DNS rules matching `outbound: "any"`.
- Omit deprecated `independent_cache`, `store_rdrc`, `rdrc_timeout`, and remote rule-set `download_detour`.
- For hosts fallback, use `preferred_by: "hosts"`.
- For response filtering, use a top-level `evaluate` rule followed by `match_response` and `respond` or another final action. Do not combine `query_type`/`ip_version` with legacy DNS address filters or DNS rule-action `strategy`; this can reject the configuration at startup.
- Global `dns.strategy` and resolver/route-resolve strategies remain supported. Use explicit DNS rules for filtering application AAAA queries; see `references/dns-routing.md`.
- Prefer `action: "reject"` for ordinary blocking; `type: "block"` is only needed for a selectable blocking outbound.

### HTTP Clients

Define top-level `http_clients` and `route.default_http_client`, or an explicit per-rule-set `http_client`. The templates download through `rule-set-proxy` with `detour: "proxy"`. Proxy bootstrap uses `local-dns`, independent of remote DNS and downloaded lists. If bootstrap is blocked, use a verified reachable resolver or supplied server IP; do not introduce a proxy-resolution loop. A cached list or `initial_path` can seed startup.

### IPv6

Only enable dual-stack TUN when the user confirms working network IPv6 and requests it. Then add an IPv6 TUN address, remove the AAAA-suppression rule, adjust DNS/resolver strategies, and add a FakeIP IPv6 range if using FakeIP. HTTPDNS and application-managed DoH can bypass sing-box DNS rules; IPv4-only DNS is not a universal IPv6 leak-prevention mechanism.

## Routing Decisions

- Start from routing intent, not DNS selection.
- A domain that must use the proxy needs an explicit route rule before the direct fallback and a matching remote DNS rule.
- A domain that must connect directly needs both DNS and route rules before the relevant fallbacks.
- Use the community `geosite-ru-blocked` domain list; do not infer blocking from country, language, TLD, or hosting ASN. Add service lists only when requested or needed for an observed omission.
- GUI / Clash API selector state is a runtime fact; JSON `default` is not necessarily the current selection. `dns.final` does not follow selector state.

The `blocked-services` selector defaults to `proxy`; selecting `direct` deliberately overrides traffic routing but does not switch its DNS policy. `proxy` itself has no direct member. VLESS/Reality in the template is a credential placeholder, not a universal Russia recommendation: preserve supplied protocol, SNI, and server parameters. Read `references/russia-dpi.md` before recommending fragmentation, spoofing, or transport changes.

For troubleshooting, identify the application/version, embedded core/version, and effective configuration before attributing failures to censorship. Distinguish endpoint blocking from allowlist-only access. A browser-like uTLS fingerprint is not proof of browser-equivalent behavior or censorship resistance; preserve supported supplied values rather than applying a purported universal fingerprint fix.

## Validation

From the skill root, validate templates and (when available) temporary instantiated copies with the matching binary:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1 -SingBoxPath C:\tools\sing-box.exe
```

For a generated configuration with real node parameters:

```bash
sing-box version
sing-box check -c config.json
```

Require version 1.14.4 for the release-specific check. A configuration check does not prove proxy reachability, remote rule-set availability, or platform VPN permissions.
