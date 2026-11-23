# VittixAutoUpdater package installation

Use Delphi 12 Athens or later on Windows. Delphi 12 Athens is the oldest version verified to build the runtime and design-time packages.

- `VittixAutoUpdaterRuntime` contains the updater and VCL component. Build it for each platform your application targets.
- `VittixAutoUpdaterDesign` contains component registration and property editors. It requires the runtime package for the same IDE architecture.

## Build and install for the Win32 IDE

1. Open `vittixAutoupdater.groupproj` in Delphi. Build `VittixAutoUpdaterRuntime.dproj` first, then build `VittixAutoUpdaterDesign.dproj`.
2. In **Component > Install Packages**, add `VittixAutoUpdaterDesign.bpl` from `$(BDSCOMMONDIR)\Bpl`. Both BPLs must be available to the IDE. The design package loads the runtime package as a dependency.
3. Open the **VittixAutoUpdater** category in the Tool Palette and confirm `TVittixAutoUpdaterUI` is available.

You can build the same packages from a RAD Studio Command Prompt in the repository root.

```bat
BuildPackages.bat
BuildPackages.bat Win64
```

The first command builds the Win32 runtime and design-time packages. The second builds the Win64 runtime. The script uses the RAD Studio environment for the current user. Set `BDS` to your RAD Studio directory if Delphi is installed in a custom location.

## Output and distribution

| Target | BPL directory | DCP directory |
| --- | --- | --- |
| Win32 | `$(BDSCOMMONDIR)\Bpl` | `$(BDSCOMMONDIR)\Dcp` |
| Win64 | `$(BDSCOMMONDIR)\Bpl\Win64` | `$(BDSCOMMONDIR)\Dcp\Win64` |

If the IDE cannot load the design package, confirm the runtime BPL is in the same package directory and built with the same Delphi version. If the design build cannot find `VittixAutoUpdaterRuntime.dcp`, rebuild the runtime for the same platform and verify the DCP path in the design project's compiler options.

For applications built with runtime packages, deploy the matching `VittixAutoUpdaterRuntime.bpl` and its RAD Studio runtime dependencies. To remove the IDE component, remove `VittixAutoUpdaterDesign.bpl` in **Component > Install Packages**.

See [README.md](README.md) and [VISUAL_COMPONENT_GUIDE.md](VISUAL_COMPONENT_GUIDE.md) for setup and usage.
