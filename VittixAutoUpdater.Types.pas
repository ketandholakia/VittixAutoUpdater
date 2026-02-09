{******************************************************************************}
{                         VittixAutoUpdater Component                         }
{                              Vittix (c) 2026                                 }
{                                                                              }
{                  A modern auto-updater for Delphi/Pascal applications       }
{                                                                              }
{******************************************************************************}
unit VittixAutoUpdater.Types;

{$IFDEF FPC}
  {$mode delphi}
{$ENDIF}

interface

uses
  Classes, SysUtils;

type
  // Version record with comparison operators
  TAppVersion = record
  public
    Major: Word;
    Minor: Word;
    Patch: Word;
    Build: Word;
    
    // Operators
    class operator Equal(const L, R: TAppVersion): Boolean;
    class operator NotEqual(const L, R: TAppVersion): Boolean;
    class operator GreaterThan(const L, R: TAppVersion): Boolean;
    class operator GreaterThanOrEqual(const L, R: TAppVersion): Boolean;
    class operator LessThan(const L, R: TAppVersion): Boolean;
    class operator LessThanOrEqual(const L, R: TAppVersion): Boolean;
    
    // Constructors
    constructor Create(const VersionStr: string); overload;
    {$IFDEF MSWINDOWS}
    constructor CreateFromFile(const FileName: string); overload;
    {$ENDIF}
    
    // Methods
    function ToString: string;
    function IsValid: Boolean;
    class function TryParse(const VersionStr: string; out Version: TAppVersion): Boolean; static;
  end;
  
  // Update states
  TUpdateState = (
    usIdle,           // Not updating
    usChecking,       // Checking for updates
    usAvailable,      // Update available
    usDownloading,    // Downloading update
    usVerifying,      // Verifying checksum
    usExtracting,     // Extracting files
    usApplying,       // Applying update
    usComplete,       // Update successful
    usFailed,         // Update failed
    usCancelled       // Cancelled by user
  );
  
  // Update severity
  TUpdateSeverity = (
    usOptional,       // Optional update
    usRecommended,    // Recommended update
    usCritical        // Critical security update
  );
  
  // Update manifest record
  TUpdateManifest = record
    AppName: string;
    Version: TAppVersion;
    DownloadUrl: string;
    ReleaseNotes: string;
    FileSize: Int64;
    Checksum: string;       // SHA256 hash
    MinVersion: TAppVersion; // Minimum version that can update
    ReleaseDate: TDateTime;
    Severity: TUpdateSeverity;
    
    function IsValid: Boolean;
  end;
  
  // Download progress event
  TDownloadProgressEvent = procedure(Sender: TObject; 
    BytesReceived, TotalBytes: Int64; 
    var Cancel: Boolean) of object;
  
  // Update state change event
  TUpdateStateEvent = procedure(Sender: TObject; 
    NewState: TUpdateState; 
    const StatusMessage: string) of object;
  
  // Update check result
  TUpdateCheckResult = (
    ucrUpdateAvailable,
    ucrNoUpdateAvailable,
    ucrError
  );
  
  // Callback for update check
  TUpdateCheckCallback = reference to procedure(
    Result: TUpdateCheckResult;
    const Manifest: TUpdateManifest;
    const ErrorMessage: string);
  
  // Configuration for updater
  TUpdaterConfig = record
    AppName: string;
    ManifestUrls: TArray<string>;
    CheckInterval: Integer;        // Hours between checks
    AutoDownload: Boolean;
    AutoInstall: Boolean;
    AllowDowngrade: Boolean;
    TempFolder: string;
    ConnectionTimeout: Integer;    // Seconds
    MaxRetries: Integer;
    
    class function Default: TUpdaterConfig; static;
  end;

  // Custom exceptions
  EUpdaterException = class(Exception);
  ENetworkException = class(EUpdaterException);
  EFileSystemException = class(EUpdaterException);
  EVersionException = class(EUpdaterException);

{$IFDEF MSWINDOWS}
function GetFileVersion(const FileName: string; out Version: TAppVersion): Boolean;
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}
uses
  Windows;
{$ENDIF}

{ TAppVersion }

constructor TAppVersion.Create(const VersionStr: string);
begin
  if not TryParse(VersionStr, Self) then
    raise EVersionException.CreateFmt('Invalid version string: %s', [VersionStr]);
end;

{$IFDEF MSWINDOWS}
constructor TAppVersion.CreateFromFile(const FileName: string);
begin
  Self := Default(TAppVersion);
  if not GetFileVersion(FileName, Self) then
    raise EVersionException.CreateFmt('Cannot read version from file: %s', [FileName]);
