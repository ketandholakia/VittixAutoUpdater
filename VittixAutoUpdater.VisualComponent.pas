unit VittixAutoUpdater.VisualComponent;

interface

uses
  System.Classes, System.SysUtils,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.ComCtrls,
  Vcl.Forms, Vcl.Graphics,
  VittixAutoUpdater.Types, VittixAutoUpdater.Engine;

type
  TVittixAutoUpdaterUI = class(TCustomPanel)
  private
    FEngine: TUpdateEngine;
    FCurrentManifest: TUpdateManifest;

    // --- UI Controls ---
    FHeaderPanel: TPanel;
    FStatusLabel: TLabel;
    FStateLabel: TLabel;

    FProgressBar: TProgressBar;

    FNotesPanel: TPanel;
    FNotesMemo: TMemo;

    FButtonPanel: TPanel;
    FBtnCheck: TButton;
    FBtnDownload: TButton;
    FBtnInstall: TButton;
    FBtnCancel: TButton;

    // ===== Design-time property accessors =====
    function GetAppName: string;
    procedure SetAppName(const Value: string);

    function GetManifestUrls: TArray<string>;
    procedure SetManifestUrls(const Value: TArray<string>);

    function GetConnectionTimeout: Integer;
    procedure SetConnectionTimeout(Value: Integer);

    function GetMaxRetries: Integer;
    procedure SetMaxRetries(Value: Integer);

    function GetTempFolder: string;
    procedure SetTempFolder(const Value: string);

    function GetCheckInterval: Integer;
    procedure SetCheckInterval(Value: Integer);

    function GetAutoDownload: Boolean;
    procedure SetAutoDownload(Value: Boolean);

    function GetAutoInstall: Boolean;
    procedure SetAutoInstall(Value: Boolean);

    function GetAllowDowngrade: Boolean;
    procedure SetAllowDowngrade(Value: Boolean);

    function GetConfig: TUpdaterConfig;
    procedure SetConfig(const Value: TUpdaterConfig);

    // Engine event handlers
    procedure OnStateChangeHandler(
      Sender: TObject;
      NewState: TUpdateState;
      const Status: string);

    procedure OnDownloadProgressHandler(
      Sender: TObject;
      BytesReceived, TotalBytes: Int64;
      var Cancel: Boolean);

    // Button handlers
    procedure DoCheckClick(Sender: TObject);
    procedure DoDownloadClick(Sender: TObject);
    procedure DoInstallClick(Sender: TObject);
    procedure DoCancelClick(Sender: TObject);

    procedure UpdateButtons;

  protected
    procedure Loaded; override;
    procedure Resize; override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure CheckForUpdates;
    procedure DownloadUpdate;
    procedure InstallUpdate;
    procedure CancelUpdate;

    property Engine: TUpdateEngine read FEngine;
    property Manifest: TUpdateManifest read FCurrentManifest;

  published
    property Align;
    property Anchors;
    property Color;

    // ===== FULL DESIGN-TIME SETTINGS =====
    property AppName: string
      read GetAppName write SetAppName;

    property ManifestUrls: TArray<string>
      read GetManifestUrls write SetManifestUrls;

    property ConnectionTimeout: Integer
      read GetConnectionTimeout write SetConnectionTimeout;

    property MaxRetries: Integer
      read GetMaxRetries write SetMaxRetries;

    property TempFolder: string
      read GetTempFolder write SetTempFolder;

    property CheckInterval: Integer
      read GetCheckInterval write SetCheckInterval;

    property AutoDownload: Boolean
      read GetAutoDownload write SetAutoDownload;

    property AutoInstall: Boolean
      read GetAutoInstall write SetAutoInstall;

    property AllowDowngrade: Boolean
      read GetAllowDowngrade write SetAllowDowngrade;

    // Keep full config if needed
    property Config: TUpdaterConfig
      read GetConfig write SetConfig;
  end;

procedure Register;

implementation

uses
  System.TypInfo;

{ TVittixAutoUpdaterUI }

