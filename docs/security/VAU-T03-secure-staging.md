# VAU-T03 — Secure Private Update Staging

**Date:** 2026-10-27  
**Branch:** `fix/vau-t01-signed-manifest`  
**Status:** **PARTIAL** — core unique staging and failure cleanup are implemented and integration-tested; several requested security simulations and post-crash/handoff cleanup cases remain unverified.

## Previous staging behavior

Before this change, `TUpdateEngine.GetTempZipFile` generated `<TempFolder or %TEMP%>\<AppName>_update_yyyymmdd_hhnnss.zip`. Two attempts in the same second could collide, and downloads used retry names derived from that shared path. `GetTempExtractPath` independently generated `%TEMP%\<AppName>_extract_yyyymmdd_hhnnss`; it did not share ownership with the archive operation. `ApplyUpdateWindows` wrote `update_<AppName>.bat` directly into the shared temp directory and saved over an existing path. Cleanup deleted the named archive and recursively removed the extraction directory using stored path strings. That allowed other update operations to collide and left helper creation and cleanup exposed to shared-temp interference.

The previous download manager used `CREATE_ALWAYS` for fresh partial files, which could truncate a pre-existing path. ZIP extraction already used lexical traversal validation and a protected ACL on the extraction directory, but staging as a whole did not have a unique operation owner.

## New staging design

`VittixAutoUpdater.Staging.pas` provides the Windows staging primitives used by the engine:

1. The base is obtained from the Windows Known Folder API (`FOLDERID_LocalAppData`), not `%TEMP%`, `TEMP`, or `TMP` environment expansion.
2. A configured `TempFolder` is accepted only when it resolves beneath the current identity's LocalAppData. Paths outside that profile scope, inaccessible paths, and paths containing reparse points are rejected with an explicit error.
3. The allocator obtains 128 random bits from `BCryptGenRandom` with `BCRYPT_USE_SYSTEM_PREFERRED_RNG`, encodes them as a 32-character hex suffix, and calls `CreateDirectory` with a protected DACL. `ERROR_ALREADY_EXISTS` retries with a new random identifier, up to 16 attempts. Other errors fail closed.
4. The protected DACL grants full access to the directory owner and LocalSystem, with inheritance to contained artifacts. The created path and every existing ancestor are checked for reparse points. Staging paths longer than the configured 230-character ceiling are rejected to leave room for fixed package, retry, and helper names within classic `MAX_PATH`.
5. An engine instance allocates one operation directory lazily when a package download starts. It stores the archive as `package.zip`, the extraction as `payload`, and the helper as `apply.cmd` inside that directory. Each updater instance/process receives a separately created directory; no operation reuses another engine's directory.
6. Fresh network partial files now use `CREATE_NEW`. Existing partial attempts are explicitly removed by the download retry logic before a new attempt is created. The helper path is also first created with `CREATE_NEW`.

`TempFolder` remains in the public configuration record and retains its intended role as an optional staging base, subject to the new LocalAppData restriction. A configured base must already exist. Applications that previously configured a shared temp folder outside LocalAppData must remove that setting or move it under LocalAppData; otherwise staging fails closed. This is a runtime behavior change, not a source-level API removal.

## Ownership, cleanup, and handoff

An engine owns its staging path until successful installer-helper launch. Download exceptions, HTTP failures, checksum/size failure, cancellation, extraction failure, apply failure, `Reset`, and destruction call safe cleanup. The cleanup routine verifies that the target is a direct child of the recorded base, has the updater staging prefix and expected identifier length, and is not itself redirected. It enumerates entries and removes reparse points as links without descending through them; ordinary directories are traversed recursively. Cleanup failure is logged to the debugger and the engine retains its path fields so a later cleanup call can retry.

After the existing batch helper has been launched, the engine relinquishes ownership so destruction cannot delete files while the helper copies them. On the helper's successful copy path it removes `package.zip`, the extracted `payload`, and its own batch file. No installer is run by the test suite.

There is no automatic stale-directory sweep. This avoids deleting a directory that belongs to another live update when there is no cross-process ownership lock (VAU-T05). If the process or machine stops before cleanup or handoff completes, private staging artifacts can remain and consume disk space. The helper handoff's actual completion/cleanup path was not run end to end because that would mutate an application installation; an empty staging parent may remain after helper self-deletion.

## Permissions and privilege boundary