end;
{$ENDIF}

class operator TAppVersion.Equal(const L, R: TAppVersion): Boolean;
begin
  Result := (L.Major = R.Major) and 
            (L.Minor = R.Minor) and 
            (L.Patch = R.Patch) and 
            (L.Build = R.Build);
end;

class operator TAppVersion.NotEqual(const L, R: TAppVersion): Boolean;
begin
  Result := not (L = R);
end;

class operator TAppVersion.GreaterThan(const L, R: TAppVersion): Boolean;
begin
  if L.Major <> R.Major then Exit(L.Major > R.Major);
  if L.Minor <> R.Minor then Exit(L.Minor > R.Minor);
  if L.Patch <> R.Patch then Exit(L.Patch > R.Patch);
  Result := L.Build > R.Build;
end;

class operator TAppVersion.GreaterThanOrEqual(const L, R: TAppVersion): Boolean;
begin
  Result := (L > R) or (L = R);
end;

class operator TAppVersion.LessThan(const L, R: TAppVersion): Boolean;
begin
  if L.Major <> R.Major then Exit(L.Major < R.Major);
  if L.Minor <> R.Minor then Exit(L.Minor < R.Minor);
  if L.Patch <> R.Patch then Exit(L.Patch < R.Patch);
  Result := L.Build < R.Build;
end;

class operator TAppVersion.LessThanOrEqual(const L, R: TAppVersion): Boolean;
begin
  Result := (L < R) or (L = R);
end;

function TAppVersion.ToString: string;
begin
  Result := Format('%d.%d.%d.%d', [Major, Minor, Patch, Build]);
end;

function TAppVersion.IsValid: Boolean;
begin
  // At minimum, major version should be > 0
  Result := (Major > 0) or (Minor > 0) or (Patch > 0) or (Build > 0);
end;

class function TAppVersion.TryParse(const VersionStr: string; 
  out Version: TAppVersion): Boolean;
var
  Parts: TArray<string>;
begin
  Result := False;
  Version := Default(TAppVersion);
  
  if VersionStr.IsEmpty then
    Exit;
  
  Parts := VersionStr.Split(['.']);
  
  try
    if Length(Parts) >= 1 then
      Version.Major := StrToInt(Trim(Parts[0]));
    if Length(Parts) >= 2 then
      Version.Minor := StrToInt(Trim(Parts[1]));
    if Length(Parts) >= 3 then
      Version.Patch := StrToInt(Trim(Parts[2]));
    if Length(Parts) >= 4 then
      Version.Build := StrToInt(Trim(Parts[3]));
    
    Result := True;
  except
    on E: EConvertError do
      Result := False;
  end;
end;

{$IFDEF MSWINDOWS}
function GetFileVersion(const FileName: string; out Version: TAppVersion): Boolean;
var
  InfoSize, Handle: DWORD;
  VerBuf: Pointer;
  VerInfo: PVSFixedFileInfo;
  VerSize: DWORD;
  FileNameW: string;
begin
  Result := False;
  Version := Default(TAppVersion);
  
  FileNameW := FileName;
  InfoSize := GetFileVersionInfoSize(PChar(FileNameW), Handle);
  
  if InfoSize = 0 then
    Exit;
  
  GetMem(VerBuf, InfoSize);
  try
    if GetFileVersionInfo(PChar(FileNameW), Handle, InfoSize, VerBuf) then
    begin
      if VerQueryValue(VerBuf, '\', Pointer(VerInfo), VerSize) then
      begin
        Version.Major := HiWord(VerInfo.dwFileVersionMS);
        Version.Minor := LoWord(VerInfo.dwFileVersionMS);
        Version.Patch := HiWord(VerInfo.dwFileVersionLS);
        Version.Build := LoWord(VerInfo.dwFileVersionLS);
        Result := True;
      end;
    end;
  finally
    FreeMem(VerBuf);
  end;
end;
{$ENDIF}

{ TUpdateManifest }

function TUpdateManifest.IsValid: Boolean;
begin
  Result := not AppName.IsEmpty and 
            Version.IsValid and 
            not DownloadUrl.IsEmpty and
            (FileSize > 0);
end;

{ TUpdaterConfig }

class function TUpdaterConfig.Default: TUpdaterConfig;
begin
  Result.AppName := '';
  SetLength(Result.ManifestUrls, 0);
  Result.CheckInterval := 24;  // Check daily
  Result.AutoDownload := False;
  Result.AutoInstall := False;
  Result.AllowDowngrade := False;
  Result.TempFolder := '';     // Use system temp
  Result.ConnectionTimeout := 30;
  Result.MaxRetries := 3;
end;

end.
