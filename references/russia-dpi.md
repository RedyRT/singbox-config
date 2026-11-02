# Russia DPI Diagnostics (sing-box 1.14.4)

## Diagnostic Approach

Use official sing-box documentation for supported configuration fields and reproducible network tests for connectivity conclusions. Record date, ISP, region, access type, client/server versions, and failure stage. Do not infer a nationwide mechanism, universal byte threshold, working SNI, or protocol ban from an isolated failure.

## Diagnose the Failure Stage

| Symptom | Check before changing configuration |
|---------|--------------------------------------|
| Name fails or resolves unexpectedly | Compare local DNS with proxied DNS; verify selected domain membership and application DoH/HTTPDNS use. Check proxy hostname bootstrap separately. |
| TCP connection never establishes | Verify server IP/port, server availability/firewall, and another access network. IP/path restrictions and outages can look alike. |
| TLS/Reality handshake fails | Check clock, SNI, UUID, public key, short ID, flow, client/server versions, and server logs. Compare the same node on another ISP. |
| Handshake succeeds but transfer stalls | Compare a small request and a sustained download, repeat on another access network, and inspect loss/MTU/server load. A URLTest 204 success does not prove sustained usability. |
| TCP works but UDP fails | Test supported UDP traffic separately; compare network paths and server UDP support. QUIC/Hysteria2/TUIC are not universal fallbacks where UDP is restricted. |
| Only one service fails | Inspect route logs, actual domains, list freshness, selected outbound, and service-side location restrictions. A missing domain uses direct routing by design. |
| Calls or games fail | Check UDP and STUN requirements, MTU, and per-service rules. Do not solve this by globally blocking STUN or QUIC. |

Use short debug captures, redact credentials, and compare one variable at a time. First run `sing-box version` and `sing-box check -c config.json`; these validate construction, not censorship or reachability. Test real service traffic after schema checks.

## Transport and TLS Policy

- Preserve server-provided protocol, SNI, credentials, and transport. The template's VLESS/Reality node is illustrative, not a nationwide recommendation.
- Changing SNI arbitrarily may break Reality/server validation. A hostname that works for one operator or time window is not a stable default.
- Keep fragmentation/spoofing disabled by default. Use supported options only after a controlled network test indicates benefit, and remove ineffective changes.
- TLS `fragment` and `record_fragment` are mutually exclusive; route `tls_fragment` and `tls_record_fragment` are also mutually exclusive. They affect different connection layers: outbound TLS settings concern the proxy handshake, while route options concern routed destination TLS. Neither promises to fix IP filtering or post-handshake stalls.
- `spoof` / `spoof_method` have platform and privilege restrictions. Consult the pinned documentation before proposing them; do not copy arbitrary third-party DPI tool flags into sing-box.
- Test a different operator-supplied endpoint or transport when evidence points to its network path, keeping client/server support aligned. Do not silently invent a new server setup.

## Selective Routing Limits

Only listed or explicitly added domains use the proxy. Local DNS and unlisted traffic intentionally stay outside it. RealIP mapping/sniffing can miss domains when applications use their own DNS, shared IPs, ECH, or IP literals. Selective FakeIP improves domain recovery only for queries sing-box receives; it is not a DPI bypass itself. Add observed service dependencies to both DNS and routing policy rather than proxying entire hosting ASNs.

The `blocked-services` selector can deliberately select direct, but DNS does not follow that selection. Full direct exceptions require paired DNS/route rules. If policy changes appear ineffective, reconnect and flush relevant application DNS caches before repeating the test.

## Authoritative Compatibility Sources

- [1.14.4 source](https://github.com/SagerNet/sing-box/tree/v1.14.4)
- [TLS options](https://sing-box.sagernet.org/configuration/shared/tls/)
- [Route actions](https://sing-box.sagernet.org/configuration/route/rule_action/)
- [DNS](https://sing-box.sagernet.org/configuration/dns/)

The website is rolling; reject features introduced after 1.14.4.
