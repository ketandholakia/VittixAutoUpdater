unit VittixAutoUpdater.Settings;

interface

uses
  Windows, Messages, SysUtils, Variants,
  Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ExtCtrls, ComCtrls, Buttons, Spin,
  CheckLst, Mask,
  VittixAutoUpdater.Types;

type
  TUpdateSettingsForm = class(TForm)
    PageControl: TPageControl;
    TabGeneral: TTabSheet;
    TabNetwork: TTabSheet;
    TabAdvanced: TTabSheet;
    ButtonPanel: TPanel;
    BtnOK: TButton;
    BtnCancel: TButton;
    BtnApply: TButton;
    BtnReset: TButton;

    // General tab controls
    GroupGeneral: TGroupBox;
    LblAppName: TLabel;
    EditAppName: TEdit;
    LblCheckInterval: TLabel;
    SpinCheckInterval: TSpinEdit;
    LblCheckIntervalUnit: TLabel;
    ChkAutoDownload: TCheckBox;
    ChkAutoInstall: TCheckBox;
    ChkAllowDowngrade: TCheckBox;
    ChkStartWithWindows: TCheckBox;

    GroupNotifications: TGroupBox;
    ChkShowNotifications: TCheckBox;
    ChkSoundNotifications: TCheckBox;
    ChkMinimizeToTray: TCheckBox;

    // Network tab controls
    GroupUrls: TGroupBox;
    LblManifestUrls: TLabel;
    ListManifestUrls: TListBox;
    EditManifestUrl: TEdit;
    BtnAddUrl: TButton;
    BtnRemoveUrl: TButton;
    BtnEditUrl: TButton;
    BtnTestUrl: TButton;

    GroupNetwork: TGroupBox;
    LblConnectionTimeout: TLabel;
    SpinConnectionTimeout: TSpinEdit;
    LblTimeoutUnit: TLabel;
    LblMaxRetries: TLabel;
    SpinMaxRetries: TSpinEdit;
    LblUserAgent: TLabel;
    EditUserAgent: TEdit;

    GroupProxy: TGroupBox;
    ChkUseProxy: TCheckBox;
    LblProxyHost: TLabel;
    EditProxyHost: TEdit;
    LblProxyPort: TLabel;
    SpinProxyPort: TSpinEdit;
    LblProxyUser: TLabel;
    EditProxyUser: TEdit;
    LblProxyPassword: TLabel;
    EditProxyPassword: TEdit;

    // Advanced tab controls
    GroupPaths: TGroupBox;
    LblTempFolder: TLabel;
    EditTempFolder: TEdit;
    BtnBrowseTempFolder: TButton;
    LblBackupFolder: TLabel;
    EditBackupFolder: TEdit;
    BtnBrowseBackupFolder: TButton;

    GroupSecurity: TGroupBox;
    ChkVerifySignature: TCheckBox;
    ChkVerifyChecksum: TCheckBox;
    ChkRequireHttps: TCheckBox;
    LblTrustedPublishers: TLabel;
    ListTrustedPublishers: TCheckListBox;
    BtnAddPublisher: TButton;
    BtnRemovePublisher: TButton;

    GroupLogging: TGroupBox;
    ChkEnableLogging: TCheckBox;
    LblLogLevel: TLabel;
    ComboLogLevel: TComboBox;
    LblLogFile: TLabel;
    EditLogFile: TEdit;
    BtnBrowseLogFile: TButton;
    LblMaxLogSize: TLabel;
    SpinMaxLogSize: TSpinEdit;
    LblLogSizeUnit: TLabel;

    // Dialogs
    OpenDialog: TOpenDialog;
    SaveDialog: TSaveDialog;
    FolderDialog: TFileOpenDialog;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure BtnOKClick(Sender: TObject);
    procedure BtnCancelClick(Sender: TObject);
    procedure BtnApplyClick(Sender: TObject);
    procedure BtnResetClick(Sender: TObject);

    // URL management
    procedure BtnAddUrlClick(Sender: TObject);
    procedure BtnRemoveUrlClick(Sender: TObject);
    procedure BtnEditUrlClick(Sender: TObject);
    procedure BtnTestUrlClick(Sender: TObject);
    procedure ListManifestUrlsClick(Sender: TObject);
    procedure EditManifestUrlKeyPress(Sender: TObject; var Key: Char);

    // Folder browsing
    procedure BtnBrowseTempFolderClick(Sender: TObject);
    procedure BtnBrowseBackupFolderClick(Sender: TObject);
    procedure BtnBrowseLogFileClick(Sender: TObject);

    // Publisher management
    procedure BtnAddPublisherClick(Sender: TObject);
    procedure BtnRemovePublisherClick(Sender: TObject);

    // Control state management
    procedure ChkUseProxyClick(Sender: TObject);
    procedure ChkEnableLoggingClick(Sender: TObject);
    procedure UpdateControlStates;
    procedure ValidateSettings;

  private
    FConfig: TUpdaterConfig;
    FOriginalConfig: TUpdaterConfig;
    FModified: Boolean;

    procedure LoadConfig(const Config: TUpdaterConfig);
    procedure SaveConfig(var Config: TUpdaterConfig);
    procedure LoadDefaults;
    procedure SetModified(const Value: Boolean);
    procedure UpdateApplyButton;

    function ValidateUrl(const Url: string): Boolean;
    function TestManifestUrl(const Url: string): Boolean;

    // Registry functions for startup
    function IsRegisteredForStartup: Boolean;
    procedure RegisterForStartup;
    procedure UnregisterFromStartup;

    // Event handlers
    procedure OnControlChanged(Sender: TObject);

  public
    class function Execute(var Config: TUpdaterConfig; AOwner: TComponent = nil): Boolean;

    property Modified: Boolean read FModified write SetModified;
  end;

