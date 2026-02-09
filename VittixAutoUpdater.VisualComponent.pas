unit VittixAutoUpdater.VisualComponent;

interface

uses
  System.Classes, System.SysUtils, System.Types, System.UITypes,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  Vcl.Buttons, Vcl.Forms, Vcl.Dialogs, Vcl.Imaging.pngimage,
  VittixAutoUpdater.Types, VittixAutoUpdater.Engine;

type
  TUpdateUIStyle = (uisCompact, uisStandard, uisDetailed);
  TUpdateButtonStyle = (ubsAutomatic, ubsManual, ubsBoth);

  // Events
  TUpdateStateChangeEvent = procedure(Sender: TObject; NewState: TUpdateState;
    const StatusMessage: string) of object;
  TDownloadProgressEvent = procedure(Sender: TObject; BytesReceived, TotalBytes: Int64;
    PercentComplete: Integer; var Cancel: Boolean) of object;
  TUpdateDecisionEvent = procedure(Sender: TObject; const Manifest: TUpdateManifest;
    var Decision: Boolean) of object;
  TUpdateCompleteEvent = procedure(Sender: TObject; Success: Boolean;
    const ErrorMessage: string) of object;

  TVittixAutoUpdaterUI = class(TCustomPanel)
  private
    // Core components
    FEngine: TUpdateEngine;
    FConfig: TUpdaterConfig;
    FCurrentManifest: TUpdateManifest;
    FIsUpdating: Boolean;
    FAutoCheck: Boolean;
    FAutoCheckTimer: TTimer;

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
    FProgressPanel: TPanel;

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
    FOnDownloadProgress: TDownloadProgressEvent;
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

  protected
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
    property Config: TUpdaterConfig read FConfig write SetConfig;
    property UIStyle: TUpdateUIStyle read FUIStyle write SetUIStyle default uisStandard;
    property ButtonStyle: TUpdateButtonStyle read FButtonStyle write SetButtonStyle default ubsBoth;
    property ShowReleaseNotes: Boolean read FShowReleaseNotes write SetShowReleaseNotes default True;
    property ShowProgressDetails: Boolean read FShowProgressDetails write SetShowProgressDetails default True;
    property AutoCheck: Boolean read FAutoCheck write SetAutoCheck default False;

    // Events
    property OnStateChange: TUpdateStateChangeEvent read FOnStateChange write FOnStateChange;
    property OnDownloadProgress: TDownloadProgressEvent read FOnDownloadProgress write FOnDownloadProgress;
    property OnUpdateDecision: TUpdateDecisionEvent read FOnUpdateDecision write FOnUpdateDecision;
    property OnUpdateComplete: TUpdateCompleteEvent read FOnUpdateComplete write FOnUpdateComplete;
    property OnSettingsClick: TNotifyEvent read FOnSettingsClick write FOnSettingsClick;
  end;

procedure Register;

implementation

uses
  System.DateUtils, System.Math, Vcl.Themes;

{ TVittixAutoUpdaterUI }

constructor TVittixAutoUpdaterUI.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  // Initialize properties
  Width := 500;
  Height := 350;
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

  // Create UI
  CreateUI;
  LayoutControls;
  UpdateButtonStates;
  ResetUI;
end;

destructor TVittixAutoUpdaterUI.Destroy;
begin
  FEngine.Free;
  inherited;
end;

