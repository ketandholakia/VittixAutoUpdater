unit VittixAutoUpdaterEnhancedDemo;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Menus, Vcl.ActnList,
  System.Actions, System.ImageList, Vcl.ImgList, Vcl.ToolWin,
  Vcl.AppEvnts, System.Win.TaskbarCore, Vcl.Taskbar,
  VittixAutoUpdater.Types, VittixAutoUpdater.Engine, VittixAutoUpdater.VisualComponent,
  VittixAutoUpdater.Settings;

type
  TEnhancedDemoForm = class(TForm)
    MainMenu: TMainMenu;
    StatusBar: TStatusBar;
    ActionList: TActionList;
    ImageList: TImageList;
    ToolBar: TToolBar;
    ApplicationEvents: TApplicationEvents;
    TaskBar: TTaskbar;

    // Menu items
    MenuFile: TMenuItem;
    MenuEdit: TMenuItem;
    MenuView: TMenuItem;
    MenuTools: TMenuItem;
    MenuHelp: TMenuItem;

    // File menu
    ActExit: TAction;
    MenuExit: TMenuItem;
    N1: TMenuItem;
    MenuCheckNow: TMenuItem;
    ActCheckNow: TAction;

    // Edit menu
    ActSettings: TAction;
    MenuSettings: TMenuItem;

    // View menu
    MenuViewStyle: TMenuItem;
    ActViewCompact: TAction;
    ActViewStandard: TAction;
    ActViewDetailed: TAction;
    MenuCompact: TMenuItem;
    MenuStandard: TMenuItem;
    MenuDetailed: TMenuItem;
    N2: TMenuItem;
    ActShowReleaseNotes: TAction;
    ActShowProgressDetails: TAction;
    MenuShowReleaseNotes: TMenuItem;
    MenuShowProgressDetails: TMenuItem;

    // Tools menu
    ActAutoCheck: TAction;
    MenuAutoCheck: TMenuItem;
    MenuResetUpdater: TMenuItem;
    ActResetUpdater: TAction;
    N3: TMenuItem;
    MenuTestConnection: TMenuItem;
    ActTestConnection: TAction;

    // Help menu
    ActAbout: TAction;
    MenuAbout: TMenuItem;
    MenuManual: TMenuItem;
    ActShowManual: TAction;

    // Toolbar buttons
    ToolBtnCheck: TToolButton;
    ToolBtnSeparator1: TToolButton;
    ToolBtnSettings: TToolButton;
    ToolBtnSeparator2: TToolButton;
    ToolBtnViewCompact: TToolButton;
    ToolBtnViewStandard: TToolButton;
    ToolBtnViewDetailed: TToolButton;

    // Main panel
    MainPanel: TPanel;

    // Info panel (top)
    InfoPanel: TPanel;
    LblAppTitle: TLabel;
    LblVersion: TLabel;
    LblStatus: TLabel;

    // Update component
    UpdaterUI: TVittixAutoUpdaterUI;

    // Log panel (bottom)
    LogPanel: TPanel;
    LogSplitter: TSplitter;
    MemoLog: TMemo;
    LblLog: TLabel;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ApplicationEventsMinimize(Sender: TObject);

    // Action handlers
    procedure ActExitExecute(Sender: TObject);
    procedure ActCheckNowExecute(Sender: TObject);
    procedure ActSettingsExecute(Sender: TObject);
    procedure ActViewCompactExecute(Sender: TObject);
    procedure ActViewStandardExecute(Sender: TObject);
    procedure ActViewDetailedExecute(Sender: TObject);
    procedure ActShowReleaseNotesExecute(Sender: TObject);
    procedure ActShowProgressDetailsExecute(Sender: TObject);
    procedure ActAutoCheckExecute(Sender: TObject);
    procedure ActResetUpdaterExecute(Sender: TObject);
    procedure ActTestConnectionExecute(Sender: TObject);
    procedure ActAboutExecute(Sender: TObject);
    procedure ActShowManualExecute(Sender: TObject);

    // Updater event handlers
    procedure UpdaterStateChange(Sender: TObject; NewState: TUpdateState;
      const StatusMessage: string);
    procedure UpdaterDownloadProgress(Sender: TObject; BytesReceived, TotalBytes: Int64;
      PercentComplete: Integer; var Cancel: Boolean);
    procedure UpdaterUpdateDecision(Sender: TObject; const Manifest: TUpdateManifest;
      var Decision: Boolean);
    procedure UpdaterComplete(Sender: TObject; Success: Boolean;
      const ErrorMessage: string);
    procedure UpdaterSettingsClick(Sender: TObject);

  private
    FAppConfig: TUpdaterConfig;
    FLogVisible: Boolean;
    FMinimizeToTray: Boolean;

    procedure LoadConfiguration;
    procedure SaveConfiguration;
    procedure SetupUpdaterComponent;
    procedure UpdateMenuStates;
    procedure LogMessage(const Message: string; const Level: string = 'INFO');
    procedure ShowTrayNotification(const Title, Message: string);
    procedure SetLogVisible(const Value: Boolean);

    property LogVisible: Boolean read FLogVisible write SetLogVisible;

  public
    { Public declarations }
  end;

