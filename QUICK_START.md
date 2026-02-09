# VittixAutoUpdater - Quick Start Guide

## 5-Minute Setup

### Step 1: Add Units to Your Project

Copy these three files to your project folder:
- `VittixAutoUpdater.Types.pas`
- `VittixAutoUpdater.Network.pas`
- `VittixAutoUpdater.Engine.pas`

### Step 2: Add to Your Main Form

```pascal
unit MainForm;

interface

uses
  Vcl.Forms, Vcl.StdCtrls,
  VittixAutoUpdater.Types, VittixAutoUpdater.Engine;

type
  TForm1 = class(TForm)
    btnCheckUpdate: TButton;
    procedure btnCheckUpdateClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FUpdater: TUpdateEngine;
    procedure CheckForUpdates;
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.FormCreate(Sender: TObject);
var
  Config: TUpdaterConfig;
begin
  // Configure the updater
  Config := TUpdaterConfig.Default;
  Config.AppName := 'MyApplication';
  SetLength(Config.ManifestUrls, 1);
  Config.ManifestUrls[0] := 'https://updates.myapp.com/manifest.json';
  
  // Create updater instance
  FUpdater := TUpdateEngine.Create(Config);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FUpdater.Free;
end;

procedure TForm1.btnCheckUpdateClick(Sender: TObject);
begin
  CheckForUpdates;
end;

procedure TForm1.CheckForUpdates;
begin
  FUpdater.CheckForUpdate(procedure(Result: TUpdateCheckResult;
    const Manifest: TUpdateManifest; const ErrorMessage: string)
  begin
    case Result of
      ucrUpdateAvailable:
        begin
          if MessageDlg(
            Format('Version %s is available. Download now?', 
              [Manifest.Version.ToString]),
            mtConfirmation, [mbYes, mbNo], 0) = mrYes then
          begin
            // Download in background thread
            TThread.CreateAnonymousThread(procedure
            begin
              if FUpdater.DownloadUpdate(Manifest) then
              begin
                TThread.Synchronize(nil, procedure
                begin
                  if MessageDlg('Update ready. Install now?',
                    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
                  begin
                    FUpdater.ApplyUpdate;
                    // Application will restart
                  end;
                end);
              end;
            end).Start;
          end;
        end;
        
      ucrNoUpdateAvailable:
        ShowMessage('You have the latest version!');
        
      ucrError:
        ShowMessage('Error checking for updates: ' + ErrorMessage);
    end;
  end);
end;

end.
```

### Step 3: Create Your Update Server

#### Option A: Simple Static Files

Create two files on your web server:

**manifest.json** (in root):
```json
{
  "MyApplication": {
    "version": "1.0.1.0",
    "download_url": "https://updates.myapp.com/releases/MyApp_v1.0.1.zip",
    "file_size": 5242880,
    "checksum": "sha256:abc123...",
    "release_notes": "Bug fixes and improvements"
  }
}
```

**Directory structure**:
```
https://updates.myapp.com/
├── manifest.json
└── releases/
    └── MyApp_v1.0.1.zip
```

#### Option B: Automated with Script

Use the included `generate_manifest.py`:

```bash
# Build your app
build_app.bat

# Create update package
zip MyApp_v1.0.1.zip MyApp.exe *.dll

# Generate manifest
python generate_manifest.py \
  --app MyApplication \
  --version 1.0.1.0 \
  --file MyApp_v1.0.1.zip \
  --url https://updates.myapp.com

# Upload
scp manifest.json user@server:/var/www/updates/
scp MyApp_v1.0.1.zip user@server:/var/www/updates/releases/
```

### Step 4: Test the Update

1. Set your app version to `1.0.0.0` (in Project > Options > Version Info)
2. Compile and run
3. Click "Check for Updates"
4. Should detect version `1.0.1.0` is available
5. Download and install

---

## Advanced: Automatic Update Checking

Add this to your main form to check on startup:

```pascal
procedure TForm1.FormShow(Sender: TObject);
begin
  // Check for updates on startup (after 2 seconds)
  TThread.CreateAnonymousThread(procedure
  begin
    Sleep(2000);
    TThread.Synchronize(nil, procedure
    begin
      CheckForUpdates;
    end);
  end).Start;
end;
```

## Advanced: Progress Dialog

```pascal
type
  TForm1 = class(TForm)
    ProgressBar1: TProgressBar;
    Label1: TLabel;
  private
    procedure SetupProgressTracking;
  end;

procedure TForm1.SetupProgressTracking;
begin
  FUpdater.OnStateChange := procedure(Sender: TObject;
    NewState: TUpdateState; const StatusMessage: string)
  begin
    Label1.Caption := StatusMessage;
  end;
  
  FUpdater.OnDownloadProgress := procedure(Sender: TObject;
    BytesReceived, TotalBytes: Int64; var Cancel: Boolean)
  begin
    ProgressBar1.Max := TotalBytes;
    ProgressBar1.Position := BytesReceived;
  end;
end;
```

---

## Common Patterns

### Silent Auto-Update

```pascal
Config.AutoDownload := True;
Config.AutoInstall := True;
Config.CheckInterval := 24; // Check daily
```

### Update on Exit

```pascal
procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FUpdateDownloaded then
  begin
    FUpdater.ApplyUpdate;
    // App will restart
  end;
end;
```

### Beta Channel

```pascal
if UserOptedIntoBeta then
  Config.ManifestUrls[0] := 'https://updates.myapp.com/beta-manifest.json'
else
  Config.ManifestUrls[0] := 'https://updates.myapp.com/manifest.json';
```

---

## Troubleshooting

### "Update not detected"
- Verify manifest URL is accessible in browser
- Check JSON is valid (use jsonlint.com)
- Ensure version in manifest is higher than app version

### "Download fails"
- Check download_url is accessible
- Verify file exists on server
- Check firewall/antivirus settings

### "Update won't apply"
- Ensure app has write permissions to its directory
- Close all instances of the app
- Check Windows UAC settings

---

## Next Steps

1. ✅ Read full documentation: `README.md`
2. ✅ Study architecture: `VittixAutoUpdater_Design.md`
3. ✅ Examine demo: `VittixAutoUpdaterDemo.dpr`
4. ✅ Set up automated deployment: `deploy-update.sh`

**You're ready to ship updates! 🚀**
