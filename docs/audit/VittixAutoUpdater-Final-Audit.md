# VittixAutoUpdater — Final audit

**Audit date:** 2026-10-27  
**Scope:** current repository worktree; source inspection and documentation only.  
**Verdict:** **NO-GO** for commercial production automatic installation.  
**Weighted readiness:** **3.60 / 10**.  
**Confidence:** moderate for source-visible behavior; low for compiler/runtime/VM behaviors not executed.

## 1. Executive summary

The repository contains a Delphi VCL updater with meaningful defensive features: HTTPS enforcement by default, SHA-256 package verification, optional detached ECDSA manifest signatures, optional Authenticode publisher pins, ZIP traversal checks, retries/resume, state tracking and a DUnitX fixture. However, the essential authenticity controls are optional by default, and the install mechanism copies files in place through a generated batch file with only EXE-level restoration. It cannot reliably roll back a partial multi-file copy, report helper completion, or recover after power loss. These are release blockers for a commercial self-updater.

This audit does not change production source. It was performed against a worktree that already had numerous modified/untracked source and documentation files; the repository state was left untouched except for these new audit documents. No tests/builds/installers were executed. No suspicious package was run.

## 2. Architecture overview

Core units: `VittixAutoUpdater.Types.pas` (config, records, four-part version), `VittixAutoUpdater.Network.pas` (Delphi HTTP client, JSON, CNG ECDSA verification, SHA-256, download/retry/resume), and `VittixAutoUpdater.Engine.pas` (state machine, policy, extraction and apply). `VittixAutoUpdater.VisualComponent.pas` provides VCL UI and workers; `ComponentReg` and `PropertyEditors` provide IDE design support. A second `TViConAutoUpdater` surface is in `Component.pas` but is absent from package composition. Runtime and design `.dpk/.dproj` projects require VCL and Windows-oriented APIs. Demo is VCL; ManifestGenerator and Python/shell tooling assist release metadata; DUnitX tests use a conditional Indy loopback server.

Actual dependencies include RTL/VCL, Delphi `System.Net.HttpClient`, JSON/hash/ZIP units, Windows CryptoAPI/CNG/ShellExecute and DUnitX/Indy for tests. No CI definition or verified compiler matrix was found. Project metadata advertises Windows architectures; FPC and old Delphi claims are not supported by build evidence.

## 3. Actual update workflow

The UI asks `TUpdateEngine` to check; engine fetches mirrors with `TUpdateNetworkManager`, optionally verifies detached signature over exact manifest bytes, parses app-specific JSON, applies freshness checks in signed mode, and compares numeric 1–4 part versions. The UI presents the result. Download uses HEAD/GET, optional ETag/Range resume, retries, progress/cancel, disk-space and size checks, SHA-256, then marks ready. Apply extracts into a temp directory with lexical ZIP path validation, optionally checks Authenticode pins, writes a temp batch helper, probes install-dir writability, launches it hidden without explicit elevation, and requests application shutdown. The batch retries rename of the running EXE, copies extracted files over the install, relaunches, and attempts EXE restoration on copy failure.

The helper launch is treated as install success before copy completion. Only the EXE is backed up; partially replaced DLLs/data are not restored. See [lifecycle details](02-update-lifecycle.md).

## 4. Security findings

| ID | Severity | Status | Finding | Source |
|---|---|---|---|---|
| VAU-001 | HIGH / P0 | CONFIRMED | Update metadata authenticity disabled by default; checksum can be attacker-controlled with unsigned manifest. | `Types.pas:367-379`; `Network.pas:927-929` |
| VAU-002 | HIGH / P0 | CONFIRMED | In-place multi-file copy and EXE-only rollback can leave mixed version after failure. | `Engine.pas:874-894` |
| VAU-003 | MEDIUM / P1 | CONFIRMED | Predictable temp batch path and no operation mutex allow collisions/interference; elevated caller makes boundary more sensitive. | `Engine.pas:847-853,902-915` |
| VAU-004 | MEDIUM / P1 | LIKELY | No demonstrated ZIP expansion limits; reparse/ACL protections need validation. | `Engine.pas:680-723,236+` |
| VAU-005 | MEDIUM | UNVERIFIED | Redirect logic exists but adversarial edge cases and final URL policy lack executed evidence. | `Network.pas:297-355,858-939` |
| VAU-006 | INFO | CONFIRMED | TLS validation is delegated to platform HTTP stack; no bypass found; transport pinning absent. | `Network.pas:719-731` |

Detailed preconditions, impacts, remediations and acceptance tests are in [security assessment](03-security-assessment.md). TLS and publisher verification runtime behavior remains unverified. No system privilege escalation is implemented; current Program Files behavior is fail-closed, while an already elevated app passes its token to the batch process.

## 5. Delphi implementation findings