var
  EnhancedDemoForm: TEnhancedDemoForm;

implementation

uses
  System.IniFiles, System.IOUtils, Vcl.Imaging.pngimage,
  Winapi.ShellAPI, System.Win.Registry;

{$R *.dfm}

procedure TEnhancedDemoForm.FormCreate(Sender: TObject);
begin
  // Initialize application
  Caption := 'VittixAutoUpdater Enhanced Demo';

  // Load configuration
  LoadConfiguration;

  // Setup updater component
  SetupUpdaterComponent;

  // Initialize UI state
  FLogVisible := False;
  FMinimizeToTray := True;
  LogPanel.Height := 150;
  SetLogVisible(False);

  // Update menu states
  UpdateMenuStates;

  // Log startup
  LogMessage('Application started', 'INFO');
  LogMessage('Configuration loaded: ' + FAppConfig.AppName, 'INFO');

  // Set window properties
  Position := poScreenCenter;

  // Setup taskbar
  TaskBar.ProgressState := TTaskBarProgressState.None;
end;

procedure TEnhancedDemoForm.FormDestroy(Sender: TObject);
begin
  SaveConfiguration;
  LogMessage('Application shutting down', 'INFO');
end;

procedure TEnhancedDemoForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FMinimizeToTray then
  begin
    // Minimize to tray instead of closing
    CanClose := False;
    WindowState := wsMinimized;
    ShowWindow(Handle, SW_HIDE);
    ShowTrayNotification('VittixAutoUpdater', 'Application minimized to system tray');
  end
  else
  begin
    CanClose := True;
  end;
end;

procedure TEnhancedDemoForm.ApplicationEventsMinimize(Sender: TObject);
begin
  if FMinimizeToTray then
  begin
    ShowWindow(Handle, SW_HIDE);
  end;
end;

procedure TEnhancedDemoForm.LoadConfiguration;
var
  IniFile: TIniFile;
  IniPath: string;
  i: Integer;
  UrlCount: Integer;
  Url: string;
