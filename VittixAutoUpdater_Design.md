# VittixAutoUpdater - Design Document

## Overview

This document outlines the architecture for building a production-ready application auto-updater component from scratch, based on analysis of the TurboUpdate reference implementation.

---

## Core Architecture

### 1. **Component Structure**

```
AppUpdater/
├── Types & Models
│   ├── Version management (semantic versioning)
│   ├── Update metadata structures
│   └── Event/callback definitions
├── Network Layer
│   ├── HTTP client wrapper
│   ├── Download manager with progress tracking
│   └── Update manifest retrieval
├── Update Engine
│   ├── Version comparison logic
│   ├── Download orchestration
│   ├── File extraction/replacement
│   └── Rollback mechanism
├── UI Layer
│   ├── Progress dialog/window
│   ├── User notifications
│   └── Update prompts
└── Utilities
    ├── File operations
    ├── Process management
    └── Configuration handling
```

---

## Key Components Breakdown

### A. Version Management System

**Purpose**: Handle version comparison and tracking

**Implementation**:

```pascal
TAppVersion = record
  Major: Word;
  Minor: Word;
  Patch: Word;
  Build: Word;
  
  class operator GreaterThan(L, R: TAppVersion): Boolean;
  class operator LessThan(L, R: TAppVersion): Boolean;
  class operator Equal(L, R: TAppVersion): Boolean;
  
  constructor Create(VersionString: string);  // Parse "1.2.3.456"
  function ToString: string;
  class function GetFileVersion(FilePath: string): TAppVersion;
end;
```

**Features**:
- Parse version strings (1.2.3.456)
- Extract version from executable resources
- Compare versions using operator overloading
- Validate version formats

---

### B. Update Manifest System

**Purpose**: Define what updates are available and where to get them

**Manifest Format** (JSON or INI):

```ini
[MyApp]
Version=2.1.5.100
Download=https://updates.myapp.com/releases/v2.1.5/MyApp.zip
ReleaseNotes=https://updates.myapp.com/releases/v2.1.5/notes.txt
MinVersion=2.0.0.0
Checksum=SHA256:abc123...
FileSize=15728640
ReleaseDate=2026-02-09
Critical=false
```

**Or JSON**:
```json
{
  "MyApp": {
    "version": "2.1.5.100",
    "download_url": "https://updates.myapp.com/releases/v2.1.5/MyApp.zip",
    "release_notes": "Bug fixes and improvements",
    "min_version": "2.0.0.0",
    "checksum": "sha256:abc123...",
    "file_size": 15728640,
    "release_date": "2026-02-09",
    "critical": false
  }
}
```

**Key Fields**:
- `Version`: Latest available version
- `Download`: Direct download URL
- `MinVersion`: Minimum version that can update (prevent skipping critical updates)
- `Checksum`: Verify download integrity
- `Critical`: Force update (security fixes)

---

### C. Network Layer

**Purpose**: Handle all HTTP operations reliably

**Features**:

1. **Manifest Retrieval**
```pascal
function FetchUpdateManifest(Urls: array of string): TUpdateManifest;
```
- Try multiple mirror URLs in order
- Timeout handling (10-30 seconds)
- Proxy support
- SSL/TLS verification

2. **File Downloader**
```pascal
type
  TDownloadProgressProc = reference to procedure(
    BytesReceived, TotalBytes: Int64; 
    var Cancel: Boolean
  );

function DownloadFile(
  Url: string;
  SavePath: string;
  OnProgress: TDownloadProgressProc;
  ExpectedChecksum: string = ''
): Boolean;
```
- Chunked download with progress callbacks
- Resume support (HTTP Range headers)
- Bandwidth throttling (optional)
- Verify checksum after download
- Automatic retry on network failure

3. **Network Resilience**
- Exponential backoff on failures
- Connection timeout management
- Mirror/fallback URL support

---

### D. Update Engine

**Purpose**: Orchestrate the entire update process

**State Machine**:

```pascal
TUpdateState = (
  Idle,           // Not checking/updating
  Checking,       // Querying server for updates
  Available,      // Update found, awaiting user action
  Downloading,    // Downloading update package
  Verifying,      // Checking download integrity
  Extracting,     // Unpacking files
  Applying,       // Replacing application files
  Complete,       // Update successful
  Failed,         // Update failed
  Cancelled       // User cancelled
);
```

