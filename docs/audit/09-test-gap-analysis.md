# 09 — Test gap analysis

## Existing evidence

`Test.VittixAutoUpdater.pas` is a DUnitX fixture with version, manifest, signature, path traversal, downgrade, state, security warning, URL/redirect, retry/resume, size and cancellation-focused cases. A local Indy HTTP server is compiled only with `VITTIX_TEST_LOOPBACK`; `TestCompilation.dpr/.dproj` provides a runner. `MANUAL_TEST_CHECKLIST.md` explicitly says GUI checks were not run. No test result or CI execution evidence was present. Tests were not run: RAD Studio/DUnitX compiler environment was not confirmed, and no executable/test binaries were run.

## Reproducible matrix

Run unit tests in a disposable test build; integration tests use loopback mock server and isolated temporary root. Windows install tests require disposable VM snapshots and copied app directories. Never target the developer install.

| Case | Level | Expected |
|---|---|---|
| Valid update / no update | Unit + mock integration | Correct callback/state and version decision |
| Invalid JSON / missing fields | Unit | Reject with stable error; no stale manifest reused |
| Tampered manifest / invalid signature | Unit + mock | Reject before download/apply |
| Tampered installer / invalid Authenticode pin | Unit + integration | Reject and clean/preserve according to policy |
| Expired, wrong-host, untrusted TLS | Windows VM integration | TLS failure; no HTTP fallback |
| Network disconnect / timeout / truncated body | Mock integration | Bounded retry; no `.part` promoted as complete |
| Cancel download / check | Mock + GUI | Prompt cancellation, no callback into destroyed form |
| Low disk space | Unit/integration | Fail before large write |
| Locked destination / unauthorized Program Files | Windows VM | Fail closed or recover; no privilege prompt/script |
| Multiple instances/users/concurrent attempts | Windows VM | One serialized install; isolated temp state |
| Invalid version / downgrade / stale replay | Unit | Reject according to explicit policy |
| Failed helper copy / process restart | Disposable VM | Old app remains runnable or journal recovers |
| Power interruption mid-apply | VM snapshot | Recovery to last-good version |
| Successful recovery | VM | Restart health acknowledged and staging cleaned |

Separate tests by unit helpers, transport integration, install VM scenarios, and owner-run GUI acceptance. Add scripted fault injection for every staged/copy boundary and capture logs, exit codes, hashes, and resulting directory tree. No destructive scenarios against a real installation.
