# 02 — Update lifecycle

## Actual sequence

```mermaid
sequenceDiagram
    participant UI as VCL component
    participant E as TUpdateEngine
    participant N as TUpdateNetworkManager
    participant S as Manifest/package server
    participant FS as Temp/application filesystem
    participant H as Hidden batch helper
    UI->>E: CheckForUpdate(callback)
    E->>N: FetchManifest(urls, app name)
    N->>S: HTTPS GET manifest (HEAD/GET redirects constrained)
    opt VerifyManifestSignature enabled
      N->>S: GET manifest.json.sig
      N->>N: ECDSA P-256 verify raw manifest bytes
    end
    N->>N: Parse JSON; validate issued_at age if signature enabled
    E->>E: compare 4-part numeric version and min version/severity
    E-->>UI: callback / update available or no update
    UI->>E: DownloadUpdate(manifest)
    E->>N: DownloadFile(URL, temp zip, checksum, file size)
    N->>S: HEAD then GET, retry; resume only under matching range metadata
    N->>FS: write .part file; cap size; verify final size/hash
    E->>E: usReady
    UI->>E: ApplyUpdate
    E->>FS: extract archive into private temp tree after entry path check
    E->>E: optional Authenticode/publisher pin checks
    E->>FS: create predictable temp batch file; verify app dir writable
    E->>H: ShellExecute hidden, non-elevated
    H->>FS: retry rename current EXE to .old; copy extracted files; relaunch EXE
    E-->>UI: usComplete; request application shutdown/restart
```

## Evidence and state details

Check and policy logic is in `Engine.pas:468-625`; download in `626-678`; extraction in `680-724`; apply and restart in `737-921`; cancellation in `924+`. The UI queues worker notifications (`VisualComponent.pas:1077-1160`); check/download/install workers are separate operations. Manifest parse and freshness rules are in `Network.pas:777-855`; fetch/signature at `656-702,858-961`; file transfer at `963+`.

Installed version may be supplied/configured or read from the running executable version resource; it is compared numerically as four unsigned 16-bit fields. Available update policy rejects equality and, unless explicitly allowed, lower versions. Critical/recommended/optional severity and min-version logic affect update decision/notifications, but there is no coherent channel/prerelease policy.

The manifest's checksum and size are passed into download. The checksum is an ordinary SHA-256 check unless authenticated metadata is enabled. Manifest signing verifies exact fetched bytes using detached `.sig` and an embedded configured public key. Signature policy defaults off. Authenticode verification defaults off and, when on, validates all extracted EXE/DLL files against configured thumbprints.

## Missing/unsafe transitions

* The batch process signals only that it was launched, not that copy/relaunch succeeded; parent marks complete immediately (`Engine.pas:914-917,769-777`).
* Only the main EXE is renamed to `.old`; other files are copied over in place. Rollback code restores the old EXE on copy error but does not restore DLLs/BPLs already overwritten (`Engine.pas:875-894`).
* Startup detection, installed version revalidation, transactional commit, restart health check, and durable recovery journal are absent.
* The helper has a fixed predictable name `update_<AppName>.bat` under general temp (`Engine.pas:847-853`), and is created before checking application directory writability (`902-915`).
* No elevation is attempted; Program Files installs fail closed based on write probe. This avoids a dangerous implicit elevation path but means machine-wide installs cannot self-update.
* A failed update can leave extracted files; some cleanup paths may remove or preserve them inconsistently. Cancellation is exposed only during check/download, not apply.
* Current running executable is renamed after lock release, which can work for that file in a writable directory. It does not guarantee safe replacement of locked DLLs or atomic replacement of the whole application.

No production installer was executed. Failure behavior is source-derived; helper timing and Windows locking outcomes need isolated Windows VM validation.