begin
  // Create default config
  FAppConfig := TUpdaterConfig.Default;
  FAppConfig.AppName := 'VittixAutoUpdater Demo';

  // Load from INI file
  IniPath := ChangeFileExt(ParamStr(0), '.ini');

  if TFile.Exists(IniPath) then
  begin
    IniFile := TIniFile.Create(IniPath);
    try
      // General settings
      FAppConfig.AppName := IniFile.ReadString('General', 'AppName', FAppConfig.AppName);
      FAppConfig.CheckInterval := IniFile.ReadInteger('General', 'CheckInterval', FAppConfig.CheckInterval);
      FAppConfig.AutoDownload := IniFile.ReadBool('General', 'AutoDownload', FAppConfig.AutoDownload);
      FAppConfig.AutoInstall := IniFile.ReadBool('General', 'AutoInstall', FAppConfig.AutoInstall);
      FAppConfig.AllowDowngrade := IniFile.ReadBool('General', 'AllowDowngrade', FAppConfig.AllowDowngrade);

      // Network settings
      FAppConfig.ConnectionTimeout := IniFile.ReadInteger('Network', 'ConnectionTimeout', FAppConfig.ConnectionTimeout);
      FAppConfig.MaxRetries := IniFile.ReadInteger('Network', 'MaxRetries', FAppConfig.MaxRetries);
      FAppConfig.UserAgent := IniFile.ReadString('Network', 'UserAgent', FAppConfig.UserAgent);

      // URLs
      UrlCount := IniFile.ReadInteger('URLs', 'Count', 0);
      if UrlCount > 0 then
      begin
        SetLength(FAppConfig.ManifestUrls, UrlCount);
        for i := 0 to UrlCount - 1 do
        begin
          Url := IniFile.ReadString('URLs', 'URL' + IntToStr(i), '');
          if Url <> '' then
            FAppConfig.ManifestUrls[i] := Url;
        end;
      end
      else
      begin
        // Set default URLs for demo
        SetLength(FAppConfig.ManifestUrls, 2);
        FAppConfig.ManifestUrls[0] := 'https://api.github.com/repos/youruser/yourapp/releases/latest';
        FAppConfig.ManifestUrls[1] := 'https://your-cdn.com/updates/manifest.json';
      end;

      // Advanced settings
      FAppConfig.TempFolder := IniFile.ReadString('Advanced', 'TempFolder', FAppConfig.TempFolder);

      // UI settings
      FMinimizeToTray := IniFile.ReadBool('UI', 'MinimizeToTray', FMinimizeToTray);

    finally
      IniFile.Free;
    end;
  end
  else
  begin
    // Set default URLs for demo
    SetLength(FAppConfig.ManifestUrls, 2);
    FAppConfig.ManifestUrls[0] := 'https://api.github.com/repos/youruser/yourapp/releases/latest';
    FAppConfig.ManifestUrls[1] := 'https://your-cdn.com/updates/manifest.json';
  end;
end;

procedure TEnhancedDemoForm.SaveConfiguration;
var
  IniFile: TIniFile;
  IniPath: string;
  i: Integer;
begin
  IniPath := ChangeFileExt(ParamStr(0), '.ini');

  IniFile := TIniFile.Create(IniPath);
  try
    // General settings
    IniFile.WriteString('General', 'AppName', FAppConfig.AppName);
    IniFile.WriteInteger('General', 'CheckInterval', FAppConfig.CheckInterval);
    IniFile.WriteBool('General', 'AutoDownload', FAppConfig.AutoDownload);
    IniFile.WriteBool('General', 'AutoInstall', FAppConfig.AutoInstall);
    IniFile.WriteBool('General', 'AllowDowngrade', FAppConfig.AllowDowngrade);

    // Network settings
    IniFile.WriteInteger('Network', 'ConnectionTimeout', FAppConfig.ConnectionTimeout);
    IniFile.WriteInteger('Network', 'MaxRetries', FAppConfig.MaxRetries);
    IniFile.WriteString('Network', 'UserAgent', FAppConfig.UserAgent);

    // URLs
    IniFile.WriteInteger('URLs', 'Count', Length(FAppConfig.ManifestUrls));
    for i := 0 to Length(FAppConfig.ManifestUrls) - 1 do
      IniFile.WriteString('URLs', 'URL' + IntToStr(i), FAppConfig.ManifestUrls[i]);

    // Advanced settings
    IniFile.WriteString('Advanced', 'TempFolder', FAppConfig.TempFolder);

    // UI settings
    IniFile.WriteBool('UI', 'MinimizeToTray', FMinimizeToTray);

  finally
    IniFile.Free;
  end;
