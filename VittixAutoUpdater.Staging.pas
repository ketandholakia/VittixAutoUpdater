unit VittixAutoUpdater.Staging;

interface

{$IFDEF MSWINDOWS}
function GetPrivateStagingBase(const ConfiguredRoot: string): string;
function AllocatePrivateStagingDirectory(const BaseDirectory: string): string;
function SafeDeletePrivateStagingDirectory(const Directory, BaseDirectory: string): Boolean;
function CreateExclusiveStagingFile(const FileName: string): Boolean;
function IsPathWithoutReparsePoints(const Directory: string): Boolean;
{$IFDEF VITTIX_TEST_STAGING}
procedure SetStagingTestIdentifiers(const Identifiers: TArray<string>);
procedure SetStagingTestRandomFailure(Value: Boolean);
{$ENDIF}
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}

uses
  Winapi.Windows,
  Winapi.ActiveX,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils;

function SHGetKnownFolderPath(const FolderId: TGUID; Flags: DWORD;
  Token: THandle; out Path: PWideChar): HRESULT; stdcall;
  external 'shell32.dll' name 'SHGetKnownFolderPath';

function BCryptGenRandom(Algorithm: THandle; Buffer: PByte; Length,
  Flags: ULONG): LongInt; stdcall; external 'bcrypt.dll' name 'BCryptGenRandom';
function ConvertStringSecurityDescriptorToSecurityDescriptorW(
  StringSecurityDescriptor: PWideChar; StringSDRevision: DWORD;
  var SecurityDescriptor: Pointer; SecurityDescriptorSize: PULONG): BOOL;
  stdcall; external 'advapi32.dll'
  name 'ConvertStringSecurityDescriptorToSecurityDescriptorW';

const
  FOLDERID_LocalAppData: TGUID = '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}';
  BCRYPT_USE_SYSTEM_PREFERRED_RNG = $00000002;
  STAGING_PREFIX = 'VittixAutoUpdater-';
  MAX_STAGING_PATH = 230;

{$IFDEF VITTIX_TEST_STAGING}
var
  GTestIdentifiers: TArray<string>;
  GTestIdentifierIndex: Integer;
  GTestRandomFailure: Boolean;

procedure SetStagingTestIdentifiers(const Identifiers: TArray<string>);
begin
  GTestIdentifiers := Copy(Identifiers);
  GTestIdentifierIndex := 0;
end;

procedure SetStagingTestRandomFailure(Value: Boolean);
begin
  GTestRandomFailure := Value;
end;
{$ENDIF}

function IsAbsoluteLocalPath(const Value: string): Boolean;
begin
  Result := (Length(Value) >= 3) and
    CharInSet(Value[1], ['A'..'Z', 'a'..'z']) and
    (Value[2] = ':') and CharInSet(Value[3], ['\', '/']);
end;

function IsPathWithoutReparsePoints(const Directory: string): Boolean;
var
  FullPath, CurrentPath, Rest, Part: string;
  P: Integer;
  Attr: DWORD;
begin
  Result := False;
  FullPath := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Directory));
  if not IsAbsoluteLocalPath(FullPath) then
    Exit;
  CurrentPath := Copy(FullPath, 1, 3);
  Rest := Copy(FullPath, 4, MaxInt);
  while Rest <> '' do
  begin
    P := Pos(PathDelim, Rest);
    if P = 0 then
    begin
      Part := Rest;
      Rest := '';
    end
    else
    begin
      Part := Copy(Rest, 1, P - 1);
      Delete(Rest, 1, P);
    end;
    if Part = '' then
      Continue;
    CurrentPath := IncludeTrailingPathDelimiter(CurrentPath) + Part;
    Attr := GetFileAttributes(PChar(CurrentPath));
    if Attr = INVALID_FILE_ATTRIBUTES then
      Exit;
    if (Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
      Exit;
    if (Rest <> '') and ((Attr and FILE_ATTRIBUTE_DIRECTORY) = 0) then
      Exit;
  end;
  Result := True;
end;

function GetPrivateStagingBase(const ConfiguredRoot: string): string;
var
  KnownPath: PWideChar;
  LocalRoot, Candidate: string;
  HR: HRESULT;
begin
  KnownPath := nil;
  HR := SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, 0, KnownPath);
  if Failed(HR) or (KnownPath = nil) then
    RaiseLastOSError(HR);
  try
    LocalRoot := ExcludeTrailingPathDelimiter(TPath.GetFullPath(KnownPath));
  finally
    CoTaskMemFree(KnownPath);
  end;

  if ConfiguredRoot = '' then
    Candidate := LocalRoot
  else
    Candidate := ExcludeTrailingPathDelimiter(TPath.GetFullPath(ConfiguredRoot));

  if not IsAbsoluteLocalPath(Candidate) then
    raise EOSError.Create('Secure staging requires an absolute local directory');
  if (Length(Candidate) < Length(LocalRoot)) or
     not SameText(Copy(Candidate, 1, Length(LocalRoot)), LocalRoot) or
     ((Length(Candidate) > Length(LocalRoot)) and
      (Candidate[Length(LocalRoot) + 1] <> PathDelim)) then
    raise EOSError.Create(
      'Configured staging folder must be inside the current user LocalAppData folder');
  if not IsPathWithoutReparsePoints(Candidate) then
    raise EOSError.Create('Staging root is missing or contains a reparse point');
  Result := Candidate;
end;

function CreatePrivateDirectory(const Directory: string): DWORD;
var
  SecurityDescriptor: Pointer;
  SecurityAttributes: SECURITY_ATTRIBUTES;
