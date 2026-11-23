unit VittixAutoUpdater.VisualComponent;

interface

uses
  System.Classes, System.SysUtils, System.Types, System.UITypes,
  System.Generics.Collections, System.SyncObjs,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  Vcl.Buttons, Vcl.Forms, Vcl.Dialogs, Vcl.Imaging.pngimage,
  VittixAutoUpdater.Types, VittixAutoUpdater.Engine;

type
  TUpdateUIStyle = (uisCompact, uisStandard, uisDetailed);
  TUpdateButtonStyle = (ubsAutomatic, ubsManual, ubsBoth);

  // Events
  TUpdateStateChangeEvent = procedure(Sender: TObject; NewState: TUpdateState;
    const StatusMessage: string) of object;
  TVittixDownloadProgressEvent = procedure(Sender: TObject; BytesReceived, TotalBytes: Int64;
    PercentComplete: Integer; var Cancel: Boolean) of object;
  TUpdateDecisionEvent = procedure(Sender: TObject; const Manifest: TUpdateManifest;
    var Decision: Boolean) of object;
  TUpdateCompleteEvent = procedure(Sender: TObject; Success: Boolean;
    const ErrorMessage: string) of object;

  IProgressCancelState = interface
    ['{31E669D2-2F04-40A7-B7D6-6A4335AEAEF7}']
    procedure SetCancelled(Value: Boolean);
    function IsCancelled: Boolean;
  end;

  TQueuedUIEventKind = (queState, queProgress, queCheckComplete,
    queDownloadComplete, queInstallComplete, queDecisionResult);
  TQueuedUIEvent = record
    Kind: TQueuedUIEventKind;
    State: TUpdateState;
    Text: string;
    BytesReceived: Int64;
    TotalBytes: Int64;
    Percent: Integer;
    CancelState: IProgressCancelState;
    CheckResult: TUpdateCheckResult;
    CheckGeneration: Int64;
    Manifest: TUpdateManifest;
    Success: Boolean;
  end;

  TVittixAutoUpdaterUI = class(TCustomPanel)
  private
    // Core components
    FEngine: TUpdateEngine;
    FConfig: TUpdaterConfig;
    FCurrentManifest: TUpdateManifest;
    FIsUpdating: Boolean;
    FCheckGeneration: Int64;
    FIsLayingOut: Boolean;
    FCreatingUI: Boolean;
    FUIInitialized: Boolean;
    FAutoCheck: Boolean;
    FAutoCheckTimer: TTimer;
    FIsDestroying: Boolean;
    FQueuedEvents: TQueue<TQueuedUIEvent>;
    FQueueLock: TCriticalSection;
    FDispatchQueued: Boolean;
    FProgressCancelState: IProgressCancelState;
    FDownloadThread: TThread;
    FInstallThread: TThread;

    // UI Style and Layout
    FUIStyle: TUpdateUIStyle;
    FButtonStyle: TUpdateButtonStyle;
    FShowReleaseNotes: Boolean;
    FShowProgressDetails: Boolean;

    // UI Controls
    FMainPanel: TPanel;
    FHeaderPanel: TPanel;
    FContentPanel: TPanel;
    FButtonPanel: TPanel;
    FRightButtonPanel: TPanel;
    FActionButtonPanel: TPanel;
    FProgressPanel: TPanel;
    FProgressDetailsPanel: TPanel;

    // Header controls
    FTitleLabel: TLabel;
    FStatusLabel: TLabel;
    FVersionLabel: TLabel;

    // Content controls
    FInfoMemo: TMemo;
    FReleaseNotesMemo: TMemo;
    FSplitter: TSplitter;

    // Progress controls
    FProgressBar: TProgressBar;
    FProgressLabel: TLabel;
    FSpeedLabel: TLabel;
    FETALabel: TLabel;

    // Buttons
    FCheckButton: TButton;
    FDownloadButton: TButton;
    FInstallButton: TButton;
    FCancelButton: TButton;
    FSettingsButton: TSpeedButton;

    // Progress tracking
    FStartTime: TDateTime;
    FLastBytes: Int64;
    FLastTime: TDateTime;

    // Events
    FOnStateChange: TUpdateStateChangeEvent;
    FOnDownloadProgress: TVittixDownloadProgressEvent;
    FOnUpdateDecision: TUpdateDecisionEvent;
    FOnUpdateComplete: TUpdateCompleteEvent;
    FOnSettingsClick: TNotifyEvent;

    // Property setters
    procedure SetUIStyle(const Value: TUpdateUIStyle);
    procedure SetButtonStyle(const Value: TUpdateButtonStyle);
    procedure SetShowReleaseNotes(const Value: Boolean);
    procedure SetShowProgressDetails(const Value: Boolean);
    procedure SetAutoCheck(const Value: Boolean);
    procedure SetConfig(const Value: TUpdaterConfig);
    procedure InitializeUI;
    procedure ReadConfigData(Stream: TStream);
    procedure WriteConfigData(Stream: TStream);
    function HasConfigData: Boolean;
    function ScaleUI(Value: Integer): Integer;

    // UI Creation and Layout
    procedure CreateUI;
    procedure LayoutControls;
    procedure UpdateButtonStates;
    procedure ApplyUIStyle;

    // Event handlers
    procedure OnEngineStateChange(Sender: TObject; NewState: TUpdateState;
      const Status: string);
    procedure OnEngineDownloadProgress(Sender: TObject; BytesReceived, TotalBytes: Int64;
      var Cancel: Boolean);
    procedure OnAutoCheckTimer(Sender: TObject);

    // Button click handlers
    procedure OnCheckButtonClick(Sender: TObject);
    procedure OnDownloadButtonClick(Sender: TObject);
    procedure OnInstallButtonClick(Sender: TObject);
    procedure OnCancelButtonClick(Sender: TObject);
    procedure OnSettingsButtonClick(Sender: TObject);

    // Utility methods
    function FormatBytes(Bytes: Int64): string;
    function FormatSpeed(BytesPerSecond: Int64): string;
    function FormatTime(Seconds: Integer): string;
    procedure UpdateProgressDetails(BytesReceived, TotalBytes: Int64);
    procedure ShowUpdateInfo(const Manifest: TUpdateManifest);
    procedure ResetUI;
    procedure UpdateMemoScrollBars;
    procedure QueueUIEvent(const Event: TQueuedUIEvent; Defer: Boolean = False);
    procedure DispatchUIEvent;

  protected
    procedure Loaded; override;
    procedure DefineProperties(Filer: TFiler); override;
    procedure SetParent(AParent: TWinControl); override;
    procedure Resize; override;
    procedure Paint; override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Public methods
    procedure CheckForUpdates;
    procedure DownloadUpdate;
    procedure InstallUpdate;
    procedure CancelOperation;
    procedure ResetToInitialState;

    // Properties (read-only)
    property Engine: TUpdateEngine read FEngine;
    property IsUpdating: Boolean read FIsUpdating;
    property CurrentManifest: TUpdateManifest read FCurrentManifest;

  published
    // Inherited properties
    property Align;
    property Anchors;
    property Color default clBtnFace;
    property Constraints;
    property Enabled;
    property Font;
    property ParentColor default False;
    property ParentFont;
    property ParentShowHint;
    property PopupMenu;
    property ShowHint;
    property TabOrder;
    property TabStop default True;
    property Visible;

    // Custom properties
    // A custom binary property serializes this record through DFM files.
    property Config: TUpdaterConfig read FConfig write SetConfig stored False;
    property UIStyle: TUpdateUIStyle read FUIStyle write SetUIStyle default uisStandard;
    property ButtonStyle: TUpdateButtonStyle read FButtonStyle write SetButtonStyle default ubsBoth;
    property ShowReleaseNotes: Boolean read FShowReleaseNotes write SetShowReleaseNotes default True;
    property ShowProgressDetails: Boolean read FShowProgressDetails write SetShowProgressDetails default True;
    property AutoCheck: Boolean read FAutoCheck write SetAutoCheck default False;

    // Events
    property OnStateChange: TUpdateStateChangeEvent read FOnStateChange write FOnStateChange;
    property OnDownloadProgress: TVittixDownloadProgressEvent read FOnDownloadProgress write FOnDownloadProgress;
    property OnUpdateDecision: TUpdateDecisionEvent read FOnUpdateDecision write FOnUpdateDecision;
    property OnUpdateComplete: TUpdateCompleteEvent read FOnUpdateComplete write FOnUpdateComplete;
    property OnSettingsClick: TNotifyEvent read FOnSettingsClick write FOnSettingsClick;
  end;

