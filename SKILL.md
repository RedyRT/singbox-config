---
name: singbox-config
description: "Generate, modify, migrate, and debug version-aware sing-box client configuration files for v1.13 and v1.14. Covers TUN and system proxy modes for end-user devices (SFM/SFA/SFI/CLI), RealIP vs FakeIP TUN templates, DNS/routing split rules, remote rule-set downloads, Clash API selectors, and node conversion for VLESS/VMess/Shadowsocks/Trojan/Hysteria2/TUIC/ShadowTLS/AnyTLS. Use when the user mentions sing-box, singbox, SFM/SFA/SFI, TUN/system proxy setup, split routing, DNS hijack, FakeIP, selector behavior, per-app routing, network strategy, TLS fragment/ECH, proxy chaining, or asks to create, update, migrate, or troubleshoot a client config. Does not cover server-side proxy inbound setup."
---

# sing-box Client Configuration Generator

Generate production-ready sing-box **client** configurations with split routing for users in China. This skill must generate configurations for the target version. Maintain the default version in the version table to avoid cross-version field misuse causing warnings, startup failures, or a complete loss of connectivity.

**Scope:** Clients (end-user devices connecting to proxy servers)—TUN/VPN, system proxy, manual mixed/socks/http, SFM/SFA/SFI GUI clients, and command-line `sing-box run`.

**Out of scope:** Server configurations (hosting proxy servers), server-side inbound listeners, server-side TLS/ACME/Reality, and server-side transparent proxy gateway deployments. For server questions, explain that this skill covers clients only and refer to the official inbound documentation.

## Reference Guide

Read only the references needed for the task first; do not load them all at once:

| Task | Read |
|------|------|
| New configurations, version/template selection, defaults, summary format | `references/workflow.md` |
| TUN, system proxy, manual mixed/http, platform.http_proxy, platform behavior | `references/network-modes.md` |
| DNS hijack, RealIP, FakeIP, DNS latency, IPv6 strategy | `references/dns-routing.md` |
| Clash/V2Ray node conversion to sing-box outbounds | `references/node-conversion.md` |
| geosite/geoip, rule-set URLs, custom split-routing rules | `references/rule-sets.md` |
| Fields, version matrix, schema-level compatibility | `references/config-schema.md` |
| Mechanism troubleshooting, connection lifecycle, common pitfalls, source-code verification | `references/cookbook.md` |
| 1.13 TUN RealIP template (default) | `references/templates/config-1.13-tun.json` |
| 1.13 TUN FakeIP template | `references/templates/config-1.13-tun-fakeip.json` |
| 1.14 TUN RealIP template | `references/templates/config-1.14-tun-realip.json` |
| 1.14 TUN FakeIP template | `references/templates/config-1.14-tun-fakeip.json` |

`references/template.json` must be equivalent to the current default version's template; as of 2026-07-03, this is `references/templates/config-1.13-tun.json`.

## Generation Entry Flow

When generating a **new configuration**, read `references/workflow.md` and assess the entry point with minimal questions:

- Generation intent only, without nodes: ask which configuration option to use.
- Nodes provided without an option: parse them and default to `1.13 TUN RealIP` with the template's built-in rules.
- Nodes and an option provided: do not ask for the option again.
- Split-routing/rule requirements provided: enter the custom-rule flow and read `references/rule-sets.md` as needed.
- Modifying an existing configuration: do not launch the full wizard; ask only for information missing for the current change.
- Unrecognized node format: ask only about the format or missing protocol fields, without expanding into other questions.

If the runtime supports structured selection controls and permits their use, prefer them for questions; otherwise, use short text questions. Do not promise a specific UI in the skill.

Always present a summary before generation. If the user explicitly requested generation, generate immediately after the summary without another confirmation.

## Defaults

- Default option: `1.13 TUN RealIP` (compatibility first)
- Default operating mode: TUN/VPN
- Default DNS/IP strategy: IPv4-only
- Default templates for `1.13 TUN` and `1.14 TUN`: RealIP (compatibility first)
- Default rules: built-in template rules (direct connections for China, ad blocking, proxy routing for common overseas services, existing service selectors)
- Clash API and service selectors enabled by default
- No platform package-name exclusions by default
- Default output: return JSON directly; write a file only if the user requests it

If DNS latency is the main concern, do not recommend FakeIP; prioritize DNS caching/optimistic caching strategies supported by the selected version.

## Version Table

Display version options in descending version order:

