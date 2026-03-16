unit VittixAutoUpdater.Types;

{$IFDEF FPC}
  {$mode delphi}
{$ENDIF}

interface

uses
  Classes, SysUtils;

type
  // ================================
  // Version record with strong parsing
  // ================================
  TAppVersion = record
  public
    Major: Word;
    Minor: Word;
    Patch: Word;
    Build: Word;

    class operator Equal(const L, R: TAppVersion): Boolean;
    class operator NotEqual(const L, R: TAppVersion): Boolean;
    class operator GreaterThan(const L, R: TAppVersion): Boolean;
    class operator GreaterThanOrEqual(const L, R: TAppVersion): Boolean;
    class operator LessThan(const L, R: TAppVersion): Boolean;
    class operator LessThanOrEqual(const L, R: TAppVersion): Boolean;

    constructor Create(const VersionStr: string); overload;
{$IFDEF MSWINDOWS}
    constructor CreateFromFile(const FileName: string); overload;
{$ENDIF}

    function ToString: string;
    function IsValid: Boolean;
    function IsZero: Boolean;

    class function TryParse(
      const VersionStr: string;
      out Version: TAppVersion): Boolean; static;
  end;

  // ================================
  // Update state machine
  // ================================
  TUpdateState = (
    usIdle,
    usChecking,
    usAvailable,
    usDownloading,
    usVerifying,
    usExtracting,
    usApplying,
    usReady,
    usComplete,
    usFailed,
    usCancelled
  );

  // ================================
  // Severity levels
  // ================================
  TUpdateSeverity = (
    usOptional,
    usRecommended,
    usCritical
  );

  // ================================
  // Manifest model (safer + clearer)
  // ================================
  TUpdateManifest = record
    AppName: string;
    Version: TAppVersion;
    DownloadUrl: string;
    ReleaseNotes: string;
    FileSize: Int64;
    Checksum: string;        // sha256:<hash>
    MinVersion: TAppVersion; // optional
    ReleaseDate: TDateTime;
    Severity: TUpdateSeverity;

    function IsValid: Boolean;
    function HasMinVersion: Boolean;
    class function Empty: TUpdateManifest; static;
  end;

  // ================================
  // Events
  // ================================
  TDownloadProgressEvent =
    procedure(
      Sender: TObject;
      BytesReceived,
      TotalBytes: Int64;
      var Cancel: Boolean) of object;

  TUpdateStateEvent =
    procedure(
      Sender: TObject;
      NewState: TUpdateState;
      const StatusMessage: string) of object;

  // ================================
  // Update result
  // ================================
  TUpdateCheckResult = (
    ucrUpdateAvailable,
    ucrNoUpdateAvailable,
    ucrError
  );

  TUpdateCheckCallback = reference to procedure(
    Result: TUpdateCheckResult;
    const Manifest: TUpdateManifest;
    const ErrorMessage: string);

  // ================================
  // Configuration (safer defaults)
  // ================================
  TUpdaterConfig = record
    AppName: string;
    ManifestUrls: TArray<string>;
    CheckInterval: Integer;      // hours
    AutoDownload: Boolean;
    AutoInstall: Boolean;
    AllowDowngrade: Boolean;
    TempFolder: string;
    ConnectionTimeout: Integer;  // seconds
    MaxRetries: Integer;
    UserAgent: string;

    class function Default: TUpdaterConfig; static;
  end;

  // ================================
  // Exceptions (clear hierarchy)
  // ================================
  EUpdaterException = class(Exception);
  ENetworkException = class(EUpdaterException);
  EFileSystemException = class(EUpdaterException);
  EVersionException = class(EUpdaterException);

// Helper procedure for version string parsing
procedure ParseVersionString(const VersionStr: string; var Parts: TArray<string>);

{$IFDEF MSWINDOWS}
function GetFileVersion(
  const FileName: string;
  out Version: TAppVersion): Boolean;
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}
uses
  Windows;
{$ENDIF}

{ ===================== TAppVersion ===================== }

constructor TAppVersion.Create(const VersionStr: string);
begin
  if not TryParse(VersionStr, Self) then
    raise EVersionException.CreateFmt(
      'Invalid version string: %s', [VersionStr]);
end;

{$IFDEF MSWINDOWS}
constructor TAppVersion.CreateFromFile(const FileName: string);
begin
  FillChar(Self, SizeOf(Self), 0);
  if not GetFileVersion(FileName, Self) then
    raise EVersionException.CreateFmt(
      'Cannot read version from file: %s', [FileName]);
end;
{$ENDIF}

class operator TAppVersion.Equal(const L, R: TAppVersion): Boolean;
begin
  Result :=
    (L.Major = R.Major) and
    (L.Minor = R.Minor) and
    (L.Patch = R.Patch) and
    (L.Build = R.Build);
end;

class operator TAppVersion.NotEqual(const L, R: TAppVersion): Boolean;
begin
  Result := not (L = R);
end;

class operator TAppVersion.GreaterThan(
  const L, R: TAppVersion): Boolean;