end;

procedure TEnhancedDemoForm.SetupUpdaterComponent;
begin
  // Configure the updater component
  UpdaterUI.Config := FAppConfig;
  UpdaterUI.UIStyle := uisStandard;
  UpdaterUI.ButtonStyle := ubsBoth;
  UpdaterUI.ShowReleaseNotes := True;
  UpdaterUI.ShowProgressDetails := True;
  UpdaterUI.AutoCheck := False; // We'll handle this manually

  // Assign event handlers
  UpdaterUI.OnStateChange := UpdaterStateChange;
  UpdaterUI.OnDownloadProgress := UpdaterDownloadProgress;
  UpdaterUI.OnUpdateDecision := UpdaterUpdateDecision;
  UpdaterUI.OnUpdateComplete := UpdaterComplete;
  UpdaterUI.OnSettingsClick := UpdaterSettingsClick;

  // Update info labels
  LblAppTitle.Caption := FAppConfig.AppName;
  try
    LblVersion.Caption := 'Version: ' + UpdaterUI.Engine.CurrentVersion.ToString;
  except
    LblVersion.Caption := 'Version: Unknown';
  end;
  LblStatus.Caption := 'Ready';
end;

procedure TEnhancedDemoForm.UpdateMenuStates;
begin
  // View menu states
  ActViewCompact.Checked := UpdaterUI.UIStyle = uisCompact;
  ActViewStandard.Checked := UpdaterUI.UIStyle = uisStandard;
  ActViewDetailed.Checked := UpdaterUI.UIStyle = uisDetailed;

  ActShowReleaseNotes.Checked := UpdaterUI.ShowReleaseNotes;
  ActShowProgressDetails.Checked := UpdaterUI.ShowProgressDetails;

  // Auto check state
  ActAutoCheck.Checked := UpdaterUI.AutoCheck;
end;

procedure TEnhancedDemoForm.LogMessage(const Message: string; const Level: string);
var
  TimeStamp: string;
  LogLine: string;
begin
  TimeStamp := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
  LogLine := Format('[%s] %s: %s', [TimeStamp, Level, Message]);

  MemoLog.Lines.Add(LogLine);

  // Auto-scroll to bottom
  SendMessage(MemoLog.Handle, EM_SCROLLCARET, 0, 0);

  // Update status bar
  StatusBar.Panels[0].Text := Message;

  // Keep log size manageable
  if MemoLog.Lines.Count > 1000 then
    MemoLog.Lines.Delete(0);
end;

procedure TEnhancedDemoForm.ShowTrayNotification(const Title, Message: string);
begin
  // This would typically show a system tray notification
  // For now, just log it
  LogMessage(Format('NOTIFICATION: %s - %s', [Title, Message]), 'INFO');
end;

procedure TEnhancedDemoForm.SetLogVisible(const Value: Boolean);
begin
  if FLogVisible <> Value then
  begin
    FLogVisible := Value;
    LogPanel.Visible := Value;
    LogSplitter.Visible := Value;

    if Value then
      LogSplitter.Top := LogPanel.Top - LogSplitter.Height;
  end;
end;

// Action handlers

procedure TEnhancedDemoForm.ActExitExecute(Sender: TObject);
begin
  FMinimizeToTray := False; // Force close
  Close;
end;

procedure TEnhancedDemoForm.ActCheckNowExecute(Sender: TObject);
begin
  LogMessage('Manual update check initiated', 'INFO');
  UpdaterUI.CheckForUpdates;
end;

procedure TEnhancedDemoForm.ActSettingsExecute(Sender: TObject);
begin
  UpdaterSettingsClick(Self);
end;