| Version | Default status | Template |
|------|----------|------|
| `1.14` | Optional | `config-1.14-tun-realip.json` or `config-1.14-tun-fakeip.json` |
| `1.13` | **Default** | `config-1.13-tun.json` or `config-1.13-tun-fakeip.json` |

As of 2026-07-03, the default version is `1.13`; treat 1.14 as the alpha/preview line. When version status changes, update only the version table and default template reference; do not hard-code recommendations elsewhere in the text.

## Template Selection

### 1.13 TUN RealIP

The default stable-release template. Use `references/templates/config-1.13-tun.json`. It has no FakeIP, enables `dns.reverse_mapping: true`, and retains fields available in 1.13 such as `independent_cache`, `store_rdrc`, and remote rule-set `download_detour`.

1.13 already supports the `reverse_mapping` required for RealIP. The advantages of 1.14 are `dns.optimistic`, `store_dns`, HTTP clients, and new DNS rule capabilities—not the introduction of RealIP support.

`reverse_mapping` only records returned real IP -> domain mappings to help domain-rule matching during routing; it does not itself prevent DNS poisoning. RealIP templates must use DNS rules to send explicitly proxied/overseas domains to remote DNS.

### 1.13 TUN FakeIP

Use only when the user explicitly needs more deterministic connection IP -> domain recovery or legacy FakeIP behavior. Use `references/templates/config-1.13-tun-fakeip.json`. Do not select FakeIP solely because of ordinary DNS latency.

### 1.14 TUN RealIP

The default 1.14 TUN template. Use `references/templates/config-1.14-tun-realip.json`. It has no FakeIP, enables `dns.reverse_mapping: true` and `store_dns`, and uses the 1.14 HTTP client configuration.

### 1.14 TUN FakeIP

Use only when the user explicitly needs more deterministic connection IP -> domain recovery. Use `references/templates/config-1.14-tun-fakeip.json`. Do not select FakeIP solely because of ordinary DNS latency.

## Mandatory Rules

### Routing Order

The first two routing rules in every TUN template must remain:

```json
{ "action": "sniff" },
{
  "type": "logical",
  "mode": "or",
  "rules": [{ "protocol": "dns" }, { "port": 53 }],
  "action": "hijack-dns"
}
```

Do not use only `"protocol": "dns"` for DNS hijacking; use `protocol dns OR port 53`.

### Legacy/Special Usage to Avoid in New v1.13+ Templates

Avoid the following legacy/special usage in new templates:

- `"type": "dns"` outbound: removed in 1.13; use `"action": "hijack-dns"` instead.
- `"type": "block"` outbound: still available, but prefer `"action": "reject"` for ordinary blocking. Use `type: "block"` only when a selector needs a selectable blocking outbound.
- `"outbound": "any"` DNS rules: use outbound `domain_resolver` or route `default_domain_resolver` instead.

### v1.14 Template Field Gating

Do not use these fields in 1.14 templates:

- `independent_cache`
- `store_rdrc`
- remote rule-set `download_detour`

1.14 remote rule-sets must explicitly use `http_client` or `route.default_http_client`; do not rely on an implicit default HTTP client.

### IPv6 Defaults

Unless the user confirms that IPv6 works on the actual network and requests full IPv6 TUN support:

- Use `"strategy": "ipv4_only"` for DNS.
- Configure only an IPv4 address for the TUN inbound.
- Do not assign an IPv6 address to TUN.

See `references/dns-routing.md` for IPv6 behavior and the reasons HTTPDNS can bypass DNS handling.

### Leak Prevention

Reject DoT and STUN after `ip_is_private -> direct`; do not globally reject UDP 443/QUIC.

## Routing Decision Principles

- Start from routing semantics, not DNS semantics.
- If a domain must use the proxy: add an explicit route rule before the CN/direct fallback rules. With RealIP and a domestic default DNS server, also add a remote DNS rule.
- If a domain must connect directly: add both DNS and route rules before the CN/proxy fallback rules.
- Do not infer `geosite-cn` membership from a site's language, brand, or TLD; consult official or trusted rule-sets when needed.
- The current GUI / Clash API selector state is a runtime fact; do not assume the JSON `"default"` is the current selection.

## Validation

After changing documentation or templates, run at least:

```bash
jq empty references/template.json references/templates/*.json
python3 /Users/shpirt/skills/.system/skill-creator/scripts/quick_validate.py /Users/shpirt/playground/singbox-config
```

If the local Python installation lacks PyYAML, run with a temporary installation directory on `PYTHONPATH`; do not add dependencies to the skill repository.