procedure Register;

implementation

uses
  Winapi.Windows, Winapi.Messages,
  System.DateUtils, System.Math, Vcl.Themes;

type
  TProgressCancelState = class(TInterfacedObject, IProgressCancelState)
  private
    FCancelled: Integer;
  public
    procedure SetCancelled(Value: Boolean);
    function IsCancelled: Boolean;
  end;

procedure TProgressCancelState.SetCancelled(Value: Boolean);
begin
  TInterlocked.Exchange(FCancelled, Ord(Value));
end;

function TProgressCancelState.IsCancelled: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0;
end;

{ TVittixAutoUpdaterUI }

constructor TVittixAutoUpdaterUI.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  // Initialize properties
  Width := 500;
  Height := 350;
  Constraints.MinWidth := ScaleUI(620);
  Constraints.MinHeight := ScaleUI(260);
  Color := clBtnFace;
  ParentColor := False;
  TabStop := True;
  BevelOuter := bvNone;

  // Initialize private fields
  FUIStyle := uisStandard;
  FButtonStyle := ubsBoth;
  FShowReleaseNotes := True;
  FShowProgressDetails := True;
  FAutoCheck := False;
  FIsUpdating := False;
  FIsDestroying := False;
  FQueuedEvents := TQueue<TQueuedUIEvent>.Create;
  FQueueLock := TCriticalSection.Create;
  FProgressCancelState := TProgressCancelState.Create;

  // Create default config
  FConfig := TUpdaterConfig.Default;

  // Create engine
  FEngine := TUpdateEngine.Create(FConfig);
  FEngine.OnStateChange := OnEngineStateChange;
  FEngine.OnDownloadProgress := OnEngineDownloadProgress;

  // Create auto-check timer
  FAutoCheckTimer := TTimer.Create(Self);
  FAutoCheckTimer.Enabled := False;
  FAutoCheckTimer.OnTimer := OnAutoCheckTimer;
  FUIInitialized := False;
end;

procedure TVittixAutoUpdaterUI.InitializeUI;
begin
  if FUIInitialized or not Assigned(Parent) then
    Exit;

  // A VCL control is constructed before its Parent is assigned by both the
  // form reader and ordinary application code. Creating child windows before
  // this point raises EInvalidOperation ("has no parent window").
  FUIInitialized := True;
  FCreatingUI := True;
  try
    CreateUI;
  finally
    FCreatingUI := False;
  end;
  ApplyUIStyle;
  ResetUI;
end;

procedure TVittixAutoUpdaterUI.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  if Assigned(AParent) then
    InitializeUI;
end;

procedure TVittixAutoUpdaterUI.DefineProperties(Filer: TFiler);
begin
  inherited DefineProperties(Filer);
  Filer.DefineBinaryProperty('ConfigData', ReadConfigData,
    WriteConfigData, HasConfigData);
end;

function TVittixAutoUpdaterUI.HasConfigData: Boolean;
begin
  Result := True;
end;

procedure TVittixAutoUpdaterUI.WriteConfigData(Stream: TStream);
var
  Writer: TWriter;

  procedure WriteStringArray(const Values: TArray<string>);
  var
    J: Integer;
  begin
    Writer.WriteInteger(Length(Values));
    for J := 0 to High(Values) do
      Writer.WriteString(Values[J]);
  end;

begin
  Writer := TWriter.Create(Stream, 1024);
  try
    Writer.WriteInteger(4); // ConfigData serialization format version
    Writer.WriteString(FConfig.AppName);
    WriteStringArray(FConfig.ManifestUrls);
    Writer.WriteInteger(FConfig.CheckInterval);
    Writer.WriteBoolean(FConfig.AutoDownload);
    Writer.WriteBoolean(FConfig.AutoInstall);
    Writer.WriteBoolean(FConfig.AllowDowngrade);
    Writer.WriteString(FConfig.TempFolder);
    Writer.WriteInteger(FConfig.ConnectionTimeout);
    Writer.WriteInteger(FConfig.MaxRetries);
    Writer.WriteInteger(FConfig.MaxManifestAgeDays);
    Writer.WriteString(FConfig.UserAgent);
    Writer.WriteBoolean(FConfig.RequireChecksum);
    Writer.WriteBoolean(FConfig.RequireHttps);
    Writer.WriteBoolean(FConfig.VerifyManifestSignature);
    Writer.WriteBoolean(FConfig.VerifyAuthenticode);
    WriteStringArray(FConfig.PinnedPublisherThumbprints);
    Writer.WriteString(FConfig.ManifestPublicKey);
    WriteStringArray(FConfig.ManifestTrustedPublicKeys);
    Writer.WriteBoolean(FConfig.AllowInsecureUnsignedManifests);
    Writer.WriteString(IntToStr(FConfig.MaxArchiveBytes));
    Writer.WriteInteger(FConfig.MaxArchiveEntryCount);
    Writer.WriteString(IntToStr(FConfig.MaxArchiveTotalUncompressedBytes));
    Writer.WriteString(IntToStr(FConfig.MaxArchiveSingleEntryBytes));
    Writer.WriteInteger(FConfig.MaxArchivePathDepth);
    Writer.WriteInteger(FConfig.MaxArchivePathLength);
    Writer.WriteInteger(FConfig.MaxArchiveExpansionRatio);
    WriteStringArray(FConfig.PreserveFiles);
  finally
    Writer.Free;
  end;
end;