procedure TVittixAutoUpdaterUI.CreateUI;
begin
  // Main panel
  FMainPanel := TPanel.Create(Self);
  FMainPanel.Parent := Self;
  FMainPanel.BevelOuter := bvNone;
  FMainPanel.Color := Color;
  FMainPanel.ParentColor := False;

  // Header panel
  FHeaderPanel := TPanel.Create(Self);
  FHeaderPanel.Parent := FMainPanel;
  FHeaderPanel.BevelOuter := bvNone;
  FHeaderPanel.Color := clWindow;
  FHeaderPanel.ParentColor := False;
  FHeaderPanel.Height := 60;

  // Content panel
  FContentPanel := TPanel.Create(Self);
  FContentPanel.Parent := FMainPanel;
  FContentPanel.BevelOuter := bvNone;
  FContentPanel.Color := Color;
  FContentPanel.ParentColor := False;

  // Button panel
  FButtonPanel := TPanel.Create(Self);
  FButtonPanel.Parent := FMainPanel;
  FButtonPanel.BevelOuter := bvNone;
  FButtonPanel.Color := Color;
  FButtonPanel.ParentColor := False;
  FButtonPanel.Height := 45;

  // Progress panel
  FProgressPanel := TPanel.Create(Self);
  FProgressPanel.Parent := FMainPanel;
  FProgressPanel.BevelOuter := bvNone;
  FProgressPanel.Color := Color;
  FProgressPanel.ParentColor := False;
  FProgressPanel.Height := 60;

  // Header controls
  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := FHeaderPanel;
  FTitleLabel.Caption := 'Application Updater';
  FTitleLabel.Font.Style := [fsBold];
  FTitleLabel.Font.Size := 12;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := FHeaderPanel;
  FStatusLabel.Caption := 'Ready to check for updates';

  FVersionLabel := TLabel.Create(Self);
  FVersionLabel.Parent := FHeaderPanel;
  FVersionLabel.Caption := 'Current version: Unknown';
  FVersionLabel.Font.Size := 8;

  // Content controls
  FInfoMemo := TMemo.Create(Self);
  FInfoMemo.Parent := FContentPanel;
  FInfoMemo.ReadOnly := True;
  FInfoMemo.ScrollBars := ssVertical;
  FInfoMemo.Lines.Clear;

  FReleaseNotesMemo := TMemo.Create(Self);
  FReleaseNotesMemo.Parent := FContentPanel;
  FReleaseNotesMemo.ReadOnly := True;
  FReleaseNotesMemo.ScrollBars := ssVertical;
  FReleaseNotesMemo.Lines.Clear;

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := FContentPanel;
  FSplitter.Align := alRight;
  FSplitter.Width := 4;

  // Progress controls
  FProgressBar := TProgressBar.Create(Self);
  FProgressBar.Parent := FProgressPanel;
  FProgressBar.Min := 0;
  FProgressBar.Max := 100;

  FProgressLabel := TLabel.Create(Self);
  FProgressLabel.Parent := FProgressPanel;
  FProgressLabel.Caption := '';

  FSpeedLabel := TLabel.Create(Self);
  FSpeedLabel.Parent := FProgressPanel;
  FSpeedLabel.Caption := '';

  FETALabel := TLabel.Create(Self);
  FETALabel.Parent := FProgressPanel;
  FETALabel.Caption := '';

  // Buttons
  FCheckButton := TButton.Create(Self);
  FCheckButton.Parent := FButtonPanel;
  FCheckButton.Caption := 'Check for Updates';
  FCheckButton.OnClick := OnCheckButtonClick;

  FDownloadButton := TButton.Create(Self);
  FDownloadButton.Parent := FButtonPanel;
  FDownloadButton.Caption := 'Download';
  FDownloadButton.OnClick := OnDownloadButtonClick;
  FDownloadButton.Enabled := False;

  FInstallButton := TButton.Create(Self);
  FInstallButton.Parent := FButtonPanel;
  FInstallButton.Caption := 'Install';
  FInstallButton.OnClick := OnInstallButtonClick;
  FInstallButton.Enabled := False;

  FCancelButton := TButton.Create(Self);
  FCancelButton.Parent := FButtonPanel;
  FCancelButton.Caption := 'Cancel';
  FCancelButton.OnClick := OnCancelButtonClick;
  FCancelButton.Enabled := False;

  FSettingsButton := TSpeedButton.Create(Self);
  FSettingsButton.Parent := FButtonPanel;
  FSettingsButton.Caption := '⚙';
  FSettingsButton.OnClick := OnSettingsButtonClick;
  FSettingsButton.Hint := 'Settings';
  FSettingsButton.ShowHint := True;
end;