**Workflow**:

```
1. Check for Updates
   ├─→ Fetch manifest from server
   ├─→ Parse version info
   ├─→ Compare with current version
   └─→ Return: UpdateAvailable / NoUpdate / Error

2. Download Update
   ├─→ Create temp directory
   ├─→ Download ZIP/installer
   ├─→ Verify checksum
   └─→ Return: Success / Failed

3. Apply Update
   ├─→ Extract files to temp location
   ├─→ Backup current executable (.old)
   ├─→ Replace files
   ├─→ Cleanup temp files
   └─→ Restart application
```

**Critical Operations**:

```pascal
procedure ApplyUpdate(UpdatePackage: string);
begin
  // 1. Validate package
  if not VerifyChecksum(UpdatePackage) then
    raise EUpdateException.Create('Corrupted package');
  
  // 2. Extract to temp location
  ExtractZip(UpdatePackage, TempDir);
  
  // 3. Backup current files
  for File in FilesToUpdate do
    RenameFile(File, File + '.old');
  
  // 4. Copy new files
  for File in NewFiles do
    CopyFile(TempDir + File, ApplicationDir + File);
  
  // 5. Cleanup
  DeleteFile(UpdatePackage);
  
  // 6. Restart
  RestartApplication;
end;
```

---

### E. Threading Model

**Purpose**: Keep UI responsive during updates

**Design Pattern**: Background Worker Thread + UI Synchronization

```pascal
TUpdateThread = class(TThread)
private
  FState: TUpdateState;
  FProgress: Double;
  FStatusMessage: string;
  FOnStateChange: TNotifyEvent;
  FOnProgress: TProgressEvent;
  
protected
  procedure Execute; override;
  procedure SyncStateChange;
  procedure SyncProgress;
  
public
  procedure StartUpdateCheck;
  procedure StartDownload;
  procedure Cancel;
end;
```

**Synchronization Points**:
- State changes (Checking → Downloading → Extracting)
- Progress updates (throttled to 30 FPS max)
- Error notifications
- User prompts

---

### F. File Replacement Strategy

**Challenge**: Cannot replace running executable on Windows

**Solutions**:

1. **Batch Script Method** (Recommended)
```pascal
procedure RestartAndUpdate;
var
  BatchFile: string;
begin
  // Create temporary batch script
  BatchFile := GetTempDir + 'update.bat';
  
  with TStringList.Create do
  try
    Add('@echo off');
    Add('timeout /t 2 /nobreak > nul');  // Wait for app to close
    Add('del /f "' + Application.ExeName + '"');
    Add('move /y "' + NewExePath + '" "' + Application.ExeName + '"');
    Add('start "" "' + Application.ExeName + '"');
    Add('del "%~f0"');  // Delete batch file itself
    SaveToFile(BatchFile);
  finally
    Free;
  end;
  
  // Execute batch and exit
  ShellExecute(0, 'open', PChar(BatchFile), nil, nil, SW_HIDE);
  Application.Terminate;
end;
```

2. **Updater Stub Method**
- Include small `updater.exe` in package
- Main app launches updater with parameters
- Updater waits for main app to close
- Updater replaces files and relaunches main app

3. **Service/Daemon Method**
- Background service handles file replacement
- Main app communicates via IPC
- Best for enterprise applications

---

### G. Rollback Mechanism

**Purpose**: Recover from failed updates

**Strategy**:

```pascal
procedure BackupCurrentVersion;
begin
  // Rename current exe
  RenameFile(AppExe, AppExe + '.old');
  
  // Save backup manifest
  SaveBackupInfo(AppVersion, BackupPath);
end;

procedure RollbackUpdate;
begin
  if FileExists(AppExe + '.old') then
  begin
    DeleteFile(AppExe);
    RenameFile(AppExe + '.old', AppExe);
    ShowMessage('Update failed. Restored previous version.');
  end;
end;
```

**When to Rollback**:
- Extraction fails
- New version crashes on launch
- Checksum verification fails
- User explicitly requests rollback

---

### H. User Interface

**Purpose**: Keep users informed and in control

**Components**:

