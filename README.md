# VittixAutoUpdater

A production-ready, cross-platform application auto-updater component written from scratch in Delphi/Pascal.

## Features

✅ **Version Management**
- Semantic versioning (Major.Minor.Patch.Build)
- Extract version from executable resources
- Flexible version comparison operators

✅ **Network Operations**
- Multiple mirror/fallback URL support
- Download progress tracking
- Automatic retry with exponential backoff
- SHA256 checksum verification

✅ **Update Process**
- Check for updates via JSON/INI manifest
- Download update packages
- Extract and apply updates
- Automatic backup and rollback
- Safe file replacement on Windows

✅ **User Experience**
- Async update checking
- Progress callbacks
- State change notifications
- Cancellable operations

---

## Quick Start

### 1. Basic Usage

```pascal
uses
  VittixAutoUpdater.Types, VittixAutoUpdater.Engine;

var
  Config: TUpdaterConfig;
  Engine: TUpdateEngine;

begin
  // Configure
  Config := TUpdaterConfig.Default;
  Config.AppName := 'MyApp';
  SetLength(Config.ManifestUrls, 1);
  Config.ManifestUrls[0] := 'https://updates.myapp.com/manifest.json';
  
  // Create engine
  Engine := TUpdateEngine.Create(Config);
  try
    // Check for updates
    Engine.CheckForUpdate(procedure(Result: TUpdateCheckResult;
      const Manifest: TUpdateManifest; const ErrorMessage: string)
    begin
      if Result = ucrUpdateAvailable then
      begin
        ShowMessage('Update available: ' + Manifest.Version.ToString);
        // Download and apply update...
      end;
    end);
  finally
    Engine.Free;
  end;
end;
```

### 2. With Progress Tracking

```pascal
procedure TMainForm.CheckForUpdates;
begin
  FEngine := TUpdateEngine.Create(FConfig);
  
  // State changes
  FEngine.OnStateChange := procedure(Sender: TObject; 
    NewState: TUpdateState; const StatusMessage: string)
  begin
    StatusBar.Text := StatusMessage;
  end;
  
  // Download progress
  FEngine.OnDownloadProgress := procedure(Sender: TObject; 
    BytesReceived, TotalBytes: Int64; var Cancel: Boolean)
  begin
    ProgressBar.Max := TotalBytes;
    ProgressBar.Position := BytesReceived;
  end;
  
  // Check
  FEngine.CheckForUpdate(procedure(Result: TUpdateCheckResult;
    const Manifest: TUpdateManifest; const ErrorMessage: string)
  begin
    if Result = ucrUpdateAvailable then
      PromptUserToUpdate(Manifest);
  end);
end;

procedure TMainForm.PromptUserToUpdate(const Manifest: TUpdateManifest);
begin
  if MessageDlg(Format('Version %s is available. Download now?', 
    [Manifest.Version.ToString]), mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    // Download in thread
    TThread.CreateAnonymousThread(procedure
    begin
      if FEngine.DownloadUpdate(Manifest) then
      begin
        TThread.Synchronize(nil, procedure
        begin
          if MessageDlg('Update downloaded. Install now?', 
            mtConfirmation, [mbYes, mbNo], 0) = mrYes then
          begin
            FEngine.ApplyUpdate;
            // App will restart
          end;
        end);
      end;
    end).Start;
  end;
end;
```

---

## Manifest Format

Create a JSON file on your update server:

### manifest.json
```json
{
  "MyApp": {
    "version": "2.1.5.100",
    "download_url": "https://cdn.myapp.com/releases/MyApp_v2.1.5.zip",
    "release_notes": "Bug fixes and performance improvements",
    "file_size": 15728640,
    "checksum": "sha256:abc123def456...",
    "min_version": "2.0.0.0",
    "severity": "recommended"
  }
}
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `version` | ✅ Yes | Version string (e.g., "2.1.5.100") |
| `download_url` | ✅ Yes | Direct download link to ZIP file |
| `file_size` | ⚠️ Recommended | File size in bytes |
| `checksum` | ⚠️ Recommended | SHA256 hash for verification |
| `release_notes` | ❌ No | Update description |
| `min_version` | ❌ No | Minimum version that can update |
| `severity` | ❌ No | "optional", "recommended", or "critical" |

---

## Update Package Structure

Your update ZIP should contain the new executable and any updated files:

```
MyApp_v2.1.5.zip
├── MyApp.exe          (new version)
├── libs/
│   ├── library1.dll
│   └── library2.dll
└── config/
    └── settings.ini