procedure TVittixAutoUpdaterUI.LayoutControls;
begin
  // Main panel fills the entire component
  FMainPanel.Align := alClient;

  // Header at top
  FHeaderPanel.Align := alTop;

  // Progress panel at bottom (initially hidden)
  FProgressPanel.Align := alBottom;
  FProgressPanel.Visible := False;

  // Button panel above progress
  FButtonPanel.Align := alBottom;

  // Content fills the middle
  FContentPanel.Align := alClient;

  // Position header labels
  FTitleLabel.Left := 10;
  FTitleLabel.Top := 8;

  FStatusLabel.Left := 10;
  FStatusLabel.Top := 28;

  FVersionLabel.Left := 10;
  FVersionLabel.Top := 44;

  // Position content controls
  FInfoMemo.Align := alClient;
  FReleaseNotesMemo.Width := 200;
  FReleaseNotesMemo.Align := alRight;

  // Position progress controls
  FProgressBar.Left := 10;
  FProgressBar.Top := 10;
  FProgressBar.Width := Width - 20;
  FProgressBar.Height := 17;
  FProgressBar.Anchors := [akLeft, akTop, akRight];

  FProgressLabel.Left := 10;
  FProgressLabel.Top := 32;

  FSpeedLabel.Left := 150;
  FSpeedLabel.Top := 32;

  FETALabel.Left := 300;
  FETALabel.Top := 32;

  // Position buttons
  FSettingsButton.Left := Width - 35;
  FSettingsButton.Top := 10;
  FSettingsButton.Width := 25;
  FSettingsButton.Height := 25;
  FSettingsButton.Anchors := [akTop, akRight];

  FCancelButton.Left := Width - 85;
  FCancelButton.Top := 10;
  FCancelButton.Width := 75;
  FCancelButton.Anchors := [akTop, akRight];

  FInstallButton.Left := Width - 170;
  FInstallButton.Top := 10;
  FInstallButton.Width := 75;
  FInstallButton.Anchors := [akTop, akRight];

  FDownloadButton.Left := Width - 255;
  FDownloadButton.Top := 10;
  FDownloadButton.Width := 75;
  FDownloadButton.Anchors := [akTop, akRight];

  FCheckButton.Left := 10;
  FCheckButton.Top := 10;
  FCheckButton.Width := 100;
end;

procedure TVittixAutoUpdaterUI.Resize;
begin
  inherited;
  if Assigned(FMainPanel) then
    LayoutControls;
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
      Height := 200;
      FHeaderPanel.Height := 40;
      FButtonPanel.Height := 35;
      FProgressPanel.Height := 45;
      FShowReleaseNotes := False;
      FReleaseNotesMemo.Visible := False;
      FSplitter.Visible := False;
    end;

    uisStandard:
    begin
      Height := 350;
      FHeaderPanel.Height := 60;
      FButtonPanel.Height := 45;
      FProgressPanel.Height := 60;
      FReleaseNotesMemo.Visible := FShowReleaseNotes;
      FSplitter.Visible := FShowReleaseNotes;
    end;

    uisDetailed:
    begin
      Height := 450;
      FHeaderPanel.Height := 80;
      FButtonPanel.Height := 50;
      FProgressPanel.Height := 80;
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
    usIdle:
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

procedure TVittixAutoUpdaterUI.OnEngineStateChange(Sender: TObject;
  NewState: TUpdateState; const Status: string);
begin
  FStatusLabel.Caption := Status;
  UpdateButtonStates;

  case NewState of
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

  // Trigger custom event
  if Assigned(FOnStateChange) then
    FOnStateChange(Self, NewState, Status);
end;

procedure TVittixAutoUpdaterUI.OnEngineDownloadProgress(Sender: TObject;
  BytesReceived, TotalBytes: Int64; var Cancel: Boolean);
var
  PercentComplete: Integer;