procedure TEnhancedDemoForm.ActViewCompactExecute(Sender: TObject);
begin
  UpdaterUI.UIStyle := uisCompact;
  UpdateMenuStates;
  LogMessage('UI style changed to Compact', 'INFO');
end;

procedure TEnhancedDemoForm.ActViewStandardExecute(Sender: TObject);
begin
  UpdaterUI.UIStyle := uisStandard;
  UpdateMenuStates;
  LogMessage('UI style changed to Standard', 'INFO');
end;

procedure TEnhancedDemoForm.ActViewDetailedExecute(Sender: TObject);
begin
  UpdaterUI.UIStyle := uisDetailed;
  UpdateMenuStates;
  LogMessage('UI style changed to Detailed', 'INFO');
end;

procedure TEnhancedDemoForm.ActShowReleaseNotesExecute(Sender: TObject);
begin
  UpdaterUI.ShowReleaseNotes := not UpdaterUI.ShowReleaseNotes;
  UpdateMenuStates;
  LogMessage('Release notes visibility: ' + BoolToStr(UpdaterUI.ShowReleaseNotes, True), 'INFO');
end;

procedure TEnhancedDemoForm.ActShowProgressDetailsExecute(Sender: TObject);
begin
  UpdaterUI.ShowProgressDetails := not UpdaterUI.ShowProgressDetails;
  UpdateMenuStates;
  LogMessage('Progress details visibility: ' + BoolToStr(UpdaterUI.ShowProgressDetails, True), 'INFO');
end;

procedure TEnhancedDemoForm.ActAutoCheckExecute(Sender: TObject);
begin
  UpdaterUI.AutoCheck := not UpdaterUI.AutoCheck;
  UpdateMenuStates;
  LogMessage('Auto check enabled: ' + BoolToStr(UpdaterUI.AutoCheck, True), 'INFO');
end;

procedure TEnhancedDemoForm.ActResetUpdaterExecute(Sender: TObject);
begin
  if MessageDlg('Reset updater to initial state?', mtConfirmation,
    [mbYes, mbNo], 0) = mrYes then
  begin
    UpdaterUI.ResetToInitialState;
    LogMessage('Updater reset to initial state', 'INFO');
  end;
end;

procedure TEnhancedDemoForm.ActTestConnectionExecute(Sender: TObject);
var
  i: Integer;
  TestResult: string;
begin
  LogMessage('Testing connection to manifest URLs...', 'INFO');

  for i := 0 to Length(FAppConfig.ManifestUrls) - 1 do
  begin
    LogMessage('Testing: ' + FAppConfig.ManifestUrls[i], 'INFO');

    // This would typically test the connection
    // For demo purposes, just simulate
    TestResult := 'Connection test would be performed here';
    LogMessage(TestResult, 'INFO');
  end;

  ShowMessage('Connection test completed. Check log for details.');
end;

procedure TEnhancedDemoForm.ActAboutExecute(Sender: TObject);
var
  AboutText: string;
begin
  AboutText := 'VittixAutoUpdater Enhanced Demo' + #13#10 +
               'Version: 1.0.0' + #13#10 +
               #13#10 +
               'A comprehensive auto-updater component for Delphi applications.' + #13#10 +
               #13#10 +
               'Features:' + #13#10 +
               '• Automatic update checking' + #13#10 +
               '• Progress tracking' + #13#10 +
               '• Multiple UI styles' + #13#10 +
               '• Comprehensive logging' + #13#10 +
               '• Network configuration' + #13#10 +
               '• Security verification' + #13#10 +
               #13#10 +
               'Copyright (c) 2024';

  ShowMessage(AboutText);
end;

procedure TEnhancedDemoForm.ActShowManualExecute(Sender: TObject);
begin
  // Open the README file or documentation
  ShellExecute(Handle, 'open', PChar('README.md'), nil, nil, SW_SHOWNORMAL);
end;

// Updater event handlers

procedure TEnhancedDemoForm.UpdaterStateChange(Sender: TObject; NewState: TUpdateState;
  const StatusMessage: string);