implementation

uses
  FileCtrl, ShellAPI, Registry;

{$R *.dfm}

class function TUpdateSettingsForm.Execute(var Config: TUpdaterConfig; AOwner: TComponent): Boolean;
begin
  Result := False;
  with TUpdateSettingsForm.Create(AOwner) do
  try
    LoadConfig(Config);
    Result := ShowModal = mrOK;
    if Result then
      SaveConfig(Config);
  finally
    Free;
  end;
end;

procedure TUpdateSettingsForm.FormCreate(Sender: TObject);
begin
  FModified := False;

  // Initialize combo boxes
  ComboLogLevel.Items.Clear;
  ComboLogLevel.Items.AddStrings(['Error', 'Warning', 'Info', 'Debug', 'Verbose']);
  ComboLogLevel.ItemIndex := 2; // Info

  // Set initial control states
  UpdateControlStates;

  // Setup folder dialog
  FolderDialog.Options := [fdoPickFolders, fdoPathMustExist];
end;

procedure TUpdateSettingsForm.FormDestroy(Sender: TObject);
begin
  // Clean up if needed
end;

procedure TUpdateSettingsForm.LoadConfig(const Config: TUpdaterConfig);
var
  i: Integer;
begin
  FOriginalConfig := Config;
  FConfig := Config;

  // General tab
  EditAppName.Text := Config.AppName;
  SpinCheckInterval.Value := Config.CheckInterval;
  ChkAutoDownload.Checked := Config.AutoDownload;
  ChkAutoInstall.Checked := Config.AutoInstall;
  ChkAllowDowngrade.Checked := Config.AllowDowngrade;

  // Load manifest URLs
  ListManifestUrls.Items.Clear;
  for i := 0 to Length(Config.ManifestUrls) - 1 do
    ListManifestUrls.Items.Add(Config.ManifestUrls[i]);

  // Network tab
  SpinConnectionTimeout.Value := Config.ConnectionTimeout;
  SpinMaxRetries.Value := Config.MaxRetries;
  EditUserAgent.Text := Config.UserAgent;

  // Proxy settings (assuming these are added to TUpdaterConfig)
  // ChkUseProxy.Checked := Config.UseProxy;
  // EditProxyHost.Text := Config.ProxyHost;
  // SpinProxyPort.Value := Config.ProxyPort;
  // EditProxyUser.Text := Config.ProxyUser;
  // EditProxyPassword.Text := Config.ProxyPassword;

  // Advanced tab
  EditTempFolder.Text := Config.TempFolder;
  // EditBackupFolder.Text := Config.BackupFolder; // If this exists

  // Load registry settings for startup
  ChkStartWithWindows.Checked := IsRegisteredForStartup;

  UpdateControlStates;
  FModified := False;
end;

procedure TUpdateSettingsForm.SaveConfig(var Config: TUpdaterConfig);
var
  i: Integer;