procedure TVittixAutoUpdaterUI.ReadConfigData(Stream: TStream);
var
  Reader: TReader;
  ConfigValue: TUpdaterConfig;
  FormatVersion: Integer;

  procedure ReadStringArray(out Values: TArray<string>);
  var
    ArrayLength, J: Integer;
  begin
    ArrayLength := Reader.ReadInteger;
    if (ArrayLength < 0) or (ArrayLength > 4096) then
      raise EReadError.Create('Updater configuration array length is invalid');
    SetLength(Values, ArrayLength);
    for J := 0 to ArrayLength - 1 do
      Values[J] := Reader.ReadString;
  end;

begin
  Reader := TReader.Create(Stream, 1024);
  try
    FormatVersion := Reader.ReadInteger;
    if not (FormatVersion in [1, 2, 3, 4]) then
      raise EReadError.CreateFmt(
        'Unsupported updater configuration stream version %d', [FormatVersion]);
    ConfigValue := TUpdaterConfig.Default;
    ConfigValue.AppName := Reader.ReadString;
    ReadStringArray(ConfigValue.ManifestUrls);
    ConfigValue.CheckInterval := Reader.ReadInteger;
    ConfigValue.AutoDownload := Reader.ReadBoolean;
    ConfigValue.AutoInstall := Reader.ReadBoolean;
    ConfigValue.AllowDowngrade := Reader.ReadBoolean;
    ConfigValue.TempFolder := Reader.ReadString;
    ConfigValue.ConnectionTimeout := Reader.ReadInteger;
    ConfigValue.MaxRetries := Reader.ReadInteger;
    ConfigValue.MaxManifestAgeDays := Reader.ReadInteger;
    ConfigValue.UserAgent := Reader.ReadString;
    ConfigValue.RequireChecksum := Reader.ReadBoolean;
    ConfigValue.RequireHttps := Reader.ReadBoolean;
    if FormatVersion <= 3 then
      Reader.ReadBoolean; // Discard the legacy secure-config flag.
    ConfigValue.VerifyManifestSignature := Reader.ReadBoolean;
    ConfigValue.VerifyAuthenticode := Reader.ReadBoolean;
    ReadStringArray(ConfigValue.PinnedPublisherThumbprints);
    ConfigValue.ManifestPublicKey := Reader.ReadString;
    ReadStringArray(ConfigValue.ManifestTrustedPublicKeys);
    ConfigValue.AllowInsecureUnsignedManifests := Reader.ReadBoolean;
    if FormatVersion <= 3 then
      Reader.ReadString; // Discard the legacy HMAC key.
    if FormatVersion >= 2 then
    begin
      ConfigValue.MaxArchiveBytes := StrToInt64(Reader.ReadString);
      ConfigValue.MaxArchiveEntryCount := Reader.ReadInteger;
      ConfigValue.MaxArchiveTotalUncompressedBytes := StrToInt64(Reader.ReadString);
      ConfigValue.MaxArchiveSingleEntryBytes := StrToInt64(Reader.ReadString);
      ConfigValue.MaxArchivePathDepth := Reader.ReadInteger;
      ConfigValue.MaxArchivePathLength := Reader.ReadInteger;
      ConfigValue.MaxArchiveExpansionRatio := Reader.ReadInteger;
    end;
    if FormatVersion >= 3 then
      ReadStringArray(ConfigValue.PreserveFiles);
    SetConfig(ConfigValue);
  finally
    Reader.Free;
  end;
end;

destructor TVittixAutoUpdaterUI.Destroy;
begin
  FQueueLock.Acquire;
  try
    FIsDestroying := True;
    FQueuedEvents.Clear;
    FDispatchQueued := False;
  finally
    FQueueLock.Release;
  end;
  TThread.RemoveQueuedEvents(DispatchUIEvent);
  if Assigned(FAutoCheckTimer) then
    FAutoCheckTimer.Enabled := False;
  if Assigned(FEngine) then
  begin
    FEngine.OnStateChange := nil;
    FEngine.OnDownloadProgress := nil;
    FEngine.Cancel;
    while (Assigned(FDownloadThread) and not FDownloadThread.Finished) or
          (Assigned(FInstallThread) and not FInstallThread.Finished) do
    begin
      CheckSynchronize(10);
      Sleep(1);
    end;
    if Assigned(FDownloadThread) then
    begin
      FDownloadThread.WaitFor;
      FreeAndNil(FDownloadThread);
    end;
    if Assigned(FInstallThread) then
    begin
      FInstallThread.WaitFor;
      FreeAndNil(FInstallThread);
    end;
    FEngine.Free;
    FEngine := nil;
  end;
  FProgressCancelState := nil;
  FQueuedEvents.Free;
  FQueueLock.Free;
  inherited;
end;

function TVittixAutoUpdaterUI.ScaleUI(Value: Integer): Integer;
begin
  Result := MulDiv(Value, CurrentPPI, 96);
end;

