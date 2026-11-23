# 01 — Repository architecture

## Scope and evidence

Reviewed the current worktree on 2026-10-27. It contains numerous pre-existing modified and untracked files (including Engine, Network, Types, demo, README, and tests); these were treated as the audit subject. No source files were edited. Line references below refer to the audited worktree.

## Structure and inventory

| Area | Files | Role |
|---|---|---|
| Core/runtime | `VittixAutoUpdater.Types.pas`, `VittixAutoUpdater.Network.pas`, `VittixAutoUpdater.Engine.pas` | Versions, manifest/config/event records; HTTP/JSON/signature/checksum/download; state machine, extraction, Windows apply |
| VCL UI | `VittixAutoUpdater.VisualComponent.pas`, `VittixAutoUpdater.Settings.pas/.dfm` | Palette component, progress UI, settings form |
| Design-time | `VittixAutoUpdater.ComponentReg.pas`, `VittixAutoUpdater.PropertyEditors.pas` | Component/property registration and editor |
| Packages/projects | Runtime/design `.dpk/.dproj`, `vittixAutoupdater.groupproj` | Delphi package builds; runtime is VCL and Windows-oriented |
| Example/tools | `demo/` VCL demo, `ManifestGenerator/`, `generate_manifest.py`, `deploy-update.sh`, `BuildPackages.bat` | Demo, manifest/deployment helpers, package build |
| Tests | `Test.VittixAutoUpdater.pas`, `TestCompilation.dpr/.dproj`, manual checklist | DUnitX fixture with loopback HTTP test server behind define; manual GUI checklist |
| Docs/config | README, QUICK_START, VISUAL_COMPONENT_GUIDE, design/install docs, `manifest.json`, `LICENSE`, `PROJECT_INFO.md` | User/developer guidance and sample metadata |

No CI workflow, automated build pipeline definition, or separate integration-test project was found. No FMX UI integration exists. VCL is explicit in package `requires` and project `FrameworkType`.

## Dependency and call map

```text
VCL form / TVittixAutoUpdaterUI
  -> TUpdateEngine (state, policy, orchestration)
      -> TUpdateNetworkManager (System.Net.HttpClient / URLClient, JSON, hash)
      -> System.Zip, Windows CryptoAPI/CNG, ShellExecute, batch helper
Design package -> ComponentReg + PropertyEditors -> runtime UI
Demo -> visual component; ManifestGenerator -> standalone JSON/signing helper
Tests -> DUnitX + Indy loopback test server (conditional define)
```

Runtime package requires RTL, VCL, `inet`, `vclimg`, `vclx`, `VclSmp`; design package additionally requires `designide`. Network implementation imports `System.Net.HttpClient`, `System.Net.URLClient`, `System.Hash`, `System.JSON`, `System.NetEncoding`, `System.DateUtils`, `System.IOUtils`; Engine uses ZIP, Windows APIs, certificate APIs, and shell launching. The test fixture uses DUnitX and Indy (`IdHTTPServer`). No dependency manager/lockfile exists.

## Public API surface

`TAppVersion` is a four-`Word` record and supports numeric operators and `TryParse` (`Types.pas:30-60, 191-276`). `TUpdateManifest`, `TUpdaterConfig`, severity/state enums, and events are in `Types.pas:62-153`. `TUpdateEngine` exposes config, state, version, check/download/apply/cancel/reset, and events (`Engine.pas:36-106`). `TUpdateNetworkManager` exposes manifest fetch, download, cancel, transport knobs, signature settings, and helpers (`Network.pas:11-125`). `TVittixAutoUpdaterUI` is the registered visual entry point; its public methods include check, download, install, cancel (`VisualComponent.pas:126-212`).

## Platform/compiler conclusions

The package projects advertise Win32, Win64, and Win64x and VCL; implementation directly uses Windows-only APIs for critical update operations (`Engine.pas:811+`, `Network.pas:186+`). Actual supported targets are therefore Windows desktop (Win32/Win64 subject to compiler support); Win64x is advertised in project metadata but has not been validated. FPC compatibility claims are not substantiated: network implementation unconditionally imports Delphi `System.Net.*` units, and package/project files are Delphi VCL packages. Project `ProjectVersion` values and `Delphi.Personality` indicate a modern Delphi project format, while `PACKAGE_INSTALLATION.md` claims XE7 onward; source uses anonymous methods, generic collections, `THTTPClient`, and conditional compatibility code but no compiler matrix/build evidence. RAD Studio 12 compatibility is unverified; explicit RAD Studio 12 build evidence is absent.

## Structural weaknesses

* Runtime package includes a visual VCL component and settings form, coupling headless update logic to VCL distribution.
* Duplicate/legacy component APIs create ambiguity; `Component.pas` is outside package composition.
* Several docs describe features (FPC, semantic versions, rollback) more broadly than current implementation demonstrates.
* Project metadata advertises platforms and historical version compatibility without reproducible CI evidence.
* The source tree has no separation into source/tests/tools and includes checked-in `.res` artifacts; current worktree also has extensive uncommitted modifications.
* HTTPS and package checksum defaults are enabled, but authenticated manifest metadata and Authenticode are opt-in by `TUpdaterConfig.Default` (`Types.pas:367-379`), an unsafe production default for an updater.