begin
  Result := ERROR_INVALID_SECURITY_DESCR;
  SecurityDescriptor := nil;
  if not ConvertStringSecurityDescriptorToSecurityDescriptorW(
    'D:P(A;OICI;FA;;;OW)(A;OICI;FA;;;SY)', 1,
    SecurityDescriptor, nil) then
    Exit;
  try
    SecurityAttributes.nLength := SizeOf(SecurityAttributes);
    SecurityAttributes.lpSecurityDescriptor := SecurityDescriptor;
    SecurityAttributes.bInheritHandle := False;
    if CreateDirectory(PChar(Directory), @SecurityAttributes) then
      Result := ERROR_SUCCESS
    else
      Result := GetLastError;
  finally
    LocalFree(HLOCAL(SecurityDescriptor));
  end;
end;

function RandomLeaf: string;
var
  Bytes: array[0..15] of Byte;
  I: Integer;
begin
{$IFDEF VITTIX_TEST_STAGING}
  if GTestRandomFailure then
    raise EOSError.Create('Injected staging identifier generation failure');
  if GTestIdentifierIndex < Length(GTestIdentifiers) then
  begin
    Result := STAGING_PREFIX + GTestIdentifiers[GTestIdentifierIndex];
    Inc(GTestIdentifierIndex);
    Exit;
  end;
{$ENDIF}
  if BCryptGenRandom(0, @Bytes[0], SizeOf(Bytes),
    BCRYPT_USE_SYSTEM_PREFERRED_RNG) <> 0 then
    raise EOSError.Create('Windows cryptographic random generation failed');
  Result := STAGING_PREFIX;
  for I := Low(Bytes) to High(Bytes) do
    Result := Result + IntToHex(Bytes[I], 2);
end;

function AllocatePrivateStagingDirectory(const BaseDirectory: string): string;
var
  I: Integer;
  ErrorCode: DWORD;
  Candidate: string;
begin
  if not IsPathWithoutReparsePoints(BaseDirectory) then
    raise EOSError.Create('Staging base is missing or contains a reparse point');
  for I := 1 to 16 do
  begin
    Candidate := IncludeTrailingPathDelimiter(BaseDirectory) + RandomLeaf;
    if Length(Candidate) > MAX_STAGING_PATH then
      raise EOSError.Create('Secure staging path exceeds the supported path limit');
    ErrorCode := CreatePrivateDirectory(Candidate);
    if ErrorCode = ERROR_SUCCESS then
    begin
      if not IsPathWithoutReparsePoints(Candidate) then
      begin
        RemoveDirectory(PChar(Candidate));
        raise EOSError.Create('New staging directory failed reparse validation');
      end;
      Exit(Candidate);
    end;
    if ErrorCode <> ERROR_ALREADY_EXISTS then
      raise EOSError.CreateFmt('Could not create private staging directory (Windows error %d)',
        [ErrorCode]);
  end;
  raise EOSError.Create('Could not allocate a unique private staging directory');
end;

function IsExpectedStagingDirectory(const Directory, BaseDirectory: string): Boolean;
var
  FullPath, FullBase, Leaf: string;
  I: Integer;
begin
  Result := False;
  try
    FullPath := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Directory));
    FullBase := ExcludeTrailingPathDelimiter(TPath.GetFullPath(BaseDirectory));
    if not SameText(ExtractFileDir(FullPath), FullBase) then
      Exit;
    Leaf := ExtractFileName(FullPath);
    if not StartsText(STAGING_PREFIX, Leaf) or (Length(Leaf) <> Length(STAGING_PREFIX) + 32) then
      Exit;
    for I := Length(STAGING_PREFIX) + 1 to Length(Leaf) do
      if not CharInSet(Leaf[I], ['0'..'9', 'a'..'f', 'A'..'F']) then
        Exit;
    Result := IsPathWithoutReparsePoints(FullPath);
  except
    Result := False;
  end;
end;

procedure DeleteTreeNoFollow(const Directory: string);
var
  SR: TSearchRec;
  Path, Child: string;
  Attr: DWORD;
begin
  Path := IncludeTrailingPathDelimiter(Directory);
  if FindFirst(Path + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      Child := Path + SR.Name;
      Attr := GetFileAttributes(PChar(Child));
      if Attr = INVALID_FILE_ATTRIBUTES then
        raise EOSError.CreateFmt('Could not inspect staging artifact "%s"', [Child]);
      if (Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
      begin
        if (Attr and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
        begin
          if not RemoveDirectory(PChar(Child)) then
            RaiseLastOSError;
        end
        else
          if not DeleteFile(PChar(Child)) then
            RaiseLastOSError;
      end
      else if (Attr and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
        DeleteTreeNoFollow(Child)
      else if not DeleteFile(PChar(Child)) then
        RaiseLastOSError;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  if not RemoveDirectory(PChar(Directory)) and
     (GetLastError <> ERROR_FILE_NOT_FOUND) then
    RaiseLastOSError;
end;

function SafeDeletePrivateStagingDirectory(const Directory, BaseDirectory: string): Boolean;
begin
  Result := False;
  if not IsExpectedStagingDirectory(Directory, BaseDirectory) then
    Exit;
  try
    DeleteTreeNoFollow(Directory);
    Result := True;
  except
    Result := False;
  end;
end;

function CreateExclusiveStagingFile(const FileName: string): Boolean;
var
  Handle: THandle;
begin
  Handle := CreateFile(PChar(FileName), GENERIC_WRITE, 0, nil, CREATE_NEW,
    FILE_ATTRIBUTE_NORMAL, 0);
  Result := Handle <> INVALID_HANDLE_VALUE;
  if Result then
    CloseHandle(Handle);
end;

{$ENDIF}

end.