procedure TVittixAutoUpdaterUI.CreateUI;
begin
  FMainPanel := TPanel.Create(Self);
  FMainPanel.Parent := Self;
  FMainPanel.Align := alClient;
  FMainPanel.BevelOuter := bvNone;
  FMainPanel.BorderWidth := 0;
  FMainPanel.Color := Color;
  FMainPanel.ParentColor := False;
  FMainPanel.ParentFont := True;

  FHeaderPanel := TPanel.Create(Self);
  FHeaderPanel.Parent := FMainPanel;
  FHeaderPanel.Align := alTop;
  FHeaderPanel.BevelOuter := bvNone;
  FHeaderPanel.BorderWidth := 0;
  FHeaderPanel.Color := clWindow;
  FHeaderPanel.ParentBackground := False;
  FHeaderPanel.ParentFont := True;

  FButtonPanel := TPanel.Create(Self);
  FButtonPanel.Parent := FMainPanel;
  FButtonPanel.Align := alBottom;
  FButtonPanel.BevelOuter := bvNone;
  FButtonPanel.BorderWidth := 0;
  FButtonPanel.Color := Color;
  FButtonPanel.ParentColor := False;
  FButtonPanel.ParentFont := True;

  FProgressPanel := TPanel.Create(Self);
  FProgressPanel.Parent := FMainPanel;
  FProgressPanel.Align := alBottom;
  FProgressPanel.BevelOuter := bvNone;
  FProgressPanel.BorderWidth := 0;
  FProgressPanel.Color := Color;
  FProgressPanel.ParentColor := False;
  FProgressPanel.ParentFont := True;

  FContentPanel := TPanel.Create(Self);
  FContentPanel.Parent := FMainPanel;
  FContentPanel.Align := alClient;
  FContentPanel.BevelOuter := bvNone;
  FContentPanel.BorderWidth := 0;
  FContentPanel.Color := Color;
  FContentPanel.ParentColor := False;
  FContentPanel.ParentFont := True;

  FRightButtonPanel := TPanel.Create(Self);
  FRightButtonPanel.Parent := FButtonPanel;
  FRightButtonPanel.Align := alRight;
  FRightButtonPanel.BevelOuter := bvNone;
  FRightButtonPanel.BorderWidth := 0;
  FRightButtonPanel.Color := Color;
  FRightButtonPanel.ParentColor := False;
  FRightButtonPanel.ParentFont := True;

  FActionButtonPanel := TPanel.Create(Self);
  FActionButtonPanel.Parent := FRightButtonPanel;
  FActionButtonPanel.Align := alClient;
  FActionButtonPanel.BevelOuter := bvNone;
  FActionButtonPanel.BorderWidth := 0;
  FActionButtonPanel.Color := Color;
  FActionButtonPanel.ParentColor := False;
  FActionButtonPanel.ParentFont := True;

  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := FHeaderPanel;
  FTitleLabel.Align := alTop;
  FTitleLabel.AutoSize := False;
  FTitleLabel.Layout := tlCenter;
  FTitleLabel.ShowAccelChar := False;
  FTitleLabel.Caption := 'Application Updater';
  FTitleLabel.Font.Style := [fsBold];
  FTitleLabel.Font.Size := 12;
  FTitleLabel.ParentFont := False;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := FHeaderPanel;
  FStatusLabel.Align := alTop;
  FStatusLabel.AutoSize := False;
  FStatusLabel.WordWrap := True;
  FStatusLabel.Layout := tlCenter;
  FStatusLabel.ShowAccelChar := False;
  FStatusLabel.Caption := 'Ready to check for updates';

  FVersionLabel := TLabel.Create(Self);
  FVersionLabel.Parent := FHeaderPanel;
  FVersionLabel.Align := alTop;
  FVersionLabel.AutoSize := False;
  FVersionLabel.Layout := tlCenter;
  FVersionLabel.Caption := 'Current version: Unknown';
  FVersionLabel.Font.Size := 9;

  // The release pane is created before the splitter so alRight alignment
  // reserves it first and leaves the splitter between it and the details pane.
  FReleaseNotesMemo := TMemo.Create(Self);
  FReleaseNotesMemo.Parent := FContentPanel;
  FReleaseNotesMemo.Align := alRight;
  FReleaseNotesMemo.AlignWithMargins := True;
  FReleaseNotesMemo.ReadOnly := True;
  FReleaseNotesMemo.WordWrap := True;
  FReleaseNotesMemo.ScrollBars := ssNone;
  FReleaseNotesMemo.TabStop := False;
  FReleaseNotesMemo.Lines.Text := 'No release notes yet.';

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := FContentPanel;
  FSplitter.Align := alRight;
  FSplitter.Width := ScaleUI(6);
  FSplitter.MinSize := ScaleUI(180);
  FSplitter.ResizeStyle := rsUpdate;

  FInfoMemo := TMemo.Create(Self);
  FInfoMemo.Parent := FContentPanel;
  FInfoMemo.Align := alClient;
  FInfoMemo.AlignWithMargins := True;
  FInfoMemo.ReadOnly := True;
  FInfoMemo.WordWrap := True;
  FInfoMemo.ScrollBars := ssNone;
  FInfoMemo.TabStop := False;
  FInfoMemo.Lines.Text := 'No update information yet.';

  FProgressBar := TProgressBar.Create(Self);
  FProgressBar.Parent := FProgressPanel;
  FProgressBar.Align := alTop;
  FProgressBar.Min := 0;
  FProgressBar.Max := 100;

  FProgressDetailsPanel := TPanel.Create(Self);
  FProgressDetailsPanel.Parent := FProgressPanel;
  FProgressDetailsPanel.Align := alTop;
  FProgressDetailsPanel.BevelOuter := bvNone;
  FProgressDetailsPanel.BorderWidth := 0;
  FProgressDetailsPanel.ParentColor := True;
  FProgressDetailsPanel.ParentFont := True;

  FProgressLabel := TLabel.Create(Self);
  FProgressLabel.Parent := FProgressDetailsPanel;
  FProgressLabel.Align := alLeft;
  FProgressLabel.AutoSize := False;
  FProgressLabel.Layout := tlCenter;

  FSpeedLabel := TLabel.Create(Self);
  FSpeedLabel.Parent := FProgressDetailsPanel;
  FSpeedLabel.Align := alLeft;
  FSpeedLabel.AutoSize := False;
  FSpeedLabel.Layout := tlCenter;

  FETALabel := TLabel.Create(Self);
  FETALabel.Parent := FProgressDetailsPanel;
  FETALabel.Align := alClient;
  FETALabel.AutoSize := False;
  FETALabel.Alignment := taRightJustify;
  FETALabel.Layout := tlCenter;

  FCheckButton := TButton.Create(Self);
  FCheckButton.Parent := FButtonPanel;
  FCheckButton.Align := alLeft;
  FCheckButton.AlignWithMargins := True;
  FCheckButton.Caption := 'Check for Update';
  FCheckButton.OnClick := OnCheckButtonClick;

  // Right-aligned controls are created in reverse visual order: VCL's alRight
  // layout consumes the right edge first, preventing sibling overlap.
  FDownloadButton := TButton.Create(Self);
  FDownloadButton.Parent := FActionButtonPanel;
  FDownloadButton.Align := alLeft;
  FDownloadButton.AlignWithMargins := True;
  FDownloadButton.Caption := 'Download';
  FDownloadButton.OnClick := OnDownloadButtonClick;
  FDownloadButton.Enabled := False;

  FInstallButton := TButton.Create(Self);
  FInstallButton.Parent := FActionButtonPanel;
  FInstallButton.Align := alRight;
  FInstallButton.AlignWithMargins := True;
  FInstallButton.Caption := 'Install';
  FInstallButton.OnClick := OnInstallButtonClick;
  FInstallButton.Enabled := False;

  FCancelButton := TButton.Create(Self);
  FCancelButton.Parent := FActionButtonPanel;
  FCancelButton.Align := alRight;
  FCancelButton.AlignWithMargins := True;
  FCancelButton.Caption := 'Cancel';
  FCancelButton.OnClick := OnCancelButtonClick;
  FCancelButton.Enabled := False;

  FSettingsButton := TSpeedButton.Create(Self);
  FSettingsButton.Parent := FRightButtonPanel;
  FSettingsButton.Align := alRight;
  FSettingsButton.AlignWithMargins := True;
  FSettingsButton.Caption := '...';
  FSettingsButton.OnClick := OnSettingsButtonClick;
  FSettingsButton.Hint := 'Settings';
  FSettingsButton.ShowHint := True;
end;

procedure TVittixAutoUpdaterUI.LayoutControls;
var
  ReleaseWidth: Integer;
