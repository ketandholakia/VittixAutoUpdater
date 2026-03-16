unit VittixAutoUpdaterEnhancedDemo;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, System.IniFiles, System.IOUtils,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls,
  VittixAutoUpdater.Types, VittixAutoUpdater.Engine,
  VittixAutoUpdater.VisualComponent;

type
  TEnhancedDemoForm = class(TForm)
    TopPanel: TPanel;
    LblTitle: TLabel;
    LblVersion: TLabel;
    LblStatus: TLabel;
    BtnCheck: TButton;
    BtnSettings: TButton;
    BtnReset: TButton;
    BtnToggleLog: TButton;
    UpdaterUI: TVittixAutoUpdaterUI;
    LogPanel: TPanel;
    MemoLog: TMemo;
    StatusBar: TStatusBar;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure BtnCheckClick(Sender: TObject);
    procedure BtnSettingsClick(Sender: TObject);
    procedure BtnResetClick(Sender: TObject);
    procedure BtnToggleLogClick(Sender: TObject);
    procedure UpdaterStateChange(Sender: TObject; NewState: TUpdateState;
      const StatusMessage: string);
    procedure UpdaterDownloadProgress(Sender: TObject; BytesReceived,
      TotalBytes: Int64; PercentComplete: Integer; var Cancel: Boolean);
    procedure UpdaterUpdateDecision(Sender: TObject;
      const Manifest: TUpdateManifest; var Decision: Boolean);
    procedure UpdaterComplete(Sender: TObject; Success: Boolean;
      const ErrorMessage: string);
    procedure UpdaterSettingsClick(Sender: TObject);
  private
    FAppConfig: TUpdaterConfig;
    FLogVisible: Boolean;
    function GetConfigFileName: string;
    procedure LoadConfiguration;
    procedure SaveConfiguration;
    procedure SetupUpdaterComponent;
    procedure LogMessage(const Message: string; const Level: string = 'INFO');
    procedure SetLogVisible(const Value: Boolean);
  public
  end;

var
  EnhancedDemoForm: TEnhancedDemoForm;

implementation

{$R *.dfm}

function EditUpdaterConfig(var Config: TUpdaterConfig; AOwner: TComponent): Boolean;
var
  Dialog: TForm;
  BtnOK: TButton;
  BtnCancel: TButton;
  LblAppName: TLabel;
  EditAppName: TEdit;
  LblUrls: TLabel;
  MemoUrls: TMemo;
  LblInterval: TLabel;
  EditInterval: TEdit;
  LblTimeout: TLabel;
  EditTimeout: TEdit;
  LblRetries: TLabel;
  EditRetries: TEdit;
  LblTemp: TLabel;
  EditTemp: TEdit;
  ChkAutoDownload: TCheckBox;
  ChkAutoInstall: TCheckBox;
  TempConfig: TUpdaterConfig;
  Lines: TStringList;
  I: Integer;