constructor TVittixAutoUpdaterUI.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  Width  := 480;
  Height := 320;
  BevelOuter := bvLowered;
  ControlStyle := ControlStyle + [csOpaque];

  // ================= HEADER =================
  FHeaderPanel := TPanel.Create(Self);
  FHeaderPanel.Parent := Self;
  FHeaderPanel.Align := alTop;
  FHeaderPanel.Height := 60;
  FHeaderPanel.BevelOuter := bvNone;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := FHeaderPanel;
  FStatusLabel.Align := alTop;
  FStatusLabel.Caption := 'Updater Ready';
  FStatusLabel.Font.Size := 12;
  FStatusLabel.Font.Style := [fsBold];

  FStateLabel := TLabel.Create(Self);
  FStateLabel.Parent := FHeaderPanel;
  FStateLabel.Align := alBottom;
  FStateLabel.Caption := 'Idle';
  FStateLabel.Font.Color := clGray;

  // ================= PROGRESS =================
  FProgressBar := TProgressBar.Create(Self);
  FProgressBar.Parent := Self;
  FProgressBar.Align := alBottom;
  FProgressBar.Min := 0;
  FProgressBar.Max := 100;
  FProgressBar.Height := 24;

  // ================= RELEASE NOTES =================
  FNotesPanel := TPanel.Create(Self);
  FNotesPanel.Parent := Self;
  FNotesPanel.Align := alClient;
  FNotesPanel.Caption := 'Release Notes';
  FNotesPanel.BevelOuter := bvLowered;

  FNotesMemo := TMemo.Create(Self);
  FNotesMemo.Parent := FNotesPanel;
  FNotesMemo.Align := alClient;
  FNotesMemo.ReadOnly := True;
  FNotesMemo.ScrollBars := ssVertical;

  // ================= BUTTONS =================
  FButtonPanel := TPanel.Create(Self);
  FButtonPanel.Parent := Self;
  FButtonPanel.Align := alBottom;
  FButtonPanel.Height := 40;
  FButtonPanel.BevelOuter := bvNone;

  FBtnCheck := TButton.Create(Self);
  FBtnCheck.Parent := FButtonPanel;
  FBtnCheck.Caption := 'Check';
  FBtnCheck.Left := 10;
  FBtnCheck.Top := 8;
  FBtnCheck.OnClick := DoCheckClick;

  FBtnDownload := TButton.Create(Self);
  FBtnDownload.Parent := FButtonPanel;
  FBtnDownload.Caption := 'Download';
  FBtnDownload.Left := 100;
  FBtnDownload.Top := 8;
  FBtnDownload.OnClick := DoDownloadClick;

  FBtnInstall := TButton.Create(Self);
  FBtnInstall.Parent := FButtonPanel;
  FBtnInstall.Caption := 'Install';
  FBtnInstall.Left := 200;
  FBtnInstall.Top := 8;
  FBtnInstall.OnClick := DoInstallClick;

  FBtnCancel := TButton.Create(Self);
  FBtnCancel.Parent := FButtonPanel;
  FBtnCancel.Caption := 'Cancel';
  FBtnCancel.Left := 300;
  FBtnCancel.Top := 8;
  FBtnCancel.OnClick := DoCancelClick;

  // ================= ENGINE =================
  FEngine := TUpdateEngine.Create(TUpdaterConfig.Default);
  FEngine.OnStateChange := OnStateChangeHandler;
  FEngine.OnDownloadProgress := OnDownloadProgressHandler;

  UpdateButtons;
end;

destructor TVittixAutoUpdaterUI.Destroy;
begin
  FEngine.Free;
  inherited;
end;

procedure TVittixAutoUpdaterUI.Loaded;
begin
  inherited Loaded;
end;

procedure TVittixAutoUpdaterUI.Resize;
begin
  inherited;
end;

// ======== DESIGN-TIME PROPERTY METHODS ========

function TVittixAutoUpdaterUI.GetConfig: TUpdaterConfig;
begin
  Result := FEngine.Config;
end;

procedure TVittixAutoUpdaterUI.SetConfig(const Value: TUpdaterConfig);
begin
  FEngine.Config := Value;
end;

function TVittixAutoUpdaterUI.GetAppName: string;
begin
  Result := FEngine.Config.AppName;
end;

procedure TVittixAutoUpdaterUI.SetAppName(const Value: string);
var
  C: TUpdaterConfig;
begin
  C := FEngine.Config;
  C.AppName := Value;
  FEngine.Config := C;
end;

function TVittixAutoUpdaterUI.GetManifestUrls: TArray<string>;
begin
  Result := FEngine.Config.ManifestUrls;
end;

procedure TVittixAutoUpdaterUI.SetManifestUrls(const Value: TArray<string>);
var
  C: TUpdaterConfig;
begin
  C := FEngine.Config;
  C.ManifestUrls := Value;
  FEngine.Config := C;
end;

function TVittixAutoUpdaterUI.GetConnectionTimeout: Integer;
begin
  Result := FEngine.Config.ConnectionTimeout;
end;

procedure TVittixAutoUpdaterUI.SetConnectionTimeout(Value: Integer);
var
  C: TUpdaterConfig;
begin
  C := FEngine.Config;
  C.ConnectionTimeout := Value;
  FEngine.Config := C;
end;

function TVittixAutoUpdaterUI.GetMaxRetries: Integer;
begin
  Result := FEngine.Config.MaxRetries;
end;

procedure TVittixAutoUpdaterUI.SetMaxRetries(Value: Integer);
var
  C: TUpdaterConfig;
begin
  C := FEngine.Config;
  C.MaxRetries := Value;
  FEngine.Config := C;
end;

function TVittixAutoUpdaterUI.GetTempFolder: string;
begin
  Result := FEngine.Config.TempFolder;
end;

procedure TVittixAutoUpdaterUI.SetTempFolder(const Value: string);
var
  C: TUpdaterConfig;