begin
  if FIsLayingOut or FCreatingUI then
    Exit;

  if not Assigned(FMainPanel) or
     not Assigned(FHeaderPanel) or
     not Assigned(FContentPanel) or
     not Assigned(FButtonPanel) or
     not Assigned(FRightButtonPanel) or
     not Assigned(FActionButtonPanel) or
     not Assigned(FProgressPanel) or
     not Assigned(FProgressDetailsPanel) or
     not Assigned(FProgressBar) or
     not Assigned(FCheckButton) or
     not Assigned(FDownloadButton) or
     not Assigned(FInstallButton) or
     not Assigned(FCancelButton) or
     not Assigned(FSettingsButton) or
     not Assigned(FInfoMemo) or
     not Assigned(FReleaseNotesMemo) then
    Exit;

  FIsLayingOut := True;
  FMainPanel.DisableAlign;
  FContentPanel.DisableAlign;
  FButtonPanel.DisableAlign;
  FRightButtonPanel.DisableAlign;
  FActionButtonPanel.DisableAlign;
  FProgressPanel.DisableAlign;
  try
    Constraints.MinWidth := ScaleUI(620);
    Constraints.MinHeight := ScaleUI(260);

    FMainPanel.Align := alClient;
    FMainPanel.Padding.SetBounds(ScaleUI(12), ScaleUI(12),
      ScaleUI(12), ScaleUI(12));

    FHeaderPanel.Align := alTop;
    FHeaderPanel.Padding.SetBounds(ScaleUI(4), ScaleUI(4),
      ScaleUI(4), ScaleUI(4));
    case FUIStyle of
      uisCompact: FHeaderPanel.Height := ScaleUI(84);
      uisStandard: FHeaderPanel.Height := ScaleUI(96);
      uisDetailed: FHeaderPanel.Height := ScaleUI(108);
    end;

    FButtonPanel.Align := alBottom;
    FButtonPanel.Height := ScaleUI(48);
    FButtonPanel.Padding.SetBounds(ScaleUI(4), ScaleUI(4),
      ScaleUI(4), ScaleUI(4));
    FCheckButton.Align := alLeft;
    FCheckButton.Width := ScaleUI(150);
    FCheckButton.Height := ScaleUI(32);
    FCheckButton.Constraints.MinWidth := ScaleUI(150);
    FCheckButton.Margins.SetBounds(0, 0, ScaleUI(8), 0);

    FRightButtonPanel.Align := alRight;
    FRightButtonPanel.Width := ScaleUI(338);
    FRightButtonPanel.Padding.SetBounds(0, 0, 0, 0);
    FActionButtonPanel.Align := alClient;
    FActionButtonPanel.Padding.SetBounds(0, 0, 0, 0);
    FDownloadButton.Align := alLeft;
    FInstallButton.Align := alRight;
    FCancelButton.Align := alRight;
    FSettingsButton.Align := alRight;
    FDownloadButton.Width := ScaleUI(104);
    FDownloadButton.Constraints.MinWidth := ScaleUI(104);
    FInstallButton.Width := ScaleUI(80);
    FInstallButton.Constraints.MinWidth := ScaleUI(80);
    FCancelButton.Width := ScaleUI(88);
    FCancelButton.Constraints.MinWidth := ScaleUI(88);
    FSettingsButton.Width := ScaleUI(34);
    FSettingsButton.Height := ScaleUI(32);
    FDownloadButton.Height := ScaleUI(32);
    FInstallButton.Height := ScaleUI(32);
    FCancelButton.Height := ScaleUI(32);
    FDownloadButton.Margins.SetBounds(ScaleUI(8), 0, 0, 0);
    FInstallButton.Margins.SetBounds(ScaleUI(8), 0, 0, 0);
    FCancelButton.Margins.SetBounds(ScaleUI(8), 0, 0, 0);
    FSettingsButton.Margins.SetBounds(ScaleUI(8), 0, 0, 0);

    FProgressPanel.Align := alBottom;
    FProgressPanel.Padding.SetBounds(ScaleUI(8), ScaleUI(6),
      ScaleUI(8), ScaleUI(6));
    if FShowProgressDetails then
      FProgressPanel.Height := ScaleUI(18 + 22 + 12)
    else
      FProgressPanel.Height := ScaleUI(18 + 12);
    FProgressBar.Align := alTop;
    FProgressBar.AlignWithMargins := True;
    FProgressBar.Height := ScaleUI(18);
    FProgressBar.Margins.SetBounds(0, 0, 0, ScaleUI(4));
    FProgressDetailsPanel.Align := alTop;
    FProgressDetailsPanel.Height := ScaleUI(22);
    FProgressDetailsPanel.Visible := FShowProgressDetails;
    FProgressLabel.Align := alLeft;
    FProgressLabel.Width := ScaleUI(200);
    FProgressLabel.Height := ScaleUI(22);
    FSpeedLabel.Align := alLeft;
    FSpeedLabel.Width := ScaleUI(150);
    FSpeedLabel.Height := ScaleUI(22);
    FETALabel.Align := alClient;
    FETALabel.Height := ScaleUI(22);

    FContentPanel.Align := alClient;
    FContentPanel.Padding.SetBounds(ScaleUI(4), ScaleUI(4),
      ScaleUI(4), ScaleUI(4));
    ReleaseWidth := Max(ScaleUI(180), FContentPanel.ClientWidth div 3);
    ReleaseWidth := Min(ReleaseWidth,
      Max(ScaleUI(180), FContentPanel.ClientWidth - ScaleUI(300)));
    FReleaseNotesMemo.Align := alRight;
    FReleaseNotesMemo.Width := ReleaseWidth;
    FReleaseNotesMemo.Margins.SetBounds(ScaleUI(4), 0, 0, 0);
    FSplitter.Align := alRight;
    FSplitter.Width := ScaleUI(6);
    FSplitter.Margins.SetBounds(ScaleUI(2), 0, ScaleUI(2), 0);
    FInfoMemo.Align := alClient;
    FInfoMemo.Margins.SetBounds(0, 0, ScaleUI(4), 0);

    FTitleLabel.Align := alTop;
    FTitleLabel.Height := ScaleUI(24);
    FTitleLabel.Margins.SetBounds(0, 0, 0, ScaleUI(2));
    FStatusLabel.Align := alTop;
    FStatusLabel.Height := ScaleUI(34);
    FStatusLabel.Margins.SetBounds(0, 0, 0, ScaleUI(2));
    FVersionLabel.Align := alTop;
    FVersionLabel.Height := ScaleUI(18);

    FInfoMemo.Perform(EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN,
      MakeLParam(0, 0));
    FReleaseNotesMemo.Perform(EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN,
      MakeLParam(ScaleUI(8), ScaleUI(8)));
    UpdateMemoScrollBars;
  finally
    FProgressPanel.EnableAlign;
    FActionButtonPanel.EnableAlign;
    FRightButtonPanel.EnableAlign;
    FButtonPanel.EnableAlign;
    FContentPanel.EnableAlign;
    FMainPanel.EnableAlign;
    FIsLayingOut := False;
  end;
end;

procedure TVittixAutoUpdaterUI.UpdateMemoScrollBars;
var
  VisibleLines: Integer;

  procedure UpdateMemo(Memo: TMemo);
  begin
    VisibleLines := Max(1, Memo.ClientHeight div Max(1, Abs(Memo.Font.Height)));
    if Memo.Perform(EM_GETLINECOUNT, 0, 0) > VisibleLines then
      Memo.ScrollBars := ssVertical
    else
      Memo.ScrollBars := ssNone;
  end;

begin
  if not Assigned(FInfoMemo) or not Assigned(FReleaseNotesMemo) then
    Exit;
  UpdateMemo(FInfoMemo);
  UpdateMemo(FReleaseNotesMemo);
end;

procedure TVittixAutoUpdaterUI.Resize;
begin
  inherited;
  if FCreatingUI or (csLoading in ComponentState) or (csDestroying in ComponentState) then
    Exit;

  if Assigned(FMainPanel) then
    LayoutControls;
end;