begin
  LblStatus.Caption := StatusMessage;
  LogMessage('State changed: ' + StatusMessage, 'INFO');

  // Update taskbar progress
  case NewState of
    usChecking, usDownloading:
      TaskBar.ProgressState := TTaskBarProgressState.Indeterminate;
    usError:
      TaskBar.ProgressState := TTaskBarProgressState.Error;
    usComplete:
      TaskBar.ProgressState := TTaskBarProgressState.None;
    else
      TaskBar.ProgressState := TTaskBarProgressState.None;
  end;

  // Show notification for important states
  case NewState of
    usAvailable:
      ShowTrayNotification('Update Available', 'A new version is available for download');
    usComplete:
      ShowTrayNotification('Update Complete', 'Update has been successfully applied');
    usError:
      ShowTrayNotification('Update Error', StatusMessage);
  end;
end;

procedure TEnhancedDemoForm.UpdaterDownloadProgress(Sender: TObject;
  BytesReceived, TotalBytes: Int64; PercentComplete: Integer; var Cancel: Boolean);
begin
  // Update taskbar progress
  TaskBar.ProgressState := TTaskBarProgressState.Normal;
  TaskBar.ProgressValue := PercentComplete;

  // Log progress milestones
  if PercentComplete mod 25 = 0 then
    LogMessage(Format('Download progress: %d%% (%d of %d bytes)',
      [PercentComplete, BytesReceived, TotalBytes]), 'INFO');
end;

procedure TEnhancedDemoForm.UpdaterUpdateDecision(Sender: TObject;
  const Manifest: TUpdateManifest; var Decision: Boolean);
var
  Msg: string;
  Response: Integer;
begin
  Msg := Format('Update Available!%s%sNew Version: %s%sCurrent Version: %s%s%s' +
                'File Size: %d bytes%s%sWould you like to download this update?',
    [#13#10, #13#10,
     Manifest.Version.ToString, #13#10,
     UpdaterUI.Engine.CurrentVersion.ToString, #13#10, #13#10,
     Manifest.FileSize, #13#10, #13#10]);

  if Manifest.ReleaseNotes <> '' then
    Msg := Msg + #13#10 + 'Release Notes:' + #13#10 + Manifest.ReleaseNotes;

  Response := MessageDlg(Msg, mtConfirmation, [mbYes, mbNo, mbCancel], 0);

  Decision := Response = mrYes;

  if Decision then
    LogMessage('User accepted update', 'INFO')
  else
    LogMessage('User declined update', 'INFO');
end;

procedure TEnhancedDemoForm.UpdaterComplete(Sender: TObject; Success: Boolean;
  const ErrorMessage: string);
begin
  TaskBar.ProgressState := TTaskBarProgressState.None;

  if Success then
  begin
    LogMessage('Update completed successfully', 'INFO');

    if MessageDlg('Update completed successfully. Restart application now?',
      mtInformation, [mbYes, mbNo], 0) = mrYes then
    begin
      LogMessage('Restarting application...', 'INFO');
      // Restart application logic would go here
      Application.Terminate;
    end;
  end
  else
  begin
    LogMessage('Update failed: ' + ErrorMessage, 'ERROR');
    ShowMessage('Update failed: ' + ErrorMessage);
  end;
end;

procedure TEnhancedDemoForm.UpdaterSettingsClick(Sender: TObject);
var
  TempConfig: TUpdaterConfig;
begin
  TempConfig := FAppConfig;

  if TUpdateSettingsForm.Execute(TempConfig, Self) then
  begin
    FAppConfig := TempConfig;
    UpdaterUI.Config := FAppConfig;
    SaveConfiguration;

    // Update UI
    LblAppTitle.Caption := FAppConfig.AppName;

    LogMessage('Settings updated and saved', 'INFO');
    ShowMessage('Settings have been updated successfully.');
  end;
end;

end.
