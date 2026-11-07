# VAU-T03 Secure Staging Integration Acceptance

**Date:** 2026-10-27 · **Branch:** `fix/vau-t01-signed-manifest`
**Result:** **PARTIAL**

## Scope and baseline

This verification covers the secure staging allocator, reparse handling, file creation, cleanup, network failure cleanup, and independent staging allocations across processes. It does not redesign installation or rollback. The working tree was already dirty at the start of this task; the branch and all pre-existing edits were preserved. Tests used unique disposable directories under the current user's LocalAppData, loopback HTTP only, and inert payload bytes. No production endpoint, installer, production registry location, or live application directory was used.

Security assumptions for the verified paths:

- LocalAppData belongs to the current Windows identity and has the normal user-profile access boundary.
- The updater process and its existing batch helper use the caller's token. This work adds no elevation or cross-process installation mutex.
- Staging directory DACLs are protected and explicitly grant Owner Rights and LocalSystem. A same-identity process or administrator can still alter the staging tree.
- Paths are checked for reparse points when the staging root is selected, after a directory is created, before network writes, and again before cleanup. The code still uses path-based enumeration and cannot eliminate a same-token swap in the interval between an attribute check and a later operation.

## Fixture and implementation changes

`Test.VittixAutoUpdater.Staging.pas` now exercises junction and directory-symbolic-link fixtures created entirely inside per-test directories. The junction helper invokes `mklink /J`; the symbolic-link fixture uses `CreateSymbolicLinkW` with the unprivileged-create flag. Symbolic links were available in this environment. Tests cover reparse ancestors, a junction and a symbolic link inside the staging tree, a staging root replaced after its initial allocation validation, a reparse redirected download destination, and outside-target sentinel preservation.

The network manager now rejects a download destination whose parent path is inaccessible or traverses a reparse point before issuing the request (`VittixAutoUpdater.Network.pas`, `DownloadFile`). This is a narrow destination validation fix. The test verifies a destination below a junction is rejected and no file appears in the junction target.

`VITTIX_TEST_STAGING`, enabled only in the DUnitX project, adds a test-only identifier queue and random-failure switch. The production build does not define this symbol and continues to obtain identifiers only from `BCryptGenRandom`.

The disposable Win32 `StagingWorker` allocates a staging directory, writes a PID marker, and can hold, clean, or leave its operation directory. The PowerShell driver starts independent processes concurrently and verifies unique paths, ownership-isolated cleanup, process-termination isolation, and diagnosable stale artifacts. It removes the entire generated fixture tree in `finally`.

## Reparse-point results

The Win32 and Win64 DUnitX suites each passed all 14 staging fixture tests. Verified cases:

- Allocation rejected a junction base and a directory symbolic-link base.
- Cleanup removed junction and symbolic-link children as links without traversing to their targets; sentinel files outside staging remained unchanged.
- Cleanup failed closed after the staging root was replaced by a junction following allocation.
- Network download rejected a destination whose parent was a junction before creating a file at the target.
- Staging cleanup left unrelated directories intact.

The root-replacement case exercises a reparse point introduced after allocation-time validation and before cleanup. It does not inject a swap in the narrower interval between cleanup's attribute check and traversal. That same-identity TOCTOU case remains **NOT VERIFIED**; path-based cleanup is not a handle-relative no-follow implementation.

## ACL results

The DUnitX ACL assertion reads each test object's security descriptor. It verified:

- The staging directory DACL is protected from inherited broad grants.
- The directory DACL contains exactly the Owner Rights (`S-1-3-4`) and LocalSystem (`S-1-5-18`) allow ACEs.
- A staged helper-like file inherits those two ACEs.

No second standard-user account/token was provisioned or used for an effective access test, and no account or machine-wide ACL was created or modified. Therefore, the following are **NOT VERIFIED**: second-user read denial, second-user write denial, replacement denial for a staged package/helper, and cleanup under an independently authenticated second identity. DACL contents support the intended boundary but do not substitute for that test.

