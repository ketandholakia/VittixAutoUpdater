# 05 — Windows installation reliability

## Current method

`TUpdateEngine.ApplyUpdateWindows` (`VittixAutoUpdater.Engine.pas:812-921`) requires the new archive to contain a same-named EXE, optionally verifies signatures, derives the install directory from `ParamStr(0)`, writes a batch file in the temp directory, probes app-dir writability, then launches the batch hidden and non-elevated. The batch retries renaming the running EXE up to 15 seconds, copies the extracted tree, launches the new EXE, and deletes itself. It renames only the EXE to `.old`; on a copy error it restores that EXE and launches it.

## Scenario assessment

| Scenario | Source-based outcome |
|---|---|
| Program Files, standard user | Fails closed at write probe; no signed elevation helper exists. |
| User-writable install | Can launch helper; correctness depends on write access and package layout. |
| App already elevated | Helper inherits caller token; temp/helper trust boundary becomes privileged. |
| Multiple app instances | No interprocess update mutex or coordination evident; competing helpers can race on same EXE and temp batch name. |
| Multiple users | Shared install may be modified by one privileged user; no user/session coordination or per-user staging policy. |
| Antivirus/locked files | EXE rename retries; other locked files can fail copy. No reboot scheduling. |
| Reboot-required replacement | No `MoveFileEx(..., MOVEFILE_DELAY_UNTIL_REBOOT)` path observed. |
| User cancellation | Available during download/check; apply helper phase not cancellable. |
| Power loss/disk full | In-place file copy can leave mixed files; EXE-only restoration is not a complete rollback. |
| Restart crash | Parent cannot observe helper completion or new process health; it marks complete once ShellExecute succeeds. |

## Reliability conclusion

Current method is a best-effort updater for writable, simple, single-EXE applications. It is unsuitable as a reliable machine-wide commercial installer for multi-file applications until staged deployment and complete recovery are implemented. A separate signed helper/installer is justified by concrete gaps: least-privilege separation, safe privileged operations, transaction/recovery journal, and observable completion. Do not elevate the current batch file.

Recommended direction: download and verify first; extract to unique ACL-restricted staging; have a signed helper validate caller, package, target, and manifest; copy into a versioned sibling directory; atomically switch a pointer/launcher or rename directories on same volume; retain last-good version; report completion and restart health; recover journal at next launch. Where directory switching is not viable, back up every replaced file and journal each operation. Validate on disposable Windows VMs with power/copy failure injection.
