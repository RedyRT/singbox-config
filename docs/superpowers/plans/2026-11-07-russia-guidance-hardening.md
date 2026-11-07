# Russia Guidance Hardening

User-approved scope: implement the four recommendations from the November 7 research review. Keep the existing JSON template policy.

## Checklist

- [x] Add explicit XHTTP/splitHTTP conversion rejection and distinguish Xray-only fields.
- [x] Explain uTLS limitations and controlled fingerprint testing.
- [x] Add allowlist-only network diagnostics without permanent subnet recommendations.
- [x] Verify application identity, embedded core, and effective configuration in troubleshooting.
- [x] Run existing validation and obtain a fresh-context documentation review.

## Execution Notes

- Documentation-only changes in the existing non-Git workspace; no worktree or commit operations apply.
- Compatibility evidence was retrieved during the preceding research: official v1.14.4 V2Ray transport source and TLS documentation. Community reports are historical observations, not configuration authority.
- Use existing validation and direct documentation review; no implementation-mirroring tests are needed for these prose changes.
- Verification: `scripts/validate.ps1 -SingBoxPath <official-1.14.4-binary>` passed all three structural and binary checks plus documentation references.
- Fresh-context review: no significant contradictions, omissions, or actionable findings. JSON templates were not edited.
