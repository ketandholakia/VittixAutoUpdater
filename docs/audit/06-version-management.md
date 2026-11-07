# 06 — Version management

`TAppVersion.TryParse` (`VittixAutoUpdater.Types.pas:191-241`) accepts one to four dot-separated nonnegative decimal integers, each within `Word` range. Missing fields are zero-filled. Comparison is numeric lexicographic across major/minor/patch/build. It rejects trailing dot, empty string, more than four parts, signs/letters, and overflow. It does not implement SemVer; prerelease labels and build metadata are rejected.

| Installed | Available | Actual behavior |
|---|---|---|
| 1.0.0 | 1.0.1 | Update (normalized to 1.0.0.0 vs 1.0.1.0) |
| 1.2.0 | 1.10.0 | Update numerically |
| 2.0.0 | 1.9.9 | Reject by default; config can opt into downgrade |
| 1.0.0 | 1.0.0 | No update |
| 1.0.0-beta | 1.0.0 | Installed version string invalid; no prerelease policy |

Minimum-version enforcement and severity exist in manifest model/parser and engine logic (`Network.pas:777-855`, `Engine.pas:468-625`). There are no explicit stable/beta channels, skipped versions, compatibility platform/architecture constraints, or persisted anti-rollback version floor. `AllowDowngrade` is a boolean override. Numeric four-part values map naturally to Windows file versions but are independent from SemVer.

Test fixture includes version parse/comparison and downgrade tests (`Test.VittixAutoUpdater.pas:299-326,445+`); execution was not attempted because Delphi toolchain availability is unknown. More boundary tests should cover Word maximum, empty interior parts (`1..2`), whitespace, leading zeros, 1-4 component equivalence, and policy around stale signed manifests.