1. **Update Notification**
```
┌─────────────────────────────────────┐
│  Update Available                   │
├─────────────────────────────────────┤
│  A new version (2.1.5) is available │
│  Current version: 2.1.0             │
│                                     │
│  Release Notes:                     │
│  • Bug fixes                        │
│  • Performance improvements         │
│                                     │
│  [Download Now] [Remind Later] [X]  │
└─────────────────────────────────────┘
```

2. **Download Progress**
```
┌─────────────────────────────────────┐
│  Downloading Update...              │
├─────────────────────────────────────┤
│  [████████████░░░░░░░░░░] 65%       │
│  12.5 MB of 19.2 MB                 │
│  Speed: 2.3 MB/s                    │
│  Time remaining: 3 seconds          │
│                                     │
│  [Cancel]                           │
└─────────────────────────────────────┘
```

3. **Apply Update Dialog**
```
┌─────────────────────────────────────┐
│  Ready to Install                   │
├─────────────────────────────────────┤
│  The application will restart to    │
│  complete the update.               │
│                                     │
│  Save your work before continuing.  │
│                                     │
│  [Install Now] [Install on Exit]    │
└─────────────────────────────────────┘
```

---

## Configuration & Settings

**Application Configuration**:

```pascal
type
  TUpdaterConfig = record
    AppName: string;              // 'MyApplication'
    ManifestUrls: TArray<string>; // Multiple mirrors
    CheckInterval: Integer;       // Hours between checks
    AutoDownload: Boolean;        // Download without prompting
    AutoInstall: Boolean;         // Install without prompting
    AllowDowngrade: Boolean;      // Enable version rollback
    ProxySettings: TProxySettings;
    TempFolder: string;           // Custom temp directory
  end;
```

**User Preferences**:
```ini
[Updater]
EnableAutoCheck=1
CheckInterval=24
NotifyBeta=0
LastCheckTime=2026-02-09 10:30:00
SkippedVersion=
```

---

## Security Considerations

### 1. **Transport Security**
- HTTPS only for manifest and downloads
- Certificate pinning (optional)
- Reject HTTP redirects to different domains

### 2. **Code Signing**
```pascal
function VerifyCodeSignature(FilePath: string): Boolean;
begin
  // Verify Authenticode signature on Windows
  // Check certificate chain
  // Ensure signer matches expected publisher
end;
```

### 3. **Checksum Verification**
```pascal
function VerifyDownload(FilePath, ExpectedChecksum: string): Boolean;
var
  Hash: THashSHA2;
begin
  Hash := THashSHA2.Create;
  Hash.GetHashStringFromFile(FilePath);
  Result := SameText(Hash.HashAsString, ExpectedChecksum);
end;
```

### 4. **Privilege Management**
- Request elevation only when needed
- Run updater with minimal permissions
- Validate all file paths (prevent directory traversal)

---

## Error Handling

**Categories**:

1. **Network Errors**
   - Connection timeout
   - DNS failure
   - Server not found
   - Incomplete download

2. **File System Errors**
   - Insufficient disk space
   - Permission denied
   - Corrupted archive
   - Missing files

3. **Version Errors**
   - Invalid version format
   - Downgrade attempted (if disabled)
   - Incompatible version

**Strategy**:

```pascal
try
  PerformUpdate;
except
  on E: ENetworkException do
    LogError('Network error: ' + E.Message);
  on E: EFileSystemException do
    LogError('File system error: ' + E.Message);
  on E: Exception do
    LogError('Unexpected error: ' + E.Message);
end;
```

---

## Testing Strategy

### Unit Tests
- Version comparison logic
- Checksum verification
- Manifest parsing
- File operations

### Integration Tests
- Download from test server
- Apply test update package
- Rollback mechanism
- Thread safety

### Stress Tests
- Slow network conditions
- Large file downloads
- Concurrent update attempts
- Disk full scenarios

---

## Deployment Workflow

### Server-Side Setup

1. **Build Pipeline**
```bash
# 1. Build release
build.bat --release

# 2. Create update package
zip MyApp_v2.1.5.zip MyApp.exe libs/*.dll

# 3. Generate checksum
sha256sum MyApp_v2.1.5.zip > checksum.txt

# 4. Update manifest
update-manifest.py --version 2.1.5 --file MyApp_v2.1.5.zip

# 5. Upload to CDN
aws s3 cp MyApp_v2.1.5.zip s3://updates.myapp.com/releases/
aws s3 cp manifest.json s3://updates.myapp.com/
```

