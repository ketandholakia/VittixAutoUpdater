unit VittixAutoUpdater.Component;

interface

uses
  System.Classes, System.SysUtils, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls,
  VittixAutoUpdater.Types, VittixAutoUpdater.Engine;

type
  TViConAutoUpdater = class(TCustomPanel)
  private
    FEngine: TUpdateEngine;
    FStatusLabel: TLabel;
    FProgressBar: TProgressBar;

    procedure OnStateChangeHandler(Sender: TObject;
      NewState: TUpdateState; const Status: string);

    procedure OnDownloadProgressHandler(Sender: TObject;
      BytesReceived, TotalBytes: Int64; var Cancel: Boolean);

    procedure SetConfig(const Value: TUpdaterConfig);

  protected
    procedure Resize; override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure CheckForUpdates;
    procedure DownloadAndInstall;

  published
    property Align;
    property Anchors;
    property Color;
    property Config: TUpdaterConfig read FEngine.Config write SetConfig;
  end;

procedure Register;

implementation

{ TViConAutoUpdater }

constructor TViConAutoUpdater.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  Height := 80;
  Width := 300;
  BevelOuter := bvLowered;

  // Create label
  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alTop;
  FStatusLabel.Caption := 'Ready to check for updates';

  // Create progress bar
  FProgressBar := TProgressBar.Create(Self);
  FProgressBar.Parent := Self;
  FProgressBar.Align := alBottom;
  FProgressBar.Min := 0;
  FProgressBar.Max := 100;
  FProgressBar.Position := 0;

  // Create engine
  FEngine := TUpdateEngine.Create(TUpdaterConfig.Default);
  FEngine.OnStateChange := OnStateChangeHandler;
  FEngine.OnDownloadProgress := OnDownloadProgressHandler;
end;

destructor TViConAutoUpdater.Destroy;
begin
  FEngine.Free;
  inherited;
end;

procedure TViConAutoUpdater.Resize;
begin
  inherited;
  FStatusLabel.Height := ClientHeight div 2;
end;

procedure TViConAutoUpdater.SetConfig(const Value: TUpdaterConfig);
begin
  FEngine.Config := Value;
end;

procedure TViConAutoUpdater.OnStateChangeHandler(Sender: TObject;
  NewState: TUpdateState; const Status: string);
begin
  FStatusLabel.Caption := Status;

  case NewState of
    usDownloading:
      FProgressBar.Position := 0;
    usComplete:
      FProgressBar.Position := 100;
  end;
end;

procedure TViConAutoUpdater.OnDownloadProgressHandler(
  Sender: TObject; BytesReceived, TotalBytes: Int64;
  var Cancel: Boolean);
begin
  if TotalBytes > 0 then
    FProgressBar.Position :=
      Round((BytesReceived / TotalBytes) * 100);
end;

procedure TViConAutoUpdater.CheckForUpdates;
begin
  FEngine.CheckForUpdate(
    procedure(Result: TUpdateCheckResult;
      const Manifest: TUpdateManifest; const ErrorMsg: string)
    begin
      if Result = ucrUpdateAvailable then
        FStatusLabel.Caption := 'Update available!'
      else if Result = ucrNoUpdateAvailable then
        FStatusLabel.Caption := 'Up to date'
      else
        FStatusLabel.Caption := 'Error: ' + ErrorMsg;
    end);
end;

procedure TViConAutoUpdater.DownloadAndInstall;
begin
  if FEngine.State = usAvailable then
  begin
    if FEngine.DownloadUpdate(FEngine.LastManifest) then
      FEngine.ApplyUpdate;
  end;
end;

procedure Register;
begin
  RegisterComponents('VI_CON', [TViConAutoUpdater]);
end;

end.
