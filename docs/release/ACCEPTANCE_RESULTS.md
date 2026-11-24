# 1.0.0-rc1 acceptance results

Run the [manual checklist](../../MANUAL_TEST_CHECKLIST.md) on a clean Windows VM
using the Delphi 12 Athens release builds. The registry rows track the
[VAU-T01 owner acceptance](../security/VAU-T01-owner-acceptance.md) scenarios,
including separate process execution for persistence. Record the date, tester,
and a link to evidence for each completed run. Store logs with release evidence.

| Acceptance item | Status | Date | Tester | Evidence link |
| --- | --- | --- | --- | --- |
| Install the signed release on a clean Windows VM as a standard user | NOT RUN | — | — | — |
| Normal update, rollback policy, signature rejection, stale-manifest rejection, and HTTPS redirect and downgrade handling | NOT RUN | — | — | — |
| Download size, checksum, retries, interrupted transfer, and matching-ETag Range resume | NOT RUN | — | — | — |
| Close during manifest check and verify worker shutdown | NOT RUN | — | — | — |
| Close during package download and verify partial download cleanup | NOT RUN | — | — | — |
| Close immediately after Install and verify helper exit, replacement, restart, and staging cleanup | NOT RUN | — | — | — |
| Repeat Install from a non-writable directory and verify refusal and absence of elevation | NOT RUN | — | — | — |
| Consecutive signed updates A → B → C with final builds, non-ASCII install path, preserved settings, and rotating executable backup | NOT RUN | — | — | — |
| Forced mid-copy failure and verification of restored hashes, settings, restart, and retained backup | NOT RUN | — | — | — |
| Program Files refusal as a standard user and responsive GUI | NOT RUN | — | — | — |
| SMB UNC refusal, responsive GUI, disabled Download, and zero network requests | NOT RUN | — | — | — |
| SMB mapped-drive refusal, responsive GUI, disabled Download, and zero network requests | NOT RUN | — | — | — |
| Authenticode publisher pin using the expected certificate SHA-256 thumbprint | NOT RUN | — | — | — |
| SmartScreen and customer antivirus with HTTPS download, signed payload, and Authenticode pin enabled | NOT RUN | — | — | — |
| Recoverable offline signing key and passphrase backups, with no private signing key on the test VM | NOT RUN | — | — | — |
| Record executable hash, manifest signature, Windows version, and GUI evidence | NOT RUN | — | — | — |
| Attach Win32 and Win64 DUnitX logs and the Python signing-test log to the release | NOT RUN | — | — | — |
| Registry rollback floor across fresh processes in a disposable HKCU test scope. Accept, persist, recreate, reload, reject older, and accept newer | NOT RUN | — | — | — |
| Corrupted rollback floor fails closed in a disposable HKCU test scope | NOT RUN | — | — | — |
| Registry access denial fails closed in a disposable HKCU test scope | NOT RUN | — | — | — |
