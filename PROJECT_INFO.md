# VittixAutoUpdater

VittixAutoUpdater is an MIT-licensed VCL component and update engine for Delphi
applications on Windows. The compiler baseline is Delphi 12 Athens or later.
Delphi 12 Athens is the oldest verified compiler.

- `VittixAutoUpdaterRuntime.dpk` provides the update engine, networking,
  staging, visual component, and settings dialog for Win32 and Win64.
- `VittixAutoUpdaterDesign.dpk` registers the component and property editors in
  the Delphi 12 Win32 IDE. It depends on the runtime package.

## Repository layout

| Path | Contents |
| --- | --- |
| Repository root | Package projects, Delphi units, DUnitX project and fixtures, package build script, Python manifest generator, and signed sample manifest |
| `demo/` | VCL demo application and settings |
| `ManifestGenerator/` | Delphi GUI for preparing and signing manifests offline |
| `tests/` | Python signing tests, shared signing vector, and cross-process staging test worker |
| `tools/` | Release ZIP script |
| `docs/security/` | Current security design and verification notes |
| `docs/audit/` | October 2026 audit records |
| `docs/release/` | Release acceptance results |

See the [package installation guide](PACKAGE_INSTALLATION.md) to build and
install the packages and the [quick start](QUICK_START.md) to configure the
component in a VCL application. See [release status](docs/RELEASE_STATUS.md)
for the audit follow-up and build verification steps.
