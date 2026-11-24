# 1.0.0-rc1 release status

## October audit follow-up

Statuses reflect current source. The test column identifies automated coverage
and remaining verification gaps. The original findings are in the
[October security assessment](audit/03-security-assessment.md).

| Finding | Status | Fix commits and current behavior | Covering tests and gaps |
| --- | --- | --- | --- |
| VAU-001 Signed metadata disabled by default | Fixed | `b306ada` requires signed manifests by default. The network manager checks detached signatures against configured keys before parsing. The engine persists the accepted floor. [Configuration](../VittixAutoUpdater.Types.pas), [network](../VittixAutoUpdater.Network.pas), [anti-rollback](security/manifest-anti-rollback.md) | `SecureDefaultsRequireSignedMetadata`, `SignedManifestFetchRejectsTamperingAndUnknownKeys`, `EngineRejectsBadMetadataBeforePackageRequest`, and the scoped registry tests below |
| VAU-002 Incomplete multi-file rollback | Partially fixed | `4bc2436` backs up destinations and restores replaced files or removes new files on handled copy failure. The helper copies files in place. Power loss and helper termination still lack startup recovery. [Apply helper generation](../VittixAutoUpdater.Engine.pas) | `ApplyScriptBacksUpRestoresAndPreservesFiles` covers a forced copy failure. File-by-file interruption and startup recovery remain uncovered. |
| VAU-003 Predictable shared-temp helper | Partially fixed | `b306ada` uses a unique private staging directory, restricted ACLs, and exclusive helper creation. The engine still launches `apply.cmd`, and separate staging directories do not serialize applies to the same install. [Staging](../VittixAutoUpdater.Staging.pas), [apply](../VittixAutoUpdater.Engine.pas) | `AllocationsAreUniqueAndUseProtectedAcl`, `ConcurrentAllocationsAreIsolated`, `ExistingStagingFileIsNotReused` cover staging. Signed helper and same-install apply serialization remain open. |
| VAU-004 ZIP limits and reparse protection | Partially fixed | `b306ada`, `b6c5236`, and `d3b198a` enforce archive limits and preflight path conflicts. The engine checks ancestors for reparse points, checks free space, and exclusively creates output with `FILE_FLAG_OPEN_REPARSE_POINT`. Output still uses full paths, so the proposed handle-relative extraction remains open. [Extraction](../VittixAutoUpdater.Engine.pas) | `ZipResourceLimitsEnforceBoundaries`, `ZipPreflightRejectsMalformedAndAmbiguousArchives`, `ZipExtractionRejectsReparsePointAncestorBeforeWrites`, `ZipExtractionRejectsReparseReplacementBeforeWrite` |
| VAU-005 Redirect and URL policy validation | Partially fixed | `b306ada` constrains secure redirect hops, and `21ad32b` discards intermediate GET response bodies. GET and HEAD validate the next resolved URL. The policy checks scheme and host presence. Explicit userinfo rejection and independent final-response URL validation remain open. [Redirect handling](../VittixAutoUpdater.Network.pas) | `HttpsAndRedirectRulesArePureAndStrict`, `LoopbackHttpDownloadRetryResumeAndRedirects`, `ManifestRedirectDiscardsResponseBody`. Live HTTPS redirect and downgrade acceptance remains pending. |
| VAU-006 Platform TLS validation and no transport pinning | Open | `b306ada` supplies the independent signed-metadata protection recommended by the audit. The network manager relies on Windows HTTP certificate and hostname validation. Authenticode publisher pins apply to installed payload binaries. [Transport](../VittixAutoUpdater.Network.pas), [Authenticode](../VittixAutoUpdater.Engine.pas) | No automated coverage for expired, hostname-mismatched, or untrusted TLS certificates. `AuthenticodeFixtureThumbprintAndPins` covers publisher pins only. |

## Windows package builds

From a Delphi 12 Athens RAD Studio Command Prompt with both Windows compilers
installed, run these commands in the repository root.

```bat
BuildPackages.bat Win32
BuildPackages.bat Win64
```

The Win32 command builds the runtime and design packages. The Win64 command
builds the runtime package. The Delphi 12 IDE uses the Win32 design package
and its Win32 `designide` dependency.

Check the Release BPL version resources for `Vittix` and version `1.0.0.0`.
Build `TestCompilation.dproj` in Debug for Win32 and Win64 and run each
`TestCompilation.exe` from the output directories under
`%TEMP%\VittixAutoUpdaterTests`. The pytest suite runs on pushes.

## Source archive

Run `powershell -File tools/make-release-zip.ps1` from the repository root
after committing the intended release contents. It archives `HEAD` to
`VittixAutoUpdater.zip`. Use `-OutputPath` to select another destination.
The optional `-IncludeTestLogs` switch includes any already committed
`docs/security/*.log` files. Keep new test logs with release evidence.

## Registry and clean-VM acceptance

`EnginePersistsRollbackFloorAndRejectsReplayedManifest` and
`RegistryCorruptionAndAccessFailureFailClosed` already cover registry persistence
across engine recreation, corruption, and simulated access failure in a
disposable HKCU test scope. Track separate process and clean-VM acceptance in
the [acceptance results](release/ACCEPTANCE_RESULTS.md).
