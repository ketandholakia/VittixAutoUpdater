unit VittixAutoUpdater.Engine;

{$IFDEF FPC}
  {$mode delphi}
{$ENDIF}

interface

uses
  Classes, SysUtils, FileCtrl,
  VittixAutoUpdater.Types,
  VittixAutoUpdater.Network;

// Compatibility function for getting temp directory
function GetTempDir: string;

// Compatibility function for file enumeration
procedure GetAllFiles(const Directory: string; Files: TStringList);

type
  TUpdateEngine = class
  private
    FConfig: TUpdaterConfig;
    FNetwork: TUpdateNetworkManager;
    FCurrentVersion: TAppVersion;
    FState: TUpdateState;
    FDownloadedFile: string;
    FExtractPath: string;
    FLastManifest: TUpdateManifest;

    FOnStateChange: TUpdateStateEvent;
    FOnDownloadProgress: TDownloadProgressEvent;

    procedure SetState(NewState: TUpdateState; const StatusMsg: string);
    function GetTempZipFile: string;
    function GetTempExtractPath: string;
    procedure CleanupTempFiles;

    function ExtractUpdate(const ZipFile, DestPath: string): Boolean;
    function BackupCurrentVersion: Boolean;
    function ApplyUpdateFiles(const SourcePath: string): Boolean;

{$IFDEF MSWINDOWS}
    function ApplyUpdateWindows(const SourcePath: string): Boolean;
{$ENDIF}

    function IsSafeToApply: Boolean;

  public
    constructor Create(const Config: TUpdaterConfig);
    destructor Destroy; override;

    procedure CheckForUpdate(Callback: TUpdateCheckCallback);
    function DownloadUpdate(const Manifest: TUpdateManifest): Boolean;
    function ApplyUpdate: Boolean;

    procedure Cancel;
    function Rollback: Boolean;
    procedure Reset;

    property CurrentVersion: TAppVersion read FCurrentVersion write FCurrentVersion;
    property State: TUpdateState read FState;
    property Config: TUpdaterConfig read FConfig write FConfig;
    property LastManifest: TUpdateManifest read FLastManifest;

    property OnStateChange: TUpdateStateEvent
      read FOnStateChange write FOnStateChange;

    property OnDownloadProgress: TDownloadProgressEvent
      read FOnDownloadProgress write FOnDownloadProgress;
  end;

implementation

uses
{$IFDEF MSWINDOWS}
  Windows, ShellAPI,
{$ENDIF}
  {$IFDEF DELPHIXE_UP}
  System.Zip, System.IOUtils, System.Types;
  {$ELSE}
  Zip, IOUtils;
  {$ENDIF}

{ TUpdateEngine }

constructor TUpdateEngine.Create(const Config: TUpdaterConfig);
begin
  inherited Create;
  FConfig := Config;
  FNetwork := TUpdateNetworkManager.Create;
  FNetwork.ConnectionTimeout := Config.ConnectionTimeout * 1000;
  FNetwork.MaxRetries := Config.MaxRetries;
  FNetwork.UserAgent := Config.UserAgent;

  FState := usIdle;
  FDownloadedFile := '';
  FExtractPath := '';

  try
{$IFDEF MSWINDOWS}
    FCurrentVersion := TAppVersion.CreateFromFile(ParamStr(0));
{$ELSE}
    FillChar(FCurrentVersion, SizeOf(FCurrentVersion), 0);
{$ENDIF}
  except
    FillChar(FCurrentVersion, SizeOf(FCurrentVersion), 0);
  end;
end;

destructor TUpdateEngine.Destroy;
begin
  CleanupTempFiles;
  FNetwork.Free;
  inherited;
end;

procedure TUpdateEngine.SetState(NewState: TUpdateState; const StatusMsg: string);
begin
  FState := NewState;
  if Assigned(FOnStateChange) then
    FOnStateChange(Self, NewState, StatusMsg);
end;

function TUpdateEngine.GetTempZipFile: string;
var
  TempPath: string;
begin
  if FConfig.TempFolder = '' then
    TempPath := GetTempDir
  else
    TempPath := IncludeTrailingPathDelimiter(FConfig.TempFolder);

  Result :=
    TempPath +
    FConfig.AppName + '_update_' +
    FormatDateTime('yyyymmdd_hhnnss', Now) + '.zip';
