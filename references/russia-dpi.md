# Russia DPI Diagnostics (sing-box 1.14.4)

## Diagnostic Approach

Use official sing-box documentation for supported configuration fields and reproducible network tests for connectivity conclusions. Record date, ISP, region, access type, client/server versions, and failure stage. Do not infer a nationwide mechanism, universal byte threshold, working SNI, or protocol ban from an isolated failure.

## November 2026 Reports: What Applies

This section is a self-contained paraphrase of the useful findings, reviewed 2026-11-23. Reading the original articles is not required. Attribution is retained as plain text so the guidance does not depend on an external page remaining available:

- Maxim / mureevms, “Методичка по построению VPN, осень 2026”, November 7, 2026, Habr article 1103460.
- Vladislav Gorodkov / fuccsoc, “Очередное исследование методов блокировок ТСПУ”, November 9, 2026, Habr article 1105268.

### Preserved Findings and Their Limits

**Entry and exit exposure:** the first author reported four individual foreign server IPs becoming unreachable over several weeks, while nearby addresses remained reachable; some affected IPs later recovered. Changes of hosting provider or address did not establish a durable remedy in that sample. The proposed architecture separates the address clients connect to from the address destinations see: a separate exit proxy, another server IP, or operator-managed WARP egress. If the exit fails, user traffic must stop rather than leave directly from the entry.

The author explicitly had no direct evidence for the chain “an application reported the exit IP, therefore that IP was blocked.” Treat it as a threat model, not established causality. Applications can discover their public egress through their own destinations, so blocking a list of IP-check websites cannot guarantee protection. Client split routing does not create a separate exit. A second address on the same host still shares hosting/subnet risks; WARP adds an external dependency. Client-side implementation and failure tests are described below.

**Protocol-specific reachability:** the second author observed successful ICMP echo while TCP attempts to multiple service ports timed out. Paired captures showed RU-originated SYNs absent at the foreign server. In the reverse test, foreign SYNs reached RU and RU sent SYN-ACKs, but those replies did not reach the foreign server. This is consistent with dropping packets destined for the foreign IP on the RU-to-foreign path; it does not mean that a connection initiated abroad can complete. Neighboring addresses responding supported a single-address restriction in that experiment, not a universal rule about block size.

The first report described some outgoing connections from blocked servers to Russian sites as working; the second showed that their return packets can also be lost. Do not assume a blocked address remains a usable exit to Russian destinations: verify complete request/response traffic on the actual path.

**Experimental tunnels are not a client recipe:** the second report observed some GRE payload variants, ESP/AH, and ICMP passing at low rates while other probes failed or were throttled. Cloud NAT confounded several tests, and traceroute silence alone did not locate the filter. These results neither establish a stable bypass nor add GRE/ICMP transports to sing-box. Preserve the diagnostic lesson—test the actual protocol and both directions—not the raw-packet experiment scripts.

**Transport claims need independent testing:** the first report recommended XHTTP, own-domain SNI, browser fingerprints, and connection-pool tuning. Its claims about raw TCP failure, byte thresholds, handshake counts, and timed penalties are not universal measurements. For sing-box, use the local VLESS transport table in `node-conversion.md`; server support and sustained traffic tests are required. The report's local-proxy warning is actionable: loopback alone does not stop other local applications from using an unauthenticated SOCKS/HTTP listener.

### Applying the Findings to sing-box

| Article advice or observation | Client-skill decision |
|--------------------------------|-----------------------|
| Separate entry IP from public egress | Explain the architecture and optional client chain below; server egress, second-IP binding, WARP, panels, and self-steal SNI need operator work. |
| Raw TCP/Reality always fails; XHTTP is mandatory | Do not adopt a universal ban. Preserve working profiles; use the supported VLESS alternatives in `node-conversion.md` for controlled trials. |
| Three handshakes, fixed byte cutoffs, timed penalties | Record measured behavior, not universal thresholds. Avoid rapid reconnect/probe storms during diagnosis; do not invent cooldown constants or translate Xray `xmux` to sing-box mux. |
| Browser fingerprint or own-domain SNI guarantees camouflage | Neither is a guarantee. SNI/Reality require a matching server; uTLS only imitates part of browser behavior. |
| GRE, ESP, ICMP, or asymmetric routing got some packets through | Not native VLESS transports or ready client fixes. Do not generate them as sing-box transport types; experimental host/network tunnels are outside scope. |
| Replace split routing with full tunneling | Different routing/privacy policy. Retain this skill's selective default unless the user requests a change; neither policy alone separates entry and exit. |

Do not copy Xray `sendThrough`, `IPOnDemand`, `fallbackTag`, `freedom`, or `blackhole` into sing-box JSON. Translate an actual client requirement using sing-box fields; server architecture remains outside scope.

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

### Ping Works, TCP Times Out: Test the Actual Path