## Collision and allocation results

Deterministic DUnitX tests verified:

- A forced collision on the first identifier retries and succeeds with the next identifier.
- Sixteen forced collisions terminate with an explicit failure and leave the colliding directory untouched.
- Injected RNG failure creates no staging directory.
- Production continues to use CNG system-preferred random bytes; application configuration cannot select predictable production identifiers.
- Twelve concurrent test threads allocate distinct directories.

## Cross-process evidence

The worker build and `verify-cross-process.ps1` completed with exit code 0. Eight independent worker processes allocated concurrently and returned eight distinct paths. A cleanup process removed only its own tree while a peer remained live. Terminating one worker left the survivor's marker and directory intact. Another terminated worker left an identifiable `worker.pid` stale artifact, which the isolated cleaner removed. This verifies allocator and directory-ownership isolation across processes, not concurrent `TUpdateEngine` downloads or installation serialization.

Common disposable base for the recorded run:

`C:\Users\Admin\AppData\Local\VAU-T03-INT-7d6800b1d8f24c598f808d07d04a8adc`

| Scenario | PID | Staging directory leaf |
|---|---:|---|
| Parallel allocation | 27460 | `VittixAutoUpdater-DC541C119A2A3F18641F8FC95B829388` |
| Parallel allocation | 15536 | `VittixAutoUpdater-FAAE6C71C02CF1F4A898DFFD5AACBFF3` |
| Parallel allocation | 29564 | `VittixAutoUpdater-154BED7C96A40516D0B9C59FD70B2D24` |
| Parallel allocation | 9148 | `VittixAutoUpdater-7E95DF3DCF549D75D29C2E88D6C6A87D` |
| Parallel allocation | 12208 | `VittixAutoUpdater-086136C85C3C2BD8205D498776C33C90` |
| Parallel allocation | 22428 | `VittixAutoUpdater-7AFC2B55A4066C22EF352E3941A4C52D` |
| Parallel allocation | 11132 | `VittixAutoUpdater-ADAF6148C079A5B8BB85029300319E01` |
| Parallel allocation | 30296 | `VittixAutoUpdater-3B6352AD450B4FAEE121940D42CACBE7` |
| Isolated cleanup | 4872 | `VittixAutoUpdater-341F7E5B4FEE23C7E379D4BB73512BD0` |
| Independent live operation | 24952 | `VittixAutoUpdater-8476CBB6BA07E3D14C55A3D01CD13C34` |
| Terminated peer | 21764 | `VittixAutoUpdater-C36355072D70FB3F09DE5DCE048F8F4E` |
| Surviving peer | 31396 | `VittixAutoUpdater-2F20C89FAAF305B7A45922CB8C9A438E` |
| Terminated stale artifact | 23652 | `VittixAutoUpdater-A33C8F1BA9F9AEE11CCE797AE0824A93` |

The process-termination scenario shows that one allocator process's termination does not delete another process's staging. It does not drive `TUpdateEngine.Cancel` in two separate updater processes; that exact cross-process cancellation behavior is **NOT VERIFIED**. Same-process engine cancellation is covered by the loopback integration test.

## Network failure cleanup

Engine-level loopback tests use a signed manifest and the real `TUpdateEngine.DownloadUpdate` API. Results:

- **Connection refusal:** the package server was allocated and then closed before download. Download failed and its operation directory was cleaned.
- **Connection reset:** the loopback server disconnected during GET. Download failed and its operation directory was cleaned.
- **Truncated response:** the server advertised a larger content length than it sent. Download failed and its operation directory was cleaned.
- **Response timeout:** the package response was held beyond the configured response timeout. The engine returned failure and cleaned its operation directory.
- **Cancellation while streaming:** cancellation produced `usCancelled`, returned no completed package, and cleaned its operation directory.
- **Checksum mismatch:** the transfer completed but failed SHA-256 validation, returned failure, and cleaned its operation directory.
- Fault cleanup preserved a separately allocated peer staging directory.

