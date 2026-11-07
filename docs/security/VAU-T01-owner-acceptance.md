# VAU-T01 Owner Acceptance & Final Verification

**Repository:** `D:\ketan\github\VittixAutoUpdater`  
**Branch:** `fix/vau-t01-signed-manifest`  
**Verification date:** 2026-10-27  
**Scope:** Read-only acceptance verification; no production source changes, commits, pushes, merges, live update requests, or installer launches were performed.

## Verdict

**PARTIAL** — The signed-metadata implementation and supported build/test targets were verified. The requested cross-process HKCU rollback integration and disposable VCL host acceptance suite were not run. These are verification gaps, so this report does not accept the full VAU-T01 acceptance criteria as completely verified.

This verdict is limited to VAU-T01. It does not indicate production readiness. Installation transactionality and recovery remain separate blockers.

## 1. Verified requirements

| Requirement | Result | Evidence |
|---|---|---|
| Signed metadata required by default | **PASS (source + DUnitX)** | `TUpdaterConfig.Default` sets signature verification and secure config true and unsigned opt-in false ([Types.pas:355](../../VittixAutoUpdater.Types.pas#L355), [Types.pas:371-L379](../../VittixAutoUpdater.Types.pas#L371)). DUnitX `SecureDefaultsRequireSignedMetadata` passed. Network manager also initializes signature verification true and unsigned mode false ([Network.pas:746-L748](../../VittixAutoUpdater.Network.pas#L746)). |
| Unsigned mode needs explicit opt-in | **PASS (source + partial test)** | Engine and network reject `VerifyManifestSignature=False` unless `AllowInsecureUnsignedManifests=True` ([Engine.pas:603-L616](../../VittixAutoUpdater.Engine.pas#L603), [Network.pas:1018-L1023](../../VittixAutoUpdater.Network.pas#L1018)). DUnitX confirms defaults and refusal without opt-in ([Test.VittixAutoUpdater.pas:527-L566](../../Test.VittixAutoUpdater.pas#L527)); it does not exercise a real unsigned HTTP response accepted after opt-in.
| Key IDs are deterministic; unknown/malformed IDs rejected | **PASS (source + DUnitX)** | ID is SHA-256 of the raw public key coordinates; envelope parser enforces the `VAU-ECDSA-P256-SHA256-v1` algorithm, lowercase 64-hex ID, and strict 88-character Base64 form ([Network.pas:685-L716](../../VittixAutoUpdater.Network.pas#L685)). Trust lookup matches only provisioned keys ([Network.pas:719-L736](../../VittixAutoUpdater.Network.pas#L719)). `SignatureEnvelopeRequiresKnownAlgorithmAndKeyId`, `TrustedKeySetSupportsExplicitRotation`, and `SignedManifestFetchRejectsTamperingAndUnknownKeys` passed ([tests:474-L525](../../Test.VittixAutoUpdater.pas#L474), [tests:822-L906](../../Test.VittixAutoUpdater.pas#L822)). |
| Keys are provisioned independently | **PASS (source)** | `TUpdaterConfig` receives `ManifestPublicKey` and `ManifestTrustedPublicKeys` from application configuration ([Types.pas:146-L148](../../VittixAutoUpdater.Types.pas#L146)). The engine copies those into the network manager ([Engine.pas:517-L531](../../VittixAutoUpdater.Engine.pas#L517)). The manifest envelope contains only an algorithm, key ID, and signature; no manifest-provided key is loaded as a trust anchor ([Network.pas:779-L831](../../VittixAutoUpdater.Network.pas#L779)). |
| Signing and verification use identical bytes | **PASS (source + shared vector tests)** | The network reads raw manifest response bytes, passes those bytes to ECDSA verification, and decodes UTF-8 only after verification ([Network.pas:1083-L1107](../../VittixAutoUpdater.Network.pas#L1083)). The documented generator signs the published file bytes without JSON reserialization ([update-manifest-signing.md:7-L13](update-manifest-signing.md#L7)). Python generator tests and Delphi known-vector tests passed. |
| Missing checksum and invalid file size rejected | **PASS (source)** | After signed parsing, network rejects `FileSize <= 0`, missing/non-64-hex SHA-256, and malformed checksum ([Network.pas:1118-L1128](../../VittixAutoUpdater.Network.pas#L1118)). Existing test coverage checks checksum tampering but has no explicit fixture for missing checksum or zero/negative file size ([Test.VittixAutoUpdater.pas:868-L878](../../Test.VittixAutoUpdater.pas#L868)). |
| Manifest/signature body limits | **PASS (source + DUnitX)** | Manifest is streamed into a 1 MiB bounded stream; detached signature into a 1 KiB bounded stream ([Network.pas:779](../../VittixAutoUpdater.Network.pas#L779), [Network.pas:1049](../../VittixAutoUpdater.Network.pas#L1049), [Network.pas:168-L175](../../VittixAutoUpdater.Network.pas#L168)). The signed-fetch fixture rejects responses one byte over each limit ([Test.VittixAutoUpdater.pas:897-L906](../../Test.VittixAutoUpdater.pas#L897)). |
| Invalid metadata cannot flow to package download | **PASS (control-flow inspection); NOT dynamically verified** | `CheckForUpdate` fetches/authenticates/parses the manifest and only returns `ucrUpdateAvailable` after success ([Engine.pas:589-L707](../../VittixAutoUpdater.Engine.pas#L589)). Package retrieval is a separate call through `DownloadUpdate` ([Engine.pas:820](../../VittixAutoUpdater.Engine.pas#L820)); invalid fetch paths report an error before that state. No download-request counter test against `TUpdateEngine` was run.
| Existing source configuration fields retained | **PASS (source inspection)** | `RequireSecureConfig`, `ManifestPublicKey`, `ManifestHmacKey`, and existing configuration members remain in `TUpdaterConfig`; newer trusted-key and opt-in fields are additive ([Types.pas:126-L150](../../VittixAutoUpdater.Types.pas#L126)). The verification note documents `RequireSecureConfig` retention ([VAU-T01-verification.md:11](VAU-T01-verification.md#L11)). This establishes source-level field compatibility, not binary compatibility of already compiled Delphi packages.

## 2. Registry rollback persistence

### Code inspection

The engine stores a floor in `HKCU\Software\VittixAutoUpdater\TrustState\<SHA256(normalized executable path)>\Floor`. The stored value combines the accepted numeric version, issuance time, and checksum ([Engine.pas:281-L321](../../VittixAutoUpdater.Engine.pas#L281)). A failed registry open/read/write or malformed prior state returns a failure and prevents `ucrUpdateAvailable`/`ucrNoUpdateAvailable` ([Engine.pas:698-L720](../../VittixAutoUpdater.Engine.pas#L698)). The pure policy helper rejects lower versions, older timestamps, and same-version/time content changes ([Engine.pas:224-L278](../../VittixAutoUpdater.Engine.pas#L224)).

### Integration result

**NOT VERIFIED.** No disposable executable was created and no registry value was written during this acceptance. DUnitX `ManifestRollbackFloorRejectsReplayAndDowngrade` tests the pure policy helper, not registry persistence, process recreation, registry corruption, or registry access denial ([Test.VittixAutoUpdater.pas:578-L599](../../Test.VittixAutoUpdater.pas#L578)). Therefore the requested accept → persist → destroy/recreate → reload → reject old → accept new sequence has no execution evidence.

The documented threat model uses HKCU, so state is not protected from the same user or an administrator who can edit/delete the value. It is also not proof of replay resistance on first run or when the system clock is manipulated. Different executable bitness/registry views were not tested. These limitations are not counted as implemented protection against local tampering.

## 3. VCL host integration

**NOT VERIFIED.** Runtime and design-time packages compile, but no disposable VCL host executable was created or launched. No form placement, DFM round trip, active-check close, repeated component check, event delivery, or invalid-signature event behavior was exercised.

`TVittixAutoUpdaterUI` publishes a `Config: TUpdaterConfig` record property ([VisualComponent.pas:178-L196](../../VittixAutoUpdater.VisualComponent.pas#L178)). No existing demo DFM contains a streamed `Config` value; the demo configures the property in code and persists its separate application config as INI settings ([demo/VittixAutoUpdaterEnhancedDemo.pas:317-L335](../../demo/VittixAutoUpdaterEnhancedDemo.pas#L317)). Package compilation does not prove that Delphi component streaming serializes the record. Therefore configuration streaming remains unverified.

The demo has `AutoCheck := False` and only checks on explicit user action, but it reads/writes an INI file beside its executable ([demo/VittixAutoUpdaterEnhancedDemo.pas:252-L272](../../demo/VittixAutoUpdaterEnhancedDemo.pas#L252), [demo/VittixAutoUpdaterEnhancedDemo.pas:408-L437](../../demo/VittixAutoUpdaterEnhancedDemo.pas#L408)). It was not launched, and no production endpoint was contacted.

## 4. Negative security test coverage

| Case | Result | Evidence / limitation |
|---|---|---|
| Missing signature response | **PASS** | Loopback test empties `.sig` body and expects `FetchManifest=False` ([tests:879-L885](../../Test.VittixAutoUpdater.pas#L879)). |
| Invalid Base64 / malformed envelope | **PASS (parser-level)** | Envelope parser rejects `***`, unsupported algorithm, uppercase/malformed and unknown IDs ([tests:474-L504](../../Test.VittixAutoUpdater.pas#L474)). A separate HTTP invalid-Base64 case was not run. |
| Unknown key ID / wrong key | **PASS** | Loopback fetch test rejects both ([tests:879-L895](../../Test.VittixAutoUpdater.pas#L879)). |
| Malformed envelope / unsupported algorithm | **PASS** | Parser unit assertions ([tests:474-L504](../../Test.VittixAutoUpdater.pas#L474)). |
| Modified manifest / checksum | **PASS** | Signature verifier rejects tampered bytes and loopback test changes checksum after signing ([tests:457-L471](../../Test.VittixAutoUpdater.pas#L457), [tests:868-L878](../../Test.VittixAutoUpdater.pas#L868)). |
| Expired and future-dated metadata | **PASS (parser-level)** | `ManifestAgeRejectsStaleAndFutureDocuments` passed ([tests:415-L435](../../Test.VittixAutoUpdater.pas#L415)). |
| Older previously signed metadata / downgrade | **PARTIAL** | Pure rollback/downgrade policy unit test passes; no persisted registry replay integration was run ([tests:578-L599](../../Test.VittixAutoUpdater.pas#L578)). |
| Oversized metadata/signature | **PASS** | Loopback checks both response limits ([tests:897-L906](../../Test.VittixAutoUpdater.pas#L897)). |
| Unsigned defaults / explicit opt-in | **PASS (configuration gate)** | Defaults reject unsigned operation; explicit flag is exercised without a live unsigned manifest response ([tests:527-L566](../../Test.VittixAutoUpdater.pas#L527)). |
| Invalid metadata does not cause package request | **NOT DYNAMICALLY VERIFIED** | Control-flow inspection only; current test fixture invokes the network manager, not engine package-download workflow.

No production server or update installer was contacted/launched. Tests use the conditional local Indy loopback server and publicly known test vectors; no production private signing key is included.

## 5. Build and test results

Toolchain found: RAD Studio 12 Athens, Delphi compiler version 36.0; MSBuild 18.10.1; Python 3.9. Build commands set `BDS=C:\Program Files (x86)\Embarcadero\Studio\23.0` before invoking MSBuild.

| Gate | Actual command / action | Result |
|---|---|---|
| Runtime package Win32 | `MSBuild.exe VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Release /p:Platform=Win32 /v:minimal` | **PASS** — compiler 36.0; 5,193 lines. Existing warnings: duplicate C++-inaccessible constructor and unused private symbol. |
| Runtime package Win64 | `MSBuild.exe VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Release /p:Platform=Win64 /v:minimal` | **PASS** — compiler 36.0; 5,193 lines. Existing duplicate-constructor warnings. |
| Design package Win32 | `MSBuild.exe VittixAutoUpdaterDesign.dproj /t:Build /p:Config=Release /p:Platform=Win32 /v:minimal` | **PASS** — compiler 36.0; 4,982 lines. Existing duplicate-constructor warnings. |
| DUnitX Win32 | `MSBuild.exe TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal`; ran `%TEMP%\VittixAutoUpdaterTests\Win32\Debug\TestCompilation.exe` | **PASS** — 27 found, 27 passed, 0 ignored, 0 failed, 0 errored, 0 leaked. |
| DUnitX Win64 | `MSBuild.exe TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal`; ran `%TEMP%\VittixAutoUpdaterTests\Win64\Debug\TestCompilation.exe` | **PASS** — 27 found, 27 passed, 0 ignored, 0 failed, 0 errored, 0 leaked. |
| Manifest generator | `pytest -q tests/test_generate_manifest_signing.py` | **PASS** — 4 passed. |
| Design package Win64 | Not requested; not run. | **SKIPPED** — existing verification record states `designide` is unavailable for Win64; design packages are Win32 IDE packages ([VAU-T01-verification.md:26](VAU-T01-verification.md#L26)). |
| VCL host smoke tests | No isolated VCL host exists in the checked-in test suite. | **NOT VERIFIED** |
| Registry persistence integration | No engine-level disposable-scope test run. | **NOT VERIFIED** |

An initial direct `rtk msbuild ...` call without setting `BDS` failed because the Embarcadero project target import was unavailable to MSBuild. Re-running with `BDS` set compiled the targets successfully. The failed setup invocation did not modify source.

## 6. Remaining security limitations and blockers

1. **Registry rollback persistence lacks integration evidence.** The code path is fail-closed by inspection, but no real registry read/write/reload/failure test has been executed.
2. **VCL integration and component streaming lack runtime evidence.** Package compilation is not equivalent to installing the design package or streaming a placed component into a form.
3. **Download ordering lacks a dynamic engine-level assertion.** Source order puts authentication/freshness before update availability and package download, but there is no package-request counter test proving rejection stops the download route.
4. **Anti-rollback is limited to HKCU and local wall-clock.** Same-user/admin registry modification, clock changes, and first-run replay remain outside the guarantees. No trusted monotonic time is implemented.
5. **Key revocation requires shipping a new trusted-key configuration through the authenticated application release channel.** A compromised currently trusted signing key can sign arbitrary manifests until clients receive a build/configuration that removes it. There is no remote unauthenticated key replacement mechanism.
6. **No production readiness conclusion follows from this acceptance.** The transactional installation/recovery work from VAU-T02 remains separate and unverified.

## 7. Owner acceptance checklist

- [x] Secure defaults enable signature verification and disable unsigned opt-in.
- [x] Key IDs, envelope algorithm, malformed signatures, and trusted-key rotation behavior covered by source checks and tests.
- [x] Signature checks raw manifest bytes before JSON decoding; generator and verifier share format/vector coverage.
- [x] Missing checksum, nonpositive file size, and response size caps enforced by source; response caps exercised.
- [x] Runtime Win32/Win64, design Win32, DUnitX Win32/Win64, and manifest generator tests pass.
- [ ] Disposable registry persistence/recreation/rollback integration executed.
- [ ] Corrupt/inaccessible registry fail-closed behavior dynamically verified.
- [ ] Disposable VCL host form placement and Config DFM round trip verified.
- [ ] Valid/invalid manifest component events verified without installer launch.
- [ ] Form close during active check and repeated component checks verified on Win32 and Win64.
- [ ] Engine-level assertion confirms invalid metadata causes zero package requests.

Acceptance should remain **PARTIAL** until the unchecked integration tests are executed or explicitly waived by the owner. No implementation work is performed by this report.
