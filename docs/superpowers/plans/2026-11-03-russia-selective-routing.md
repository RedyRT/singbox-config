# Russia Selective Routing Implementation Plan

**Goal:** Apply the user's approved Russia default: proxy selected blocked domains/services, connect directly otherwise, on sing-box 1.14.4.

**Design:** Keep RealIP and FakeIP variants. Use the maintained community `ru-blocked` domain list, ad blocking, and a blocked-services selector. No country-wide or ASN-wide proxy rules by default. Unmatched DNS uses the system resolver; matched domains use proxied DoH (or selective FakeIP for address queries). Download rules through the supplied proxy using a bootstrap resolver independent of routing lists. Remove blanket STUN/DoT rejection so ordinary direct traffic and calls are not blocked by the template.

**Evidence boundary:** Official sing-box documentation and version-pinned validation define supported fields. Connectivity conclusions require reproducible network tests.

## Checklist

- [x] Verify community rule-set provenance and actual SRS download paths.
- [x] Replace all three bundled configurations with selective Russia routing and matched DNS policy.
- [x] Update skill, README, workflow, DNS, rule-set and cookbook examples; add Russia-specific diagnostics with sources and limitations.
- [x] Extend existing validation for direct fallbacks, selective FakeIP, and matching DNS/route lists.
- [x] Validate with the official 1.14.4 binary, decode downloaded rule-sets, and independently review the resulting guidance.

## Decisions

- Use `ru-blocked` (community + re:filter), not the much larger `ru-blocked-all` or GeoIP-derived ranges; shared IP ranges can proxy unrelated services.
- Add individual service lists only on request or an observed omission; do not proxy all foreign services by geography.
- Keep node credentials, SNI, and protocol supplied by the user; VLESS/Reality remains a placeholder example, not a Russia-wide recommendation.
- A direct default intentionally sends unlisted traffic outside the proxy. State this prominently.

## Verification Record

- New policy assertions failed against the old defaults before template replacement, then passed against the Russia templates.
- Final `scripts/validate.ps1 -SingBoxPath <official-1.14.4-binary>` run passed structure, documentation/template references, and all three instantiated configuration checks. Default and versioned RealIP remain byte-identical.
- Downloaded both configured SRS files and successfully ran `sing-box rule-set decompile` with 1.14.4; artifacts are in the approved temporary directory under `russia-rule-validation`.
- Fresh-context review found one optional service example lacking paired DNS routing. Added real DNS and guarded FakeIP examples, with placement and selector-state caveats.
- Stale regional-default search across Markdown returned no matches after synchronization.
- No live Russian ISP connectivity test was performed. At the user's request, forum sources and the associated research requirement were removed.