begin
  if TotalBytes > 0 then
  begin
    PercentComplete := Round((BytesReceived / TotalBytes) * 100);
    FProgressBar.Position := PercentComplete;

    if FShowProgressDetails then
      UpdateProgressDetails(BytesReceived, TotalBytes);

    // Trigger custom event
    if Assigned(FOnDownloadProgress) then
      FOnDownloadProgress(Self, BytesReceived, TotalBytes, PercentComplete, Cancel);
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
begin
  if FIsUpdating then
    Exit;

  FIsUpdating := True;
  ResetUI;

  FEngine.CheckForUpdate(
    procedure(Result: TUpdateCheckResult; const Manifest: TUpdateManifest;
      const ErrorMsg: string)
    begin
      FIsUpdating := False;

      case Result of
        ucrUpdateAvailable:
        begin
          FCurrentManifest := Manifest;

          // Ask user if they want to proceed (if event handler assigned)
          if Assigned(FOnUpdateDecision) then
          begin
            var Decision: Boolean := True;
            FOnUpdateDecision(Self, Manifest, Decision);
            if Decision and (FButtonStyle = ubsAutomatic) then
              DownloadUpdate;
          end
          else if FButtonStyle = ubsAutomatic then
            DownloadUpdate;
        end;

        ucrNoUpdateAvailable:
          FStatusLabel.Caption := 'Application is up to date';

        ucrError:
          FStatusLabel.Caption := 'Error: ' + ErrorMsg;
      end;
    end);
end;

procedure TVittixAutoUpdaterUI.DownloadUpdate;
begin
  if FIsUpdating or (FEngine.State <> usAvailable) then
    Exit;

  FIsUpdating := True;
  FStartTime := Now;
  FLastBytes := 0;
  FLastTime := Now;

  TThread.CreateAnonymousThread(
    procedure
    begin
      var Success := FEngine.DownloadUpdate(FCurrentManifest);

      TThread.Synchronize(nil,
        procedure
        begin
          FIsUpdating := False;
          if Success then
          begin
            if FButtonStyle = ubsAutomatic then
              InstallUpdate;
          end
          else
          begin
            if Assigned(FOnUpdateComplete) then
              FOnUpdateComplete(Self, False, 'Download failed');
          end;
        end);
    end).Start;
end;

procedure TVittixAutoUpdaterUI.InstallUpdate;
begin
  if FIsUpdating or (FEngine.State <> usReady) then
    Exit;

  FIsUpdating := True;

  TThread.CreateAnonymousThread(
    procedure
    begin
      var Success := FEngine.ApplyUpdate;

      TThread.Synchronize(nil,
        procedure
        begin
          FIsUpdating := False;
          if Assigned(FOnUpdateComplete) then
          begin
            if Success then
              FOnUpdateComplete(Self, Success, 'Update completed successfully')
            else
              FOnUpdateComplete(Self, Success, 'Update failed');
          end;
        end);
    end).Start;
end;

procedure TVittixAutoUpdaterUI.CancelOperation;
begin
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

  if FShowReleaseNotes and (Manifest.ReleaseNotes <> '') then
  begin
    FReleaseNotesMemo.Lines.Clear;
    FReleaseNotesMemo.Lines.Add('Release Notes:');
    FReleaseNotesMemo.Lines.Add('');
    FReleaseNotesMemo.Lines.Add(Manifest.ReleaseNotes);
  end;
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
  FInfoMemo.Lines.Clear;
  FReleaseNotesMemo.Lines.Clear;
end;

// Property Setters

procedure TVittixAutoUpdaterUI.SetUIStyle(const Value: TUpdateUIStyle);
begin
  if FUIStyle <> Value then
  begin
    FUIStyle := Value;
    ApplyUIStyle;
  end;
end;

procedure TVittixAutoUpdaterUI.SetButtonStyle(const Value: TUpdateButtonStyle);
begin
  if FButtonStyle <> Value then
  begin
    FButtonStyle := Value;
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
  end;
end;

procedure TVittixAutoUpdaterUI.SetShowProgressDetails(const Value: Boolean);
begin
  if FShowProgressDetails <> Value then
  begin
    FShowProgressDetails := Value;
    if Assigned(FProgressLabel) then
    begin
      FProgressLabel.Visible := Value;
      FSpeedLabel.Visible := Value;
      FETALabel.Visible := Value;
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
    if FConfig.AppName <> '' then
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
