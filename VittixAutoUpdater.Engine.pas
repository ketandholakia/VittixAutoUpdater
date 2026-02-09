{******************************************************************************}
{                         VittixAutoUpdater Component                         }
{                              Vittix (c) 2026                                 }
{                                                                              }
{                  A modern auto-updater for Delphi/Pascal applications       }
{                                                                              }
{******************************************************************************}
unit VittixAutoUpdater.Engine;

{$IFDEF FPC}
  {$mode delphi}
{$ENDIF}

interface

uses
  Classes, SysUtils, VittixAutoUpdater.Types, VittixAutoUpdater.Network;

type
  // Main updater engine
  TUpdateEngine = class
  private
    FConfig: TUpdaterConfig;
    FNetwork: TUpdateNetworkManager;
    FCurrentVersion: TAppVersion;
    FState: TUpdateState;
    FDownloadedFile: string;
    FOnStateChange: TUpdateStateEvent;
    FOnDownloadProgress: TDownloadProgressEvent;
    
    procedure SetState(NewState: TUpdateState; const StatusMsg: string);
    function GetTempFileName: string;
    procedure CleanupTempFiles;
    function ExtractUpdate(const ZipFile, DestPath: string): Boolean;
    function BackupCurrentVersion: Boolean;
    function ApplyUpdateFiles(const SourcePath: string): Boolean;
  public
    constructor Create(const Config: TUpdaterConfig);
    destructor Destroy; override;
    
    // Check for updates (async callback)
    procedure CheckForUpdate(Callback: TUpdateCheckCallback);
    
    // Download update (synchronous, use in thread)
    function DownloadUpdate(const Manifest: TUpdateManifest): Boolean;
    
    // Apply downloaded update
    function ApplyUpdate: Boolean;
    
    // Cancel ongoing operation
    procedure Cancel;
    
    // Rollback to previous version
    function Rollback: Boolean;
    
    // Properties
    property CurrentVersion: TAppVersion read FCurrentVersion write FCurrentVersion;
    property State: TUpdateState read FState;
    property Config: TUpdaterConfig read FConfig write FConfig;
    
    // Events
    property OnStateChange: TUpdateStateEvent read FOnStateChange write FOnStateChange;
    property OnDownloadProgress: TDownloadProgressEvent read FOnDownloadProgress write FOnDownloadProgress;
  end;

implementation

uses
  {$IFDEF MSWINDOWS}
  Windows, ShellAPI,
  {$ENDIF}
  System.Zip, System.IOUtils;

{ TUpdateEngine }

constructor TUpdateEngine.Create(const Config: TUpdaterConfig);
begin
  inherited Create;
  FConfig := Config;
  FNetwork := TUpdateNetworkManager.Create;
  FNetwork.ConnectionTimeout := Config.ConnectionTimeout * 1000;
  FNetwork.MaxRetries := Config.MaxRetries;
  FState := usIdle;
  
  // Get current version from executable
  try
    {$IFDEF MSWINDOWS}
    FCurrentVersion := TAppVersion.CreateFromFile(ParamStr(0));
    {$ELSE}
    // For non-Windows, version must be set manually
    FCurrentVersion := Default(TAppVersion);
    {$ENDIF}
  except
    FCurrentVersion := Default(TAppVersion);
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

function TUpdateEngine.GetTempFileName: string;
var
  TempPath: string;
begin
  if FConfig.TempFolder.IsEmpty then
    TempPath := TPath.GetTempPath
  else
    TempPath := IncludeTrailingPathDelimiter(FConfig.TempFolder);
  
  Result := TempPath + FConfig.AppName + '_update_' + 
    FormatDateTime('yyyymmdd_hhnnss', Now) + '.zip';
end;

procedure TUpdateEngine.CleanupTempFiles;
begin
  if not FDownloadedFile.IsEmpty and FileExists(FDownloadedFile) then
  begin
    try
      DeleteFile(FDownloadedFile);
    except
      // Ignore cleanup errors
    end;
    FDownloadedFile := '';
  end;
end;

procedure TUpdateEngine.CheckForUpdate(Callback: TUpdateCheckCallback);
var
  Thread: TThread;
