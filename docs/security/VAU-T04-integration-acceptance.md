# VAU-T04-INT hostile ZIP verification

Date: 2026-10-28

## Decision

**PARTIAL.** The bounded ZIP preflight, malformed-archive fixtures, configured resource-limit tests, reparse-point ancestor check, and signed-package engine integration passed on the available Delphi 12 Athens toolchain. Win64 passed the complete DUnitX suite (60/60). Win32 reported 59/60 with a reproducible VCL repeated-check timeout. Cancellation during decompression and concurrent extraction were not exercised through the actual extraction API, and reparse-point replacement races were not deterministically injected. The acceptance criteria therefore are not all verified.

## Trust boundaries and state

The package remains untrusted until manifest signature verification and checksum validation have succeeded. The engine downloads it to its operation-owned VAU-T03 private staging directory. ExtractUpdate then performs a bounded container preflight before TZipFile.Open, validates the RTL entry list and Windows destinations before creating the payload directory, creates files exclusively, and checks streamed output, final length, and CRC before returning success. ApplyUpdate proceeds to its existing helper handoff only after extraction returns success.

The new preflight bounds the archive file, EOCD search, central-directory bytes, raw filename size, entry count, local-record extents, and central/local metadata agreement before the RTL allocates its central-entry array. It rejects ZIP64, multi-disk archives, prepended/self-extracting data, and unaccounted bytes in the local-record region. This defines a deliberately restricted compact ZIP format for updater packages.

Extraction failures return False and set usFailed; the existing apply path does not hand failed extraction to the installation helper. Test fixtures use disposable temporary directories. No production package or installer was run.

## Changes in this verification phase

- VittixAutoUpdater.Engine.pas: moved PreflightZipArchive outside the test-only registry conditional so runtime and design-time packages compile with the bounded parser. Added a local-record region coverage check to reject unowned bytes, including the reproduced shortened deflate-size fixture. Added a pre-creation check for reparse points and missing components in the extraction parent.
- Test.VittixAutoUpdater.pas: added deterministic malformed archive, resource boundary, and junction-ancestor tests. The fixtures are generated and mutated under unique disposable temporary directories.

The first Win32 package build exposed that the preflight had accidentally been enclosed by VITTIX_TEST_REGISTRY; this was corrected before final builds. No signing, staging allocation, installation, or manifest protocol behavior was changed.

## Hostile archive fixtures

ZipPreflightRejectsMalformedAndAmbiguousArchives exercised:

- Truncated EOCD.
- Invalid central-directory offset.
- Incorrect CRC metadata.
- Inconsistent expanded and compressed sizes.
- Truncated declared deflate data (the RTL accepted the initial fixture before the local-region coverage check).
- Unsupported compression method.
- Encrypted-entry flag.
- Local/central filename mismatch.
- Overlapping local records.
- ZIP64 sentinel.
- Invalid central-directory signature.

All 12 cases rejected with usFailed; the focused malformed-archive DUnitX test passed on Win32. The fixtures assert extraction does not return success. They do not launch an installer or target installed application files.

ZIP64 is rejected as unsupported by policy, including legacy sentinel fields and ZIP64 extra fields. Multi-disk ZIP is likewise rejected. The Delphi RTL is not invoked for archives rejected by preflight.

## Resource-limit results

ZipResourceLimitsEnforceBoundaries accepted an archive exactly at configured limits and rejected:

- Compressed archive size one byte above the limit.
- Entry count one above the limit.
- Total expanded bytes one byte above the limit.
- Single-entry expanded bytes one byte above the limit.
- Path depth one component above the limit.
- Normalized path length one character above the limit.
- Expansion ratio one above the configured ratio.
- A deflated payload whose local and central expanded sizes were both falsified to one byte, when streamed output exceeded the configured single-entry cap.

The configured values come from TUpdaterConfig; defaults are documented in VAU-T04-zip-extraction-security.md. Arithmetic uses unsigned bounded checks before accumulation. Central-directory parsing is now preceded by a preflight that limits the archive to its configured compressed byte cap, caps the EOCD scan at 65,557 bytes, caps the central directory at 16 MiB, rejects entry counts above the configured maximum (default 4,096), and bounds each raw name to 1,024 bytes.

Exact lower/upper boundaries were tested for a small archive and its entry count, byte totals, path, and ratio. The test suite did not allocate near-default maximum payloads, stress CPU limits at scale, or verify available disk-space exhaustion behavior. No claim is made about a hard CPU-time bound for the RTL decompressor.

## Reparse points and TOCTOU

ZipExtractionRejectsReparsePointAncestorBeforeWrites created a disposable junction from the destination parent to an external fixture directory. Extraction failed before creating the payload directory through the junction; an outside sentinel remained byte-for-byte unchanged. The test passed on Win32.

The production implementation uses path-based attribute checks around directory creation and CreateFile(CREATE_NEW, FILE_FLAG_OPEN_REPARSE_POINT) for regular files. This prevents an already-present reparse point in the checked parent chain and avoids following an existing final file reparse point. It does not provide complete handle-relative, race-free traversal. A same-identity actor able to change staging directories between checks and file creation may still race parent-path validation. Replacement-after-preflight and replacement-during-extraction races were not deterministically injected. Symlink, nested destination, and reparse-point leaf fixtures were not separately added in this phase.

## Cancellation and concurrency

The extractor checks the cancellation flag between entries and during each output-copy iteration, with a 64 KiB copy buffer. This code path was inspected, but cancellation before extraction, during a large decompression stream, between entries, and destruction during extraction were not executed by a deterministic DUnitX test. Because decompression is supplied by System.Zip/System.ZLib, cancellation cannot interrupt an individual blocking decompressor read; it is observed when that read returns to the copy loop.

