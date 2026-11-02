# singbox-config

An English-language skill for generating, migrating, and troubleshooting **sing-box 1.14.4 client configurations**. Covers TUN/VPN, system proxy, manual mixed/SOCKS/HTTP, SFM/SFA/SFI clients, DNS and traffic routing, remote rule-sets, Clash API selectors, and proxy node conversion.

## Release Target

**1.14.4 stable**, released October 24, 2026. Sources checked November 3, 2026:

- [GitHub release](https://github.com/SagerNet/sing-box/releases/tag/v1.14.4)
- [Official configuration documentation](https://sing-box.sagernet.org/configuration/)
- [Migration guide](https://sing-box.sagernet.org/migration/)
- [Version-pinned source](https://github.com/SagerNet/sing-box/tree/v1.14.4)

The website includes newer development features. Check version badges and use the pinned release when validating compatibility.

## Configuration Variants

| Variant | Template | Use |
|---------|----------|-----|
| **1.14.4 TUN RealIP** | `references/templates/config-1.14.4-tun-realip.json` | Default; real DNS responses and domain recovery through reverse mapping/sniffing |
| **1.14.4 TUN FakeIP** | `references/templates/config-1.14.4-tun-fakeip.json` | Optional; more deterministic IP-to-domain recovery |

`references/template.json` is identical to the RealIP template. Custom system-proxy/manual modes are described in `references/network-modes.md`.

Both templates use typed DNS servers, optimistic/persistent DNS caching, explicit HTTP clients for rule-set downloads, and TUN `dns_mode: "hijack"`. IPv4-only defaults include an explicit empty AAAA response and an IPv4 TUN address. FakeIP additionally persists mappings with `store_fakeip`.

The built-in routing policy targets users in China: domestic direct traffic, ad blocking, and proxy/service selectors for overseas traffic. Adjust it for the user's location and requirements. `dns.final` is independent of the route final outbound and current selector state; RealIP proxy domains need explicit remote DNS rules.

Templates contain **placeholder node parameters**. Replace these and update selector/URLTest references before using a configuration.

## Files

- `SKILL.md`: entrypoint, scope, defaults, and mandatory configuration rules.
- `references/workflow.md`: generation questions and summary format.
- `references/config-schema.md`: 1.14.4 field reference.
- `references/cookbook.md`: DNS/routing mechanisms and configuration patterns.
- `references/dns-routing.md`, `network-modes.md`, `rule-sets.md`, `node-conversion.md`: task-specific references.
- `references/templates/`: versioned RealIP and FakeIP templates.
- `scripts/validate.ps1`: structural checks and optional release-binary validation.

## Validation

From the skill root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1 -SingBoxPath C:\tools\sing-box.exe
```

The binary must report version 1.14.4. The validator substitutes syntactically valid test credentials in temporary copies, retains the configuration structure, and runs `sing-box check`; it does not start TUN or connect to a proxy. Temporary copies are removed afterward.

For a generated configuration containing real node parameters:

```bash
sing-box version
sing-box check -c config.json
```

These checks validate configuration construction, not live connectivity, rule-set downloads, or platform VPN permissions.

## Scope

Client configuration only. Server-side proxy hosting, inbound TLS/ACME/Reality setup, and transparent gateway deployment are outside this skill's scope.