Positive: explicit update states, locks around key engine state, `try/finally` for many resources, queued UI events, reference-counted cancellation state, and useful source-level unit tests. Risks: shared mutable network fields and callback state, engine callbacks whose thread affinity depends on UI wrapper, blocking worker waits during destruction, incomplete cancellation during extraction/apply, broad exception-to-string conversion, unmanaged state transition semantics, possible managed-record `FillChar` hazard, duplicate API, config fields not centrally validated, and VCL coupling in the runtime package. See [code quality review](04-delphi-code-quality.md).

## 6. Network and install reliability

Network uses Delphi `THTTPClient`; it configures connection/response timeouts, default HTTPS, mirrors, retries, constrained redirect helpers, optional resume, disk-space and size checks, and checksum verification. Open concerns include manifest response buffering without a clear cap, predictable partial files, races between operations, optional size metadata, and cancellation latency. The install flow is acceptable only as best-effort for a simple app in a writable location. Program Files updates fail closed; there is no signed elevated helper or reboot replacement. See [network review](07-network-reliability.md) and [Windows install review](05-windows-installation-reliability.md).

## 7. Version policy

Versions are numeric 1–4 dot-separated unsigned 16-bit values. Comparison is numeric; equality yields no update; downgrade is rejected unless configured. SemVer prerelease/build labels, channels, skipped releases and compatibility constraints are unsupported. The version examples requested are handled accordingly; `1.0.0-beta` is invalid. See [version management](06-version-management.md).

## 8. Score and prioritized findings

| Category | Weight | Score / 10 | Evidence summary |
|---|---:|---:|---|
| Security | 25% | 3 | HTTPS default and URL checks; signatures/authenticode optional; temp/install trust weaknesses |
| Integrity/authenticity | 20% | 3 | SHA-256 and ECDSA support, but signature not mandatory |
| Installation/rollback | 20% | 2 | EXE retry/restore exists; partial multi-file state and no recovery handshake |
| Delphi quality | 10% | 5 | Sound elements with lifecycle/concurrency/API concerns |
| Network | 10% | 6 | Several defensive controls; unbounded manifest and unexecuted resume paths |
| API/usability | 5% | 5 | Useful VCL flow; headless separation and documentation consistency gaps |
| Test coverage | 10% | 5 | Broad DUnitX source fixture; no execution/CI evidence |
| **Weighted total** | **100%** | **3.60** | **NO-GO despite useful foundations** |

## 9. Recommended architecture changes

1. Require publisher-authenticated metadata by default and define a key lifecycle and anti-replay policy.
2. Use unique ACL-restricted staging and bounded archive extraction.
3. Move installation into a signed helper/installer with least privilege, staged version directories, atomic activation, journaled recovery, and completion/health handshake.
4. Serialize attempts and harden worker/callback lifetime and cancellation.
5. Separate headless runtime from VCL UI/design packages; publish an actual supported compiler/platform matrix backed by CI.

## 10. Testing strategy

Run DUnitX unit cases and loopback HTTP integration in a dedicated test build. Validate TLS and redirect cases with test certificates. Use copied application trees and disposable Windows VM snapshots for install, access denial, locked files, multiple processes, disk exhaustion, helper failure, and power-loss/recovery simulations. Capture package/manifest hashes, process exit codes, final tree and logs. Never target the development machine's installed application. Detailed matrix: [test gap analysis](09-test-gap-analysis.md).

## 11. Development roadmap

P0: VAU-T01 authenticated metadata; VAU-T02 transactional installer/recovery. P1: VAU-T03 private staging, VAU-T04 archive bounds, VAU-T05 operation mutex, VAU-T06 network caps, VAU-T07 worker lifetime. P2: VAU-T08 config/state API, VAU-T09 package separation, VAU-T10 CI/compiler matrix. P3: VAU-T11 channels/rollouts and VAU-T12 background/diagnostics. Task descriptions, dependencies, estimates, regression risks and criteria: [development roadmap](11-development-roadmap.md).

## 12. Final verdict and first task

**NO-GO** for commercial production auto-install until the P0 integrity and recovery blockers are fixed and validated. The highest-priority first task is **VAU-T01: require signed update metadata**. Acceptance criteria: production defaults reject unsigned metadata; malformed, tampered, missing-key, stale, future-dated and replayed manifests fail before package download; valid metadata verifies against an out-of-band pinned public key; key rotation/revocation procedure and test fixtures are documented; the manifest generator and updater agree on exact signed bytes.

## 13. Documents produced

* [Repository architecture](01-repository-architecture.md)
* [Update lifecycle](02-update-lifecycle.md)
* [Security assessment](03-security-assessment.md)
* [Delphi code quality](04-delphi-code-quality.md)
* [Windows installation reliability](05-windows-installation-reliability.md)
* [Version management](06-version-management.md)
* [Network reliability](07-network-reliability.md)
* [Component API review](08-component-api-review.md)
* [Test gap analysis](09-test-gap-analysis.md)
* [Production readiness](10-production-readiness.md)
* [Development roadmap](11-development-roadmap.md)
* This final report.
