# VittixAutoUpdater manual shutdown checklist

These are owner-run GUI checks; they were **not run as part of this code change**.
Use a disposable demo install, a test HTTPS update endpoint, and a backup of the
application directory. The local HTTP exception exists only in the DUnitX build.

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

## Clean-VM release checklist

- Install the signed release on a clean, non-admin Windows VM.
- Verify normal update, rollback policy, signature rejection, stale-manifest
  rejection, and HTTPS redirect/downgrade behavior against the release endpoint.
- Verify download size/checksum handling and retry behavior with the staging
  service; exercise an interrupted transfer and a matching-ETag Range resume.
- Exercise the three shutdown cases above and check the updated executable,
  helper exit, and temporary-folder cleanup.
- Verify Authenticode pins against the expected SHA-256 certificate thumbprint.
- Confirm a Program Files install fails closed until the signed elevated helper
  is available; verify no private signing key is present on the VM.
- Record the executable hash, manifest signature, Windows version, and GUI
  acceptance results before release.
