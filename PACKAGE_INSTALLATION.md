# VittixAutoUpdater Package Installation Guide

This guide explains how to install and use the VittixAutoUpdater design-time and runtime packages in Delphi.

## Overview

VittixAutoUpdater provides two packages:

1. **VittixAutoUpdaterRuntime.dpk** - Contains the runtime components
2. **VittixAutoUpdaterDesign.dpk** - Contains design-time editors and component registration

## Prerequisites

- Delphi XE7 or later (recommended: Delphi 10.4 Sydney or newer)
- Windows 7 or later
- Administrator rights for package installation

## Installation Steps

### Method 1: Using Delphi IDE (Recommended)

#### Step 1: Install Runtime Package

1. **Open Delphi IDE**
2. **File → Open Project...** and select `VittixAutoUpdaterRuntime.dpk`
3. **Right-click** on the package in Project Manager
4. **Select "Install"** or press **Ctrl+F9** to compile and install
5. **Confirm** when prompted about installing the package

#### Step 2: Install Design Package

1. **File → Open Project...** and select `VittixAutoUpdaterDesign.dpk`
2. **Right-click** on the package in Project Manager
3. **Select "Install"** or press **Ctrl+F9** to compile and install
4. **Confirm** when prompted about installing the package

#### Step 3: Verify Installation

1. **Open** the **Tool Palette** (View → Tool Palette)
2. **Look for** the **"VittixAutoUpdater"** tab
3. **Verify** that `TVittixAutoUpdaterUI` component is available

### Method 2: Command Line Installation

```batch
# Navigate to the VittixAutoUpdater directory
cd "C:\Path\To\VittixAutoUpdater"

# Compile runtime package
dcc32 VittixAutoUpdaterRuntime.dpk

# Compile design package  
dcc32 VittixAutoUpdaterDesign.dpk

# Install packages (requires IDE to be closed)
# Use Component → Install Packages in IDE afterwards
```

### Method 3: Manual BPL Installation

If automatic installation fails:

1. **Compile both packages** using Build → Compile
2. **Locate the generated BPL files** (usually in `$(BDSBIN)` directory)
3. **Tools → Options → Environment Options → Library**
4. **Add the BPL directory** to Library Path
5. **Component → Install Packages**
6. **Add** both BPL files manually

## Verification

### Design-Time Features

After successful installation, you should have:

1. **Component Palette**
   - New "VittixAutoUpdater" tab
   - `TVittixAutoUpdaterUI` component available

2. **Property Editors**
   - Config property with custom dialog editor
   - ManifestUrls property with string list editor

3. **Object Inspector**
   - All component properties visible
   - Custom property editors functional

### Test Installation

Create a simple test:

```pascal
// 1. Create new VCL Forms Application
// 2. Drop TVittixAutoUpdaterUI on the form
// 3. Set properties in Object Inspector:

procedure TForm1.FormCreate(Sender: TObject);
var
  Config: TUpdaterConfig;
begin
  Config := TUpdaterConfig.Default;
  Config.AppName := 'Test App';
  SetLength(Config.ManifestUrls, 1);
  Config.ManifestUrls[0] := 'https://example.com/manifest.json';
  
  VittixAutoUpdaterUI1.Config := Config;
end;
```

## Troubleshooting

### Package Won't Install

**Error: "Cannot load package"**
- Ensure all required units are in the library path
- Check that all dependencies are installed (RTL, VCL, etc.)
- Try installing runtime package first

**Error: "Unit not found"**
- Verify all source files are in the same directory
- Check library path includes the source directory
- Ensure no circular unit references

### Component Not Visible

**Component doesn't appear in palette**
- Restart Delphi IDE
- Check Component → Install Packages for package status
- Verify design package is loaded and enabled

**Property editors not working**
- Ensure design package is installed after runtime package
- Check for any compilation errors in design units
- Restart IDE after installation

### Build Errors

**Cannot find DCU files**
- Clean all projects (Build → Clean)
- Rebuild packages in correct order (Runtime → Design)
- Check output directory settings

**Linker errors**
- Ensure no duplicate units in different packages
- Check library path for conflicting units
- Remove old BPL/DCU files

## Advanced Configuration

### Custom Library Paths

Add these paths to your library configuration:

```
# Library Path
$(VittixAutoUpdater)\Source
$(VittixAutoUpdater)

# Browse Path  
$(VittixAutoUpdater)\Source
$(VittixAutoUpdater)
```

### Package-Specific Settings

For project-specific installation:

```pascal
// Add to your project's .dproj file:
<DCC_UnitSearchPath>$(VittixAutoUpdater);$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
```

### IDE Templates

Create component templates:

1. **Component → Create Component Template**
2. **Select** configured VittixAutoUpdaterUI
3. **Save** as template for reuse

## Distribution

### With Your Application

Include these files for redistribution:

```
# Required Runtime Files
VittixAutoUpdaterRuntime.bpl    (if using runtime packages)
VittixAutoUpdater.Types.dcu     (if static linking)
VittixAutoUpdater.Engine.dcu
VittixAutoUpdater.Network.dcu
VittixAutoUpdater.VisualComponent.dcu
```

### Source Code Distribution

For source code distribution:

```
VittixAutoUpdater\
├── VittixAutoUpdater.Types.pas
├── VittixAutoUpdater.Engine.pas  
├── VittixAutoUpdater.Network.pas
├── VittixAutoUpdater.VisualComponent.pas
├── VittixAutoUpdater.Settings.pas
├── VittixAutoUpdater.Settings.dfm
├── VittixAutoUpdaterRuntime.dpk
├── VittixAutoUpdaterDesign.dpk
└── Documentation\
```

## Uninstallation

### Remove Packages

1. **Component → Install Packages**
2. **Select** VittixAutoUpdaterDesign
3. **Click Remove**
4. **Select** VittixAutoUpdaterRuntime  
5. **Click Remove**
6. **Restart** Delphi IDE

### Clean Files

Remove these files if present:

```batch
# From $(BDSBIN) directory
del VittixAutoUpdaterRuntime.bpl
del VittixAutoUpdaterDesign.bpl

# From project directories
del *.dcu
del *.bpl
del *.dcp
```

## Version Compatibility

### Supported Delphi Versions

| Version | Status | Notes |
|---------|---------|-------|
| XE7     | ✅ Supported | Minimum version |
| XE8     | ✅ Supported | |
| 10.0 Seattle | ✅ Supported | |
| 10.1 Berlin | ✅ Supported | |
| 10.2 Tokyo | ✅ Supported | |
| 10.3 Rio | ✅ Supported | |
| 10.4 Sydney | ✅ Recommended | |
| 11.0 Alexandria | ✅ Recommended | |
| 12.0 Athens | ✅ Latest | |

### Platform Support

- ✅ **Win32** - Fully supported
- ✅ **Win64** - Fully supported  
- ❌ **macOS** - Not supported (Windows-specific features)
- ❌ **Linux** - Not supported (Windows-specific features)
- ❌ **Mobile** - Not supported (VCL components)

## Getting Help

### Documentation

- **VISUAL_COMPONENT_GUIDE.md** - Component usage guide
- **README.md** - General project documentation
- **Source code** - Inline documentation

### Common Issues

1. **"Component already exists"**
   - Uninstall old version first
   - Clear component cache

2. **"Cannot find unit"**
   - Check library paths
   - Verify file permissions

3. **"Package load error"**
   - Install in correct order (Runtime → Design)
   - Check dependencies

### Support

For additional support:
- Check GitHub issues
- Review documentation
- Contact developer

---

**Happy coding with VittixAutoUpdater! 🚀**