1. Test the configured service port, not just ICMP, from the affected network and a control network. On Windows use `Test-NetConnection <server-ip> -Port <server-port>` and inspect `TcpTestSucceeded`, not `PingSucceeded`. Test only endpoints/ports you control or have permission to probe.
2. With operator access, capture the same timestamped attempt on both sides. For example, on a Linux client/router: `sudo tcpdump -ni any 'host <server-ip> and tcp port <server-port>'`; on the server filter by the client's observed public/NAT IP instead. Redact captures before sharing.
3. Repeated outgoing SYNs absent from the server capture indicate loss on the forward path. SYNs arriving with SYN-ACKs sent but absent at the client indicate return-path loss. Account for NAT, capture placement, host/cloud firewalls, and routing before assigning blame to TSPU. Missing `mtr` hop replies do not locate a filter by themselves.
4. A foreign-to-RU SYN arriving is not a successful reverse connection: the RU SYN-ACK can still be dropped when its destination is the blocked foreign IP. Verify a completed handshake and application data in both directions.
5. UDP silence alone is inconclusive: use a service expected to reply and paired captures. A surviving old connection does not establish that new connections work.

If evidence indicates destination-IP filtering before TLS, changing VLESS flow, SNI, fingerprint, DNS, FakeIP, mux, or fragmentation cannot restore that IP path. Use a verified reachable entry/relay supplied by the operator or another access network. If TCP/TLS succeeds but data stalls, compare small and sustained transfers; do not conflate that with a pre-handshake IP drop.

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

## Entry/Exit Separation and Fail-Closed Chains

**Threat model:** a destination or application can observe its public source IP. If proxy entry and egress use the same address, that reveals the entry to the destination. An app can contact its own endpoint; blocking `ipify`/`2ip`, Russian domains, STUN, or selected app packages does not guarantee concealment. This does not prove that a particular app reports addresses or caused a block. Split routing can reduce which traffic sees the proxy exit, not guarantee secrecy.

The preferred operational arrangement is an operator-managed entry A forwarding user traffic through a distinct exit B. Clients keep the supplied A profile; no client DNS switch can create a second server egress IP. The operator must prevent direct egress from A when B fails and handle both address families. A second IP on the same host does not protect against a whole-subnet block. WARP is an operator-side option with reachability and service dependencies, not a universal client switch.

When the user supplies **two compatible proxy profiles** and requests a client-managed `client -> A -> B -> destination` chain:

- Keep A's real reachable server address/port and bootstrap independent of the chain. Keep B's real server address/port and credentials; add `"detour": "entry-A"` to **B**, tagged `exit-B`. A must be able to reach B. Do not put the detour on A, make a cycle, or treat ShadowTLS's special wrapper address as a general proxy-chain recipe.
- Route protected traffic to `exit-B`, or a selector whose members are complete exit-via-entry chains. The protected DNS transport and rule-set HTTP client's detour must select the same complete chain. Bootstrap A separately; if B uses a hostname, check resolution through the upstream path without introducing a resolver dependency on B itself.
- For this threat model, keep `entry-A` alone and `direct` out of protected selectors/URLTest members and fallbacks. Remove the template's deliberate `blocked-services -> direct` option for that protected policy, or explicitly disclose it as an escape hatch that breaks the policy. This is a requested variant, not a change to the default template.
- Failure of B must fail the protected connection, not retry through A alone or direct. `route.final: "direct"` for unmatched traffic is a routing decision, not automatic failover after an outbound fails.
- Verify normal traffic and remote DNS use B's egress; with B deliberately unavailable, verify protected connections fail and never emerge from A or the device directly. Test TCP, supported UDP, and IPv6 if enabled. Schema validation and a successful 204 probe cannot establish these invariants.

This hides the entry from destinations for traffic using the chain, not from the local ISP observing connections to A, the entry operator, or an application able to inspect local configuration. Do not claim anonymity or immunity to active probing. Entry/exit topology is distinct from the choice of VLESS transport.

## Local Proxy Exposure

An unauthenticated SOCKS/HTTP listener on `127.0.0.1` is not access control against other local applications. A TUN-excluded application may explicitly use that listener; its traffic then enters the proxy inbound, so do not assume the TUN exclusion still applies.

For TUN-only use, do not add an unnecessary mixed/socks/http listener; check GUI-created listeners as well. If a listener is needed, bind it to loopback and configure nonempty `users` with unique credentials where the consuming application supports proxy authentication. Verify authentication works in the actual GUI/browser/system-proxy path; system proxy settings do not guarantee credential propagation. See `network-modes.md`. Do not copy Happ subscription headers as sing-box JSON or claim a localhost password defeats privileged local software.

## Authoritative Compatibility Sources

- [1.14.4 source](https://github.com/SagerNet/sing-box/tree/v1.14.4)
- [TLS options](https://sing-box.sagernet.org/configuration/shared/tls/)
- [Route actions](https://sing-box.sagernet.org/configuration/route/rule_action/)
- [DNS](https://sing-box.sagernet.org/configuration/dns/)
- [1.14.4 V2Ray transports](https://github.com/SagerNet/sing-box/blob/v1.14.4/docs/configuration/shared/v2ray-transport.md)
- [1.14.4 dial fields / detour](https://github.com/SagerNet/sing-box/blob/v1.14.4/docs/configuration/shared/dial.md)
- [1.14.4 mixed inbound authentication](https://github.com/SagerNet/sing-box/blob/v1.14.4/docs/configuration/inbound/mixed.md)

The website is rolling; reject features introduced after 1.14.4.