Separate operation-owned staging contexts are used by the existing engine. VAU-T03 staging allocation concurrency tests remain in the full DUnitX suite, but two simultaneous ZIP extractions and failure isolation between concurrent extractions were not directly tested here.

## Engine integration

The existing SignedZipDownloadIsValidatedBeforeExtractionAndUnsafeZipIsRejected integration test was included in both full DUnitX runs. It uses a local signing key and loopback server, authenticates metadata, downloads a checksummed ZIP only after explicit authorization, extracts a safe package, then downloads a signed/hash-valid traversal archive and verifies rejection and staging cleanup. Installation is not executed. The test uses loopback request counters; hostile extraction does not trigger a further package download.

The new malformed ZIP tests call the actual engine extraction method through a test-only seam. They do not individually drive every malformed fixture through signed manifest and network download.

## Regression verification

RAD Studio 12 Athens compiler 36.0 was used. The explicit DELPHIXE_UP and test defines are required by the current project setup.

| Command | Outcome |
|---|---|
| MSBuild VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /p:DCC_Define=DELPHIXE_UP /v:minimal | PASS, exit 0 |
| MSBuild VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /p:DCC_Define=DELPHIXE_UP /v:minimal | PASS, exit 0 |
| MSBuild VittixAutoUpdaterDesign.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /p:DCC_Define=DELPHIXE_UP /v:minimal | PASS, exit 0 |
| MSBuild TestCompilation.dproj Win32 with DELPHIXE_UP;VITTIX_TEST_LOOPBACK;VITTIX_TEST_REGISTRY;VITTIX_TEST_STAGING | PASS, exit 0 |
| Win32 focused ZIP tests (malformed, limits, junction) | 3 passed, 0 failed/errored |
| Win32 full DUnitX suite | 60 found; 59 passed, 0 failed, 1 errored |
| Win32 isolated VclComponentSupportsDataModuleOwnershipAndRepeatedChecks | 1 found; 0 passed, 1 errored |
| MSBuild TestCompilation.dproj Win64 with DELPHIXE_UP;VITTIX_TEST_LOOPBACK;VITTIX_TEST_REGISTRY;VITTIX_TEST_STAGING | PASS, exit 0 |
| Win64 full DUnitX suite | 60 passed, 0 failed/errored |
| rtk pytest -q tests/test_generate_manifest_signing.py | 4 passed |
| rtk git diff --check | PASS, exit 0 |

For both MSBuild test commands, semicolons in the define list were URL-escaped as %3B in the actual PowerShell command.

### VCL timeout investigation

The Win32 full suite and an isolated rerun both reproduced the timeout. The failing state was manifest=1, states=2, updating=True, engine-state=0. The second check is requested immediately after the UI callback clears IsUpdating, while the engine's synchronized completion closure is still active. CheckForUpdate refuses to start or wait on its own still-running worker in this window, so the UI remains marked updating although the engine is idle. This is a confirmed lifecycle race outside ZIP extraction; it is not counted as a ZIP failure and remains an acceptance blocker for the requested regression gate.

## Exact commands used

All commands below ran from the repository root in PowerShell after setting BDS to C:\Program Files (x86)\Embarcadero\Studio\23.0 and using MSBuild at C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe.

- Runtime Win32: VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /p:DCC_Define=DELPHIXE_UP /v:minimal
- Runtime Win64: VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /p:DCC_Define=DELPHIXE_UP /v:minimal
- Design-time Win32: VittixAutoUpdaterDesign.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /p:DCC_Define=DELPHIXE_UP /v:minimal
- DUnitX Win32 build: TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /p:DCC_Define=DELPHIXE_UP%3BVITTIX_TEST_LOOPBACK%3BVITTIX_TEST_REGISTRY%3BVITTIX_TEST_STAGING /v:minimal
- DUnitX Win32: $env:TEMP\VittixAutoUpdaterTests\Win32\Debug\TestCompilation.exe --exitbehavior:Continue --consolemode:Quiet
- DUnitX isolated lifecycle: same Win32 executable with --run:Test.VittixAutoUpdater.Integration.TVittixAutoUpdaterIntegrationTests.VclComponentSupportsDataModuleOwnershipAndRepeatedChecks --exitbehavior:Continue --consolemode:Verbose
- DUnitX Win64 build: TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /p:DCC_Define=DELPHIXE_UP%3BVITTIX_TEST_LOOPBACK%3BVITTIX_TEST_REGISTRY%3BVITTIX_TEST_STAGING /v:minimal
- DUnitX Win64: $env:TEMP\VittixAutoUpdaterTests\Win64\Debug\TestCompilation.exe --exitbehavior:Continue --consolemode:Quiet
- Manifest tests: rtk pytest -q tests/test_generate_manifest_signing.py
- Whitespace validation: rtk git diff --check

The integration test output recorded counts and the timeout message shown above. All archive fixtures were generated locally; no production endpoint, installer, registry key, or installed application was used.

## Remaining limitations

- Win32 VCL repeated-check lifecycle race is confirmed and unresolved.
- ZIP64 is intentionally unsupported; no positive ZIP64 extraction is claimed.
- Replacement races in extraction ancestors are not fully mitigated or dynamically tested.
- Cancellation and concurrent extraction behavior remain source-inspected, not integration-verified.
- Cross-user ACL behavior remains inherited from VAU-T03 and was not retested.
- Full installer transaction and rollback remain outside VAU-T04.

## Verdict

**PARTIAL.** Malformed archive rejection, configured limits, one junction redirection case, signed engine extraction integration, and both architecture builds have evidence. Win32 regression has a reproducible VCL timeout, and cancellation, concurrent extraction, and replacement-race scenarios remain unverified.