begin
  TempConfig := Config;
  Dialog := TForm.Create(AOwner);
  try
    Dialog.Caption := 'Updater Settings';
    Dialog.Position := poScreenCenter;
    Dialog.BorderStyle := bsDialog;
    Dialog.ClientWidth := 520;
    Dialog.ClientHeight := 500;
    Dialog.Font.Name := 'Tahoma';
    Dialog.Font.Size := 9;

    LblAppName := TLabel.Create(Dialog);
    LblAppName.Parent := Dialog;
    LblAppName.Left := 16;
    LblAppName.Top := 16;
    LblAppName.Caption := 'Application Name';

    EditAppName := TEdit.Create(Dialog);
    EditAppName.Parent := Dialog;
    EditAppName.Left := 16;
    EditAppName.Top := 34;
    EditAppName.Width := 320;
    EditAppName.Text := TempConfig.AppName;

    LblUrls := TLabel.Create(Dialog);
    LblUrls.Parent := Dialog;
    LblUrls.Left := 16;
    LblUrls.Top := 68;
    LblUrls.Caption := 'Manifest URLs (one per line)';

    MemoUrls := TMemo.Create(Dialog);
    MemoUrls.Parent := Dialog;
    MemoUrls.Left := 16;
    MemoUrls.Top := 86;
    MemoUrls.Width := 488;
    MemoUrls.Height := 190;
    MemoUrls.ScrollBars := ssVertical;
    for I := 0 to Length(TempConfig.ManifestUrls) - 1 do
      MemoUrls.Lines.Add(TempConfig.ManifestUrls[I]);

    LblInterval := TLabel.Create(Dialog);
    LblInterval.Parent := Dialog;
    LblInterval.Left := 16;
    LblInterval.Top := 292;
    LblInterval.Caption := 'Check Interval (hours)';

    EditInterval := TEdit.Create(Dialog);
    EditInterval.Parent := Dialog;
    EditInterval.Left := 16;
    EditInterval.Top := 310;
    EditInterval.Width := 100;
    EditInterval.Text := IntToStr(TempConfig.CheckInterval);

    LblTimeout := TLabel.Create(Dialog);
    LblTimeout.Parent := Dialog;
    LblTimeout.Left := 136;
    LblTimeout.Top := 292;
    LblTimeout.Caption := 'Timeout (sec)';

    EditTimeout := TEdit.Create(Dialog);
    EditTimeout.Parent := Dialog;
    EditTimeout.Left := 136;
    EditTimeout.Top := 310;
    EditTimeout.Width := 100;
    EditTimeout.Text := IntToStr(TempConfig.ConnectionTimeout);

    LblRetries := TLabel.Create(Dialog);
    LblRetries.Parent := Dialog;
    LblRetries.Left := 256;
    LblRetries.Top := 292;
    LblRetries.Caption := 'Max Retries';

    EditRetries := TEdit.Create(Dialog);
    EditRetries.Parent := Dialog;
    EditRetries.Left := 256;
    EditRetries.Top := 310;
    EditRetries.Width := 100;
    EditRetries.Text := IntToStr(TempConfig.MaxRetries);

    LblTemp := TLabel.Create(Dialog);
    LblTemp.Parent := Dialog;
    LblTemp.Left := 16;
    LblTemp.Top := 348;
    LblTemp.Caption := 'Temp Folder (optional)';

    EditTemp := TEdit.Create(Dialog);
    EditTemp.Parent := Dialog;
    EditTemp.Left := 16;
    EditTemp.Top := 366;
    EditTemp.Width := 488;
    EditTemp.Text := TempConfig.TempFolder;

    ChkAutoDownload := TCheckBox.Create(Dialog);
    ChkAutoDownload.Parent := Dialog;
    ChkAutoDownload.Left := 16;
    ChkAutoDownload.Top := 404;
    ChkAutoDownload.Caption := 'Auto Download';
    ChkAutoDownload.Checked := TempConfig.AutoDownload;

    ChkAutoInstall := TCheckBox.Create(Dialog);
    ChkAutoInstall.Parent := Dialog;
    ChkAutoInstall.Left := 144;
    ChkAutoInstall.Top := 404;
    ChkAutoInstall.Caption := 'Auto Install';
    ChkAutoInstall.Checked := TempConfig.AutoInstall;

    BtnOK := TButton.Create(Dialog);
    BtnOK.Parent := Dialog;
    BtnOK.Caption := 'OK';
    BtnOK.ModalResult := mrOK;
    BtnOK.Default := True;
    BtnOK.Left := 348;
    BtnOK.Top := 448;
    BtnOK.Width := 75;

    BtnCancel := TButton.Create(Dialog);
    BtnCancel.Parent := Dialog;
    BtnCancel.Caption := 'Cancel';
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Cancel := True;
    BtnCancel.Left := 429;
    BtnCancel.Top := 448;
    BtnCancel.Width := 75;

    Result := Dialog.ShowModal = mrOK;
    if not Result then
      Exit;

    if Trim(EditAppName.Text) = '' then
      raise Exception.Create('Application name cannot be empty.');

    TempConfig.AppName := Trim(EditAppName.Text);
    TempConfig.CheckInterval := StrToIntDef(Trim(EditInterval.Text), TempConfig.CheckInterval);
    TempConfig.ConnectionTimeout := StrToIntDef(Trim(EditTimeout.Text), TempConfig.ConnectionTimeout);
    TempConfig.MaxRetries := StrToIntDef(Trim(EditRetries.Text), TempConfig.MaxRetries);
    TempConfig.TempFolder := Trim(EditTemp.Text);
    TempConfig.AutoDownload := ChkAutoDownload.Checked;
    TempConfig.AutoInstall := ChkAutoInstall.Checked;

    Lines := TStringList.Create;
    try
      for I := 0 to MemoUrls.Lines.Count - 1 do
        if Trim(MemoUrls.Lines[I]) <> '' then
          Lines.Add(Trim(MemoUrls.Lines[I]));

      SetLength(TempConfig.ManifestUrls, Lines.Count);
      for I := 0 to Lines.Count - 1 do
        TempConfig.ManifestUrls[I] := Lines[I];
    finally
      Lines.Free;
    end;

    Config := TempConfig;
  finally
    Dialog.Free;
  end;
end;