begin
  C := FEngine.Config;
  C.TempFolder := Value;
  FEngine.Config := C;
end;

function TVittixAutoUpdaterUI.GetCheckInterval: Integer;
begin
  Result := FEngine.Config.CheckInterval;
end;

procedure TVittixAutoUpdaterUI.SetCheckInterval(Value: Integer);
var
  C: TUpdaterConfig;
begin
  C := FEngine.Config;
  C.CheckInterval := Value;
  FEngine.Config := C;
end;

function TVittixAutoUpdaterUI.GetAutoDownload: Boolean;
begin
  Result := FEngine.Config.AutoDownload;
end;

procedure TVittixAutoUpdaterUI.SetAutoDownload(Value: Boolean);
var
  C: TUpdaterConfig;
begin
  C := FEngine.Config;
  C.AutoDownload := Value;
  FEngine.Config := C;
end;

function TVittixAutoUpdaterUI.GetAutoInstall: Boolean;
begin
  Result := FEngine.Config.AutoInstall;
end;

procedure TVittixAutoUpdaterUI.SetAutoInstall(Value: Boolean);
var
  C: TUpdaterConfig;
begin
  C := FEngine.Config;
  C.AutoInstall := Value;
  FEngine.Config := C;
end;

function TVittixAutoUpdaterUI.GetAllowDowngrade: Boolean;
begin
  Result := FEngine.Config.AllowDowngrade;
end;

procedure TVittixAutoUpdaterUI.SetAllowDowngrade(Value: Boolean);
var
  C: TUpdaterConfig;
begin
  C := FEngine.Config;
  C.AllowDowngrade := Value;
  FEngine.Config := C;
end;

// ======== ENGINE EVENT HANDLERS ========

procedure TVittixAutoUpdaterUI.OnStateChangeHandler(
  Sender: TObject;
  NewState: TUpdateState;
  const Status: string);
begin
  FStatusLabel.Caption := Status;
  FStateLabel.Caption := GetEnumName(TypeInfo(TUpdateState), Ord(NewState));

  case NewState of
    usDownloading:
      FProgressBar.Position := 0;

    usAvailable:
      FNotesMemo.Lines.Text := FCurrentManifest.ReleaseNotes;

    usComplete:
      FProgressBar.Position := 100;
  end;

  UpdateButtons;
end;

procedure TVittixAutoUpdaterUI.OnDownloadProgressHandler(
  Sender: TObject;
  BytesReceived, TotalBytes: Int64;
  var Cancel: Boolean);
begin
  if TotalBytes > 0 then
    FProgressBar.Position :=
      Round((BytesReceived / TotalBytes) * 100);
end;

// ======== BUTTON LOGIC ========

procedure TVittixAutoUpdaterUI.UpdateButtons;
begin
  FBtnCheck.Enabled :=
    (FEngine.State = usIdle) or (FEngine.State = usFailed);

  FBtnDownload.Enabled :=
    (FEngine.State = usAvailable);

  FBtnInstall.Enabled :=
    (FEngine.State = usVerifying);

  FBtnCancel.Enabled :=
    (FEngine.State in [usChecking, usDownloading]);
end;

procedure TVittixAutoUpdaterUI.DoCheckClick(Sender: TObject);
begin
  CheckForUpdates;
end;

procedure TVittixAutoUpdaterUI.DoDownloadClick(Sender: TObject);
begin
  DownloadUpdate;
end;

procedure TVittixAutoUpdaterUI.DoInstallClick(Sender: TObject);
begin
  InstallUpdate;
end;

procedure TVittixAutoUpdaterUI.DoCancelClick(Sender: TObject);
begin
  CancelUpdate;
end;

// ======== PUBLIC METHODS ========

procedure TVittixAutoUpdaterUI.CheckForUpdates;
begin
  FEngine.CheckForUpdate(
    procedure(Result: TUpdateCheckResult;
      const Manifest: TUpdateManifest; const ErrorMsg: string)
    begin
      FCurrentManifest := Manifest;

      case Result of
        ucrUpdateAvailable:
          FNotesMemo.Lines.Text := Manifest.ReleaseNotes;
        ucrNoUpdateAvailable:
          FNotesMemo.Lines.Text := 'Your application is up to date.';
        ucrError:
          FNotesMemo.Lines.Text := 'Error: ' + ErrorMsg;
      end;
    end);
end;

procedure TVittixAutoUpdaterUI.DownloadUpdate;
begin
  if FEngine.State = usAvailable then
    FEngine.DownloadUpdate(FCurrentManifest);
end;

procedure TVittixAutoUpdaterUI.InstallUpdate;
begin
  if FEngine.State in [usVerifying, usDownloading] then
    FEngine.ApplyUpdate;
end;

procedure TVittixAutoUpdaterUI.CancelUpdate;
begin
  FEngine.Cancel;
end;

procedure Register;
begin
  RegisterComponents('VI_CON', [TVittixAutoUpdaterUI]);
end;

end.
