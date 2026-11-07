# Generation Workflow (sing-box 1.14.4)

This file defines the question-and-answer flow, defaults, and summary format for generating sing-box client configurations.

## Initial Assessment

- Generation requested without node information: ask for the generation option first.
- Node information provided without a generation option: parse the nodes and use the default `1.14.4 TUN RealIP` and the template's built-in default rules.
- Both node information and a generation option provided: do not ask for the option again.
- Routing/rule requirements provided: enter the custom rules flow.
- Modifying an existing configuration: do not launch the full wizard; ask only for information missing for the current change.
- Unrecognized node format: ask only about the node format or missing protocol fields; do not expand into other questions.

Node information includes Clash YAML, sing-box outbound JSON, proxy sharing links, subscription links, or manually specified protocol parameters.

## Interaction Strategy

If the current runtime supports structured selection controls and permits their use, prefer them for questions. Otherwise, use short text questions. Use structured controls only for multiple-choice questions; use ordinary chat input for nodes, subscriptions, YAML, and JSON.

Do not promise any specific UI format. Do not claim that the skill can switch runtime modes.

## Standard Generation Flow

If the user has only requested generation, ask:

```md
Please select a generation option:

1. `1.14.4 TUN RealIP` (default)
   Configuration for the current default stable release, prioritizing compatibility and suitable for most users.

2. `1.14.4 TUN FakeIP`
   Uses the stable release's FakeIP template, for users who need more deterministic domain recovery.

3. `Custom`
   Select the operating mode, DNS, IPv6, Clash API, selectors, and rules for 1.14.4.
```

After `Custom` is selected, ask:

- Target version: fixed at `1.14.4`; do not ask for a version choice.
- Operating mode: `TUN/VPN` / `system proxy` / `manual mixed/socks/http`
- Configuration level: `Recommended defaults` / `Advanced customization`

Only expand into DNS optimization, IPv6, Clash API, service selectors, platform package-name exclusions, and routing rules when the user selects `Advanced customization`. Do not ask about these items in the recommended defaults path.

When the generation option is determined but nodes are missing, ask in plain text:

```md
Please paste node information: Clash YAML, sharing links, subscription links, sing-box outbound JSON, or manually specified protocol parameters are all accepted.
```

## Recommended Defaults

- Version: `1.14.4`
- Operating mode: TUN/VPN
- IPv6: IPv4-only
- Clash API: enabled
- Service selectors: enabled
- Platform package-name exclusions: disabled
- Routing rules: template's built-in default rules
- Output: return JSON directly

1.14.4 TUN defaults to Russia selective RealIP: `geosite-ru-blocked` uses `blocked-services` (default `proxy`) and remote DoH; unmatched traffic uses direct and local DNS. Both variants use reverse mapping, optimistic/persistent DNS caching, and IPv4-only AAAA suppression. FakeIP is optional and restricted to selected blocked address queries.

State the direct fallback in the generation summary. Preserve supplied transport and Reality/SNI parameters. For blocking problems, collect ISP, connection type, region, client/server versions, and failure stage using `references/russia-dpi.md`.

### Application and Effective-Configuration Check

When troubleshooting imports, unexplained routing/DNS behavior, or transport compatibility, ask only for missing details:

- Application name/version and operating system.
- Actual embedded core name/version (not merely the application's advertised protocol support).
- Active profile and effective/generated configuration, with credentials and subscription tokens redacted; if export is unavailable, use relevant settings and startup/routing logs.
- Application overrides for DNS, routing, TUN/system proxy, and the selected outbound/Clash mode.

Confirm that the application loaded and applied the intended DNS, routing, and transport settings before diagnosing TSPU interference. A successful check with a standalone 1.14.4 binary does not establish compatibility with a different embedded core. Do not launch this diagnostic questionnaire for routine generation when the target is already known.

Use `references/templates/config-1.14.4-tun-realip.json` or `references/templates/config-1.14.4-tun-fakeip.json`. Replace the placeholder node with the user's outbounds and update every selector and URLTest member. For custom system-proxy/manual modes, adapt the RealIP structure using `references/network-modes.md`.

## Custom Rule Triggers

By default, do not ask separately about a rule scheme; use the template's built-in rules directly. Enter the rule question-and-answer flow only in the following cases:

- The user selects `Custom -> Advanced customization -> Routing rules`
- The user explicitly mentions "traffic routing, rules, rule, geosite, geoip, service outbounds"
- The user requests that a service, domain, or country/region use a specific outbound

Rule questions:

```md
How would you like to customize routing rules?

1. `By service`
   For example, AI, Netflix, YouTube, GitHub, Apple, or Telegram.

2. `By domain`
   For example, example.com must connect directly or must use a proxy.

3. `By country/region`
   For example, US, JP, and SG use specified outbounds, while CN connects directly.

4. `Describe directly`
   Simply describe your goal, and I will match a rule-set or generate explicit rules.
```

See `references/rule-sets.md` for rule details.

## Pre-Generation Summary

A summary must be shown before generation. If the user has explicitly requested generation, generate immediately after the summary without additional confirmation.

```md
The configuration will be generated with the following selections:
- Generation option: 1.14.4 TUN RealIP
- Nodes: 3 outbounds recognized
- Routing rules: template's built-in default rules
- IPv6: IPv4-only
- Clash API: enabled
- Service selectors: enabled
- Defaults applied: no generation option selected; using the default 1.14.4 TUN RealIP
```