function TEnhancedDemoForm.GetConfigFileName: string;
begin
  Result := ChangeFileExt(ParamStr(0), '.ini');
end;

procedure TEnhancedDemoForm.FormCreate(Sender: TObject);
begin
  Caption := 'VittixAutoUpdater Demo';
  Position := poScreenCenter;
  FLogVisible := True;

  LoadConfiguration;
  SetupUpdaterComponent;
  SetLogVisible(True);

  LogMessage('Demo started');
  if Length(FAppConfig.ManifestUrls) = 0 then
    LogMessage('No manifest URL configured. Open Settings before checking.', 'WARN');
end;

procedure TEnhancedDemoForm.FormDestroy(Sender: TObject);
begin
  SaveConfiguration;
end;

procedure TEnhancedDemoForm.LoadConfiguration;
var
  IniFile: TIniFile;
  IniPath: string;
  I: Integer;
  UrlCount: Integer;
begin
  FAppConfig := TUpdaterConfig.Default;
  FAppConfig.AppName := 'VittixAutoUpdater Demo';

  IniPath := GetConfigFileName;
  if not TFile.Exists(IniPath) then
    Exit;

  IniFile := TIniFile.Create(IniPath);
  try
    FAppConfig.AppName := IniFile.ReadString('General', 'AppName', FAppConfig.AppName);
    FAppConfig.CheckInterval := IniFile.ReadInteger('General', 'CheckInterval', FAppConfig.CheckInterval);
    FAppConfig.AutoDownload := IniFile.ReadBool('General', 'AutoDownload', FAppConfig.AutoDownload);
    FAppConfig.AutoInstall := IniFile.ReadBool('General', 'AutoInstall', FAppConfig.AutoInstall);
    FAppConfig.AllowDowngrade := IniFile.ReadBool('General', 'AllowDowngrade', FAppConfig.AllowDowngrade);
    FAppConfig.ConnectionTimeout := IniFile.ReadInteger('Network', 'ConnectionTimeout', FAppConfig.ConnectionTimeout);
    FAppConfig.MaxRetries := IniFile.ReadInteger('Network', 'MaxRetries', FAppConfig.MaxRetries);
    FAppConfig.UserAgent := IniFile.ReadString('Network', 'UserAgent', FAppConfig.UserAgent);
    FAppConfig.TempFolder := IniFile.ReadString('Advanced', 'TempFolder', FAppConfig.TempFolder);

    UrlCount := IniFile.ReadInteger('URLs', 'Count', 0);
    SetLength(FAppConfig.ManifestUrls, UrlCount);
    for I := 0 to UrlCount - 1 do
      FAppConfig.ManifestUrls[I] := IniFile.ReadString('URLs', 'URL' + IntToStr(I), '');
  finally
    IniFile.Free;
  end;
end;

procedure TEnhancedDemoForm.SaveConfiguration;
var
  IniFile: TIniFile;
  IniPath: string;
  I: Integer;
begin
  IniPath := GetConfigFileName;
  IniFile := TIniFile.Create(IniPath);
  try
    IniFile.WriteString('General', 'AppName', FAppConfig.AppName);
    IniFile.WriteInteger('General', 'CheckInterval', FAppConfig.CheckInterval);
    IniFile.WriteBool('General', 'AutoDownload', FAppConfig.AutoDownload);
    IniFile.WriteBool('General', 'AutoInstall', FAppConfig.AutoInstall);
    IniFile.WriteBool('General', 'AllowDowngrade', FAppConfig.AllowDowngrade);
    IniFile.WriteInteger('Network', 'ConnectionTimeout', FAppConfig.ConnectionTimeout);
    IniFile.WriteInteger('Network', 'MaxRetries', FAppConfig.MaxRetries);
    IniFile.WriteString('Network', 'UserAgent', FAppConfig.UserAgent);
    IniFile.WriteString('Advanced', 'TempFolder', FAppConfig.TempFolder);

    IniFile.EraseSection('URLs');
    IniFile.WriteInteger('URLs', 'Count', Length(FAppConfig.ManifestUrls));
    for I := 0 to Length(FAppConfig.ManifestUrls) - 1 do
      IniFile.WriteString('URLs', 'URL' + IntToStr(I), FAppConfig.ManifestUrls[I]);
  finally
    IniFile.Free;
  end;
end;

