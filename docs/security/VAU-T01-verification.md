# VAU-T01 verification record

## Changes made

* Signed manifest verification and `RequireSecureConfig` now default on. Unsigned mode requires explicit `AllowInsecureUnsignedManifests` and emits a prominent warning.
* The detached signature format is versioned and includes a deterministic key ID. The exact manifest response bytes remain the signed payload; ECDSA P-256/SHA-256 and raw `r||s` are preserved.
* Added multiple trusted public keys for overlap rotation while retaining `ManifestPublicKey`. Keys are provisioned in application configuration, never accepted from manifest content.
* Added manifest and signature response size limits, signed timestamp and package checksum requirements, and a per-user persistent rollback floor. Signed mode rejects downgrade regardless of legacy `AllowDowngrade`.
* Engine config assignment now updates the network manager, so a key configured after engine construction is applied.
* The generator emits the new envelope. Python and Delphi tests verify the shared public signature vector.
* `RequireSecureConfig` remains in the public record for source compatibility; signed checks are mandatory independently of its value. `AllowInsecureUnsignedManifests` is the only unsigned escape hatch.

## Compatibility changes

Old `.sig` files containing only Base64 are rejected. Regenerate and publish a versioned envelope. Existing applications must provision at least one trusted public key. `TUpdaterConfig` grew fields, so rebuild consuming applications/packages; source compatibility is largely preserved. Unsigned migration requires both `VerifyManifestSignature := False` and `AllowInsecureUnsignedManifests := True`, and is unsuitable for production.

## Verification results

Builds used RAD Studio 12 Athens (Delphi compiler 36.0), with `BDS` set to `C:\Program Files (x86)\Embarcadero\Studio\23.0`.

| Gate | Status | Evidence |
|---|---|---|
| Runtime package Win32 | PASS | `msbuild VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Release /p:Platform=Win32 /v:minimal` |
| Runtime package Win64 | PASS | Same command with `/p:Platform=Win64` |
| Design package Win32 | PASS | `msbuild VittixAutoUpdaterDesign.dproj /t:Build /p:Config=Release /p:Platform=Win32 /v:minimal` |
| Design package Win64 | NOT APPLICABLE | Attempted; `designide` is unavailable for Win64. IDE design packages are Win32; runtime Win64 succeeds. |
| Python generator tests | PASS | `pytest -q tests/test_generate_manifest_signing.py` — 4 passed, including UTF-8/LF serialization |
| DUnitX Win32 | PASS | Built and ran `TestCompilation.exe` — 27 found, 27 passed, 0 failed/errored/leaked |
| DUnitX Win64 | PASS | Built and ran `TestCompilation.exe` — 27 found, 27 passed, 0 failed/errored/leaked |
| Valid signed manifest accepted | PASS | Loopback DUnitX case accepts the fixed vector and a pre-provisioned rotated key |
| Invalid metadata rejected before package download | PASS for tested cases | Loopback rejects tampering, unknown ID, missing signature, unprovisioned rotation key, and wrong key in `FetchManifest`; test never invokes a package endpoint |
| Key replacement through manifest | PASS by source/test inspection | Manifest schema contains no key field; verifier selects configured keys; unknown IDs are rejected |
| Persistent registry-floor integration | NOT VERIFIED | Pure rollback policy is unit tested; registry integration was not run to avoid modifying the real user trust store |
| Existing unrelated application behavior | NOT VERIFIED | No broad application regression suite covers all host application behavior |
| No production endpoints contacted | PASS | Tests use only `127.0.0.1`; Python tests use temporary files |
| No production private key committed | PASS by inspection | Shared vectors use publicly known test scalars; generator test key is created in pytest temporary storage |

Test project commands:

```powershell
msbuild TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal
$env:TEMP\VittixAutoUpdaterTests\Win32\Debug\TestCompilation.exe
msbuild TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal
$env:TEMP\VittixAutoUpdaterTests\Win64\Debug\TestCompilation.exe
```

Captured console summaries: [DUnitX Win32](DUnitX-Win32.log), [DUnitX Win64](DUnitX-Win64.log), and [Python generator tests](Python-generator-tests.log).

The loopback server is enabled only by the test-only `VITTIX_TEST_LOOPBACK` define. No production endpoint or installer was contacted or run.

## Known limitations

Freshness checks use local Windows wall-clock time. The persistent floor is HKCU state bound to executable path; it resists network replay after first accepted metadata but not same-user/admin clearing or editing registry state, a fresh install, or clock manipulation on first run. This is not full replay resistance against local attackers. Registry persistence itself was not integration-tested. See [anti-rollback details](manifest-anti-rollback.md).
