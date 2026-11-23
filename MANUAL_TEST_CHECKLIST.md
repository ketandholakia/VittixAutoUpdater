# VittixAutoUpdater manual update checklist

Use a disposable demo install, a test HTTPS update endpoint, and a backup of the
application directory. Loopback HTTP requires a test build with the loopback
exception explicitly enabled.

## Shutdown behavior

1. **Close during manifest check**
   - Point the demo at a test endpoint that delays its manifest response.
   - Start Check for Updates, then close the form while the request is pending.
   - Expected: the updater requests cancellation, waits for the check worker to
     unwind, and exits without an access violation or a queued callback touching
     destroyed controls. A blocked server may take up to the configured timeout
     to release the worker.

2. **Close during package download**
   - Start a slow package download, then close the form.
   - Expected: cancellation is sent, the worker is joined before the engine and
     controls are destroyed, and any partial download is deleted. No background
     progress callback should access the closed form.

3. **Close immediately after Install**
   - Install a valid package into a writable disposable application directory;
     close the form as soon as the helper is launched.
   - Expected: the app exits through `Application.Terminate` (or the documented
     fallback), the helper waits for the executable lock to clear, copies the
     package, starts the updated app, and removes its private extraction folder.
   - Repeat from a non-writable directory. Expected: install is refused with
     “Install location not writable; a signed elevated helper is required”; no
     UAC prompt or elevated batch process is launched.

## Consecutive updates

1. Install signed version A into a writable disposable directory. Include a
   non-ASCII character in the path and add a local `config/settings.ini` value.
   Configure `PreserveFiles` to include the settings file.
2. Publish a signed manifest and ZIP for B. Include the executable, a changed
   secondary file, and a different settings file. Update in place.
3. Verify B starts, the secondary file changed, the local settings survived,
   and `App.exe.old` contains A.
4. Publish a signed manifest and ZIP for C. Update from the same install
   directory without deleting `App.exe.old`.
5. Verify C starts, the new secondary file matches its payload hash, the local
   settings survived, and `App.exe.old` now contains B.

## Forced copy failure

1. Start from a fresh B test installation. Record hashes of its executable
   and installed files. Prepare a signed C package that replaces at least two
   files and adds one new file.
2. Lock a later file in the helper's copy order from a separate PowerShell
   process. Allow other processes to read it so backup can complete, but
   deny writes while the copy runs.

   ```powershell
   $locked = [IO.File]::Open('C:\test\App\locked.dll', 'Open', 'Read', 'Read')
   try { Read-Host 'Press Enter after the helper attempts the update' }
   finally { $locked.Dispose() }
   ```

3. Install C. Hold the lock until the helper has attempted the copy. Verify
   an earlier file was eligible for copying and the old application restarts.
4. Compare all installed file hashes against the B snapshot. Confirm the new
   file from C is absent, preserved settings match B, and the failed
   operation's staging backup is available. If B does not restart or any
   installed hash differs, record the helper exit and retained staging path.


## Clean-VM release checklist

- Install the signed release on a clean Windows VM and run it from a standard
  user account.
- Verify normal update, rollback policy, signature rejection, stale-manifest
  rejection, and HTTPS redirect/downgrade behavior against the release endpoint.
- Verify download size/checksum handling and retry behavior with the staging
  service; exercise an interrupted transfer and a matching-ETag Range resume.
- Exercise the three shutdown cases above and check the updated executable,
  helper exit, and temporary-folder cleanup.
- Verify Authenticode pins against the expected SHA-256 certificate thumbprint.
- Try the update from `C:\Program Files` as a standard user. Verify the
  updater reports "Install location not writable" and stays responsive.
- Run the app directly from an SMB UNC path and verify Install reports that
  UNC paths are unsupported. Repeat using a real SMB mapped drive such as
  `Z:` and record the result separately. If installation succeeds, check the
  installed and backup hashes and verify relaunch.
- Download the release application over HTTPS and use the release publisher
  certificate on the application and all payload EXEs and DLLs. Set
  `VerifyAuthenticode=True` and configure the publisher certificate's SHA-256
  thumbprint in `PinnedPublisherThumbprints`. Run with SmartScreen and the
  customer's antivirus policy enabled and record any prompt or block when
  the hidden `apply.cmd` runs or the replacement launches.
- Repeat the consecutive-update sequence above with the final release builds
  and signed manifests on the HTTPS test endpoint.
- Confirm the offline signing key and its passphrase have recoverable backups
  per the [key-management guide](docs/security/signing-key-management.md).
  Verify no private signing key is present on the test VM.
- Record the executable hash, manifest signature, Windows version, and GUI
  acceptance results before release.
