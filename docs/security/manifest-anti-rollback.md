# Manifest freshness and anti-rollback

## Enforced policy

In signed mode, `issued_at` is required and parsed as an ISO-8601 timestamp. Invalid or future-dated timestamps are rejected. `MaxManifestAgeDays` defaults to 30 and rejects metadata older than that window. Version comparison is numeric with one to four components. Signed metadata below the installed version is rejected, even if `AllowDowngrade=True`; that override applies only when the explicit insecure unsigned mode has been selected.

After successful signature, schema, and freshness validation, the engine stores a rollback floor in `HKCU\Software\VittixAutoUpdater\TrustState\<hash>\Floor`. The subkey hash is derived from the normalized full executable path, not ordinary updater configuration. The single stored value contains the highest accepted version, signed issuance time, and checksum. Lower versions and older timestamps are rejected; an equal version/time with a different checksum is rejected. Registry read/write or malformed-state errors fail closed. Failed signature, parse, freshness, network, or cancellation paths do not write trust state. The floor is persisted before the UI receives an available/no-update result and before package download.

Moving/renaming the installed executable creates a different path-derived scope. A deliberate reinstall or path migration must therefore be handled as a trusted application deployment and may establish a new floor. Ordinary changes to `TUpdaterConfig` do not reset the registry value.

## Limits and threat model

This provides persistence against replay by a remote/network attacker after a valid manifest has been accepted, and ordinary configuration edits do not clear the floor. It is not tamper-proof against the same Windows user or an administrator: they can edit/delete HKCU state or replace the application. A first-run client also has no previously persisted floor. Windows wall-clock time is not a trusted-time source; a user/admin can move it. The freshness window rejects future timestamps against local time, but a manipulated clock can cause denial of service or weaken first-run age checks. Therefore this implementation does **not** claim full replay resistance against local attackers or compromised time.

For stronger guarantees, applications need an OS-protected per-machine monotonic state mechanism and a trusted-time strategy appropriate to their deployment, plus recovery/reinstallation policy. Those controls are outside VAU-T01's completed implementation evidence and require separate design/security review. The updater does not silently clear malformed or inaccessible state to recover.
