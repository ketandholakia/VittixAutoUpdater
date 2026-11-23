# VAU-T04 — ZIP extraction security hardening

## Scope and observed baseline

Before this change, `TUpdateEngine.ExtractUpdate` opened the downloaded package with Embarcadero `System.Zip.TZipFile`, checked each `FileNames[I]` using `IsSafeZipEntryPath`, then called `TZipFile.Extract`. The old path check rejected rooted names, colons, and paths that failed a full-path prefix check. It did not enumerate collisions or archive resource use before writing.

The Delphi 12 RTL extraction routine applies archive metadata, opens regular output files in overwrite mode, and creates symbolic links when the entry attributes identify a link. An entry could therefore reach behaviors outside the intended update layout even when its final pathname passed the earlier basic check. Extraction reported success after the loop and relied on `ApplyUpdate` to stop installation when `ExtractUpdate` returned false.

This change keeps the existing `System.Zip.TZipFile` reader and engine/install workflow. It does not change the signature protocol, package checksum rules, secure staging allocator, or installation transaction design.

## New extraction flow

1. The engine verifies that the package file exists and is below the configured compressed archive size limit before opening it.
2. The RTL parses the central directory. The engine bounds the entry count, rejects an empty archive, and validates all names, types, declared sizes, duplicate destinations, and file/directory conflicts before creating the payload directory.
3. The payload directory is created with the existing private staging ACL. Reparse points are rejected in the payload root and checked again in parent paths before and after directory creation.
4. Entries are read through `TZipFile.Read(..., CheckCrc=True)` and copied manually. Regular output files use `CreateFile(..., CREATE_NEW, FILE_FLAG_OPEN_REPARSE_POINT)` so existing files cannot be overwritten and the final component is not followed as a reparse point. Timestamps and archive permissions are ignored.
5. The engine checks actual bytes streamed against per-entry and total limits and checks the actual length against the central-directory size. ZIP CRC validation is delegated to the RTL stream.
6. Any exception returns extraction failure. `ApplyUpdate` then cleans the operation-owned staging context and does not call the installer helper. The test-only extraction seam also cleans its own operation context after a failed downloaded-package extraction.

## Entry-name and entry-type policy