end;

function TUpdateEngine.GetTempExtractPath: string;
begin
  Result :=
    GetTempDir +
    FConfig.AppName + '_extract_' +
    FormatDateTime('yyyymmdd_hhnnss', Now);
end;

procedure TUpdateEngine.CleanupTempFiles;
begin
  try
    if (FDownloadedFile <> '') then
    begin
      {$IFDEF DELPHIXE_UP}
      if TFile.Exists(FDownloadedFile) then
        TFile.Delete(FDownloadedFile);
      {$ELSE}
      if FileExists(FDownloadedFile) then
        SysUtils.DeleteFile(FDownloadedFile);
      {$ENDIF}
    end;

    if (FExtractPath <> '') then
    begin
      {$IFDEF DELPHIXE_UP}
      if TDirectory.Exists(FExtractPath) then
        TDirectory.Delete(FExtractPath, True);
      {$ELSE}
      if DirectoryExists(FExtractPath) then
        RemoveDir(FExtractPath);
      {$ENDIF}
    end;
  except
    // ignore cleanup errors
  end;

  FDownloadedFile := '';
  FExtractPath := '';
end;

procedure TUpdateEngine.CheckForUpdate(Callback: TUpdateCheckCallback);
begin
  if FState <> usIdle then
    Exit;

  SetState(usChecking, 'Checking for updates...');

  TThread.CreateAnonymousThread(
    procedure
    var
      Manifest: TUpdateManifest;
      Success: Boolean;
      ErrorMsg: string;
    begin
      try
        Success :=
          FNetwork.FetchManifest(
            FConfig.ManifestUrls,
            FConfig.AppName,
            Manifest);

        if not Success then
        begin
          ErrorMsg := 'Failed to fetch update manifest';
          TThread.Synchronize(nil,
            procedure
            begin
              SetState(usFailed, ErrorMsg);
              if Assigned(Callback) then
                Callback(ucrError, TUpdateManifest.Empty, ErrorMsg);
            end);
          Exit;
        end;

        if Manifest.Version > FCurrentVersion then
        begin
          if Manifest.MinVersion.IsValid and
             (FCurrentVersion < Manifest.MinVersion) then
          begin
            ErrorMsg :=
              Format(
                'Cannot update from %s. Minimum required: %s',
                [FCurrentVersion.ToString,
                 Manifest.MinVersion.ToString]);

            TThread.Synchronize(nil,
              procedure
              begin
                SetState(usFailed, ErrorMsg);
                if Assigned(Callback) then
                  Callback(ucrError, Manifest, ErrorMsg);
              end);
            Exit;
          end;

          TThread.Synchronize(nil,
            procedure
            begin
              FLastManifest := Manifest;
              SetState(usAvailable, 'Update available');
              if Assigned(Callback) then
                Callback(ucrUpdateAvailable, Manifest, '');
            end);
        end
        else
        begin
          TThread.Synchronize(nil,
            procedure
            begin
              SetState(usIdle, 'No updates');
              if Assigned(Callback) then
                Callback(ucrNoUpdateAvailable, Manifest, '');
            end);
        end;

      except
        on E: Exception do
        begin
          TThread.Synchronize(nil,
            procedure
            begin
              SetState(usFailed, E.Message);
              if Assigned(Callback) then
                Callback(ucrError, TUpdateManifest.Empty, E.Message);
            end);
        end;
      end;
    end
  ).Start;
end;

function TUpdateEngine.DownloadUpdate(const Manifest: TUpdateManifest): Boolean;
begin
  Result := False;

  if FState <> usAvailable then
    Exit;

  SetState(usDownloading, 'Downloading update...');

  try
    FDownloadedFile := GetTempZipFile;

    Result :=
      FNetwork.DownloadFile(
        Manifest.DownloadUrl,
        FDownloadedFile,
        FOnDownloadProgress,
        Manifest.Checksum);

    if Result then
      SetState(usReady, 'Update ready to install')
    else
    begin
      SetState(usFailed, 'Download failed');
      CleanupTempFiles;
    end;

  except
    on E: Exception do
    begin
      SetState(usFailed, 'Download error: ' + E.Message);
      CleanupTempFiles;
      Result := False;
    end;
  end;