begin
  // General tab
  Config.AppName := EditAppName.Text;
  Config.CheckInterval := SpinCheckInterval.Value;
  Config.AutoDownload := ChkAutoDownload.Checked;
  Config.AutoInstall := ChkAutoInstall.Checked;
  Config.AllowDowngrade := ChkAllowDowngrade.Checked;

  // Save manifest URLs
  SetLength(Config.ManifestUrls, ListManifestUrls.Items.Count);
  for i := 0 to ListManifestUrls.Items.Count - 1 do
    Config.ManifestUrls[i] := ListManifestUrls.Items[i];

  // Network tab
  Config.ConnectionTimeout := SpinConnectionTimeout.Value;
  Config.MaxRetries := SpinMaxRetries.Value;
  Config.UserAgent := EditUserAgent.Text;

  // Advanced tab
  Config.TempFolder := EditTempFolder.Text;

  // Handle startup registration
  if ChkStartWithWindows.Checked then
    RegisterForStartup
  else
    UnregisterFromStartup;
end;

procedure TUpdateSettingsForm.LoadDefaults;
begin
  LoadConfig(TUpdaterConfig.Default);
  FModified := True;
  UpdateApplyButton;
end;

procedure TUpdateSettingsForm.SetModified(const Value: Boolean);
begin
  if FModified <> Value then
  begin
    FModified := Value;
    UpdateApplyButton;
  end;
end;

procedure TUpdateSettingsForm.UpdateApplyButton;
begin
  BtnApply.Enabled := FModified;
end;

procedure TUpdateSettingsForm.UpdateControlStates;
begin
  // URL list management
  BtnRemoveUrl.Enabled := ListManifestUrls.ItemIndex >= 0;
  BtnEditUrl.Enabled := ListManifestUrls.ItemIndex >= 0;
  BtnTestUrl.Enabled := ListManifestUrls.ItemIndex >= 0;

  // Proxy controls
  EditProxyHost.Enabled := ChkUseProxy.Checked;
  SpinProxyPort.Enabled := ChkUseProxy.Checked;
  EditProxyUser.Enabled := ChkUseProxy.Checked;
  EditProxyPassword.Enabled := ChkUseProxy.Checked;
  LblProxyHost.Enabled := ChkUseProxy.Checked;
  LblProxyPort.Enabled := ChkUseProxy.Checked;
  LblProxyUser.Enabled := ChkUseProxy.Checked;
  LblProxyPassword.Enabled := ChkUseProxy.Checked;

  // Logging controls
  ComboLogLevel.Enabled := ChkEnableLogging.Checked;
  EditLogFile.Enabled := ChkEnableLogging.Checked;
  BtnBrowseLogFile.Enabled := ChkEnableLogging.Checked;
  SpinMaxLogSize.Enabled := ChkEnableLogging.Checked;
  LblLogLevel.Enabled := ChkEnableLogging.Checked;
  LblLogFile.Enabled := ChkEnableLogging.Checked;
  LblMaxLogSize.Enabled := ChkEnableLogging.Checked;
  LblLogSizeUnit.Enabled := ChkEnableLogging.Checked;

  // Publisher list management
  BtnRemovePublisher.Enabled := ListTrustedPublishers.ItemIndex >= 0;
end;

procedure TUpdateSettingsForm.ValidateSettings;
var
  i: Integer;
  ErrorMsg: string;