procedure TVittixAutoUpdaterUI.Loaded;
begin
  inherited;
  InitializeUI;
  if not FCreatingUI then
  begin
    if FUIInitialized then
    begin
      LayoutControls;
      UpdateButtonStates;
    end;
  end;
end;

procedure TVittixAutoUpdaterUI.Paint;
var
  R: TRect;
begin
  inherited;

  // Draw border if themed
  if StyleServices.Enabled then
  begin
    R := ClientRect;
    Canvas.Pen.Color := StyleServices.GetStyleColor(scBorder);
    Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(R);
  end;
end;

procedure TVittixAutoUpdaterUI.ApplyUIStyle;
begin
  case FUIStyle of
    uisCompact:
    begin
      Height := ScaleUI(260);
      FShowReleaseNotes := False;
      FReleaseNotesMemo.Visible := False;
      FSplitter.Visible := False;
    end;

    uisStandard:
    begin
      Height := ScaleUI(350);
      FReleaseNotesMemo.Visible := FShowReleaseNotes;
      FSplitter.Visible := FShowReleaseNotes;
    end;

    uisDetailed:
    begin
      Height := ScaleUI(450);
      FReleaseNotesMemo.Visible := True;
      FSplitter.Visible := True;
    end;
  end;

  UpdateButtonStates;
  LayoutControls;
end;

procedure TVittixAutoUpdaterUI.UpdateButtonStates;
var
  State: TUpdateState;
begin
  if not Assigned(FEngine) then
    Exit;

  State := FEngine.State;

  // Update button visibility based on style
  case FButtonStyle of
    ubsAutomatic:
    begin
      FCheckButton.Visible := True;
      FDownloadButton.Visible := False;
      FInstallButton.Visible := False;
    end;

    ubsManual:
    begin
      FCheckButton.Visible := True;
      FDownloadButton.Visible := True;
      FInstallButton.Visible := True;
    end;

    ubsBoth:
    begin
      FCheckButton.Visible := True;
      FDownloadButton.Visible := True;
      FInstallButton.Visible := True;
    end;
  end;

  // Update button states based on current state
  case State of
    usIdle, usFailed:
    begin
      FCheckButton.Enabled := True;
      FDownloadButton.Enabled := False;
      FInstallButton.Enabled := False;
      FCancelButton.Enabled := False;
    end;

    usChecking:
    begin
      FCheckButton.Enabled := False;
      FDownloadButton.Enabled := False;
      FInstallButton.Enabled := False;
      FCancelButton.Enabled := True;
    end;

    usAvailable:
    begin
      FCheckButton.Enabled := True;
      FDownloadButton.Enabled := True;
      FInstallButton.Enabled := False;
      FCancelButton.Enabled := False;
    end;

    usDownloading:
    begin
      FCheckButton.Enabled := False;
      FDownloadButton.Enabled := False;
      FInstallButton.Enabled := False;
      FCancelButton.Enabled := True;
    end;

    usReady:
    begin
      FCheckButton.Enabled := True;
      FDownloadButton.Enabled := False;
      FInstallButton.Enabled := True;
      FCancelButton.Enabled := False;
    end;

    usApplying:
    begin
      FCheckButton.Enabled := False;
      FDownloadButton.Enabled := False;
      FInstallButton.Enabled := False;
      FCancelButton.Enabled := False;
    end;
  end;

  FProgressPanel.Visible := State in [usDownloading, usApplying];
end;

// Event Handlers

procedure TVittixAutoUpdaterUI.QueueUIEvent(const Event: TQueuedUIEvent;
  Defer: Boolean);
var
  ShouldDispatch: Boolean;
begin
  ShouldDispatch := False;
  FQueueLock.Acquire;
  try
    if FIsDestroying then
      Exit;
    FQueuedEvents.Enqueue(Event);
    if not FDispatchQueued then
    begin
      FDispatchQueued := True;
      ShouldDispatch := True;
    end;
  finally
    FQueueLock.Release;
  end;

  if ShouldDispatch then
    if Defer then
      TThread.ForceQueue(nil, DispatchUIEvent)
    else
      TThread.Queue(nil, DispatchUIEvent);
end;

procedure TVittixAutoUpdaterUI.DispatchUIEvent;
var
  Event: TQueuedUIEvent;
  QueueAgain: Boolean;
  Cancel: Boolean;
begin
  FQueueLock.Acquire;
  try
    if FIsDestroying then
    begin
      FQueuedEvents.Clear;
      FDispatchQueued := False;
      Exit;
    end;
    if FQueuedEvents.Count = 0 then
    begin
      FDispatchQueued := False;
      Exit;
    end;
    Event := FQueuedEvents.Dequeue;
    QueueAgain := FQueuedEvents.Count > 0;
    if not QueueAgain then
      FDispatchQueued := False;
  finally
    FQueueLock.Release;
  end;

  if QueueAgain then
    TThread.ForceQueue(nil, DispatchUIEvent);
  if FIsDestroying then
    Exit;

  if ((Event.Kind = queState) or (Event.Kind = queCheckComplete)) and
     (Event.CheckGeneration <> TInterlocked.Read(FCheckGeneration)) then
    Exit;

  case Event.Kind of
    queState:
    begin
      FStatusLabel.Caption := Event.Text;
      UpdateButtonStates;
      case Event.State of
        usAvailable:
        begin
          ShowUpdateInfo(FEngine.LastManifest);
          FCurrentManifest := FEngine.LastManifest;
        end;
        usComplete:
        begin
          FProgressBar.Position := 100;
          FIsUpdating := False;
        end;
        usFailed:
        begin
          FIsUpdating := False;
          FProgressPanel.Visible := False;
        end;
      end;
      if Assigned(FOnStateChange) then
        FOnStateChange(Self, Event.State, Event.Text);
    end;

    queProgress:
    begin
      FProgressBar.Position := Event.Percent;
      if FShowProgressDetails then
        UpdateProgressDetails(Event.BytesReceived, Event.TotalBytes);
      Cancel := Event.CancelState.IsCancelled;
      if Assigned(FOnDownloadProgress) then
        FOnDownloadProgress(Self, Event.BytesReceived, Event.TotalBytes,
          Event.Percent, Cancel);
      Event.CancelState.SetCancelled(Cancel);
    end;

    queCheckComplete:
    begin
      FIsUpdating := False;
      case Event.CheckResult of
        ucrUpdateAvailable:
        begin
          FCurrentManifest := Event.Manifest;
          if Assigned(FOnUpdateDecision) then
          begin
            var DecisionState: IProgressCancelState := TProgressCancelState.Create;
            var Continuation := Default(TQueuedUIEvent);
            var DecisionEvent := FOnUpdateDecision;
            Continuation.Kind := queDecisionResult;
            Continuation.CancelState := DecisionState;
            QueueUIEvent(Continuation, True);
            var Decision := True;
            DecisionEvent(Self, Event.Manifest, Decision);
            DecisionState.SetCancelled(Decision);
          end
          else if FButtonStyle = ubsAutomatic then
            DownloadUpdate;
        end;
        ucrNoUpdateAvailable:
          FStatusLabel.Caption := 'Application is up to date';
        ucrError:
        begin
          FStatusLabel.Caption := 'Error: ' + Event.Text;
          if (Event.Text = UnsupportedUncInstall) or (Event.Text = UnsupportedNetworkInstall) then
          begin
            FInfoMemo.Clear;
            FReleaseNotesMemo.Clear;
            if Assigned(FOnUpdateComplete) then
              FOnUpdateComplete(Self, False, Event.Text)
            else
              MessageDlg(Event.Text, mtError, [mbOK], 0);
          end;
        end;
      end;
    end;

    queDownloadComplete:
    begin
      FIsUpdating := False;
      if Event.Success then
      begin
        if FButtonStyle = ubsAutomatic then
          InstallUpdate;
      end
      else if Assigned(FOnUpdateComplete) then
        FOnUpdateComplete(Self, False, Event.Text)
      else if (Event.Text = UnsupportedUncInstall) or (Event.Text = UnsupportedNetworkInstall) then
        MessageDlg(Event.Text, mtError, [mbOK], 0);
    end;

    queInstallComplete:
    begin
      FIsUpdating := False;
      if Assigned(FOnUpdateComplete) then
        FOnUpdateComplete(Self, Event.Success, Event.Text);
    end;

    queDecisionResult:
      if Event.CancelState.IsCancelled and (FButtonStyle = ubsAutomatic) then
        DownloadUpdate;
  end;