end;

function TUpdateEngine.ExtractUpdate(
  const ZipFile, DestPath: string): Boolean;
var
  ZipArchive: TZipFile;
begin
  Result := False;

  try
    {$IFDEF DELPHIXE_UP}
    TDirectory.CreateDirectory(DestPath);
    {$ELSE}
    ForceDirectories(DestPath);
    {$ENDIF}

    ZipArchive := TZipFile.Create;
    try
      ZipArchive.Open(ZipFile, zmRead);
      ZipArchive.ExtractAll(DestPath);
      Result := True;
    finally
      ZipArchive.Free;
    end;

  except
    on E: Exception do
    begin
      SetState(usFailed, 'Extraction failed: ' + E.Message);
      Result := False;
    end;
  end;
end;

function TUpdateEngine.BackupCurrentVersion: Boolean;
var
  CurrentExe, BackupExe: string;
begin
  CurrentExe := ParamStr(0);
  BackupExe := CurrentExe + '.old';

  {$IFDEF DELPHIXE_UP}
  if TFile.Exists(BackupExe) then
    TFile.Delete(BackupExe);
  {$ELSE}
  if FileExists(BackupExe) then
    SysUtils.DeleteFile(BackupExe);
  {$ENDIF}

  Result := RenameFile(CurrentExe, BackupExe);
end;

function TUpdateEngine.ApplyUpdateFiles(
  const SourcePath: string): Boolean;
var
  Files: TStringList;
  FileName, SourceFile, DestFile: string;
  AppDir: string;
  I: Integer;
begin
  AppDir := ExtractFilePath(ParamStr(0));

  Files := TStringList.Create;
  try
    {$IFDEF DELPHIXE_UP}
    Files.AddStrings(TDirectory.GetFiles(
      SourcePath, '*.*', TSearchOption.soAllDirectories));
    {$ELSE}
    GetAllFiles(SourcePath, Files);
    {$ENDIF}

    for I := 0 to Files.Count - 1 do
    begin
      FileName := Files[I];
      SourceFile := FileName;
      DestFile :=
        AppDir +
        ExtractRelativePath(SourcePath, FileName);

      {$IFDEF DELPHIXE_UP}
      TDirectory.CreateDirectory(ExtractFilePath(DestFile));
      {$ELSE}
      ForceDirectories(ExtractFilePath(DestFile));
      {$ENDIF}

      {$IFDEF DELPHIXE_UP}
      if not TFile.Copy(SourceFile, DestFile, True) then
      {$ELSE}
      if not Windows.CopyFile(PChar(SourceFile), PChar(DestFile), False) then
      {$ENDIF}
        Exit(False);
    end;

    Result := True;
  finally
    Files.Free;
  end;
end;

function TUpdateEngine.IsSafeToApply: Boolean;
begin
  Result :=
    (FDownloadedFile <> '') and
    {$IFDEF DELPHIXE_UP}
    TFile.Exists(FDownloadedFile);
    {$ELSE}
    FileExists(FDownloadedFile);
    {$ENDIF}
end;

function TUpdateEngine.ApplyUpdate: Boolean;
begin
  Result := False;

  if not IsSafeToApply then
    Exit;

  SetState(usExtracting, 'Extracting update...');

  try
    FExtractPath := GetTempExtractPath;

    if not ExtractUpdate(FDownloadedFile, FExtractPath) then
      Exit;

    SetState(usApplying, 'Installing update...');

{$IFDEF MSWINDOWS}
    Result := ApplyUpdateWindows(FExtractPath);
{$ELSE}
    if BackupCurrentVersion then
      Result := ApplyUpdateFiles(FExtractPath);
{$ENDIF}

    if Result then
    begin
      SetState(usComplete, 'Update installed successfully');
      CleanupTempFiles;
    end
    else
      SetState(usFailed, 'Failed to apply update');

  except
    on E: Exception do
    begin
      SetState(usFailed, 'Update error: ' + E.Message);
      Result := False;
    end;
  end;
end;

{$IFDEF MSWINDOWS}
function TUpdateEngine.ApplyUpdateWindows(
  const SourcePath: string): Boolean;
var
  BatchFile: string;
  BatchContent: TStringList;
  AppExe, NewExe: string;