begin
  if FState <> usIdle then
    Exit;
  
  SetState(usChecking, 'Checking for updates...');
  
  Thread := TThread.CreateAnonymousThread(procedure
  var
    Manifest: TUpdateManifest;
    Success: Boolean;
    ErrorMsg: string;
  begin
    try
      Success := FNetwork.FetchManifest(FConfig.ManifestUrls, 
        FConfig.AppName, Manifest);
      
      if Success then
      begin
        // Check if update is available
        if Manifest.Version > FCurrentVersion then
        begin
          // Check minimum version requirement
          if (Manifest.MinVersion.IsValid) and 
             (FCurrentVersion < Manifest.MinVersion) then
          begin
            ErrorMsg := Format('Cannot update from version %s. ' +
              'Minimum required version is %s', 
              [FCurrentVersion.ToString, Manifest.MinVersion.ToString]);
            
            TThread.Synchronize(nil, procedure
            begin
              SetState(usFailed, ErrorMsg);
              if Assigned(Callback) then
                Callback(ucrError, Manifest, ErrorMsg);
            end);
          end
          else
          begin
            TThread.Synchronize(nil, procedure
            begin
              SetState(usAvailable, 'Update available');
              if Assigned(Callback) then
                Callback(ucrUpdateAvailable, Manifest, '');
            end);
          end;
        end
        else if (not FConfig.AllowDowngrade) and (Manifest.Version < FCurrentVersion) then
        begin
          ErrorMsg := 'Downgrade not allowed';
          TThread.Synchronize(nil, procedure
          begin
            SetState(usIdle, 'No updates');
            if Assigned(Callback) then
              Callback(ucrNoUpdateAvailable, Manifest, ErrorMsg);
          end);
        end
        else
        begin
          TThread.Synchronize(nil, procedure
          begin
            SetState(usIdle, 'No updates');
            if Assigned(Callback) then
              Callback(ucrNoUpdateAvailable, Manifest, '');
          end);
        end;
      end
      else
      begin
        ErrorMsg := 'Failed to fetch update manifest';
        TThread.Synchronize(nil, procedure
        begin
          SetState(usFailed, ErrorMsg);
          if Assigned(Callback) then
            Callback(ucrError, Default(TUpdateManifest), ErrorMsg);
        end);
      end;
      
    except
      on E: Exception do
      begin
        ErrorMsg := E.Message;
        TThread.Synchronize(nil, procedure
        begin
          SetState(usFailed, ErrorMsg);
          if Assigned(Callback) then
            Callback(ucrError, Default(TUpdateManifest), ErrorMsg);
        end);
      end;
    end;
  end);
  
  Thread.FreeOnTerminate := True;
  Thread.Start;
end;

function TUpdateEngine.DownloadUpdate(const Manifest: TUpdateManifest): Boolean;
begin
  Result := False;
  
  if FState <> usAvailable then
    Exit;
  
  SetState(usDownloading, 'Downloading update...');
  
  try
    FDownloadedFile := GetTempFileName;
    
    Result := FNetwork.DownloadFile(
      Manifest.DownloadUrl,
      FDownloadedFile,
      FOnDownloadProgress,
      Manifest.Checksum
    );
    
    if Result then
    begin
      SetState(usVerifying, 'Download complete');
    end
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

function TUpdateEngine.ExtractUpdate(const ZipFile, DestPath: string): Boolean;
var
  ZipArchive: TZipFile;
begin
  Result := False;
  
  try
    ForceDirectories(DestPath);
    
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
  Result := False;
  
  try
    CurrentExe := ParamStr(0);
    BackupExe := CurrentExe + '.old';
    
    // Delete old backup if exists
    if FileExists(BackupExe) then
      DeleteFile(BackupExe);
    
    // Rename current to backup
    Result := RenameFile(CurrentExe, BackupExe);
    
  except
    on E: Exception do
      Result := False;
  end;
end;

function TUpdateEngine.ApplyUpdateFiles(const SourcePath: string): Boolean;
var
  Files: TStringDynArray;
  FileName, SourceFile, DestFile: string;
  AppDir: string;