```

**Important:** The updater will:
1. Extract all files from the ZIP
2. Backup the current executable as `MyApp.exe.old`
3. Replace all files
4. Restart the application

---

## Configuration Options

```pascal
type
  TUpdaterConfig = record
    AppName: string;              // Application name
    ManifestUrls: TArray<string>; // Multiple mirror URLs
    CheckInterval: Integer;        // Hours between auto-checks
    AutoDownload: Boolean;         // Download without prompting
    AutoInstall: Boolean;          // Install without prompting
    AllowDowngrade: Boolean;       // Enable version rollback
    TempFolder: string;            // Custom temp directory
    ConnectionTimeout: Integer;    // Seconds
    MaxRetries: Integer;           // Retry attempts
  end;
```

### Example Configurations

**Conservative (manual control)**
```pascal
Config.AutoDownload := False;
Config.AutoInstall := False;
Config.CheckInterval := 168; // Check weekly
```

**Aggressive (automatic updates)**
```pascal
Config.AutoDownload := True;
Config.AutoInstall := True;
Config.CheckInterval := 24; // Check daily
```

**Enterprise (controlled updates)**
```pascal
Config.AllowDowngrade := True;  // Allow admin to rollback
Config.ManifestUrls := [
  'https://internal-updates.company.com/manifest.json',
  'https://backup.company.com/manifest.json'
];
```

---

## Server Setup

### 1. Simple Static Server

```
your-server.com/
├── manifest.json          (update info)
└── releases/
    ├── v2.1.5/
    │   └── MyApp.zip
    └── v2.1.6/
        └── MyApp.zip
```

**nginx config:**
```nginx
server {
    listen 443 ssl;
    server_name updates.myapp.com;
    
    location / {
        root /var/www/updates;
        add_header Access-Control-Allow-Origin *;
    }
}
```

### 2. Update Script (Python)

```python
#!/usr/bin/env python3
import json
import hashlib
import os

def update_manifest(version, zip_file):
    # Calculate checksum
    sha256 = hashlib.sha256()
    with open(zip_file, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b''):
            sha256.update(chunk)
    
    # Get file size
    file_size = os.path.getsize(zip_file)
    
    # Update manifest
    manifest = {
        'MyApp': {
            'version': version,
            'download_url': f'https://cdn.myapp.com/releases/{os.path.basename(zip_file)}',
            'file_size': file_size,
            'checksum': f'sha256:{sha256.hexdigest()}',
            'release_notes': 'New version available'
        }
    }
    
    with open('manifest.json', 'w') as f:
        json.dump(manifest, f, indent=2)
    
    print(f'Manifest updated for version {version}')

if __name__ == '__main__':
    update_manifest('2.1.5.100', 'MyApp_v2.1.5.zip')
```

### 3. Build & Deploy Pipeline

```bash
#!/bin/bash
# build-and-deploy.sh

VERSION="2.1.5"
APP_NAME="MyApp"

# 1. Build release
echo "Building release..."
dcc32 -B $APP_NAME.dpr

# 2. Create update package
echo "Creating update package..."
zip -r ${APP_NAME}_v${VERSION}.zip $APP_NAME.exe libs/

# 3. Generate checksum
echo "Generating checksum..."
CHECKSUM=$(sha256sum ${APP_NAME}_v${VERSION}.zip | cut -d' ' -f1)

# 4. Update manifest
echo "Updating manifest..."
cat > manifest.json <<EOF
{
  "$APP_NAME": {
    "version": "$VERSION.0",
    "download_url": "https://cdn.example.com/releases/${APP_NAME}_v${VERSION}.zip",
    "file_size": $(stat -f%z ${APP_NAME}_v${VERSION}.zip),
    "checksum": "sha256:$CHECKSUM"
  }
}
EOF

# 5. Upload to server
echo "Uploading to server..."
scp ${APP_NAME}_v${VERSION}.zip user@server:/var/www/updates/releases/
scp manifest.json user@server:/var/www/updates/