begin
  AppExe := ParamStr(0);
  NewExe :=
    IncludeTrailingPathDelimiter(SourcePath) +
    ExtractFileName(AppExe);

  {$IFDEF DELPHIXE_UP}
  if not TFile.Exists(NewExe) then
  {$ELSE}
  if not FileExists(NewExe) then
  {$ENDIF}
    Exit(False);

  BatchFile :=
    GetTempDir +
    'update_' + FConfig.AppName + '.bat';

  BatchContent := TStringList.Create;
  try
    BatchContent.Add('@echo off');
    BatchContent.Add('timeout /t 2 /nobreak > nul');
    BatchContent.Add('');
    BatchContent.Add(
      Format('ren "%s" "%s.old"',
        [AppExe, ExtractFileName(AppExe)]));
    BatchContent.Add(
      Format(
        'xcopy "%s\*.*" "%s" /E /Y /I',
        [SourcePath, ExtractFilePath(AppExe)]));
    BatchContent.Add(
      Format('start "" "%s"', [AppExe]));
    BatchContent.Add(
      Format('rd /s /q "%s"', [SourcePath]));
    BatchContent.Add('del "%~f0"');

    BatchContent.SaveToFile(BatchFile);

    ShellExecute(0, 'open', PChar(BatchFile), nil, nil, SW_HIDE);
    Result := True;
  finally
    BatchContent.Free;
  end;
end;
{$ENDIF}

procedure TUpdateEngine.Cancel;
begin
  if FState in [usChecking, usDownloading] then
    SetState(usCancelled, 'Update cancelled');
end;

function TUpdateEngine.Rollback: Boolean;
var
  CurrentExe, BackupExe: string;
begin
  CurrentExe := ParamStr(0);
  BackupExe := CurrentExe + '.old';

  {$IFDEF DELPHIXE_UP}
  if not TFile.Exists(BackupExe) then
  {$ELSE}
  if not FileExists(BackupExe) then
  {$ENDIF}
    Exit(False);

  {$IFDEF DELPHIXE_UP}
  TFile.Delete(CurrentExe);
  {$ELSE}
  SysUtils.DeleteFile(CurrentExe);
  {$ENDIF}
  Result := RenameFile(BackupExe, CurrentExe);
end;

procedure TUpdateEngine.Reset;
begin
  // Cancel any ongoing operations
  Cancel;

  // Clean up temporary files
  CleanupTempFiles;

  // Reset state to idle
  SetState(usIdle, 'Ready to check for updates');

  // Clear last manifest
  FillChar(FLastManifest, SizeOf(FLastManifest), 0);
end;

// Compatibility function implementation
function GetTempDir: string;
begin
  {$IFDEF DELPHIXE_UP}
  Result := TPath.GetTempPath;
  {$ELSE}
  Result := GetEnvironmentVariable('TEMP');
  if Result = '' then
    Result := GetEnvironmentVariable('TMP');
  if Result = '' then
    Result := 'C:\TEMP\';
  Result := IncludeTrailingPathDelimiter(Result);
  {$ENDIF}
end;

// Simple manual file enumeration - guaranteed compatibility
procedure GetAllFiles(const Directory: string; Files: TStringList);

  procedure EnumFiles(const Dir: string);
  var
    SR: TSearchRec;
    Path: string;
    Dirs: TStringList;
    I: Integer;
  begin
    Path := IncludeTrailingPathDelimiter(Dir);
    Dirs := TStringList.Create;
    try
      // Collect all entries first
      if SysUtils.FindFirst(Path + '*.*', faAnyFile, SR) = 0 then
      try
        repeat
          if (SR.Name <> '.') and (SR.Name <> '..') then
          begin
            if (SR.Attr and faDirectory) = 0 then
              Files.Add(Path + SR.Name)  // It's a file
            else
              Dirs.Add(Path + SR.Name);  // It's a directory
          end;
        until SysUtils.FindNext(SR) <> 0;
      finally
        SysUtils.FindClose(SR);
      end;

      // Recurse into directories
      for I := 0 to Dirs.Count - 1 do
        EnumFiles(Dirs[I]);
    finally
      Dirs.Free;
    end;
  end;

begin
  EnumFiles(Directory);
end;

end.
