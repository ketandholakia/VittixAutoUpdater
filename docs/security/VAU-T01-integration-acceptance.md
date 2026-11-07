# VAU-T01 Integration Verification and Acceptance

**Date:** 2026-10-27  
**Branch:** `fix/vau-t01-signed-manifest`  
**Scope:** Integration verification of signed update metadata, rollback persistence, engine download ordering, and VCL component lifecycle. This report does not assert overall production readiness.

## Decision

**PASS within the defined VAU-T01 threat model, with documented limitations.**

The final Win32 and Win64 DUnitX runs each passed 34 tests with no failures, errors, ignored tests, or leaks. Runtime packages built for Win32 and Win64, and the design package built for Win32 using RAD Studio 12 Athens compiler 36.0. Four Python signing-generator tests passed. Invalid metadata cases did not reach the package endpoint. The tested scope does not protect against a same-user or administrator who can modify HKCU, does not establish a first-run baseline independent of the signing key/server, and does not provide trusted time against a hostile system clock.

## Test infrastructure

`Test.VittixAutoUpdater.Integration.pas` adds seven DUnitX integration tests to the existing `TestCompilation` application. It generates a disposable P-256 ECDSA keypair in memory with Windows CNG; the private key is not written to fixtures or source. The loopback HTTP server returns signed manifest data and separately counts manifest, signature, package HEAD, and package GET requests. The payload is inert test data and is never installed or executed.

Registry tests use a per-test `HKCU\Software\VittixAutoUpdater\IntegrationTests\<GUID>` scope. A test-only conditional seam (`VITTIX_TEST_REGISTRY`) redirects rollback state to that scope; the test removes only its generated child key. The production registry path is not read or written. A second test-only switch supplies an invalid, overlong child key to exercise a concrete `TRegistry.OpenKey` failure. This tests fail-closed handling of registry open failure, not ACL denial or a real permissions failure.

The test executable enables `VITTIX_TEST_LOOPBACK` for loopback HTTP only. Tests invoke the actual `TUpdateEngine` check and download APIs. VCL checks create actual components under forms and a data module, round-trip a component resource stream, pump synchronized callbacks deterministically, and hold a loopback request while cancellation/destruction occurs.

## Results

### Registry persistence and rollback

`EnginePersistsRollbackFloorAndRejectsReplay` verified: a valid signed manifest is accepted; its floor is written in the disposable HKCU scope; a new engine instance reloads it; the earlier signed manifest is rejected; a newer valid signed manifest advances the floor; and a further engine recreation observes the advanced floor and rejects the now older manifest. Rejected inputs did not advance the floor, and no package request occurred during check-only operations.

`RegistryCorruptionAndAccessFailureFailClosed` verified malformed state and the injected invalid test-scope path fail closed; neither resulted in accepted metadata or a package request. Access failure specifically means `OpenKey` fails against an invalid, overlong isolated subkey, not a simulated ACL denial.

### Engine download ordering

`EngineRejectsBadMetadataBeforePackageRequests` covered seven cases: missing signature, altered manifest, unknown key, expired metadata, future-dated metadata, invalid checksum metadata, and invalid package size. Each was rejected and recorded zero package requests. The implementation also rejects malformed signature encodings/envelopes through the security parser; those cases are not separate entries in this seven-case engine matrix.

`EngineDownloadsOnlyAfterExplicitRequest` checked a valid signed manifest and observed zero package requests during check-only. An explicit call to `TUpdateEngine.DownloadUpdate` then caused exactly one package HEAD and one package GET. No installer was launched.

### VCL host and lifecycle

`VclComponentStreamsConfigAndDeliversEvents` verified component resource streaming of the published configuration, secure defaults and trusted public key retention, valid update-available delivery, invalid-signature error delivery, and main-thread event execution.

`VclComponentSupportsDataModuleOwnershipAndRepeatedChecks` verified data-module ownership and repeated no-update checks without package requests or stuck component state. `VclCancelAndDestroyDuringActiveCheckDoNotCallDestroyedComponent` held an active loopback check, exercised cancellation and form/component destruction, then confirmed no callback after destruction and no package request. These tests passed on both Win32 and Win64.

### Build and automated test commands

All Delphi commands used RAD Studio 12 Athens, `BDS=C:\Program Files (x86)\Embarcadero\Studio\23.0`, MSBuild 18.10.1, and `/p:Config=Debug`:

| Command | Result |
|---|---|
| `MSBuild.exe VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal` | PASS, exit 0; Delphi Win32 compiler 36.0 |
| `MSBuild.exe VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal` | PASS, exit 0; Delphi Win64 compiler 36.0 |
| `MSBuild.exe VittixAutoUpdaterDesign.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal` | PASS, exit 0; Delphi Win32 compiler 36.0 |
| `MSBuild.exe TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal` | PASS, exit 0 |
| `MSBuild.exe TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal` | PASS, exit 0 |
| `TestCompilation.exe --consolemode:Quiet` (Win32) | PASS, 34 found, 34 passed, 0 ignored, 0 leaked, 0 failed, 0 errored; exit 0 |
| `TestCompilation.exe --consolemode:Quiet` (Win64) | PASS, 34 found, 34 passed, 0 ignored, 0 leaked, 0 failed, 0 errored; exit 0 |
| `python -m pytest -q tests/test_generate_manifest_signing.py` | PASS, 4 passed |
| `git diff --check` | PASS; no whitespace errors. Git emitted line-ending conversion notices for pre-existing working-tree edits. |

The command invocations above were run through `rtk proxy powershell -NoProfile -Command` with the stated BDS value. One initial grouped build invocation failed before compilation because the command wrapper stripped the environment assignment; it was corrected and each listed build then returned exit code 0. This invocation failure is not a code failure.

## Defects found and corrected

Integration execution exposed three concrete VCL/engine lifecycle defects; narrow fixes were made in `VittixAutoUpdater.VisualComponent.pas` and `VittixAutoUpdater.Engine.pas`:

1. The visual component created child controls in its constructor before Delphi's form streaming had assigned a parent window. UI setup is now deferred until parent/loading initialization.
2. The record-valued `Config` property was not preserved by ordinary published-property streaming. The property remains available, while versioned custom `ConfigData` streaming preserves the existing settings and trusted keys.
3. Completion timing could leave the engine worker unwinding as the next check began, and the component's `IsUpdating` flag could remain set after a no-update result. Completion synchronization now accounts for the terminal callback window, and the component clears its busy flag in the main-thread callback. The repeated-check regression test passes.

These changes preserve the public `Config` property and source-level usage. The DFM representation now uses custom `ConfigData`; existing forms should be loaded and resaved by the updated component version, and consumers must rebuild against the updated runtime package. This acceptance test did not validate loading every historical DFM produced by prior component releases; that remains a compatibility check before broad deployment.

## Known limitations and remaining blockers

- HKCU state raises the bar against remote replay but is mutable by the same user and by administrators. It is not a secure boundary against local attackers. Tampering with or deleting the scope can reset persisted rollback state.
- On first run there is no locally persisted floor. An old but validly signed manifest may be replayed if no independent baseline or trusted time is available.
- Freshness depends on local system time. A maliciously adjusted clock can weaken expiry enforcement; this work does not introduce a trusted-time source.
- The isolated registry failure case verifies malformed-path/open failure fail-closed behavior; a true denied-access ACL scenario was not exercised.
- The test package build is DUnitX Win32/Win64. No separate test was run against a production endpoint, and none should be used for this verification.
- This verdict applies only to VAU-T01's defined threat model and these verified paths. It is not a statement that the updater as a whole is production-ready.

## Owner acceptance checklist

- [x] Mandatory signed metadata behavior exercised through the engine.
- [x] Rollback floor persistence, reload, replay rejection, and advancement exercised using a unique HKCU test scope.
- [x] Invalid metadata scenarios produced zero package requests.
- [x] Valid package request occurred only after explicit download API invocation.
- [x] VCL form/data-module ownership, streaming, event delivery, thread affinity, repeated checks, cancellation, and destruction exercised on Win32 and Win64.
- [x] Runtime Win32/Win64 and design-time Win32 packages compiled with compiler 36.0.
- [x] Python generator tests and `git diff --check` passed.
- [ ] True ACL-denied registry access test (the current test covers failing `OpenKey` on an invalid isolated subkey).
- [ ] Historical DFM compatibility matrix across all previously shipped component versions.
- [ ] Same-user-resistant rollback storage and independent first-run replay baseline; explicitly outside this task's protection boundary.