begin
  Result := False;
  
  try
    AppDir := ExtractFilePath(ParamStr(0));
    Files := TDirectory.GetFiles(SourcePath, '*.*', TSearchOption.soAllDirectories);
    
    for FileName in Files do
    begin
      SourceFile := FileName;
      DestFile := AppDir + ExtractRelativePath(SourcePath, FileName);
      
      // Create directory if needed
      ForceDirectories(ExtractFilePath(DestFile));
      
      // Copy file
      if not TFile.Copy(SourceFile, DestFile, True) then
        Exit(False);
    end;
    
    Result := True;
    
  except
    on E: Exception do
      Result := False;
  end;
end;

function TUpdateEngine.ApplyUpdate: Boolean;
var
  TempExtractPath: string;
  AppDir: string;
begin
  Result := False;
  
  if FDownloadedFile.IsEmpty or not FileExists(FDownloadedFile) then
    Exit;
  
  SetState(usExtracting, 'Extracting update...');
  
  try
    AppDir := ExtractFilePath(ParamStr(0));
    TempExtractPath := TPath.GetTempPath + FConfig.AppName + '_extract_' + 
      FormatDateTime('yyyymmdd_hhnnss', Now);
    
    // Extract files
    if not ExtractUpdate(FDownloadedFile, TempExtractPath) then
      Exit;
    
    SetState(usApplying, 'Installing update...');
    
    {$IFDEF MSWINDOWS}
    // On Windows, we need to use a batch script since we can't replace running exe
    Result := ApplyUpdateWindows(TempExtractPath);
    {$ELSE}
    // On other platforms, we can replace files directly
    if BackupCurrentVersion then
      Result := ApplyUpdateFiles(TempExtractPath);
    {$ENDIF}
    
    if Result then
    begin
      SetState(usComplete, 'Update installed successfully');
      CleanupTempFiles;
    end
    else
    begin
      SetState(usFailed, 'Failed to apply update');
    end;
    
  except
    on E: Exception do
    begin
      SetState(usFailed, 'Update error: ' + E.Message);
      Result := False;
    end;
  end;
end;

{$IFDEF MSWINDOWS}
function TUpdateEngine.ApplyUpdateWindows(const SourcePath: string): Boolean;
var
  BatchFile: string;
  BatchContent: TStringList;
  AppExe, NewExe: string;
begin
  Result := False;
  
  try
    AppExe := ParamStr(0);
    NewExe := IncludeTrailingPathDelimiter(SourcePath) + ExtractFileName(AppExe);
    
    if not FileExists(NewExe) then
      Exit;
    
    // Create update batch script
    BatchFile := TPath.GetTempPath + 'update_' + FConfig.AppName + '.bat';
    BatchContent := TStringList.Create;
    try
      BatchContent.Add('@echo off');
      BatchContent.Add('echo Waiting for application to close...');
      BatchContent.Add('timeout /t 2 /nobreak > nul');
      BatchContent.Add('');
      BatchContent.Add('REM Backup current version');
      BatchContent.Add(Format('if exist "%s.old" del /f /q "%s.old"', [AppExe, AppExe]));
      BatchContent.Add(Format('ren "%s" "%s.old"', [AppExe, ExtractFileName(AppExe)]));
      BatchContent.Add('');
      BatchContent.Add('REM Copy new files');
      BatchContent.Add(Format('xcopy "%s\*.*" "%s" /E /Y /I', 
        [SourcePath, ExtractFilePath(AppExe)]));
      BatchContent.Add('');
      BatchContent.Add('REM Start updated application');
      BatchContent.Add(Format('start "" "%s"', [AppExe]));
      BatchContent.Add('');
      BatchContent.Add('REM Cleanup');
      BatchContent.Add(Format('rd /s /q "%s"', [SourcePath]));
      BatchContent.Add('del "%~f0"');
      
      BatchContent.SaveToFile(BatchFile);
      
      // Execute batch script and exit
      ShellExecute(0, 'open', PChar(BatchFile), nil, nil, SW_HIDE);
      Result := True;
      
    finally
      BatchContent.Free;
    end;
    
  except
    on E: Exception do
      Result := False;
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
  Result := False;
  
  try
    CurrentExe := ParamStr(0);
    BackupExe := CurrentExe + '.old';
    
    if FileExists(BackupExe) then
    begin
      DeleteFile(CurrentExe);
      Result := RenameFile(BackupExe, CurrentExe);
    end;
    
  except
    on E: Exception do
      Result := False;
  end;
end;

end.