procedure TEnhancedDemoForm.SetupUpdaterComponent;
begin
  UpdaterUI.Config := FAppConfig;
  UpdaterUI.UIStyle := uisStandard;
  UpdaterUI.ButtonStyle := ubsBoth;
  UpdaterUI.ShowReleaseNotes := True;
  UpdaterUI.ShowProgressDetails := True;
  UpdaterUI.AutoCheck := False;

  UpdaterUI.OnStateChange := UpdaterStateChange;
  UpdaterUI.OnDownloadProgress := UpdaterDownloadProgress;
  UpdaterUI.OnUpdateDecision := UpdaterUpdateDecision;
  UpdaterUI.OnUpdateComplete := UpdaterComplete;
  UpdaterUI.OnSettingsClick := UpdaterSettingsClick;

  LblTitle.Caption := FAppConfig.AppName;
  try
    LblVersion.Caption := 'Version: ' + UpdaterUI.Engine.CurrentVersion.ToString;
  except
    LblVersion.Caption := 'Version: Unknown';
  end;
  LblStatus.Caption := 'Ready';
  StatusBar.SimpleText := 'Ready';
end;

procedure TEnhancedDemoForm.LogMessage(const Message: string; const Level: string);
begin
  MemoLog.Lines.Add(Format('[%s] %s: %s',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), Level, Message]));
  MemoLog.SelStart := Length(MemoLog.Text);
  MemoLog.Perform(EM_SCROLLCARET, 0, 0);
  StatusBar.SimpleText := Message;
end;

procedure TEnhancedDemoForm.SetLogVisible(const Value: Boolean);
begin
  FLogVisible := Value;
  LogPanel.Visible := Value;
  if Value then
    BtnToggleLog.Caption := 'Hide Log'
  else
    BtnToggleLog.Caption := 'Show Log';
end;

procedure TEnhancedDemoForm.BtnCheckClick(Sender: TObject);
begin
  if Length(FAppConfig.ManifestUrls) = 0 then
  begin
    MessageDlg('Configure at least one manifest URL in Settings first.',
      mtWarning, [mbOK], 0);
    Exit;
  end;

  LogMessage('Manual update check started');
  UpdaterUI.CheckForUpdates;
end;

procedure TEnhancedDemoForm.BtnSettingsClick(Sender: TObject);
begin
  UpdaterSettingsClick(Sender);
end;

procedure TEnhancedDemoForm.BtnResetClick(Sender: TObject);
begin
  UpdaterUI.ResetToInitialState;
  LogMessage('Updater reset');
end;

procedure TEnhancedDemoForm.BtnToggleLogClick(Sender: TObject);
begin
  SetLogVisible(not FLogVisible);
end;

procedure TEnhancedDemoForm.UpdaterStateChange(Sender: TObject;
  NewState: TUpdateState; const StatusMessage: string);
begin
  LblStatus.Caption := StatusMessage;
  LogMessage('State changed: ' + StatusMessage);
end;

procedure TEnhancedDemoForm.UpdaterDownloadProgress(Sender: TObject;
  BytesReceived, TotalBytes: Int64; PercentComplete: Integer;
  var Cancel: Boolean);
begin
  if (PercentComplete = 0) or (PercentComplete = 100) or
     ((PercentComplete mod 25) = 0) then
    LogMessage(Format('Download progress: %d%%', [PercentComplete]));
end;

procedure TEnhancedDemoForm.UpdaterUpdateDecision(Sender: TObject;
  const Manifest: TUpdateManifest; var Decision: Boolean);
var
  Msg: string;
begin
  Msg := Format('Version %s is available.%s%sDownload this update now?',
    [Manifest.Version.ToString, sLineBreak, sLineBreak]);
  if Manifest.ReleaseNotes <> '' then
    Msg := Msg + sLineBreak + 'Release notes:' + sLineBreak + Manifest.ReleaseNotes;

  Decision := MessageDlg(Msg, mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  if Decision then
    LogMessage('User accepted update')
  else
    LogMessage('User declined update', 'WARN');
end;

procedure TEnhancedDemoForm.UpdaterComplete(Sender: TObject; Success: Boolean;
  const ErrorMessage: string);
begin
  if Success then
  begin
    LogMessage('Update completed successfully');
    MessageDlg('Update completed successfully.', mtInformation, [mbOK], 0);
  end
  else
  begin
    LogMessage('Update failed: ' + ErrorMessage, 'ERROR');
    MessageDlg('Update failed: ' + ErrorMessage, mtError, [mbOK], 0);
  end;
end;

procedure TEnhancedDemoForm.UpdaterSettingsClick(Sender: TObject);
var
  TempConfig: TUpdaterConfig;
begin
  TempConfig := FAppConfig;
  if EditUpdaterConfig(TempConfig, Self) then
  begin
    FAppConfig := TempConfig;
    SetupUpdaterComponent;
    SaveConfiguration;
    LogMessage('Settings updated');
  end;
end;

end.
