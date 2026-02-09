# VittixAutoUpdater Visual Component Guide

This guide provides comprehensive documentation for using the enhanced visual components of VittixAutoUpdater in your Delphi applications.

## Table of Contents

- [Overview](#overview)
- [Components](#components)
- [Quick Start](#quick-start)
- [Visual Component Features](#visual-component-features)
- [Settings Dialog](#settings-dialog)
- [Event Handling](#event-handling)
- [UI Customization](#ui-customization)
- [Integration Examples](#integration-examples)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)

## Overview

VittixAutoUpdater provides two main visual components:

1. **TVittixAutoUpdaterUI** - The main updater interface component
2. **TUpdateSettingsForm** - A comprehensive settings dialog

These components provide a complete, professional-looking update interface that can be easily integrated into any Delphi application.

## Components

### TVittixAutoUpdaterUI

The main visual component that provides:
- Multiple UI styles (Compact, Standard, Detailed)
- Progress tracking with detailed statistics
- Release notes display
- Configurable button layouts
- Event-driven architecture
- Modern, themed appearance

### TUpdateSettingsForm

A complete settings dialog offering:
- General update preferences
- Network configuration
- URL management
- Proxy settings
- Security options
- Logging configuration
- Advanced path settings

## Quick Start

### 1. Add Components to Your Project

```pascal
// Add these units to your uses clause
uses
  VittixAutoUpdater.Types,
  VittixAutoUpdater.Engine,
  VittixAutoUpdater.VisualComponent,
  VittixAutoUpdater.Settings;
```

### 2. Basic Implementation

```pascal
type
  TMainForm = class(TForm)
    UpdaterUI: TVittixAutoUpdaterUI;
    procedure FormCreate(Sender: TObject);
    procedure UpdaterUIStateChange(Sender: TObject; NewState: TUpdateState;
      const StatusMessage: string);
  end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  Config: TUpdaterConfig;
begin
  // Configure the updater
  Config := TUpdaterConfig.Default;
  Config.AppName := 'MyApplication';
  SetLength(Config.ManifestUrls, 1);
  Config.ManifestUrls[0] := 'https://myserver.com/updates/manifest.json';
  
  // Setup the visual component
  UpdaterUI.Config := Config;
  UpdaterUI.UIStyle := uisStandard;
  UpdaterUI.ShowReleaseNotes := True;
  UpdaterUI.OnStateChange := UpdaterUIStateChange;
end;

procedure TMainForm.UpdaterUIStateChange(Sender: TObject; 
  NewState: TUpdateState; const StatusMessage: string);
begin
  // Handle state changes
  Caption := 'MyApp - ' + StatusMessage;
end;
```

### 3. Register Components (Optional)

For design-time support, register the components:

```pascal
procedure Register;
begin
  RegisterComponents('VittixAutoUpdater', [TVittixAutoUpdaterUI]);
end;
```

## Visual Component Features

### UI Styles

The component supports three UI styles:

#### Compact Style (`uisCompact`)
- Minimal height (200px)
- Essential controls only
- No release notes panel
- Perfect for small dialogs or status bars

#### Standard Style (`uisStandard`) - Default
- Balanced layout (350px)
- All main features visible
- Optional release notes panel
- Ideal for most applications

#### Detailed Style (`uisDetailed`)
- Maximum information display (450px)
- All panels visible
- Extended progress details
- Best for power users

### Button Styles

Control how users interact with the updater:

#### Automatic (`ubsAutomatic`)
- Single "Check for Updates" button
- Automatic download and installation
- Minimal user interaction required

#### Manual (`ubsManual`)
- Separate buttons for each step
- Check → Download → Install
- Full user control

#### Both (`ubsBoth`) - Default
- All buttons available
- User can choose workflow
- Maximum flexibility

### Progress Display

The component provides detailed progress information:

```pascal
// Enable/disable progress details
UpdaterUI.ShowProgressDetails := True;

// Progress information includes:
// - Bytes downloaded / total size
// - Download speed (KB/s, MB/s)
// - Estimated time remaining
// - Percentage complete
```

### Release Notes

Display update information to users:

```pascal
// Show release notes panel
UpdaterUI.ShowReleaseNotes := True;

// Release notes are automatically populated from the manifest
// Users can see what's new in the update before installing
```

## Settings Dialog

### Basic Usage

```pascal
procedure TMainForm.ShowSettings;
var
  Config: TUpdaterConfig;
begin
  Config := UpdaterUI.Config;
  
  if TUpdateSettingsForm.Execute(Config, Self) then
  begin
    UpdaterUI.Config := Config;
    // Save configuration if needed
    SaveConfigToFile(Config);
  end;
end;
```

### Settings Categories

#### General Tab
- Application name
- Check interval (hours)
- Automatic download/install options
- Version downgrade permission
- Windows startup integration
- Notification preferences

#### Network Tab
- Multiple manifest URLs with testing
- Connection timeout settings
- Retry configuration
- Custom User-Agent string
- Proxy server configuration
- Authentication settings

#### Advanced Tab
- Custom file paths (temp, backup)
- Security settings (signature verification)
- Trusted publisher management
- Logging configuration
- Log file management

## Event Handling

### Available Events

```pascal
type
  TVittixAutoUpdaterUI = class(TCustomPanel)
  published
    // State change notifications
    property OnStateChange: TUpdateStateChangeEvent;
    
    // Download progress updates
    property OnDownloadProgress: TDownloadProgressEvent;
    
    // User decision requests
    property OnUpdateDecision: TUpdateDecisionEvent;
    
    // Update completion notification
    property OnUpdateComplete: TUpdateCompleteEvent;
    
    // Settings button clicked
    property OnSettingsClick: TNotifyEvent;
  end;
```

### Event Implementation Examples

#### State Change Handling

```pascal
procedure TMainForm.UpdaterUIStateChange(Sender: TObject; 
  NewState: TUpdateState; const StatusMessage: string);
begin
  case NewState of
    usIdle:
      StatusBar.Panels[0].Text := 'Ready';
    usChecking:
      StatusBar.Panels[0].Text := 'Checking for updates...';
    usAvailable:
      StatusBar.Panels[0].Text := 'Update available';
    usDownloading:
      StatusBar.Panels[0].Text := 'Downloading update...';
    usReady:
      StatusBar.Panels[0].Text := 'Ready to install';
    usInstalling:
      StatusBar.Panels[0].Text := 'Installing update...';
    usComplete:
      StatusBar.Panels[0].Text := 'Update completed';
    usError:
      StatusBar.Panels[0].Text := 'Error: ' + StatusMessage;
  end;
end;
```

#### Progress Tracking

```pascal
procedure TMainForm.UpdaterUIDownloadProgress(Sender: TObject; 
  BytesReceived, TotalBytes: Int64; PercentComplete: Integer; 
  var Cancel: Boolean);
begin
  // Update taskbar progress (Windows 7+)
  TaskBarProgressBar.ProgressValue := PercentComplete;
  
  // Log major milestones
  if PercentComplete mod 10 = 0 then
    LogMessage(Format('Download %d%% complete', [PercentComplete]));
    
  // Allow user cancellation
  if UserRequestedCancel then
    Cancel := True;
end;
```

#### User Decision Handling

```pascal
procedure TMainForm.UpdaterUIUpdateDecision(Sender: TObject; 
  const Manifest: TUpdateManifest; var Decision: Boolean);
var
  Msg: string;
begin
  Msg := Format('Update to version %s is available (%s).%s%sInstall now?',
    [Manifest.Version.ToString, 
     FormatBytes(Manifest.FileSize),
     #13#10#13#10,
     Manifest.ReleaseNotes]);
     
  Decision := MessageDlg(Msg, mtConfirmation, [mbYes, mbNo], 0) = mrYes;
end;
```

#### Completion Handling

```pascal
procedure TMainForm.UpdaterUIComplete(Sender: TObject; Success: Boolean; 
  const ErrorMessage: string);
begin
  if Success then
  begin
    ShowMessage('Update completed successfully. Please restart the application.');
    // Optionally restart automatically
    // RestartApplication;
  end
  else
  begin
    ShowMessage('Update failed: ' + ErrorMessage);
    LogError('Update failed: ' + ErrorMessage);
  end;
end;
```

## UI Customization

### Theming Support

The component automatically adapts to Windows themes:

```pascal
// The component respects:
// - Windows visual styles
// - High contrast modes
// - Dark/light theme preferences
// - Custom color schemes
```

### Custom Styling

```pascal
procedure TMainForm.CustomizeUpdaterUI;
begin
  // Customize colors
  UpdaterUI.Color := clWhite;
  UpdaterUI.Font.Name := 'Segoe UI';
  UpdaterUI.Font.Size := 9;
  
  // Set size constraints
  UpdaterUI.Constraints.MinWidth := 400;
  UpdaterUI.Constraints.MinHeight := 200;
  
  // Configure layout
  UpdaterUI.Align := alClient;
  UpdaterUI.Anchors := [akLeft, akTop, akRight, akBottom];
end;
```

### Dynamic UI Changes

```pascal
procedure TMainForm.AdaptUIToSpace;
begin
  // Adapt to available space
  if ClientHeight < 300 then
    UpdaterUI.UIStyle := uisCompact
  else if ClientHeight < 400 then
    UpdaterUI.UIStyle := uisStandard
  else
    UpdaterUI.UIStyle := uisDetailed;
end;
```

## Integration Examples

### Modal Update Dialog

```pascal
type
  TUpdateDialog = class(TForm)
    UpdaterUI: TVittixAutoUpdaterUI;
    BtnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure UpdaterUIComplete(Sender: TObject; Success: Boolean; 
      const ErrorMessage: string);
  end;

procedure TUpdateDialog.FormCreate(Sender: TObject);
begin
  Caption := 'Check for Updates';
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  
  UpdaterUI.UIStyle := uisCompact;
  UpdaterUI.ButtonStyle := ubsAutomatic;
  UpdaterUI.OnUpdateComplete := UpdaterUIComplete;
  
  // Start checking immediately
  UpdaterUI.CheckForUpdates;
end;

procedure TUpdateDialog.UpdaterUIComplete(Sender: TObject; Success: Boolean; 
  const ErrorMessage: string);
begin
  BtnClose.Enabled := True;
  if Success then
    ModalResult := mrOK
  else
    ModalResult := mrCancel;
end;
```

### Embedded in Main Form

```pascal
type
  TMainForm = class(TForm)
    Panel1: TPanel;
    UpdaterUI: TVittixAutoUpdaterUI;
    MenuUpdates: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure MenuUpdatesClick(Sender: TObject);
  end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  // Embed updater in a panel
  UpdaterUI.Parent := Panel1;
  UpdaterUI.Align := alClient;
  UpdaterUI.UIStyle := uisStandard;
  
  // Hide panel initially
  Panel1.Visible := False;
end;

procedure TMainForm.MenuUpdatesClick(Sender: TObject);
begin
  // Show/hide updater panel
  Panel1.Visible := not Panel1.Visible;
  if Panel1.Visible then
    UpdaterUI.CheckForUpdates;
end;
```

### System Tray Integration

```pascal
type
  TMainForm = class(TForm)
    TrayIcon: TTrayIcon;
    UpdaterUI: TVittixAutoUpdaterUI;
    procedure TrayIconDblClick(Sender: TObject);
    procedure UpdaterUIStateChange(Sender: TObject; NewState: TUpdateState; 
      const StatusMessage: string);
  end;

procedure TMainForm.TrayIconDblClick(Sender: TObject);
begin
  Show;
  WindowState := wsNormal;
  Application.BringToFront;
  UpdaterUI.CheckForUpdates;
end;

procedure TMainForm.UpdaterUIStateChange(Sender: TObject; 
  NewState: TUpdateState; const StatusMessage: string);
begin
  // Update tray icon and hint
  TrayIcon.Hint := Application.Title + ' - ' + StatusMessage;
  
  if NewState = usAvailable then
  begin
    TrayIcon.ShowBalloonHint('Update Available', 
      'A new version is ready to download', bfInfo, 5000);
  end;
end;
```

## Advanced Usage

### Custom Update Workflow

```pascal
procedure TMainForm.CustomUpdateWorkflow;
begin
  // Disable auto-check, handle manually
  UpdaterUI.AutoCheck := False;
  
  // Check for updates every hour
  Timer1.Interval := 3600000; // 1 hour
  Timer1.OnTimer := procedure(Sender: TObject)
  begin
    if not UpdaterUI.IsUpdating then
      UpdaterUI.CheckForUpdates;
  end;
  Timer1.Enabled := True;
end;
```

### Conditional Updates

```pascal
procedure TMainForm.UpdaterUIUpdateDecision(Sender: TObject; 
  const Manifest: TUpdateManifest; var Decision: Boolean);
begin
  // Only allow updates during business hours
  Decision := (TimeOf(Now) >= EncodeTime(9, 0, 0, 0)) and 
              (TimeOf(Now) <= EncodeTime(17, 0, 0, 0));
              
  if not Decision then
    ShowMessage('Updates are only allowed during business hours (9 AM - 5 PM)');
end;
```

### Multi-Channel Updates

```pascal
procedure TMainForm.SetUpdateChannel(Channel: string);
var
  Config: TUpdaterConfig;
begin
  Config := UpdaterUI.Config;
  
  case Channel.ToLower of
    'stable':
      begin
        SetLength(Config.ManifestUrls, 1);
        Config.ManifestUrls[0] := 'https://updates.myapp.com/stable/manifest.json';
      end;
    'beta':
      begin
        SetLength(Config.ManifestUrls, 1);
        Config.ManifestUrls[0] := 'https://updates.myapp.com/beta/manifest.json';
      end;
    'alpha':
      begin
        SetLength(Config.ManifestUrls, 1);
        Config.ManifestUrls[0] := 'https://updates.myapp.com/alpha/manifest.json';
      end;
  end;
  
  UpdaterUI.Config := Config;
end;
```

## Troubleshooting

### Common Issues

#### Component Not Visible
```pascal
// Ensure proper parent and alignment
UpdaterUI.Parent := Self;  // or specific panel
UpdaterUI.Align := alClient;
UpdaterUI.Visible := True;
```

#### Events Not Firing
```pascal
// Assign events after creating the component
UpdaterUI.OnStateChange := MyStateChangeHandler;
UpdaterUI.OnDownloadProgress := MyProgressHandler;
```

#### Settings Not Persisting
```pascal
// Save configuration after changes
procedure SaveConfig;
var
  IniFile: TIniFile;
begin
  IniFile := TIniFile.Create(ChangeFileExt(ParamStr(0), '.ini'));
  try
    // Save your configuration here
  finally
    IniFile.Free;
  end;
end;
```

### Debug Information

Enable detailed logging to troubleshoot issues:

```pascal
procedure TMainForm.EnableDebugMode;
begin
  // This would require extending the component with logging
  UpdaterUI.Engine.OnDebugMessage := procedure(const Msg: string)
  begin
    OutputDebugString(PChar('[UpdaterUI] ' + Msg));
  end;
end;
```

### Performance Optimization

For applications with limited resources:

```pascal
procedure TMainForm.OptimizeForPerformance;
begin
  // Use compact UI to reduce memory usage
  UpdaterUI.UIStyle := uisCompact;
  
  // Disable detailed progress to reduce CPU usage
  UpdaterUI.ShowProgressDetails := False;
  
  // Reduce check frequency
  UpdaterUI.Config := ModifyConfig(UpdaterUI.Config, 
    procedure(var Config: TUpdaterConfig)
    begin
      Config.CheckInterval := 24; // Check daily instead of hourly
    end);
end;
```

## Best Practices

1. **Always handle the OnUpdateComplete event** to notify users of success/failure
2. **Provide user control** over when updates are installed
3. **Save user preferences** for update behavior
4. **Test with various network conditions** including slow connections and proxies
5. **Implement proper error handling** for network failures
6. **Consider user workflow** when choosing UI style and button layout
7. **Provide visual feedback** for all operations
8. **Allow users to cancel** long-running operations
9. **Test update scenarios** thoroughly before deployment
10. **Document your update process** for end users

## Conclusion

The VittixAutoUpdater visual components provide a complete, professional solution for application updating in Delphi. With multiple UI styles, comprehensive event handling, and extensive customization options, they can be adapted to fit any application's needs.

For additional support and examples, refer to the demo application and the main VittixAutoUpdater documentation.