2. **Manifest Generation**
```python
def generate_manifest(version, file_path):
    checksum = calculate_sha256(file_path)
    file_size = os.path.getsize(file_path)
    
    manifest = {
        'version': version,
        'download_url': f'https://cdn.myapp.com/{file_path}',
        'checksum': checksum,
        'file_size': file_size,
        'release_date': datetime.now().isoformat()
    }
    
    save_json('manifest.json', manifest)
```

---

## Performance Optimization

### 1. **Differential Updates**
- Download only changed files
- Binary diff patches (bsdiff/xdelta)
- Reduce bandwidth usage

### 2. **Compression**
- Use ZIP with maximum compression
- Consider 7z for better ratios
- LZMA compression for large binaries

### 3. **Caching**
```pascal
// Cache manifest for N minutes
function GetCachedManifest: TUpdateManifest;
begin
  if (Now - LastFetchTime) < CacheTimeout then
    Result := CachedManifest
  else
    Result := FetchFreshManifest;
end;
```

### 4. **Background Downloads**
- Download in idle time
- Respect user bandwidth limits
- Pause during active use

---

## Platform Considerations

### Windows
- Use Windows API for file version extraction
- Handle UAC prompts
- Support Windows 7+ compatibility

### macOS
- App bundle structure (.app)
- Code signing requirements
- Gatekeeper compatibility

### Linux
- Package manager integration
- AppImage self-update
- Permission handling

---

## Advanced Features

### 1. **Beta/Alpha Channels**
```pascal
type
  TUpdateChannel = (Stable, Beta, Alpha, Nightly);
  
// Allow users to opt-in to pre-release updates
```

### 2. **Partial Updates**
```pascal
// Update plugins/libraries without restarting
procedure UpdatePlugin(PluginName: string);
```

### 3. **Update Scheduling**
```pascal
// Install update at specific time
procedure ScheduleUpdate(DateTime: TDateTime);
```

### 4. **Analytics**
```pascal
// Track update success/failure rates
procedure ReportUpdateMetrics(Success: Boolean; Duration: Integer);
```

---

## Recommended Libraries

### Delphi/Pascal
- **Indy HTTP**: HTTP client operations
- **System.Net.HttpClient**: Modern HTTP (Delphi 10.x+)
- **System.Zip**: Built-in ZIP handling
- **SynZip**: Alternative ZIP library
- **OpenSSL**: HTTPS support

### C#/.NET
- **HttpClient**: Network operations
- **SharpCompress**: Archive handling
- **Octokit**: GitHub releases integration

### C++
- **libcurl**: HTTP downloads
- **zlib**: Compression
- **OpenSSL**: Secure connections

---

## Example Implementation Timeline

**Week 1**: Core architecture
- Version comparison
- Manifest parsing
- Basic HTTP operations

**Week 2**: Download engine
- Progress tracking
- Checksum verification
- Error handling

**Week 3**: Update application
- File extraction
- Replacement logic
- Rollback mechanism

**Week 4**: UI & Polish
- Progress dialogs
- User notifications
- Configuration

**Week 5**: Testing & Refinement
- Unit tests
- Integration tests
- Security audit

---

## Conclusion

Building an auto-updater requires careful attention to:
- **Reliability**: Handle network failures gracefully
- **Security**: Verify downloads, use HTTPS
- **User Experience**: Clear progress indication
- **Safety**: Always allow rollback
- **Platform Compatibility**: Handle OS-specific quirks

Start with the core version comparison and manifest system, then build outward to networking and UI layers. Test thoroughly with real-world network conditions and edge cases.

---

## References & Resources

- **Microsoft ClickOnce**: Study deployment strategies
- **Sparkle Framework** (macOS): Well-designed updater
- **Squirrel.Windows**: Modern Windows updater
- **Electron AutoUpdater**: Cross-platform reference
- **Google Omaha**: Chrome update protocol

---

*This design is based on analysis of TurboUpdate and incorporates industry best practices for application auto-updating.*