The staging directory is created with a protected owner/SYSTEM DACL and no broad Users or Everyone grant. LocalAppData is scoped to the effective Windows identity. The updater and the current batch helper inherit the caller's token; this task does not add UAC elevation, a privileged helper, or a cross-process installation mutex. If the application already runs elevated, the existing helper also runs with that token. Staging integrity relies on the protected directory ACL and the signed metadata/package checks already present in VAU-T01; this does not make the existing in-place installation transactional or suitable for privileged installation.

An attacker running as the same Windows identity or an administrator can alter that identity's staging data and ACL. Handle-relative no-follow filesystem operations were not introduced, so same-token races remain outside the verified boundary. Other standard-user access was not tested by impersonating a second Windows identity.

## Tests and evidence

Added `Test.VittixAutoUpdater.Staging.pas` with tests for unique directory allocation, protected DACL state, concurrent allocation by 12 threads, operation-scoped cleanup that leaves unrelated directories intact, invalid base rejection, and exclusive file creation. Added engine integration tests proving checksum failure and cancellation remove their operation staging directories. Existing VAU-T01 integration tests continue to exercise signed-manifest ordering, and no package is installed or executed.

Final results with RAD Studio 12 Athens compiler 36.0:

| Check | Result |
|---|---|
| Runtime package Win32 | PASS, build exit 0 |
| Runtime package Win64 | PASS, build exit 0 |
| Design-time package Win32 | PASS, build exit 0 |
| DUnitX test application Win32 | PASS, build exit 0; 41/41 passed, 0 failed, 0 errors, 0 leaks |
| DUnitX test application Win64 | PASS, build exit 0; 41/41 passed, 0 failed, 0 errors, 0 leaks |
| VAU-T01 signature and engine integration cases | Included in both 41-test runs; PASS |
| `python -m pytest -q tests/test_generate_manifest_signing.py` | PASS, 4 passed |
| `git diff --check` | PASS; only existing LF/CRLF conversion notices |

Commands were run through `rtk proxy powershell -NoProfile -Command` with `BDS=C:\Program Files (x86)\Embarcadero\Studio\23.0` and MSBuild 18.10.1. Build forms were:

```text
MSBuild.exe VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal
MSBuild.exe VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal
MSBuild.exe VittixAutoUpdaterDesign.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal
MSBuild.exe TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal
MSBuild.exe TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal
TestCompilation.exe --consolemode:Quiet  # run once from Win32 output and once from Win64 output
python -m pytest -q tests/test_generate_manifest_signing.py
git diff --check
```

One initial full Win32 run had a transient timeout in the existing repeated-check VCL test. That test passed in isolation and the subsequent full Win32 run passed 41/41. A first Win64 test compile also exposed generic assertion inference errors; explicit integer generic arguments fixed those, after which Win64 compiled and all 41 tests passed.

## NOT VERIFIED

- Junction/symlink creation and cleanup redirection tests. Code inspection confirms ancestor checks and non-following cleanup branches, but no reparse fixture was exercised.
- Access from a second standard-user token and actual ACL-denied operations. The test asserts a protected DACL control bit; it does not impersonate or perform an access check as another user.
- Deterministic collision-retry injection. Concurrent random allocations passed, but no forced RNG collision was injected.
- Separate processes or multiple real updater components downloading concurrently. The allocator uses exclusive atomic directory creation, but the integration concurrency case uses threads within one test process.
- Real network disconnection cleanup. Checksum failure and cancellation cleanup passed; a distinct package-server failure case was not added.
- Crash-recovery cleanup of stale staging artifacts and actual installer helper completion. No stale sweep is implemented, intentionally, because no process ownership lock exists.
- Full-path behavior for unusually deep ZIP entries beyond the existing lexical extraction checks. Entries resolving to 260 or more characters are now rejected; archive link/reparse extraction policy remains outside this task.

## Remaining risks and acceptance

This implementation removes shared predictable filenames, gives each operation a cryptographically named, exclusively created private staging directory, uses a protected DACL, makes network partial-file creation exclusive, and cleans operation-owned staging on tested failure/cancel paths. Cross-process mutex/serialization remains VAU-T05. Stale artifacts may remain after crashes. Reparse behavior and second-user ACL denial need isolated Windows VM coverage before claiming the full acceptance criteria.

**VAU-T03 verdict: PARTIAL.** Core staging controls and both architecture test suites pass, but multiple required filesystem/identity scenarios and crash/handoff cleanup are not verified. No claim is made that VAU-T03 is fully accepted or that installation is production-ready.
