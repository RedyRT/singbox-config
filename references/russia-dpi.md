# Russia DPI Diagnostics (sing-box 1.14.4)

## Diagnostic Approach

Use official sing-box documentation for supported configuration fields and reproducible network tests for connectivity conclusions. Record date, ISP, region, access type, client/server versions, and failure stage. Do not infer a nationwide mechanism, universal byte threshold, working SNI, or protocol ban from an isolated failure.

## Confirm the Running Client First

Record application name/version, OS, and embedded core name/version. Inspect the active profile and effective configuration or relevant logs, redacting credentials. Check whether application overrides change DNS, routing, transport, or selector state. A subscription accepted by a GUI is not proof that all fields were applied, and a standalone sing-box check does not validate another core's behavior.

Compare intended versus effective settings before attributing the failure to TSPU. Reports about one application's DNS or subscription handling must not be generalized to other versions or clients. For unsupported XHTTP/splitHTTP input, follow the compatibility gate in `node-conversion.md` rather than diagnosing it as blocking.

## Diagnose the Failure Stage

| Symptom | Check before changing configuration |
|---------|--------------------------------------|
| Name fails or resolves unexpectedly | Compare local DNS with proxied DNS; verify selected domain membership and application DoH/HTTPDNS use. Check proxy hostname bootstrap separately. |
| TCP connection never establishes | Verify server IP/port, server availability/firewall, and another access network. IP/path restrictions and outages can look alike. |
| Only a small set of sites works, especially on mobile access | Check for allowlist-only access using the procedure below; distinguish it from an individual blocked node, captive portal, or outage. |
| TLS/Reality handshake fails | Check clock, SNI, UUID, public key, short ID, flow, client/server versions, and server logs. Compare the same node on another ISP. |
| Handshake succeeds but transfer stalls | Compare a small request and a sustained download, repeat on another access network, and inspect loss/MTU/server load. A URLTest 204 success does not prove sustained usability. |
| TCP works but UDP fails | Test supported UDP traffic separately; compare network paths and server UDP support. QUIC/Hysteria2/TUIC are not universal fallbacks where UDP is restricted. |
| Only one service fails | Inspect route logs, actual domains, list freshness, selected outbound, and service-side location restrictions. A missing domain uses direct routing by design. |
| Calls or games fail | Check UDP and STUN requirements, MTU, and per-service rules. Do not solve this by globally blocking STUN or QUIC. |

Use short debug captures, redact credentials, and compare one variable at a time. First run `sing-box version` and `sing-box check -c config.json`; these validate construction, not censorship or reachability. Test real service traffic after schema checks.

## Allowlist-Only Access (Белые списки)

Compare several unrelated ordinary destinations and the configured tunnel endpoint on the affected network, then on another available access network. Record whether restrictions affect only mobile access, particular times, or a broader set of destinations. Check captive-portal/account restrictions and outages before concluding an allowlist is involved; a few failed connections alone do not prove it.

If connectivity is genuinely restricted by an IP-level allowlist, changing DNS, FakeIP, SNI, or fragmentation cannot make an excluded endpoint reachable. A usable tunnel requires a reachable endpoint/path supplied by its operator, or another access network. SNI-based filtering is a different case and must not be conflated with IP-level allowlisting.

Do not embed historical "working subnet" lists, assume all Russian hosting is reachable, or promise that an advertised allowlisted address works across operators. Recheck the actual endpoint, protocol, and sustained traffic on the user's current network. Routing more domains through an unreachable proxy cannot restore connectivity.

## Transport and TLS Policy

- Preserve server-provided protocol, SNI, credentials, and transport. The template's VLESS/Reality node is illustrative, not a nationwide recommendation.
- Changing SNI arbitrarily may break Reality/server validation. A hostname that works for one operator or time window is not a stable default.
- The [official 1.14.4 uTLS guidance](https://github.com/SagerNet/sing-box/blob/v1.14.4/docs/configuration/shared/tls.md#utls) warns that ClientHello imitation does not reproduce a browser's full TLS stack and behavior. The template's `chrome` fingerprint is illustrative, not proof of censorship resistance.
- Preserve supported supplied fingerprints. Do not apply automatic Chrome-to-Firefox/QQ/randomized substitutions based on historical anecdotes. For a controlled comparison, keep the endpoint, SNI, credentials, transport, and workload fixed; change one supported fingerprint, record network/time/core version, and test both handshake and sustained transfer. A successful comparison does not establish a universal fix or the censor's exact mechanism.
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
