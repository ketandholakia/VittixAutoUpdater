# 03 — Security assessment

Threat model: network attacker, compromised update host/CDN, malicious archive, local unprivileged user, and update running with the application's current token. Findings are source inspection unless stated; no suspicious package was executed.

## Findings

### VAU-001 — HIGH — Authenticated update metadata is disabled by default (CONFIRMED)
**Evidence:** `VittixAutoUpdater.Types.pas:367-379`: `RequireSecureConfig`, `VerifyManifestSignature`, and `VerifyAuthenticode` default `False`; only `RequireChecksum` and `RequireHttps` default true. `Network.pas:927-929` verifies signature only when enabled. **Preconditions:** attacker can alter manifest and package on a trusted HTTPS origin/CDN, or origin is compromised. **Impact:** attacker supplies matching malicious package and checksum; HTTPS and checksum do not prove publisher authenticity. **Fix:** fail closed by default on pinned ECDSA signed metadata or pinned Authenticode; make secure mode impossible to silently omit. **Acceptance:** release configuration rejects unsigned/tampered manifests and untrusted package signatures; key rotation/revocation is documented and tested.

### VAU-002 — HIGH — In-place multi-file deployment has no complete rollback (CONFIRMED)
**Evidence:** `VittixAutoUpdater.Engine.pas:874-894` renames only EXE then copies tree; COPY_FAILED restores EXE only. **Preconditions:** copy failure after one or more DLL/data files were replaced, e.g. power loss, antivirus lock, or disk full. **Impact:** mixed-version installation; old EXE may load incompatible new DLLs. **Fix:** stage a complete version directory and switch atomically through a trusted helper/installer, or journal and back up every changed file with recovery on next startup. **Acceptance:** injected mid-copy failure leaves a runnable old release or recoverable staged state; tests cover every file boundary.

### VAU-003 — MEDIUM — Predictable shared-temp helper and partial ownership risk (CONFIRMED)
**Evidence:** helper name uses app name only at `Engine.pas:847-853`; temp location is `GetTempDir`; writes and launches via `SaveToFile`/`ShellExecute` at `902-915`. **Preconditions:** another same-user process can pre-create/replace the helper path or concurrent update attempts collide. **Impact:** unintended batch commands may run as the updater user's token; interference or denial of service. Elevated impact is limited because this code does not elevate. **Fix:** create a unique private directory/file with restrictive ACL and CREATE_NEW semantics, verify ownership/reparse status, and pass quoted arguments to signed helper executable. **Acceptance:** parallel attempts receive isolated helper paths; pre-created path is rejected; no batch script is launched.

### VAU-004 — MEDIUM — Archive resource exhaustion and filesystem reparse defenses are incomplete (LIKELY)
**Evidence:** extraction iterates every ZIP entry with path validation (`Engine.pas:680-723`), but no total expanded-size, entry-count, compression-ratio, or free-space cap is evident in extraction path; path validation is lexical (`236+`). Private directory ACL creation exists (`323+`) but no audit evidence establishes reparse traversal protection. **Preconditions:** signed/trusted or checksum-matching malicious archive, or unsigned package accepted due to VAU-001. **Impact:** disk exhaustion, long extraction, or potentially writing through a reparse point depending on directory/ancestor state. **Fix:** enforce archive count/size/ratio caps; create/validate private directory and reject reparse points at each path; use safe handle-relative extraction. **Acceptance:** oversized/zip-bomb/reparse fixtures fail before writes outside isolated staging.

### VAU-005 — LOW — Broad downloader URL surface and redirect behavior need adversarial validation (UNVERIFIED)
**Evidence:** `Network.pas:297-355,858-939,963+` validates schemes and implements secure redirect helpers; HTTPS validation is on by default. **Preconditions:** malformed/ambiguous Location or redirect chain behavior inconsistent with helper policy. **Impact:** possible policy bypass or denial of service. **Fix:** regression tests for HTTPS-to-HTTP, userinfo, host parsing, excessive hops, relative redirects and host changes; validate final response URL. **Acceptance:** all downgrade and redirect cases are rejected/allowed only per explicit policy.

### VAU-006 — INFO — Transport defaults have HTTPS and certificate checks but no pinning (CONFIRMED)
**Evidence:** `System.Net.HttpClient` is used and no custom certificate-validation bypass was found; server TLS validation is delegated to platform stack. **Impact:** conventional public CA trust applies; compromise of trusted CA/origin remains in threat model. Certificate pinning is not mandatory or present for transport. **Fix:** retain platform certificate/hostname validation; rely on signed metadata for authenticity rather than brittle TLS pinning. **Acceptance:** test expired, hostname-invalid, and untrusted test certificates fail.

## Security control inventory

* HTTPS: enforced for configured URLs by default; redirects are manually constrained (`Network.pas:297-355,893-910`). Certificate/hostname validation: delegated to `THTTPClient`/Windows trust; no bypass found, runtime test absent.
* Manifest authenticity: ECDSA P-256 detached signature support via CNG and a configured public key (`Network.pas:570-654,656-702`), but optional. Signature is fetched from same origin; trust comes from out-of-band pinned public key, not its location.
* Package integrity: SHA-256 support; checksum defaults required. Integrity is unauthenticated if manifest is unsigned.
* Replay/freshness: signed mode requires `issued_at` and max age; no monotonic sequence/persisted last accepted version or nonce. Clock rollback and replay inside acceptance age remain possible. Downgrades blocked by default (`Engine.pas:214+`) but can be enabled.
* Authenticode: optional, checks EXE/DLL and pinned publisher thumbprints. No built-in key rotation/revocation playbook.
* Filesystem: ZIP traversal guard and private extraction directory exist; temp archive and helper names need review; application directory probe does not validate ACL policy robustly against races.
* Privileges: no explicit elevation; updater inherits caller's rights. Running elevated applications can cause helper to run elevated, therefore package authenticity and temp integrity become critical.
* Proxies: configurable basic proxy host/port surface, no auth configuration evident. HTTP response manifest size is not explicitly capped before buffering into memory.

No package was run; conclusions about Windows trust behavior, TOCTOU exploitability, and ACL/reparse handling require VM tests.