end;

procedure TVittixAutoUpdaterUI.OnEngineStateChange(Sender: TObject;
  NewState: TUpdateState; const Status: string);
var
  Event: TQueuedUIEvent;
begin
  Event := Default(TQueuedUIEvent);
  Event.Kind := queState;
  Event.State := NewState;
  Event.Text := Status;
  Event.CheckGeneration := TInterlocked.Read(FCheckGeneration);
  QueueUIEvent(Event, True);
end;

procedure TVittixAutoUpdaterUI.OnEngineDownloadProgress(Sender: TObject;
  BytesReceived, TotalBytes: Int64; var Cancel: Boolean);
var
  PercentComplete: Integer;
  Event: TQueuedUIEvent;
begin
  Cancel := FProgressCancelState.IsCancelled;
  if TotalBytes > 0 then
  begin
    PercentComplete := Round((BytesReceived / TotalBytes) * 100);
    Event := Default(TQueuedUIEvent);
    Event.Kind := queProgress;
    Event.BytesReceived := BytesReceived;
    Event.TotalBytes := TotalBytes;
    Event.Percent := PercentComplete;
    Event.CancelState := FProgressCancelState;
    QueueUIEvent(Event);
  end;
end;

procedure TVittixAutoUpdaterUI.OnAutoCheckTimer(Sender: TObject);
begin
  if not FIsUpdating and (FEngine.State = usIdle) then
    CheckForUpdates;
end;

// Button Click Handlers

procedure TVittixAutoUpdaterUI.OnCheckButtonClick(Sender: TObject);
begin
  CheckForUpdates;
end;

procedure TVittixAutoUpdaterUI.OnDownloadButtonClick(Sender: TObject);
begin
  DownloadUpdate;
end;

procedure TVittixAutoUpdaterUI.OnInstallButtonClick(Sender: TObject);
begin
  InstallUpdate;
end;

procedure TVittixAutoUpdaterUI.OnCancelButtonClick(Sender: TObject);
begin
  CancelOperation;
end;

procedure TVittixAutoUpdaterUI.OnSettingsButtonClick(Sender: TObject);
begin
  if Assigned(FOnSettingsClick) then
    FOnSettingsClick(Self);
end;

// Public Methods

procedure TVittixAutoUpdaterUI.CheckForUpdates;
var
  OperationGeneration: Int64;
begin
  if FIsDestroying then
    Exit;
  if FIsUpdating and not (FEngine.State in
    [usIdle, usAvailable, usFailed, usCancelled]) then
    Exit;

  OperationGeneration := TInterlocked.Increment(FCheckGeneration);
  FIsUpdating := True;
  ResetUI;

  FEngine.CheckForUpdate(
    procedure(Result: TUpdateCheckResult; const Manifest: TUpdateManifest;
      const ErrorMsg: string)
    var
      Event: TQueuedUIEvent;
    begin
      if FIsDestroying or
         (OperationGeneration <> TInterlocked.Read(FCheckGeneration)) then
        Exit;
      // Engine check callbacks are delivered on the main thread. Clear the
      // operation gate here so a completed no-update check can be followed by
      // another check even if its queued presentation event is still pending.
      FIsUpdating := False;
      Event := Default(TQueuedUIEvent);
      Event.Kind := queCheckComplete;
      Event.CheckResult := Result;
      Event.CheckGeneration := OperationGeneration;
      Event.Manifest := Manifest;
      Event.Text := ErrorMsg;
      QueueUIEvent(Event, True);
    end);
end;

procedure TVittixAutoUpdaterUI.DownloadUpdate;
begin
  if FIsUpdating or (FEngine.State <> usAvailable) then
    Exit;

  FIsUpdating := True;
  FProgressCancelState.SetCancelled(False);
  FStartTime := Now;
  FLastBytes := 0;
  FLastTime := Now;

  if Assigned(FDownloadThread) then
  begin
    FDownloadThread.WaitFor;
    FreeAndNil(FDownloadThread);
  end;
  FDownloadThread := TThread.CreateAnonymousThread(
    procedure
    begin
      var ErrorMessage: string;
      var Success := FEngine.DownloadUpdate(FCurrentManifest, ErrorMessage);
      var Event := Default(TQueuedUIEvent);
      Event.Kind := queDownloadComplete;
      Event.Success := Success;
      if ErrorMessage <> '' then
        Event.Text := ErrorMessage
      else
        Event.Text := 'Download failed';
      QueueUIEvent(Event);
    end);
  FDownloadThread.FreeOnTerminate := False;
  FDownloadThread.Start;
end;

procedure TVittixAutoUpdaterUI.InstallUpdate;
begin
  if FIsUpdating or (FEngine.State <> usReady) then
    Exit;

  FIsUpdating := True;

  if Assigned(FInstallThread) then
  begin
    FInstallThread.WaitFor;
    FreeAndNil(FInstallThread);
  end;
  FInstallThread := TThread.CreateAnonymousThread(
    procedure
    begin
      var ErrorMessage: string;
      var Success := FEngine.ApplyUpdate(ErrorMessage);
      var Event := Default(TQueuedUIEvent);
      Event.Kind := queInstallComplete;
      Event.Success := Success;
      if Success then
        Event.Text := 'Update completed successfully'
      else if ErrorMessage <> '' then
        Event.Text := ErrorMessage
      else
        Event.Text := 'Update failed';
      QueueUIEvent(Event);
    end);
  FInstallThread.FreeOnTerminate := False;
  FInstallThread.Start;
end;

procedure TVittixAutoUpdaterUI.CancelOperation;
begin
  FProgressCancelState.SetCancelled(True);
  FEngine.Cancel;
  FIsUpdating := False;
  ResetUI;
end;

procedure TVittixAutoUpdaterUI.ResetToInitialState;
begin
  FIsUpdating := False;
  ResetUI;
  FEngine.Reset;
