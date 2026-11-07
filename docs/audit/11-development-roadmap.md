# 11 — Development roadmap

Complexity estimates cover implementation plus focused validation. Findings are tied to audit IDs; tasks are independently reviewable where possible.

| Task | Priority | Affected units | Problem and recommendation | Dependencies | Size | Regression risks | Tests and acceptance criteria |
|---|---|---|---|---|---|---|---|
| VAU-T01 | P0 | Types, Network, Engine, manifest tooling | Default to authenticated metadata; validate signed mode and reject missing keys/signatures; define key rotation/revocation and replay policy. | Signing format/operations decision | L | Existing unsigned deployments stop updating | Unit+mock: missing/tampered/expired/future/replayed signature rejected; valid pinned signature accepted; docs and generator produce matching format. |
| VAU-T02 | P0 | Engine, new helper/installer project | Replace in-place batch copy with signed, least-privilege staged installer and durable recovery journal; report actual result. | VAU-T01 package trust | XL | Install path/package layout changes | VM fault injection: every interrupted step recovers old or new complete version; no mixed install; restart health acknowledged. |
| VAU-T03 | P0 | Engine, Network | Create unique private temp/staging paths with restrictive ACL, CREATE_NEW, ownership and reparse checks; serialize updates. | None | M | Cleanup behavior and resume paths change | Collision/concurrency/reparse tests; distinct attempt dirs; no external file overwritten or executed. |
| VAU-T04 | P1 | Engine | Bound ZIP entry count, expanded size, ratio and free-space; extraction handle-relative into private root. | VAU-T03 | M | Legitimate large archives may be rejected | Zip bomb/path/reparse fixtures fail before escaping caps; normal package extracts exactly. |
| VAU-T05 | P1 | Engine/helper | Add global/per-install mutex, user/session policy and multiple-instance coordination. | VAU-T02 design | M | Existing app startup may wait | Two-process VM test: one apply, second receives deterministic busy state; no temp collisions. |
| VAU-T06 | P1 | Network | Cap manifest bytes and validate required expected size; normalize errors; verify response status, final URL, exact body length and final checksum for every retry/resume path. | None | M | Some servers lack HEAD/size | Mock matrix: truncation, oversized body, inconsistent range/ETag never completes; bounded retries and cleanup. |
| VAU-T07 | P1 | Engine, VisualComponent | Define operation lifetime, cancellation and callback thread contract; prevent callbacks after destruction and expose worker completion. | None | L | UI event timing/API changes | DUnitX + GUI close/cancel tests complete without hangs or AV; timeout behavior bounded. |
| VAU-T08 | P2 | Types, Engine, Network | Central config validation and state transition table with structured error codes; remove unsafe managed-record FillChar usage where applicable. | API compatibility policy | M | Source compatibility | Boundary tests reject invalid timeout/retry/URL/key configs; every state transition documented and tested. |
| VAU-T09 | P2 | Package/source layout | Split VCL adapter/design package from headless runtime; clarify/remove duplicate legacy component API. | VAU-T08 | L | Package install and source search path changes | Headless test app builds without VCL; VCL design install/build verified on supported Delphi versions. |
| VAU-T10 | P2 | All projects, CI | Establish supported compiler/platform matrix and automated build/unit pipeline. | Toolchain runners | M | CI setup maintenance | Clean build matrix for named RAD Studio versions and Win32/Win64; DUnitX results published; no unsupported FPC claim. |
| VAU-T11 | P3 | Engine, manifest schema | Add channels, staged rollout, skipped releases, compatibility constraints, and monotonic version policy. | VAU-T01 | L | Policy/schema evolution | Unit tests for stable/beta, prerelease, rollout cohorts and minimum version; backward schema fixture coverage. |
| VAU-T12 | P3 | Network, Engine | Add background download scheduling, bandwidth controls, diagnostics and retention policy for rollback history. | VAU-T02 | L | Resource use and storage growth | Load/cleanup tests and documented limits; telemetry contains no secrets. |

## Recommended implementation order

1. VAU-T01: require verifiable publisher-authenticated update metadata.
2. VAU-T03 and VAU-T04: isolate all staging and bound untrusted archive handling.
3. VAU-T02 and VAU-T05: transactional, observable install/recovery and serialization.
4. VAU-T06 and VAU-T07: network and lifecycle hardening.
5. VAU-T08 through VAU-T10: stabilize API and establish repeatable builds.
6. Optional policy/features VAU-T11/T12.