begin
  if L.Major <> R.Major then Exit(L.Major > R.Major);
  if L.Minor <> R.Minor then Exit(L.Minor > R.Minor);
  if L.Patch <> R.Patch then Exit(L.Patch > R.Patch);
  Result := L.Build > R.Build;
end;

class operator TAppVersion.GreaterThanOrEqual(
  const L, R: TAppVersion): Boolean;
begin
  Result := (L > R) or (L = R);
end;

class operator TAppVersion.LessThan(
  const L, R: TAppVersion): Boolean;
begin
  if L.Major <> R.Major then Exit(L.Major < R.Major);
  if L.Minor <> R.Minor then Exit(L.Minor < R.Minor);
  if L.Patch <> R.Patch then Exit(L.Patch < R.Patch);
  Result := L.Build < R.Build;
end;

class operator TAppVersion.LessThanOrEqual(
  const L, R: TAppVersion): Boolean;
begin
  Result := (L < R) or (L = R);
end;

function TAppVersion.ToString: string;
begin
  Result := Format('%d.%d.%d.%d',
    [Major, Minor, Patch, Build]);
end;

function TAppVersion.IsValid: Boolean;
begin
  Result := not IsZero;
end;

function TAppVersion.IsZero: Boolean;
begin
  Result :=
    (Major = 0) and
    (Minor = 0) and
    (Patch = 0) and
    (Build = 0);
end;

class function TAppVersion.TryParse(
  const VersionStr: string;
  out Version: TAppVersion): Boolean;
var
  Parts: TArray<string>;
begin
  Result := False;
  FillChar(Version, SizeOf(Version), 0);

  if Trim(VersionStr) = '' then
    Exit;

  // Split version string by dots - compatible with older Delphi
  SetLength(Parts, 0);
  ParseVersionString(VersionStr, Parts);

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
    Result := False;
  end;
end;

{$IFDEF MSWINDOWS}
function GetFileVersion(
  const FileName: string;
  out Version: TAppVersion): Boolean;
var
  InfoSize, Handle: DWORD;
  VerBuf: Pointer;
  VerInfo: PVSFixedFileInfo;
  VerSize: DWORD;
begin
  Result := False;
  FillChar(Version, SizeOf(Version), 0);

  InfoSize := GetFileVersionInfoSize(PChar(FileName), Handle);
  if InfoSize = 0 then
    Exit;

  GetMem(VerBuf, InfoSize);
  try
    if GetFileVersionInfo(
         PChar(FileName), Handle, InfoSize, VerBuf) then
    begin
      if VerQueryValue(
           VerBuf, '\', Pointer(VerInfo), VerSize) then
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

{ ===================== TUpdateManifest ===================== }

function TUpdateManifest.HasMinVersion: Boolean;
begin
  Result := MinVersion.IsValid;
end;

function TUpdateManifest.IsValid: Boolean;
begin
  Result :=
    (Trim(AppName) <> '') and
    Version.IsValid and
    (Trim(DownloadUrl) <> '');
end;

{ ===================== TUpdaterConfig ===================== }

class function TUpdaterConfig.Default: TUpdaterConfig;
begin
  Result.AppName := '';
  SetLength(Result.ManifestUrls, 0);

  Result.CheckInterval := 24;     // daily
  Result.AutoDownload := False;
  Result.AutoInstall := False;
  Result.AllowDowngrade := False;
  Result.TempFolder := '';        // system temp

  Result.ConnectionTimeout := 30; // seconds
  Result.MaxRetries := 3;
  Result.UserAgent := 'VittixAutoUpdater/1.0';
end;

// Helper procedure for parsing version strings (compatibility)
procedure ParseVersionString(const VersionStr: string; var Parts: TArray<string>);
var
  S: string;
  I, StartPos, Len: Integer;
  PartsList: array of string;
  Count: Integer;
begin
  S := VersionStr;
  Count := 0;
  SetLength(PartsList, 10); // Initial capacity

  StartPos := 1;
  for I := 1 to Length(S) do
  begin
    if S[I] = '.' then
    begin
      if Count >= Length(PartsList) then
        SetLength(PartsList, Length(PartsList) * 2);
      PartsList[Count] := Copy(S, StartPos, I - StartPos);
      Inc(Count);
      StartPos := I + 1;
    end;
  end;

  // Add the last part
  if StartPos <= Length(S) then
  begin
    if Count >= Length(PartsList) then
      SetLength(PartsList, Count + 1);
    PartsList[Count] := Copy(S, StartPos, Length(S) - StartPos + 1);
    Inc(Count);
  end;

  // Copy to result array
  SetLength(Parts, Count);
  for I := 0 to Count - 1 do
    Parts[I] := PartsList[I];
end;

class function TUpdateManifest.Empty: TUpdateManifest;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.AppName := '';
  Result.DownloadUrl := '';
  Result.ReleaseNotes := '';
  Result.Checksum := '';
  FillChar(Result.Version, SizeOf(Result.Version), 0);
  FillChar(Result.MinVersion, SizeOf(Result.MinVersion), 0);
  Result.ReleaseDate := 0;
  Result.Severity := usOptional;
end;

end.