echo "Deployment complete!"
```

---

## Platform-Specific Notes

### Windows
- Executable replacement uses batch script
- Requires file version resources in .exe
- UAC elevation may be needed for Program Files installation

### macOS
- App bundle structure requires special handling
- Code signing verification recommended
- Gatekeeper compatibility

### Linux
- Standard file replacement works
- Consider integration with package managers
- AppImage self-update support

---

## Security Best Practices

### 1. Use HTTPS
```pascal
// Always use secure URLs
Config.ManifestUrls := [
  'https://updates.myapp.com/manifest.json'  // ✅ Good
  // 'http://updates.myapp.com/manifest.json'  // ❌ Bad
];
```

### 2. Verify Checksums
```json
{
  "checksum": "sha256:abc123def456..."  // Always include
}
```

### 3. Code Signing (Windows)
```bash
# Sign your executables
signtool sign /f certificate.pfx /p password /t http://timestamp.server.com MyApp.exe
```

### 4. Minimum Version Enforcement
```json
{
  "min_version": "2.0.0.0",  // Prevent skipping critical updates
  "severity": "critical"      // Force update
}
```

---

## Error Handling

### Network Errors
```pascal
Engine.CheckForUpdate(procedure(Result: TUpdateCheckResult;
  const Manifest: TUpdateManifest; const ErrorMessage: string)
begin
  case Result of
    ucrError:
      case ErrorCode of
        // Connection timeout
        // DNS failure
        // Server error
      end;
  end;
end);
```

### Rollback on Failure
```pascal
if not Engine.ApplyUpdate then
begin
  if MessageDlg('Update failed. Restore previous version?', 
    mtError, [mbYes, mbNo], 0) = mrYes then
  begin
    Engine.Rollback;
  end;
end;
```

---

## Testing

### Unit Tests
```pascal
procedure TestVersionComparison;
var
  V1, V2: TAppVersion;
begin
  V1 := TAppVersion.Create('1.0.0.0');
  V2 := TAppVersion.Create('1.0.1.0');
  
  Assert(V2 > V1);
  Assert(V1 < V2);
  Assert(V1 <> V2);
end;
```

### Integration Tests
1. Set up test server with known manifest
2. Test download with various file sizes
3. Test checksum verification (valid/invalid)
4. Test network failures and retries
5. Test rollback mechanism

---

## Troubleshooting

### Updates Not Detected
- Check manifest URL is accessible
- Verify JSON format is valid
- Ensure version string format is correct
- Check network connectivity

### Download Fails
- Verify download URL is accessible
- Check disk space
- Verify checksum format
- Check firewall/proxy settings

### Update Won't Apply
- Ensure app has write permissions
- Check if files are in use
- Verify ZIP structure is correct
- Check Windows UAC settings

---

## Advanced Features

### Beta Channels
```pascal
type
  TUpdateChannel = (ucStable, ucBeta, ucAlpha);

// Use different manifest URLs per channel
if Channel = ucBeta then
  Config.ManifestUrls := ['https://updates.myapp.com/beta-manifest.json']
else
  Config.ManifestUrls := ['https://updates.myapp.com/manifest.json'];
```

### Scheduled Updates
```pascal
procedure ScheduleUpdate(UpdateTime: TDateTime);
begin
  // Schedule update at specific time
  Timer.Interval := MilliSecondsBetween(Now, UpdateTime);
  Timer.OnTimer := procedure(Sender: TObject)
  begin
    Engine.ApplyUpdate;
    Timer.Enabled := False;
  end;
  Timer.Enabled := True;
end;
```

### Update Analytics
```pascal
procedure ReportUpdateMetrics(Success: Boolean; Duration: Integer);
begin
  // Send analytics to your server
  HttpClient.Post('https://analytics.myapp.com/update', 
    Format('{"success": %s, "duration": %d}', 
      [BoolToStr(Success, True), Duration]));
end;
```

---

## License

This code is provided as-is for reference and educational purposes.

## Credits

Based on analysis of TurboUpdate by ErrorSoft, incorporating industry best practices from:
- Microsoft ClickOnce
- Sparkle Framework (macOS)
- Squirrel.Windows
- Electron AutoUpdater

---

## Support

For questions and issues, consult:
- Design document: `AppUpdater_Design.md`
- Demo application: `UpdaterDemo.dpr`
- Source code comments

**Happy Updating! 🚀**