begin
  ErrorMsg := '';

  // Validate app name
  if Trim(EditAppName.Text) = '' then
    ErrorMsg := ErrorMsg + '- Application name cannot be empty' + #13#10;

  // Validate URLs
  for i := 0 to ListManifestUrls.Items.Count - 1 do
  begin
    if not ValidateUrl(ListManifestUrls.Items[i]) then
    begin
      ErrorMsg := ErrorMsg + '- Invalid URL: ' + ListManifestUrls.Items[i] + #13#10;
      Break;
    end;
  end;

  // Validate temp folder
  if (Trim(EditTempFolder.Text) <> '') and
     not DirectoryExists(EditTempFolder.Text) then
    ErrorMsg := ErrorMsg + '- Temp folder does not exist: ' + EditTempFolder.Text + #13#10;

  // Validate proxy settings
  if ChkUseProxy.Checked then
  begin
    if Trim(EditProxyHost.Text) = '' then
      ErrorMsg := ErrorMsg + '- Proxy host cannot be empty when proxy is enabled' + #13#10;
    if SpinProxyPort.Value <= 0 then
      ErrorMsg := ErrorMsg + '- Proxy port must be greater than 0' + #13#10;
  end;

  if ErrorMsg <> '' then
    raise Exception.Create('Validation errors:' + #13#10 + ErrorMsg);
end;

function TUpdateSettingsForm.ValidateUrl(const Url: string): Boolean;
var
  LowerUrl: string;
begin
  LowerUrl := LowerCase(Trim(Url));
  Result := (LowerUrl <> '') and
            ((Pos('http://', LowerUrl) = 1) or (Pos('https://', LowerUrl) = 1)) and
            (Pos(' ', LowerUrl) = 0) and
            (Length(LowerUrl) > 10);
end;

function TUpdateSettingsForm.TestManifestUrl(const Url: string): Boolean;
begin
  Result := ValidateUrl(Url);
end;

// Button event handlers

procedure TUpdateSettingsForm.BtnOKClick(Sender: TObject);
begin
  try
    ValidateSettings;
    SaveConfig(FConfig);
    ModalResult := mrOK;
  except
    on E: Exception do
    begin
      ShowMessage('Cannot save settings: ' + E.Message);
      ModalResult := mrNone;
    end;
  end;
end;

procedure TUpdateSettingsForm.BtnCancelClick(Sender: TObject);
begin
  if FModified then
  begin
    case MessageDlg('Settings have been modified. Do you want to save changes?',
      mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrYes: BtnOKClick(nil);
      mrCancel: ModalResult := mrNone;
    end;
  end;
end;

procedure TUpdateSettingsForm.BtnApplyClick(Sender: TObject);
begin
  try
    ValidateSettings;
    SaveConfig(FConfig);
    FModified := False;
    UpdateApplyButton;
    ShowMessage('Settings applied successfully.');
  except
    on E: Exception do
      ShowMessage('Cannot apply settings: ' + E.Message);
  end;
end;

procedure TUpdateSettingsForm.BtnResetClick(Sender: TObject);
begin
  if MessageDlg('Reset all settings to default values?', mtConfirmation,
    [mbYes, mbNo], 0) = mrYes then
  begin
    LoadDefaults;
  end;
end;

// URL management

procedure TUpdateSettingsForm.BtnAddUrlClick(Sender: TObject);
var
  Url: string;
begin
  Url := Trim(EditManifestUrl.Text);
  if Url <> '' then
  begin
    if ValidateUrl(Url) then
    begin
      if ListManifestUrls.Items.IndexOf(Url) < 0 then
      begin
        ListManifestUrls.Items.Add(Url);
        EditManifestUrl.Clear;
        SetModified(True);
      end
      else
        ShowMessage('URL already exists in the list.');
    end
    else
      ShowMessage('Invalid URL format.');
  end;
end;

procedure TUpdateSettingsForm.BtnRemoveUrlClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := ListManifestUrls.ItemIndex;
  if Index >= 0 then
  begin
    ListManifestUrls.Items.Delete(Index);
    SetModified(True);
    UpdateControlStates;
  end;
end;

procedure TUpdateSettingsForm.BtnEditUrlClick(Sender: TObject);
var
  Index: Integer;
  NewUrl: string;
begin
  Index := ListManifestUrls.ItemIndex;
  if Index >= 0 then
  begin
    NewUrl := ListManifestUrls.Items[Index];
    if InputQuery('Edit URL', 'Manifest URL:', NewUrl) then
    begin
      if ValidateUrl(NewUrl) then
      begin
        ListManifestUrls.Items[Index] := NewUrl;
        SetModified(True);
      end
      else
        ShowMessage('Invalid URL format.');
    end;
  end;
end;

procedure TUpdateSettingsForm.BtnTestUrlClick(Sender: TObject);
var
  Index: Integer;
  Url: string;
begin
  Index := ListManifestUrls.ItemIndex;
  if Index >= 0 then
  begin
    Url := ListManifestUrls.Items[Index];
    if TestManifestUrl(Url) then
      ShowMessage('URL format validation passed.')
    else
      ShowMessage('URL format validation failed.');
  end;
end;

procedure TUpdateSettingsForm.ListManifestUrlsClick(Sender: TObject);
begin
  UpdateControlStates;
end;

procedure TUpdateSettingsForm.EditManifestUrlKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then // Enter key
  begin
    BtnAddUrlClick(nil);
    Key := #0;
  end;
end;

// Folder browsing

procedure TUpdateSettingsForm.BtnBrowseTempFolderClick(Sender: TObject);
begin
  FolderDialog.Title := 'Select Temporary Folder';
  if EditTempFolder.Text <> '' then
    FolderDialog.DefaultFolder := EditTempFolder.Text;

  if FolderDialog.Execute then
  begin
    EditTempFolder.Text := FolderDialog.FileName;
    SetModified(True);
  end;
end;

procedure TUpdateSettingsForm.BtnBrowseBackupFolderClick(Sender: TObject);
begin
  FolderDialog.Title := 'Select Backup Folder';
  if EditBackupFolder.Text <> '' then
    FolderDialog.DefaultFolder := EditBackupFolder.Text;

  if FolderDialog.Execute then
  begin
    EditBackupFolder.Text := FolderDialog.FileName;
    SetModified(True);
  end;
end;

procedure TUpdateSettingsForm.BtnBrowseLogFileClick(Sender: TObject);
begin
  SaveDialog.Title := 'Select Log File';
  SaveDialog.Filter := 'Log Files (*.log)|*.log|Text Files (*.txt)|*.txt|All Files (*.*)|*.*';
  SaveDialog.DefaultExt := 'log';
  if EditLogFile.Text <> '' then
    SaveDialog.FileName := EditLogFile.Text;

  if SaveDialog.Execute then
  begin
    EditLogFile.Text := SaveDialog.FileName;
    SetModified(True);
  end;
end;

// Publisher management

procedure TUpdateSettingsForm.BtnAddPublisherClick(Sender: TObject);
var
  Publisher: string;
begin
  if InputQuery('Add Trusted Publisher', 'Publisher Name or Certificate Thumbprint:', Publisher) then
  begin
    if Trim(Publisher) <> '' then
    begin
      ListTrustedPublishers.Items.Add(Publisher);
      ListTrustedPublishers.Checked[ListTrustedPublishers.Items.Count - 1] := True;
      SetModified(True);
    end;
  end;
end;

procedure TUpdateSettingsForm.BtnRemovePublisherClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := ListTrustedPublishers.ItemIndex;
  if Index >= 0 then
  begin
    ListTrustedPublishers.Items.Delete(Index);
    SetModified(True);
    UpdateControlStates;
  end;
end;

// Control state event handlers

procedure TUpdateSettingsForm.ChkUseProxyClick(Sender: TObject);
begin
  UpdateControlStates;
  SetModified(True);
end;

procedure TUpdateSettingsForm.ChkEnableLoggingClick(Sender: TObject);
begin
  UpdateControlStates;
  SetModified(True);
end;

// Registry functions for startup

function TUpdateSettingsForm.IsRegisteredForStartup: Boolean;
var
  Registry: TRegistry;
  AppPath: string;
begin
  Result := False;
  Registry := TRegistry.Create;
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    if Registry.OpenKey('Software\Microsoft\Windows\CurrentVersion\Run', False) then
    begin
      AppPath := ParamStr(0);
      Result := Registry.ValueExists(EditAppName.Text) and
                (Registry.ReadString(EditAppName.Text) = AppPath);
    end;
  finally
    Registry.Free;
  end;
end;

procedure TUpdateSettingsForm.RegisterForStartup;
var
  Registry: TRegistry;
  AppPath: string;
begin
  Registry := TRegistry.Create;
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    if Registry.OpenKey('Software\Microsoft\Windows\CurrentVersion\Run', True) then
    begin
      AppPath := ParamStr(0);
      Registry.WriteString(EditAppName.Text, AppPath);
    end;
  finally
    Registry.Free;
  end;
end;

procedure TUpdateSettingsForm.UnregisterFromStartup;
var
  Registry: TRegistry;
begin
  Registry := TRegistry.Create;
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    if Registry.OpenKey('Software\Microsoft\Windows\CurrentVersion\Run', False) then
    begin
      if Registry.ValueExists(EditAppName.Text) then
        Registry.DeleteValue(EditAppName.Text);
    end;
  finally
    Registry.Free;
  end;
end;

procedure TUpdateSettingsForm.OnControlChanged(Sender: TObject);
begin
  Modified := True;
end;

end.
