# singbox-config

[Main README](README.md)

`singbox-config` is a Codex skill for generating, migrating, and troubleshooting sing-box client configuration files. It focuses on client-side use cases, including TUN/VPN, system proxy, SFM/SFA/SFI graphical clients, command-line `sing-box run`, DNS routing, remote rule sets, Clash API selectors, and common proxy node conversion.

## Version Strategy

When generating a new config, choose the target version in descending version order:

| Version | Default status | Template |
| --- | --- | --- |
| `1.14` | Optional | `references/templates/config-1.14-tun-realip.json` or `references/templates/config-1.14-tun-fakeip.json` |
| `1.13` | Default | `references/templates/config-1.13-tun.json` or `references/templates/config-1.13-tun-fakeip.json` |

As of 2026-07-03, the default version is `1.13`. When 1.14 becomes the default stable version, update only the version table and default template pointer.

## TUN Templates

- `1.13 RealIP template (default, compatibility first)`: the current default stable template. Applications receive real IPs, which keeps browser, system cache, and debugging semantics more natural. It supports multi-outlet domain routing through DNS hijack, `dns.reverse_mapping: true`, and sniffing. Proxied/overseas domains must have remote DNS rules; otherwise a domestic `dns.final` can still return polluted answers.
- `1.13 FakeIP template (routing determinism first)`: kept for users who need more deterministic domain recovery or legacy FakeIP behavior. It is not the default.
- `1.14 RealIP template (preview enhancement)`: uses `dns.optimistic`, `store_dns`, HTTP client, and newer 1.14 DNS rule capabilities. RealIP itself is not new in 1.14.
- `1.14 FakeIP template (routing determinism first)`: for cases that require more deterministic recovery from connection IPs back to domains. It may reduce application-side DNS waiting time, but it is not the first-choice DNS latency optimization. Use it only when you accept browser LNA, Service Worker/cache pollution, missing mappings, and debugging ambiguity risks.

## DNS final Policy

`dns.final` is the default DNS server for the DNS stage. It does not follow route `final` or the current Clash API selector choice. The default RealIP template uses `dns.final: alidns`, while `clash_mode` and overseas/proxied-domain DNS rules send explicitly proxied domains to remote DNS. Do not derive `dns.final` dynamically from selector state.

## Files

- `SKILL.md`: skill entrypoint and operating rules.
- `references/config-schema.md`: configuration field reference and version compatibility matrix.
- `references/cookbook.md`: mechanics for RealIP/FakeIP, DNS, routing, and TUN.
- `references/template.json`: current default template, currently equivalent to `references/templates/config-1.13-tun.json`.
- `references/templates/`: versioned configuration templates.

## Verification

Templates should at least pass JSON syntax validation:

```bash
jq empty references/template.json references/templates/*.json
```

When changing version-specific fields, also check:

- The 1.13 RealIP template must contain `dns.reverse_mapping: true` and must not contain a FakeIP DNS server or `store_fakeip`.
- The 1.13 FakeIP template must contain a FakeIP DNS server, an A/AAAA FakeIP rule, and `cache_file.store_fakeip: true`.
- 1.13 templates must not contain `optimistic`, `store_dns`, `http_client`, `preferred_by`, `default_http_client`, or `http_clients`.
- 1.14 templates must not contain `independent_cache`, `store_rdrc`, or `download_detour`.
- The 1.14 RealIP template must contain `dns.reverse_mapping: true` and must not contain a FakeIP DNS server or `store_fakeip`.
- The 1.14 FakeIP template must contain a FakeIP DNS server, an A/AAAA FakeIP rule, and `cache_file.store_fakeip: true`.

## Scope

This skill only covers sing-box client configuration. It does not cover server-side inbounds, server-side TLS/ACME/Reality, or transparent proxy gateway server deployment.
