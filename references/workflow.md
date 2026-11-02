# Generation Workflow

This file defines the question-and-answer flow, defaults, and summary format for generating sing-box client configurations.

## Initial Assessment

- Generation requested without node information: ask for the generation option first.
- Node information provided without a generation option: parse the nodes and use the default `1.13 TUN RealIP` and the template's built-in default rules.
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

1. `1.13 TUN RealIP` (default)
   Configuration for the current default stable release, prioritizing compatibility and suitable for most users.

2. `1.13 TUN FakeIP`
   Uses the stable release's FakeIP template, suitable for users who need more deterministic domain recovery or legacy FakeIP behavior.

3. `1.14 TUN`
   Uses preview fields from 1.14; after selection, ask whether to use RealIP or FakeIP.

4. `Custom`
   Manually select the version, operating mode, DNS, IPv6, Clash API, selectors, rules, etc.
```

After `1.14 TUN` is selected, ask:

- `RealIP` (default, compatibility first)
- `FakeIP` (routing determinism first; not recommended solely for DNS latency)

After `Custom` is selected, ask:

- Version: `1.14` / `1.13`
- Operating mode: `TUN/VPN` / `system proxy` / `manual mixed/socks/http`
- Configuration level: `Recommended defaults` / `Advanced customization`

Only expand into DNS optimization, IPv6, Clash API, service selectors, platform package-name exclusions, and routing rules when the user selects `Advanced customization`. Do not ask about these items in the recommended defaults path.

When the generation option is determined but nodes are missing, ask in plain text:

```md
Please paste node information: Clash YAML, sharing links, subscription links, sing-box outbound JSON, or manually specified protocol parameters are all accepted.
```

## Recommended Defaults

- Version: `1.13`
- Operating mode: TUN/VPN
- IPv6: IPv4-only
- Clash API: enabled
- Service selectors: enabled
- Platform package-name exclusions: disabled
- Routing rules: template's built-in default rules
- Output: return JSON directly

1.13 TUN defaults to RealIP. Version 1.13 already supports `dns.reverse_mapping`, which RealIP requires, but cannot use `dns.optimistic` / `store_dns`, which are available only in 1.14. The default template reduces cold queries and DNS pollution risks through domestic/overseas DNS routing, ordinary DNS caching, `independent_cache`, and `store_rdrc`.

1.14 TUN defaults to RealIP. FakeIP is not the first choice for DNS latency optimization.

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
- Generation option: 1.13 TUN RealIP
- Nodes: 3 outbounds recognized
- Routing rules: template's built-in default rules
- IPv6: IPv4-only
- Clash API: enabled
- Service selectors: enabled
- Defaults applied: no generation option selected; using the default 1.13 TUN RealIP
```