Names are normalized to Windows separators and rejected if empty, rooted, drive-qualified, UNC/device namespaced, contain a colon/ADS, contain control or invalid Win32 filename characters, contain empty, `.` or `..` components, end a component with a dot or space, or use reserved DOS device basenames (`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `LPT1`–`LPT9`). The normalized full destination must remain inside the payload root and below the path length cap.

Archive paths are compared using Windows `CompareStringOrdinal` case-insensitive comparisons. Duplicate names, case-only aliases, file/directory collisions, a file used as a parent directory, and a file path that already has child entries are rejected before extraction.

Only unencrypted ZIP entries using Store (method 0) or Deflate (method 8) are accepted. Symbolic links, reparse-point attributes, and non-regular Unix entry types are rejected. Directory and ordinary file entries are supported. Other metadata such as file permissions, timestamps, and ownership is not applied.

## Resource limits

`TUpdaterConfig.Default` supplies these limits:

| Limit | Default |
|---|---:|
| Compressed archive bytes | 512 MiB |
| Entry count | 4,096 |
| Total uncompressed bytes | 1 GiB |
| Single entry uncompressed bytes | 256 MiB |
| Path depth | 32 components |
| Normalized path length | 240 characters |
| Expansion ratio | 200:1 |

The configured limits are validated as positive values. Declared sizes are accumulated with unsigned overflow-safe limit checks. The configured expansion ratio is checked from central-directory sizes before extraction; actual output bytes are capped while streaming. Available disk space is checked against the declared uncompressed total before payload creation.

The total and per-entry output caps are authoritative even if archive size headers lie. A mismatching actual entry size or an RTL CRC error makes extraction fail. The compressed archive byte cap also bounds the amount of data presented to the RTL central-directory parser, although the RTL parses that directory before the entry-count limit can be checked.

## Compatibility

Seven fields were added to `TUpdaterConfig` for ZIP limits. Existing source code remains compatible when it initializes configuration with `TUpdaterConfig.Default`; code that manually fills every record field should add the new fields or begin from `Default`. This changes the record's binary layout, so applications must rebuild against the updated runtime package.

ZIP limits were introduced in version 2 of `ConfigData`. Current version 4 streams also store `PreserveFiles`, and versions 1–3 remain readable. Version 1 receives secure ZIP defaults.

## Tests and verification

New DUnitX coverage builds archives in disposable directories and exercises valid extraction, traversal rejection, mixed separator traversal, absolute/drive/UNC/device forms, ADS, reserved names, invalid Win32 names, trailing dots/spaces, case-insensitive duplicate destinations, single-entry size rejection, and secure defaults. An engine integration fixture signs metadata for a generated ZIP, verifies that metadata is accepted without package retrieval, explicitly downloads and checks the ZIP, extracts a safe package without invoking installation, then downloads a correctly signed and hashed traversal archive and verifies that extraction fails and its private staging context is removed.

Delphi 12 compiler 36.0 results at the time of this audit:

- Runtime package Win32: built.
- Runtime package Win64: built.
- Design-time package Win32: built.
- DUnitX Win32: 57 tests passed, 0 failed, 0 errored.
- DUnitX Win64: 57 tests passed, 0 failed, 0 errored. An earlier full run had one order-dependent VCL data-module timeout; the final full run passed.
- Manifest generator tests: 4 passed.
- `git diff --check`: passed after the final source/test additions.

The VCL data-module repeated-check test has timed out intermittently in full-suite runs on both Win32 and Win64; it passed when run alone and passed in the final full run on both targets. The timeout is an existing integration-test/lifecycle flakiness signal and should be stabilized separately.

Commands used with RAD Studio 12 Athens compiler 36.0 (the workspace's Delphi conditional symbol is supplied explicitly):

```powershell
$env:BDS = 'C:\Program Files (x86)\Embarcadero\Studio\23.0'
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /p:DCC_Define=DELPHIXE_UP /v:minimal
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /p:DCC_Define=DELPHIXE_UP /v:minimal
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' VittixAutoUpdaterDesign.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /p:DCC_Define=DELPHIXE_UP /v:minimal
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win32 '/p:DCC_Define=DELPHIXE_UP%3BVITTIX_TEST_LOOPBACK%3BVITTIX_TEST_REGISTRY%3BVITTIX_TEST_STAGING' /v:minimal
& "$env:TEMP\VittixAutoUpdaterTests\Win32\Debug\TestCompilation.exe" --exitbehavior:Continue --consolemode:Quiet
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win64 '/p:DCC_Define=DELPHIXE_UP%3BVITTIX_TEST_LOOPBACK%3BVITTIX_TEST_REGISTRY%3BVITTIX_TEST_STAGING' /v:minimal
& "$env:TEMP\VittixAutoUpdaterTests\Win64\Debug\TestCompilation.exe" --exitbehavior:Continue --consolemode:Quiet
rtk pytest -q tests/test_generate_manifest_signing.py
rtk git diff --check
```

## Residual risks and NOT VERIFIED cases

- Reparse-point and ancestor checks use path-based Windows attribute queries around creation. `CREATE_NEW` and `FILE_FLAG_OPEN_REPARSE_POINT` protect final regular-file creation, but do not eliminate every same-identity time-of-check/time-of-use race in parent directories. A handle-relative extraction implementation would be needed for stronger same-user race resistance.
- Cross-user ACL behavior is inherited from the operation-owned VAU-T03 staging directory and was not retested as part of VAU-T04.
- Dedicated DUnitX fixtures for junctions/symbolic links at every path component, malformed/truncated ZIPs, corrupt compressed data, expansion-ratio limits, excessive entry count/depth, extraction cancellation, and simultaneous extraction were not added in this phase. These cases are NOT VERIFIED by VAU-T04 tests.
- The RTL central-directory parser allocates/parses before the updater can enforce the entry-count limit. The compressed archive cap bounds the input size but is not a parser-level entry allocation limit.
- ZIP extraction does not provide transactional installation or rollback. Those concerns remain VAU-T02 work; the updater does ensure the installer handoff is skipped when extraction fails.
- Win64 full DUnitX currently has one intermittent/order-dependent VCL integration timeout; it passed when isolated. This remains open.

## Verdict

**PARTIAL.** The primary extraction path now validates all entries before writes, rejects common Windows path and collision attacks, avoids RTL symlink creation and overwrite behavior, enforces declared and streamed resource caps, verifies CRC through the RTL reader, and demonstrates signed-package engine integration without launching installation. The required reparse-point race fixtures and broader malformed/resource/concurrency matrix are not complete. VAU-T04 is not accepted as PASS until those verification gaps are closed.

## VAU-T04-INT follow-up

The bounded preflight now runs before the Delphi RTL ZIP parser. It limits the configured compressed archive size, EOCD scan, central-directory size (16 MiB), raw entry name (1,024 bytes), and configured entry count. It validates local/central metadata and rejects ZIP64, multi-disk archives, prepended data, overlapping local records, and unaccounted bytes in the local-record region. This intentionally restricts accepted update archives to compact, single-disk ZIP files.

A focused test reproduced the RTL accepting a deflate entry after the declared compressed size was shortened by one byte. The local-region coverage check now rejects that fixture. A disposable junction test also confirmed that extraction rejects a reparse-point ancestor before creating a payload directory through it.

See docs/security/VAU-T04-integration-acceptance.md for the actual Win32/Win64 build and test results. The final VAU-T04-INT verdict is PARTIAL: the Win32 VCL repeated-check test fails both in the full suite and in isolation, and cancellation, concurrent extraction, and reparse-point replacement races remain unverified.


## Path conflict lookup

Preflight indexes explicit file and directory entries plus implicit parents in
a case-insensitive dictionary. It rejects duplicate destinations and file and
directory conflicts in either entry order, including Windows ordinal Unicode
case matches. ZIP limits and reparse-point checks still apply before writes.