Existing retry/resume tests also ran in the full suite. The new engine fault matrix sets one retry for deterministic failure assertions; retry under intermittent failures is not separately verified at engine level.

## Installer handoff lifecycle

No helper was launched during testing. Source inspection shows `ApplyUpdateWindows` treats `ShellExecute` returning a value greater than 32 as success; `ApplyUpdate` then transitions to `usComplete` and relinquishes the staging path immediately. The updater does not observe helper completion, copy failure, or post-launch termination. The batch helper's success branch removes the package and extraction tree; a failed helper can leave staging behind.

The requested harmless helper signals and handoff completion/failure tests are **NOT VERIFIED** because the current architecture has no injectable helper contract and launching the existing helper would modify an application installation. VAU-T02 should provide observable helper completion and explicit final status. VAU-T03 does preserve staged content after process handoff so the existing helper has time to read it, but the engine's `usComplete` status currently means helper launch succeeded, not installation completed.

## Build and regression evidence

Toolchain: RAD Studio 12 Athens, Delphi compiler 36.0; MSBuild 18.10.1. Commands were invoked through `rtk proxy powershell -NoProfile -Command` after setting `BDS=C:\Program Files (x86)\Embarcadero\Studio\23.0`.

| Command | Result |
|---|---|
| `MSBuild.exe VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal` | PASS, exit 0 |
| `MSBuild.exe VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal` | PASS, exit 0 |
| `MSBuild.exe VittixAutoUpdaterDesign.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal` | PASS, exit 0 |
| `MSBuild.exe TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal` | PASS, exit 0 |
| `MSBuild.exe TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal` | PASS, exit 0 |
| `MSBuild.exe tests\staging-worker\StagingWorker.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal` | PASS, exit 0 |
| `TestCompilation.exe --consolemode:Quiet` (Win32) | PASS, 52 found, 52 passed, 0 ignored, 0 leaked, 0 failed, 0 errors; exit 0 |
| `TestCompilation.exe --consolemode:Quiet` (Win64) | PASS, 52 found, 52 passed, 0 ignored, 0 leaked, 0 failed, 0 errors; exit 0 |
| `TestCompilation.exe --run:Test.VittixAutoUpdater.Staging --consolemode:Quiet` (Win32/Win64) | PASS, 14/14 on each target |
| `verify-cross-process.ps1 -WorkerPath ...\StagingWorker.exe` | PASS, script exit 0; 8 simultaneous allocations plus isolation, termination, stale-artifact scenarios |
| `python -m pytest -q tests/test_generate_manifest_signing.py` | PASS, 4 passed |
| `git diff --check` | PASS; only existing line-ending notices |

VAU-T01 signed-manifest, registry, engine ordering, and VCL regressions are included in both 52-test runs. One earlier run failed only because the first ACL assertion incorrectly required file DACLs to set the protected bit instead of inheriting the two intended ACEs. The test was corrected; final Win32 and Win64 runs passed.

## Remaining gaps and decision

**Verified:** cryptographically unpredictable unique directories; atomic collision handling; protected directory ACL contents; inherited file ACL contents; junction and directory-symbolic-link rejection/removal; network destination rejection through reparse ancestors; safe cleanup for connection failure, reset, truncation, timeout, cancellation, and hash mismatch; multi-process allocator isolation; deterministic collision and RNG-failure behavior; VAU-T01 regression builds and tests.

**NOT VERIFIED:** effective access under a distinct second standard-user token; a reparse swap during the cleanup check/use interval; cancellation via actual updater engines in independent processes; retries under fault injection at engine level; helper completion/failure observation; a full installation handoff using a harmless helper. Stale directories from process or machine crashes are identifiable but are not automatically swept by production code.

**VAU-T03 verdict: PARTIAL.** Core staging and failure cleanup behavior now has broad integration evidence on Win32/Win64, including reparse fixtures, deterministic collisions, and independent worker processes. The second-user access test and helper handoff lifecycle remain material verification gaps. This verdict does not imply overall production readiness.