end;

// Utility Methods

procedure TVittixAutoUpdaterUI.ShowUpdateInfo(const Manifest: TUpdateManifest);
begin
  FInfoMemo.Lines.Clear;
  FInfoMemo.Lines.Add('Update Available');
  FInfoMemo.Lines.Add('');
  FInfoMemo.Lines.Add('New Version: ' + Manifest.Version.ToString);
  FInfoMemo.Lines.Add('Current Version: ' + FEngine.CurrentVersion.ToString);
  FInfoMemo.Lines.Add('');
  FInfoMemo.Lines.Add('File Size: ' + FormatBytes(Manifest.FileSize));
  if Manifest.Checksum <> '' then
    FInfoMemo.Lines.Add('Checksum: ' + Copy(Manifest.Checksum, 1, 16) + '...');
  FInfoMemo.Lines.Add('');

  FReleaseNotesMemo.Lines.BeginUpdate;
  try
    FReleaseNotesMemo.Lines.Clear;
    if Manifest.ReleaseNotes <> '' then
    begin
      FReleaseNotesMemo.Lines.Add('Release Notes');
      FReleaseNotesMemo.Lines.Add('');
      FReleaseNotesMemo.Lines.Add(Manifest.ReleaseNotes);
    end
    else
      FReleaseNotesMemo.Lines.Add('No release notes available.');
  finally
    FReleaseNotesMemo.Lines.EndUpdate;
  end;
  UpdateMemoScrollBars;
end;

procedure TVittixAutoUpdaterUI.UpdateProgressDetails(BytesReceived, TotalBytes: Int64);
var
  CurrentTime: TDateTime;
  ElapsedSeconds: Double;
  Speed: Int64;
  RemainingBytes: Int64;
  ETASeconds: Integer;
begin
  CurrentTime := Now;
  ElapsedSeconds := SecondsBetween(CurrentTime, FLastTime);

  if ElapsedSeconds >= 1.0 then
  begin
    Speed := Round((BytesReceived - FLastBytes) / ElapsedSeconds);

    FProgressLabel.Caption := Format('%s of %s',
      [FormatBytes(BytesReceived), FormatBytes(TotalBytes)]);
    FSpeedLabel.Caption := FormatSpeed(Speed);

    if Speed > 0 then
    begin
      RemainingBytes := TotalBytes - BytesReceived;
      ETASeconds := Round(RemainingBytes / Speed);
      FETALabel.Caption := 'ETA: ' + FormatTime(ETASeconds);
    end;

    FLastBytes := BytesReceived;
    FLastTime := CurrentTime;
  end;
end;

function TVittixAutoUpdaterUI.FormatBytes(Bytes: Int64): string;
begin
  if Bytes < 1024 then
    Result := Format('%d B', [Bytes])
  else if Bytes < 1024 * 1024 then
    Result := Format('%.1f KB', [Bytes / 1024])
  else if Bytes < 1024 * 1024 * 1024 then
    Result := Format('%.1f MB', [Bytes / (1024 * 1024)])
  else
    Result := Format('%.2f GB', [Bytes / (1024 * 1024 * 1024)]);
end;

function TVittixAutoUpdaterUI.FormatSpeed(BytesPerSecond: Int64): string;
begin
  Result := FormatBytes(BytesPerSecond) + '/s';
end;

function TVittixAutoUpdaterUI.FormatTime(Seconds: Integer): string;
var
  Hours, Minutes, Secs: Integer;
begin
  if Seconds < 60 then
    Result := Format('%ds', [Seconds])
  else if Seconds < 3600 then
  begin
    Minutes := Seconds div 60;
    Secs := Seconds mod 60;
    Result := Format('%dm %ds', [Minutes, Secs]);
  end
  else
  begin
    Hours := Seconds div 3600;
    Minutes := (Seconds mod 3600) div 60;
    Result := Format('%dh %dm', [Hours, Minutes]);
  end;
end;

procedure TVittixAutoUpdaterUI.ResetUI;
begin
  FProgressBar.Position := 0;
  FProgressLabel.Caption := '';
  FSpeedLabel.Caption := '';
  FETALabel.Caption := '';
  FProgressPanel.Visible := False;
  FInfoMemo.Lines.Text := 'No update information yet.';
  FReleaseNotesMemo.Lines.Text := 'No release notes yet.';
  UpdateMemoScrollBars;
end;

// Property Setters

procedure TVittixAutoUpdaterUI.SetUIStyle(const Value: TUpdateUIStyle);
begin
  if FUIStyle <> Value then
  begin
    FUIStyle := Value;
    if FUIInitialized then
      ApplyUIStyle;
  end;
end;

procedure TVittixAutoUpdaterUI.SetButtonStyle(const Value: TUpdateButtonStyle);
begin
  if FButtonStyle <> Value then
  begin
    FButtonStyle := Value;
    if FUIInitialized then
      UpdateButtonStates;
  end;
end;

procedure TVittixAutoUpdaterUI.SetShowReleaseNotes(const Value: Boolean);
begin
  if FShowReleaseNotes <> Value then
  begin
    FShowReleaseNotes := Value;
    if Assigned(FReleaseNotesMemo) then
    begin
      FReleaseNotesMemo.Visible := Value and (FUIStyle <> uisCompact);
      FSplitter.Visible := FReleaseNotesMemo.Visible;
    end;
    LayoutControls;
  end;
end;

procedure TVittixAutoUpdaterUI.SetShowProgressDetails(const Value: Boolean);
begin
  if FShowProgressDetails <> Value then
  begin
    FShowProgressDetails := Value;
    if Assigned(FProgressLabel) then
    begin
      FProgressDetailsPanel.Visible := Value;
      LayoutControls;
    end;
  end;
end;

procedure TVittixAutoUpdaterUI.SetAutoCheck(const Value: Boolean);
begin
  if FAutoCheck <> Value then
  begin
    FAutoCheck := Value;
    if Assigned(FAutoCheckTimer) then
    begin
      FAutoCheckTimer.Enabled := Value;
      if Value and (FConfig.CheckInterval > 0) then
        FAutoCheckTimer.Interval := FConfig.CheckInterval * 3600000; // Convert hours to milliseconds
    end;
  end;
end;

procedure TVittixAutoUpdaterUI.SetConfig(const Value: TUpdaterConfig);
begin
  FConfig := Value;
  if Assigned(FEngine) then
  begin
    FEngine.Config := Value;

    // Update version label if possible
    if (FConfig.AppName <> '') and Assigned(FTitleLabel) and
       Assigned(FVersionLabel) then
    begin
      FTitleLabel.Caption := FConfig.AppName + ' Updater';
      try
        FVersionLabel.Caption := 'Current version: ' + FEngine.CurrentVersion.ToString;
      except
        FVersionLabel.Caption := 'Current version: Unknown';
      end;
    end;

    // Update auto-check timer interval
    if FAutoCheck and (Value.CheckInterval > 0) then
      FAutoCheckTimer.Interval := Value.CheckInterval * 3600000;
  end;
end;


procedure Register;
begin
  RegisterComponents('VittixAutoUpdater', [TVittixAutoUpdaterUI]);
end;

end.
