unit VittixAutoUpdater.Engine;

{$IFDEF FPC}
  {$mode delphi}
{$ENDIF}

interface

uses
  Classes, SysUtils, SyncObjs,
  VittixAutoUpdater.Types,
  VittixAutoUpdater.Network;

// Compatibility function for getting temp directory
function GetTempDir: string;

// Compatibility function for file enumeration
procedure GetAllFiles(const Directory: string; Files: TStringList);

// Validates a ZIP entry and returns its canonical destination. Exposed so
// callers and regression tests can verify archive paths without extraction.
function IsSafeZipEntryPath(const DestinationPath, EntryName: string;
  out FullPath: string): Boolean;

function VerifyAuthenticodeFile(const FileName: string): Boolean;
function VerifyAuthenticodeFilePinned(const FileName: string;
  const PinnedThumbprints: TArray<string>): Boolean;
function TryGetAuthenticodeThumbprint(const FileName: string;
  out Thumbprint: string): Boolean;
function IsThumbprintPinned(const Thumbprint: string;
  const PinnedThumbprints: TArray<string>): Boolean;
function IsVersionAllowed(const CurrentVersion, AvailableVersion: TAppVersion;
  AllowDowngrade: Boolean): Boolean;
function IsManifestRollbackAllowed(const CandidateVersion: TAppVersion;
  CandidateIssuedAt: Int64; const CandidateChecksum, StoredState: string;
  out ErrorMessage: string): Boolean;
function BuildBatchCopyCommand(const SourcePath, DestinationPath: string): string;

{$IFDEF VITTIX_TEST_REGISTRY}
procedure SetRollbackRegistryTestScope(const KeyName: string);
procedure SetRollbackRegistryTestAccessFailure(Value: Boolean);
{$ENDIF}

type
  TUpdateEngine = class
  private
    FConfig: TUpdaterConfig;
    FNetwork: TUpdateNetworkManager;
    FCurrentVersion: TAppVersion;
    FState: TUpdateState;
    FDownloadedFile: string;
    FExtractPath: string;
    FStagingPath: string;
    FStagingBase: string;
    FLastManifest: TUpdateManifest;
    FCancelRequested: Boolean;
    FStateLock: TCriticalSection;
    FCheckOperationGeneration: Int64;
    FRestartAfterInstall: Boolean;
    FOnRestartRequired: TNotifyEvent;
    FOnSecurityWarning: TSecurityWarningEvent;
    FCheckThread: TThread;

    FOnStateChange: TUpdateStateEvent;
    FOnDownloadProgress: TDownloadProgressEvent;
{$IFDEF VITTIX_TEST_LOOPBACK}
    FOnZipProgressForTests: TNotifyEvent;
    FOnZipOutputForTests: TNotifyEvent;
    FOnZipBeforeCreateForTests: TNotifyEvent;
    FOnZipEntryCompleteForTests: TNotifyEvent;
    FOnZipBeforeCompleteForTests: TNotifyEvent;
{$ENDIF}

    procedure SetState(NewState: TUpdateState; const StatusMsg: string);
    procedure SetConfig(const Value: TUpdaterConfig);
    procedure QueueCheckCompletion(OperationGeneration: Int64;
      const Action: TThreadProcedure);
    function GetTempZipFile: string;
    function GetTempExtractPath: string;
    procedure CleanupTempFiles;

    function ExtractUpdate(const ZipFile, DestPath: string): Boolean;

{$IFDEF MSWINDOWS}
    function ApplyUpdateWindows(const SourcePath: string): Boolean;
{$ENDIF}

    function IsSafeToApply: Boolean;
    procedure SetOnSecurityWarning(const Value: TSecurityWarningEvent);

  public
    constructor Create(const Config: TUpdaterConfig);
    destructor Destroy; override;

    procedure CheckForUpdate(Callback: TUpdateCheckCallback);
    function DownloadUpdate(const Manifest: TUpdateManifest): Boolean;
    function ApplyUpdate: Boolean;

    procedure Cancel;
    function Rollback: Boolean;
    procedure Reset;
    procedure ReportSecurityWarnings;

{$IFDEF VITTIX_TEST_LOOPBACK}
    procedure EnableLoopbackHttpForTests;
    function WaitForCheckWorkerForTests(Timeout: Cardinal): Boolean;
    function ExtractArchiveForTests(const ZipFile, DestPath: string): Boolean;
    function ExtractDownloadedPackageForTests(out ExtractedPath: string): Boolean;
    function ApplyArchiveForTests(const ZipFile: string;
      out OperationStagingPath: string): Boolean;
    property OnZipProgressForTests: TNotifyEvent read FOnZipProgressForTests
      write FOnZipProgressForTests;
    property OnZipOutputForTests: TNotifyEvent read FOnZipOutputForTests
      write FOnZipOutputForTests;
    property OnZipBeforeCreateForTests: TNotifyEvent
      read FOnZipBeforeCreateForTests write FOnZipBeforeCreateForTests;
    property OnZipEntryCompleteForTests: TNotifyEvent
      read FOnZipEntryCompleteForTests write FOnZipEntryCompleteForTests;
    property OnZipBeforeCompleteForTests: TNotifyEvent
      read FOnZipBeforeCompleteForTests write FOnZipBeforeCompleteForTests;
{$ENDIF}

    property CurrentVersion: TAppVersion read FCurrentVersion write FCurrentVersion;
    property State: TUpdateState read FState;
    property Config: TUpdaterConfig read FConfig write SetConfig;
    property LastManifest: TUpdateManifest read FLastManifest;

    // On Windows, request host shutdown after the helper has been started.
    // Assign OnRestartRequired to control the host-specific shutdown behavior.
    property RestartAfterInstall: Boolean
      read FRestartAfterInstall write FRestartAfterInstall;
    property OnRestartRequired: TNotifyEvent
      read FOnRestartRequired write FOnRestartRequired;
    property OnSecurityWarning: TSecurityWarningEvent
      read FOnSecurityWarning write SetOnSecurityWarning;

    property OnStateChange: TUpdateStateEvent
      read FOnStateChange write FOnStateChange;

    property OnDownloadProgress: TDownloadProgressEvent
      read FOnDownloadProgress write FOnDownloadProgress;
  end;

implementation

uses
{$IFDEF MSWINDOWS}
  Windows, ShellAPI, Forms, System.Hash, System.Win.Registry,
{$ENDIF}
  {$IFDEF DELPHIXE_UP}
  System.Zip, System.IOUtils, System.Types, System.StrUtils,
  System.Generics.Collections,
  VittixAutoUpdater.Staging;
  {$ELSE}
  Zip, IOUtils, StrUtils, Generics.Collections,
  VittixAutoUpdater.Staging;
  {$ENDIF}

type
  TZipCancellationObserver = class
  private
    FEngine: TUpdateEngine;
  public
    constructor Create(AEngine: TUpdateEngine);
    procedure OnProgress(Sender: TObject; FileName: string; Header: TZipHeader;
      Position: Int64);
  end;

constructor TZipCancellationObserver.Create(AEngine: TUpdateEngine);
begin
  inherited Create;
  FEngine := AEngine;
end;

procedure TZipCancellationObserver.OnProgress(Sender: TObject; FileName: string;
  Header: TZipHeader; Position: Int64);
var
  CancelRequested: Boolean;
begin
{$IFDEF VITTIX_TEST_LOOPBACK}
  if Assigned(FEngine.FOnZipProgressForTests) then
    FEngine.FOnZipProgressForTests(FEngine);
{$ENDIF}
  FEngine.FStateLock.Acquire;
  try
    CancelRequested := FEngine.FCancelRequested;
  finally
    FEngine.FStateLock.Release;
  end;
  if CancelRequested then
    raise EAbort.Create('ZIP extraction cancelled');
end;

{$IFDEF VITTIX_TEST_REGISTRY}
var
  GRollbackRegistryTestScope: string;
  GRollbackRegistryTestAccessFailure: Boolean;

procedure SetRollbackRegistryTestScope(const KeyName: string);
begin
  GRollbackRegistryTestScope := KeyName;
end;
{$ENDIF}

procedure PreflightZipArchive(const FileName: string; MaxArchiveBytes: Int64;
  MaxEntryCount: Integer; out EntryCount: Integer);
const
  EOCD_SIGNATURE = $06054B50;
  CENTRAL_SIGNATURE = $02014B50;
  LOCAL_SIGNATURE = $04034B50;
  DESCRIPTOR_SIGNATURE = $08074B50;
  MAX_EOCD_TAIL = 65557;
  MAX_CENTRAL_DIRECTORY_BYTES = 16 * 1024 * 1024;
  MAX_RAW_NAME_BYTES = 1024;
type
  TRange = record
    First: UInt64;
    Last: UInt64;
  end;
var
  Stream: TFileStream;
  Tail: TBytes;
  TailStart, EocdPosition, CentralOffset, CentralSize, CentralEnd: UInt64;
  EntryCount64, EntryOnDisk: UInt64;
  EocdIndex, I, J, NameLength, ExtraLength, CommentLength, TailLength: Integer;
  CentralFixed: array[0..45] of Byte;
  LocalFixed: array[0..29] of Byte;
  DescriptorBytes: array[0..15] of Byte;
  CentralName, LocalName, ExtraData: TBytes;
  CentralPosition, LocalOffset, DataStart, DataEnd, RangeEnd, LocalRegionBytes: UInt64;
  Flags, MethodId, Crc, CompressedSize, UncompressedSize: UInt32;
  LocalFlags, LocalMethod, LocalCrc, LocalCompressed, LocalUncompressed: UInt32;
  Ranges: TArray<TRange>;
  FoundEOCD, HasDescriptor: Boolean;

  function U16(Buffer: PByte; Offset: Integer): UInt32; inline;
  var
    P: PByte;
  begin
    P := Buffer;
    Result := UInt32(P[Offset]) or (UInt32(P[Offset + 1]) shl 8);
  end;

  function U32(Buffer: PByte; Offset: Integer): UInt32; inline;
  var
    P: PByte;
  begin
    P := Buffer;
    Result := UInt32(P[Offset]) or (UInt32(P[Offset + 1]) shl 8) or
      (UInt32(P[Offset + 2]) shl 16) or (UInt32(P[Offset + 3]) shl 24);
  end;

  procedure ReadAt(Offset: UInt64; var Buffer; Count: Integer);
  begin
    if (Offset > UInt64(Stream.Size)) or
       (UInt64(Count) > UInt64(Stream.Size) - Offset) then
      raise EFileSystemException.Create('ZIP structure extends beyond the archive');
    Stream.Position := Int64(Offset);
    Stream.ReadBuffer(Buffer, Count);
  end;

  procedure RejectZip64;
  begin
    raise EFileSystemException.Create(
      'ZIP64 archives are outside the bounded update archive format');
  end;

begin
  EntryCount := 0;
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    if (MaxArchiveBytes <= 0) or (Stream.Size <= 0) or
       (UInt64(Stream.Size) > UInt64(MaxArchiveBytes)) then
      raise EFileSystemException.Create('ZIP archive size limit exceeded');
    if Stream.Size > MAX_EOCD_TAIL then
      TailLength := MAX_EOCD_TAIL
    else
      TailLength := Integer(Stream.Size);
    SetLength(Tail, TailLength);
    TailStart := UInt64(Stream.Size - Length(Tail));
    Stream.Position := Int64(TailStart);
    Stream.ReadBuffer(Tail[0], Length(Tail));
    FoundEOCD := False;
    EocdIndex := Length(Tail) - 22;
    while EocdIndex >= 0 do
    begin
      if (U32(@Tail[0], EocdIndex) = EOCD_SIGNATURE) and
         (UInt64(EocdIndex) + 22 + U16(@Tail[0], EocdIndex + 20) = UInt64(Length(Tail))) then
      begin
        FoundEOCD := True;
        Break;
      end;
      Dec(EocdIndex);
    end;
    if not FoundEOCD then
      raise EFileSystemException.Create('ZIP End of Central Directory is missing or truncated');
    EocdPosition := TailStart + UInt64(EocdIndex);
    if (U16(@Tail[0], EocdIndex + 4) <> 0) or
       (U16(@Tail[0], EocdIndex + 6) <> 0) or
       (U16(@Tail[0], EocdIndex + 8) <> U16(@Tail[0], EocdIndex + 10)) then
      raise EFileSystemException.Create('Multi-disk ZIP archives are unsupported');
    EntryOnDisk := U16(@Tail[0], EocdIndex + 8);
    EntryCount64 := U16(@Tail[0], EocdIndex + 10);
    CentralSize := U32(@Tail[0], EocdIndex + 12);
    CentralOffset := U32(@Tail[0], EocdIndex + 16);
    if (EntryOnDisk = $FFFF) or (EntryCount64 = $FFFF) or
       (CentralSize = $FFFFFFFF) or (CentralOffset = $FFFFFFFF) then
      RejectZip64;
    if (EntryCount64 = 0) or (MaxEntryCount <= 0) or
       (EntryCount64 > UInt64(MaxEntryCount)) then
      raise EFileSystemException.Create('ZIP archive entry-count limit exceeded');
    if (CentralSize > MAX_CENTRAL_DIRECTORY_BYTES) or
       (CentralOffset > EocdPosition) or
       (CentralSize > EocdPosition - CentralOffset) then
      raise EFileSystemException.Create('ZIP central directory is outside its bounded region');
    CentralEnd := CentralOffset + CentralSize;
    CentralPosition := CentralOffset;
    SetLength(Ranges, Integer(EntryCount64));
    LocalRegionBytes := 0;

    for I := 0 to Integer(EntryCount64) - 1 do
    begin
      ReadAt(CentralPosition, CentralFixed, SizeOf(CentralFixed));
      if U32(@CentralFixed[0], 0) <> CENTRAL_SIGNATURE then
        raise EFileSystemException.Create('Malformed ZIP central-directory header');
      Flags := U16(@CentralFixed[0], 8);
      MethodId := U16(@CentralFixed[0], 10);
      Crc := U32(@CentralFixed[0], 16);
      CompressedSize := U32(@CentralFixed[0], 20);
      UncompressedSize := U32(@CentralFixed[0], 24);
      NameLength := U16(@CentralFixed[0], 28);
      ExtraLength := U16(@CentralFixed[0], 30);
      CommentLength := U16(@CentralFixed[0], 32);
      LocalOffset := U32(@CentralFixed[0], 42);
      if (U16(@CentralFixed[0], 34) <> 0) or
         (CompressedSize = $FFFFFFFF) or (UncompressedSize = $FFFFFFFF) or
         (LocalOffset = $FFFFFFFF) then
        RejectZip64;
      if (NameLength = 0) or (NameLength > MAX_RAW_NAME_BYTES) then
        raise EFileSystemException.Create('ZIP raw entry name length is invalid');
      if CentralPosition + 46 + UInt64(NameLength) + UInt64(ExtraLength) +
         UInt64(CommentLength) > CentralEnd then
        raise EFileSystemException.Create('ZIP central-directory record is truncated');
      SetLength(CentralName, NameLength);
      Stream.Position := Int64(CentralPosition + 46);
      Stream.ReadBuffer(CentralName[0], NameLength);
      SetLength(ExtraData, ExtraLength);
      if ExtraLength > 0 then
        Stream.ReadBuffer(ExtraData[0], ExtraLength);
      // ZIP64 extra data is rejected even when the legacy fields are not sentinels.
      J := 0;
      while J + 4 <= Length(ExtraData) do
      begin
        if (U16(@ExtraData[0], J) = 1) then
          RejectZip64;
        Inc(J, 4 + Integer(U16(@ExtraData[0], J + 2)));
      end;
      if J <> Length(ExtraData) then
        raise EFileSystemException.Create('Malformed ZIP extra field');

      if (LocalOffset > CentralOffset) or
         (UInt64(SizeOf(LocalFixed)) > CentralOffset - LocalOffset) then
        raise EFileSystemException.Create('ZIP local header offset is invalid');
      ReadAt(LocalOffset, LocalFixed, SizeOf(LocalFixed));
      if U32(@LocalFixed[0], 0) <> LOCAL_SIGNATURE then
        raise EFileSystemException.Create('ZIP local file header is missing');
      LocalFlags := U16(@LocalFixed[0], 6);
      LocalMethod := U16(@LocalFixed[0], 8);
      LocalCrc := U32(@LocalFixed[0], 14);
      LocalCompressed := U32(@LocalFixed[0], 18);
      LocalUncompressed := U32(@LocalFixed[0], 22);
      if (LocalFlags <> Flags) or (LocalMethod <> MethodId) then
        raise EFileSystemException.Create('ZIP local and central headers disagree');
      if (MethodId = 0) and (CompressedSize <> UncompressedSize) then
        raise EFileSystemException.Create('Stored ZIP entries must have matching compressed and expanded sizes');
      if (LocalCompressed = $FFFFFFFF) or (LocalUncompressed = $FFFFFFFF) then
        RejectZip64;
      NameLength := U16(@LocalFixed[0], 26);
      ExtraLength := U16(@LocalFixed[0], 28);
      if (NameLength = 0) or (NameLength > MAX_RAW_NAME_BYTES) then
        raise EFileSystemException.Create('ZIP local filename length is invalid');
      DataStart := LocalOffset + 30 + UInt64(NameLength) + UInt64(ExtraLength);
      if (DataStart > CentralOffset) or
         (UInt64(CompressedSize) > CentralOffset - DataStart) then
        raise EFileSystemException.Create('ZIP compressed data overlaps the central directory');
      DataEnd := DataStart + CompressedSize;
      if NameLength <> Length(CentralName) then
        raise EFileSystemException.Create('ZIP local and central filenames disagree');
      SetLength(LocalName, NameLength);
      Stream.Position := Int64(LocalOffset + 30);
      Stream.ReadBuffer(LocalName[0], NameLength);
      if not CompareMem(@LocalName[0], @CentralName[0], NameLength) then
        raise EFileSystemException.Create('ZIP local and central filenames disagree');
      SetLength(ExtraData, ExtraLength);
      if ExtraLength > 0 then
      begin
        Stream.ReadBuffer(ExtraData[0], ExtraLength);
        J := 0;
        while J + 4 <= Length(ExtraData) do
        begin
          if U16(@ExtraData[0], J) = 1 then
            RejectZip64;
          Inc(J, 4 + Integer(U16(@ExtraData[0], J + 2)));
        end;
        if J <> Length(ExtraData) then
          raise EFileSystemException.Create('Malformed ZIP local extra field');
      end;
      HasDescriptor := (Flags and (1 shl 3)) <> 0;
      if HasDescriptor then
      begin
        if not ((LocalCrc = 0) or (LocalCrc = Crc)) or
           not ((LocalCompressed = 0) or (LocalCompressed = CompressedSize)) or
           not ((LocalUncompressed = 0) or (LocalUncompressed = UncompressedSize)) then
          raise EFileSystemException.Create('ZIP descriptor local metadata is inconsistent');
        if DataEnd + 12 > CentralOffset then
          raise EFileSystemException.Create('ZIP data descriptor is truncated');
        ReadAt(DataEnd, DescriptorBytes, 4);
        if U32(@DescriptorBytes[0], 0) = DESCRIPTOR_SIGNATURE then
        begin
          if DataEnd + 16 > CentralOffset then
            raise EFileSystemException.Create('ZIP signed data descriptor is truncated');
          ReadAt(DataEnd, DescriptorBytes, 16);
          if (U32(@DescriptorBytes[0], 4) <> Crc) or
             (U32(@DescriptorBytes[0], 8) <> CompressedSize) or
             (U32(@DescriptorBytes[0], 12) <> UncompressedSize) then
            raise EFileSystemException.Create('ZIP data descriptor does not match central metadata');
          RangeEnd := DataEnd + 16;
        end
        else
        begin
          ReadAt(DataEnd, DescriptorBytes, 12);
          if (U32(@DescriptorBytes[0], 0) <> Crc) or
             (U32(@DescriptorBytes[0], 4) <> CompressedSize) or
             (U32(@DescriptorBytes[0], 8) <> UncompressedSize) then
            raise EFileSystemException.Create('ZIP data descriptor does not match central metadata');
          RangeEnd := DataEnd + 12;
        end;
      end
      else
      begin
        if (LocalCrc <> Crc) or (LocalCompressed <> CompressedSize) or
           (LocalUncompressed <> UncompressedSize) then
          raise EFileSystemException.Create('ZIP local and central sizes or CRC disagree');
        RangeEnd := DataEnd;
      end;
      Ranges[I].First := LocalOffset;
      Ranges[I].Last := RangeEnd;
      if (RangeEnd < LocalOffset) or
         (LocalRegionBytes > High(UInt64) - (RangeEnd - LocalOffset)) then
        raise EFileSystemException.Create('ZIP local data region size overflow');
      Inc(LocalRegionBytes, RangeEnd - LocalOffset);
      for J := 0 to I - 1 do
        if (Ranges[I].First < Ranges[J].Last) and
           (Ranges[J].First < Ranges[I].Last) then
          raise EFileSystemException.Create('ZIP entries overlap in the local data region');
      CentralPosition := CentralPosition + 46 + UInt64(U16(@CentralFixed[0], 28)) +
        UInt64(U16(@CentralFixed[0], 30)) + UInt64(U16(@CentralFixed[0], 32));
    end;
    if CentralPosition <> CentralEnd then
      raise EFileSystemException.Create('ZIP central-directory size or entry count is inconsistent');
    // The updater accepts the compact ZIP layout emitted by its supported
    // package generators. Reject unowned bytes (including truncated deflate
    // tails) and self-extracting prefixes in the local-record region.
    if LocalRegionBytes <> CentralOffset then
      raise EFileSystemException.Create('ZIP local-record region contains unaccounted bytes');
    EntryCount := Integer(EntryCount64);
  finally
    Stream.Free;
  end;
end;

{$IFDEF VITTIX_TEST_REGISTRY}
procedure SetRollbackRegistryTestAccessFailure(Value: Boolean);
begin
  GRollbackRegistryTestAccessFailure := Value;
end;
{$ENDIF}

{$IFDEF MSWINDOWS}
function ConvertStringSecurityDescriptorToSecurityDescriptorW(
  StringSecurityDescriptor: PWideChar; StringSDRevision: DWORD;
  var SecurityDescriptor: Pointer; SecurityDescriptorSize: PULONG): BOOL;
  stdcall; external 'advapi32.dll'
  name 'ConvertStringSecurityDescriptorToSecurityDescriptorW';
function CryptQueryObject(ObjectType: DWORD; ObjectData: Pointer;
  ExpectedContentTypeFlags, ExpectedFormatTypeFlags, Flags: DWORD;
  MsgAndCertEncodingType, ContentType, FormatType: PDWORD;
  CertStore: PHCERTSTORE; Msg: Pointer; Context: PPointer): BOOL;
  stdcall; external 'crypt32.dll' name 'CryptQueryObject';
function CryptMsgGetParam(Msg: HCRYPTMSG; ParamType, Index: DWORD;
  Data: Pointer; DataSize: PDWORD): BOOL; stdcall;
  external 'crypt32.dll' name 'CryptMsgGetParam';
function CertFindCertificateInStore(CertStore: HCERTSTORE;
  CertEncodingType, Flags, FindType: DWORD; FindPara: Pointer;
  PreviousContext: PCCERT_CONTEXT): PCCERT_CONTEXT; stdcall;
  external 'crypt32.dll' name 'CertFindCertificateInStore';
function CertGetCertificateContextProperty(CertContext: PCCERT_CONTEXT;
  PropId: DWORD; Data: Pointer; DataSize: PDWORD): BOOL; stdcall;
  external 'crypt32.dll' name 'CertGetCertificateContextProperty';
function CertFreeCertificateContext(CertContext: PCCERT_CONTEXT): BOOL;
  stdcall; external 'crypt32.dll' name 'CertFreeCertificateContext';
function CertCloseStore(CertStore: HCERTSTORE; Flags: DWORD): BOOL;
  stdcall; external 'crypt32.dll' name 'CertCloseStore';
function CryptMsgClose(Msg: HCRYPTMSG): BOOL; stdcall;
  external 'crypt32.dll' name 'CryptMsgClose';

function TryGetAuthenticodeThumbprint(const FileName: string;
  out Thumbprint: string): Boolean;
var
  CertStore: HCERTSTORE;
  Msg: HCRYPTMSG;
  EncodingType, ContentType, FormatType, DataSize: DWORD;
  SignerBuffer: Pointer;
  SignerInfo: PCMSG_SIGNER_INFO;
  CertInfo: CERT_INFO;
  CertContext: PCCERT_CONTEXT;
  HashBytes: TBytes;
begin
  Result := False;
  Thumbprint := '';
  CertStore := nil;
  Msg := nil;
  SignerBuffer := nil;
  CertContext := nil;
  if not CryptQueryObject(1, PWideChar(FileName), 1 shl 10, 1 shl 1, 0,
    @EncodingType, @ContentType, @FormatType, @CertStore, @Msg, nil) then
    Exit;
  try
    DataSize := 0;
    if not CryptMsgGetParam(Msg, 6, 0, nil, @DataSize) or (DataSize = 0) then
      Exit;
    GetMem(SignerBuffer, DataSize);
    if not CryptMsgGetParam(Msg, 6, 0, SignerBuffer, @DataSize) then
      Exit;
    SignerInfo := PCMSG_SIGNER_INFO(SignerBuffer);
    FillChar(CertInfo, SizeOf(CertInfo), 0);
    CertInfo.Issuer := SignerInfo.Issuer;
    CertInfo.SerialNumber := SignerInfo.SerialNumber;
    CertContext := CertFindCertificateInStore(CertStore,
      $00010001, 0, $000B0000, @CertInfo, nil);
    if not Assigned(CertContext) then
      Exit;
    DataSize := 0;
    if not CertGetCertificateContextProperty(CertContext, 107, nil,
      @DataSize) or (DataSize = 0) then
      Exit;
    SetLength(HashBytes, DataSize);
    if not CertGetCertificateContextProperty(CertContext, 107,
      @HashBytes[0], @DataSize) then
      Exit;
    SetLength(HashBytes, DataSize);
    Thumbprint := BytesToHex(HashBytes);
    Result := True;
  finally
    if Assigned(CertContext) then
      CertFreeCertificateContext(CertContext);
    if Assigned(SignerBuffer) then
      FreeMem(SignerBuffer);
    if Assigned(Msg) then
      CryptMsgClose(Msg);
    if Assigned(CertStore) then
      CertCloseStore(CertStore, 0);
  end;
end;

{$ENDIF}

{$IFNDEF MSWINDOWS}
function TryGetAuthenticodeThumbprint(const FileName: string;
  out Thumbprint: string): Boolean;
begin
  Thumbprint := '';
  Result := False;
end;
{$ENDIF}

function IsVersionAllowed(const CurrentVersion, AvailableVersion: TAppVersion;
  AllowDowngrade: Boolean): Boolean;
begin
  Result := (AvailableVersion > CurrentVersion) or AllowDowngrade;
end;

function IsManifestRollbackAllowed(const CandidateVersion: TAppVersion;
  CandidateIssuedAt: Int64; const CandidateChecksum, StoredState: string;
  out ErrorMessage: string): Boolean;
var
  Sep1, Sep2: Integer;
  StoredVersionText, StoredTimeText, StoredChecksum: string;
  StoredVersion: TAppVersion;
  StoredIssuedAt: Int64;
begin
  Result := False;
  ErrorMessage := '';
  if StoredState = '' then
    Exit(True);
  Sep1 := Pos('|', StoredState);
  if Sep1 = 0 then
  begin
    ErrorMessage := 'Persistent update trust state is malformed; refusing update.';
    Exit;
  end;
  Sep2 := Pos('|', Copy(StoredState, Sep1 + 1, MaxInt));
  if Sep2 = 0 then
  begin
    ErrorMessage := 'Persistent update trust state is malformed; refusing update.';
    Exit;
  end;
  Inc(Sep2, Sep1);
  StoredVersionText := Copy(StoredState, 1, Sep1 - 1);
  StoredTimeText := Copy(StoredState, Sep1 + 1, Sep2 - Sep1 - 1);
  StoredChecksum := Copy(StoredState, Sep2 + 1, MaxInt);
  if not TryStrToInt64(StoredTimeText, StoredIssuedAt) then
  begin
    ErrorMessage := 'Persistent update trust timestamp is malformed; refusing update.';
    Exit;
  end;
  if not TAppVersion.TryParse(StoredVersionText, StoredVersion) then
  begin
    ErrorMessage := 'Persistent update trust version is malformed; refusing update.';
    Exit;
  end;
  if CandidateVersion < StoredVersion then
  begin
    ErrorMessage := Format('Manifest version %s is below the previously accepted version %s.',
      [CandidateVersion.ToString, StoredVersion.ToString]);
    Exit;
  end;
  if (CandidateIssuedAt < StoredIssuedAt) or
     ((CandidateIssuedAt = StoredIssuedAt) and
      (CandidateVersion = StoredVersion) and
      not SameText(CandidateChecksum, StoredChecksum)) then
  begin
    ErrorMessage := 'Manifest timestamp or content rolls back persistent update trust state.';
    Exit;
  end;
  Result := True;
end;

{$IFDEF MSWINDOWS}
function PersistManifestRollbackFloor(const Manifest: TUpdateManifest;
  out ErrorMessage: string): Boolean;
var
  Registry: TRegistry;
  Identity, KeyName, Stored, NewState: string;
  NewIssuedAt: Int64;
  Hash: THashSHA2;
  Digest: TBytes;
begin
  Result := False;
  ErrorMessage := '';
  Identity := LowerCase(ExpandFileName(ParamStr(0)));
  Hash := THashSHA2.Create(SHA256);
  Hash.Update(TEncoding.UTF8.GetBytes(Identity));
  Digest := Hash.HashAsBytes;
  KeyName := 'Software\VittixAutoUpdater\TrustState\' + BytesToHex(Digest);
{$IFDEF VITTIX_TEST_REGISTRY}
  if GRollbackRegistryTestScope <> '' then
    KeyName := GRollbackRegistryTestScope;
  if GRollbackRegistryTestAccessFailure then
    KeyName := KeyName + '\' + StringOfChar('X', 1024);
{$ENDIF}
  NewIssuedAt := Trunc(Manifest.IssuedAt * 86400);
  Registry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    try
      Registry.RootKey := HKEY_CURRENT_USER;
      if not Registry.OpenKey(KeyName, True) then
      begin
        ErrorMessage := 'Could not open persistent update trust state.';
        Exit;
      end;

      if Registry.ValueExists('Floor') then
      begin
        Stored := Registry.ReadString('Floor');
        if not IsManifestRollbackAllowed(Manifest.Version, NewIssuedAt,
          Manifest.Checksum, Stored, ErrorMessage) then
          Exit;
      end;

      NewState := Manifest.Version.ToString + '|' + IntToStr(NewIssuedAt) +
        '|' + Manifest.Checksum;
      Registry.WriteString('Floor', NewState);
      Result := True;
    except
      on E: Exception do
        ErrorMessage := 'Could not persist update trust state: ' + E.Message;
    end;
  finally
    Registry.Free;
  end;
end;
{$ENDIF}

function BatchPath(const Value: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(Value);
  // ExcludeTrailingPathDelimiter('C:\') returns 'C:' rather than a root path.
  if (Length(Result) = 2) and (Result[2] = ':') then
    Result := Result + PathDelim;
  // cmd.exe expands percent signs even inside double quotes.
  Result := StringReplace(Result, '%', '%%', [rfReplaceAll]);
end;

function BuildBatchCopyCommand(const SourcePath, DestinationPath: string): string;
begin
  Result := Format('xcopy "%s\*.*" "%s" /E /Y /I',
    [BatchPath(SourcePath), BatchPath(DestinationPath)]);
end;

function IsSafeZipEntryPath(const DestinationPath, EntryName: string;
  out FullPath: string): Boolean;
var
  RootPath, Normalized, Component, BaseName: string;
  I, StartAt, PartCount, DotAt: Integer;
  C: Char;
begin
  Result := False;
  FullPath := '';
  if (EntryName = '') or (EntryName[1] in ['/', '\']) or
     (Pos(':', EntryName) > 0) or
     (Pos(#0, EntryName) > 0) then
    Exit;

  try
    if TPath.IsPathRooted(EntryName) then
      Exit;
    Normalized := StringReplace(EntryName, '/', '\', [rfReplaceAll]);
    if (Normalized <> '') and (Normalized[Length(Normalized)] = '\') then
      Delete(Normalized, Length(Normalized), 1);
    if Normalized = '' then
      Exit;
    if (Copy(Normalized, 1, 2) = '\\') or
       (Copy(Normalized, 1, 4) = '\\?\') or
       (Copy(Normalized, 1, 4) = '\\.\') then
      Exit;
    PartCount := 0;
    StartAt := 1;
    for I := 1 to Length(Normalized) + 1 do
      if (I > Length(Normalized)) or (Normalized[I] = '\') then
      begin
        Component := Copy(Normalized, StartAt, I - StartAt);
        if (Component = '') or (Component = '.') or (Component = '..') or
           (Component[Length(Component)] = '.') or
           (Component[Length(Component)] = ' ') then
          Exit;
        Inc(PartCount);
        if PartCount > 32 then
          Exit;
        for C in Component do
          if (Ord(C) < 32) or (C in ['<', '>', '"', '|', '?', '*']) then
            Exit;
        DotAt := Pos('.', Component);
        if DotAt > 0 then
          BaseName := Copy(Component, 1, DotAt - 1)
        else
          BaseName := Component;
        if Pos('|' + UpperCase(BaseName) + '|',
          '|CON|PRN|AUX|NUL|COM1|COM2|COM3|COM4|COM5|COM6|COM7|COM8|COM9|' +
          'LPT1|LPT2|LPT3|LPT4|LPT5|LPT6|LPT7|LPT8|LPT9|') > 0 then
          Exit;
        StartAt := I + 1;
      end;
    RootPath := IncludeTrailingPathDelimiter(TPath.GetFullPath(DestinationPath));
    FullPath := TPath.GetFullPath(TPath.Combine(DestinationPath, Normalized));
    Result := (Length(Normalized) <= 240) and (Length(FullPath) < 260) and
      SameText(Copy(FullPath, 1, Length(RootPath)), RootPath);
  except
    FullPath := '';
    Result := False;
  end;
end;

function VerifyAuthenticodeFile(const FileName: string): Boolean;
begin
  Result := VerifyAuthenticodeFilePinned(FileName, nil);
end;

function VerifyAuthenticodeFilePinned(const FileName: string;
  const PinnedThumbprints: TArray<string>): Boolean;
{$IFDEF MSWINDOWS}
var
  FileInfo: WINTRUST_FILE_INFO;
  TrustData: WINTRUST_DATA;
  ActionId: TGUID;
  Status: LongInt;
  Thumbprint: string;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  FillChar(FileInfo, SizeOf(FileInfo), 0);
  FileInfo.cbStruct := SizeOf(FileInfo);
  FileInfo.pcwszFilePath := PWideChar(FileName);

  FillChar(TrustData, SizeOf(TrustData), 0);
  TrustData.cbStruct := SizeOf(TrustData);
  TrustData.dwUIChoice := WTD_UI_NONE;
  TrustData.fdwRevocationChecks := WTD_REVOKE_NONE;
  TrustData.dwUnionChoice := WTD_CHOICE_FILE;
  TrustData.pFile := @FileInfo;
  TrustData.dwStateAction := WTD_STATEACTION_VERIFY;
  ActionId := WINTRUST_ACTION_GENERIC_VERIFY_V2;
  Status := WinVerifyTrust(INVALID_HANDLE_VALUE, ActionId, @TrustData);

  TrustData.dwStateAction := WTD_STATEACTION_CLOSE;
  WinVerifyTrust(INVALID_HANDLE_VALUE, ActionId, @TrustData);
  Result := Status = 0;
  if Result and (Length(PinnedThumbprints) > 0) then
  begin
    Result := TryGetAuthenticodeThumbprint(FileName, Thumbprint) and
      IsThumbprintPinned(Thumbprint, PinnedThumbprints);
  end;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function IsThumbprintPinned(const Thumbprint: string;
  const PinnedThumbprints: TArray<string>): Boolean;
var
  I: Integer;
  NormalizedThumbprint, Pin: string;
begin
  Result := False;
  NormalizedThumbprint := UpperCase(StringReplace(
    StringReplace(Trim(Thumbprint), ' ', '', [rfReplaceAll]),
    ':', '', [rfReplaceAll]));
  for I := 0 to High(PinnedThumbprints) do
  begin
    Pin := UpperCase(StringReplace(
      StringReplace(Trim(PinnedThumbprints[I]), ' ', '', [rfReplaceAll]),
      ':', '', [rfReplaceAll]));
    if ConstantTimeEquals(NormalizedThumbprint, Pin) then
      Exit(True);
  end;
end;

{$IFDEF MSWINDOWS}
function CreatePrivateUpdateDirectory(const Directory: string): Boolean;
var
  SecurityDescriptor: Pointer;
  SecurityAttributes: SECURITY_ATTRIBUTES;
begin
  Result := False;
  SecurityDescriptor := nil;
  if not ConvertStringSecurityDescriptorToSecurityDescriptorW(
    'D:P(A;OICI;FA;;;OW)(A;OICI;FA;;;SY)', 1,
    SecurityDescriptor, nil) then
    Exit;
  try
    SecurityAttributes.nLength := SizeOf(SecurityAttributes);
    SecurityAttributes.lpSecurityDescriptor := SecurityDescriptor;
    SecurityAttributes.bInheritHandle := False;
    Result := CreateDirectory(PChar(Directory), @SecurityAttributes);
  finally
    LocalFree(HLOCAL(SecurityDescriptor));
  end;
end;
{$ENDIF}

{ TUpdateEngine }

constructor TUpdateEngine.Create(const Config: TUpdaterConfig);
begin
  inherited Create;
{$IFNDEF MSWINDOWS}
  raise EUpdaterException.Create(
    'VittixAutoUpdater is not supported on this platform (Windows only)');
{$ENDIF}
  FConfig := Config;
  FStateLock := TCriticalSection.Create;
  FRestartAfterInstall := True;
  FNetwork := TUpdateNetworkManager.Create;
  SetConfig(Config);

  ReportSecurityWarnings;

  FState := usIdle;
  FDownloadedFile := '';
  FExtractPath := '';
  FCancelRequested := False;

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

{$IFDEF VITTIX_TEST_LOOPBACK}
procedure TUpdateEngine.EnableLoopbackHttpForTests;
begin
  FNetwork.AllowLoopbackHttpForTests := True;
end;

function TUpdateEngine.WaitForCheckWorkerForTests(Timeout: Cardinal): Boolean;
begin
  if not Assigned(FCheckThread) then
    Exit(True);
  Result := WaitForSingleObject(FCheckThread.Handle, Timeout) = WAIT_OBJECT_0;
end;

function TUpdateEngine.ExtractArchiveForTests(const ZipFile, DestPath: string): Boolean;
begin
  FStateLock.Acquire;
  try
    FCancelRequested := False;
  finally
    FStateLock.Release;
  end;
  SetState(usExtracting, 'Extracting update');
  Result := ExtractUpdate(ZipFile, DestPath);
  if Result then
    SetState(usReady, 'Update extracted');
end;

function TUpdateEngine.ExtractDownloadedPackageForTests(
  out ExtractedPath: string): Boolean;
begin
  ExtractedPath := '';
  Result := False;
  if FDownloadedFile = '' then
    Exit;
  FExtractPath := GetTempExtractPath;
  ExtractedPath := FExtractPath;
  Result := ExtractUpdate(FDownloadedFile, FExtractPath);
  if not Result then
    CleanupTempFiles;
end;

function TUpdateEngine.ApplyArchiveForTests(const ZipFile: string;
  out OperationStagingPath: string): Boolean;
begin
  OperationStagingPath := '';
  Result := False;
  FDownloadedFile := GetTempZipFile;
  TFile.Copy(ZipFile, FDownloadedFile);
  OperationStagingPath := FStagingPath;
  SetState(usReady, 'Test package ready');
  Result := ApplyUpdate;
end;
{$ENDIF}

destructor TUpdateEngine.Destroy;
begin
  Cancel;
  if Assigned(FCheckThread) then
  begin
    FCheckThread.WaitFor;
    TThread.RemoveQueuedEvents(FCheckThread);
    FreeAndNil(FCheckThread);
  end;
  CleanupTempFiles;
  FNetwork.Free;
  FStateLock.Free;
  inherited;
end;

procedure TUpdateEngine.SetState(NewState: TUpdateState; const StatusMsg: string);
begin
  if FCancelRequested and (NewState <> usCancelled) then
    Exit;

  FState := NewState;
  if Assigned(FOnStateChange) then
    FOnStateChange(Self, NewState, StatusMsg);
end;

procedure TUpdateEngine.SetConfig(const Value: TUpdaterConfig);
begin
  FConfig := Value;
  if not Assigned(FNetwork) then
    Exit;
  FNetwork.ConnectionTimeout := Value.ConnectionTimeout * 1000;
  FNetwork.MaxRetries := Value.MaxRetries;
  FNetwork.MaxManifestAgeDays := Value.MaxManifestAgeDays;
  FNetwork.UserAgent := Value.UserAgent;
  FNetwork.RequireHttps := Value.RequireHttps;
  FNetwork.VerifyManifestSignatures := Value.VerifyManifestSignature;
  FNetwork.ManifestPublicKey := Value.ManifestPublicKey;
  FNetwork.ManifestTrustedPublicKeys := Value.ManifestTrustedPublicKeys;
  FNetwork.AllowInsecureUnsignedManifests :=
    Value.AllowInsecureUnsignedManifests;
end;

procedure TUpdateEngine.QueueCheckCompletion(OperationGeneration: Int64;
  const Action: TThreadProcedure);
begin
  // Completion must not block the worker on a main-thread Synchronize call.
  // A consumer may immediately start the next check from the terminal
  // callback; it can safely wait for this worker because it no longer needs
  // the main thread to return.
  TThread.Queue(FCheckThread,
    procedure
    begin
      if OperationGeneration <> TInterlocked.Read(FCheckOperationGeneration) then
        Exit;
      Action();
    end);
end;

function TUpdateEngine.GetTempZipFile: string;
begin
  if FStagingPath = '' then
  begin
    FStagingBase := GetPrivateStagingBase(FConfig.TempFolder);
    FStagingPath := AllocatePrivateStagingDirectory(FStagingBase);
  end;
  Result := IncludeTrailingPathDelimiter(FStagingPath) + 'package.zip';
end;

function TUpdateEngine.GetTempExtractPath: string;
begin
  if FStagingPath = '' then
    raise EFileSystemException.Create('Private staging context is not allocated');
  Result := IncludeTrailingPathDelimiter(FStagingPath) + 'payload';
end;

procedure TUpdateEngine.CleanupTempFiles;
begin
  if (FStagingPath <> '') and
     not SafeDeletePrivateStagingDirectory(FStagingPath, FStagingBase) then
  begin
    OutputDebugString(PChar('VittixAutoUpdater: safe staging cleanup failed: ' +
      FStagingPath));
    Exit;
  end;
  FDownloadedFile := '';
  FExtractPath := '';
  FStagingPath := '';
  FStagingBase := '';
end;

procedure TUpdateEngine.CheckForUpdate(Callback: TUpdateCheckCallback);
var
  ErrorMsg, TrustedKey: string;
  OperationGeneration: Int64;
begin
  if not (FState in [usIdle, usAvailable, usFailed, usCancelled]) then
    Exit;

  if Assigned(FCheckThread) then
  begin
    // Queued completion does not wait for the UI thread. Waiting here is
    // therefore safe even when this call is made from the completion callback.
    FCheckThread.WaitFor;
    FreeAndNil(FCheckThread);
  end;

  if (not FConfig.VerifyManifestSignature) and
     (not FConfig.AllowInsecureUnsignedManifests) then
  begin
    ErrorMsg :=
      'Manifest signature verification is mandatory. Set '
      + 'AllowInsecureUnsignedManifests=True only for an explicit insecure migration.';
    SetState(usFailed, ErrorMsg);
    if Assigned(Callback) then
      Callback(ucrError, TUpdateManifest.Empty, ErrorMsg);
    Exit;
  end;

  if FConfig.VerifyManifestSignature then
  begin
    if (Trim(FConfig.ManifestPublicKey) = '') and
       (Length(FConfig.ManifestTrustedPublicKeys) = 0) then
    begin
      ErrorMsg := 'A trusted manifest signing public key is required.';
      SetState(usFailed, ErrorMsg);
      if Assigned(Callback) then
        Callback(ucrError, TUpdateManifest.Empty, ErrorMsg);
      Exit;
    end;
    if (Trim(FConfig.ManifestPublicKey) <> '') and
       (ManifestSigningKeyId(FConfig.ManifestPublicKey) = '') then
    begin
      ErrorMsg := 'ManifestPublicKey is not a valid ECDSA P-256 X||Y key.';
      SetState(usFailed, ErrorMsg);
      if Assigned(Callback) then
        Callback(ucrError, TUpdateManifest.Empty, ErrorMsg);
      Exit;
    end;
    for TrustedKey in FConfig.ManifestTrustedPublicKeys do
      if ManifestSigningKeyId(TrustedKey) = '' then
      begin
        ErrorMsg := 'ManifestTrustedPublicKeys contains an invalid ECDSA P-256 key.';
        SetState(usFailed, ErrorMsg);
        if Assigned(Callback) then
          Callback(ucrError, TUpdateManifest.Empty, ErrorMsg);
        Exit;
      end;
  end;

  FCancelRequested := False;
  OperationGeneration := TInterlocked.Increment(FCheckOperationGeneration);
  SetState(usChecking, 'Checking for updates...');
  if OperationGeneration <> TInterlocked.Read(FCheckOperationGeneration) then
    Exit;

  FCheckThread := TThread.CreateAnonymousThread(
    procedure
    var
      Manifest: TUpdateManifest;
      Success: Boolean;
      ErrorMsg: string;
      TrustStateSaved: Boolean;
    begin
      try
        Success :=
          FNetwork.FetchManifest(
            FConfig.ManifestUrls,
            FConfig.AppName,
            Manifest);

        if FCancelRequested then
          Exit;

        if not Success then
        begin
          ErrorMsg := 'Failed to fetch update manifest';
          QueueCheckCompletion(OperationGeneration,
            procedure
            begin
              SetState(usFailed, ErrorMsg);
              if OperationGeneration <> TInterlocked.Read(FCheckOperationGeneration) then
                Exit;
              if Assigned(Callback) then
                Callback(ucrError, TUpdateManifest.Empty, ErrorMsg);
            end);
          Exit;
        end;

        if FConfig.VerifyManifestSignature and
           (Manifest.Version < FCurrentVersion) then
        begin
          ErrorMsg := Format('Signed manifest version %s is below installed version %s.',
            [Manifest.Version.ToString, FCurrentVersion.ToString]);
          QueueCheckCompletion(OperationGeneration,
            procedure
            begin
              SetState(usFailed, ErrorMsg);
              if OperationGeneration <> TInterlocked.Read(FCheckOperationGeneration) then
                Exit;
              if Assigned(Callback) then
                Callback(ucrError, TUpdateManifest.Empty, ErrorMsg);
            end);
          Exit;
        end;

{$IFDEF MSWINDOWS}
        if FConfig.VerifyManifestSignature then
        begin
          FStateLock.Acquire;
          try
            if FCancelRequested then
              Exit;
            TrustStateSaved := PersistManifestRollbackFloor(Manifest, ErrorMsg);
          finally
            FStateLock.Release;
          end;
          if not TrustStateSaved then
          begin
            QueueCheckCompletion(OperationGeneration,
              procedure
              begin
                SetState(usFailed, ErrorMsg);
                if OperationGeneration <> TInterlocked.Read(FCheckOperationGeneration) then
                  Exit;
                if Assigned(Callback) then
                  Callback(ucrError, TUpdateManifest.Empty, ErrorMsg);
              end);
            Exit;
          end;
        end;
{$ENDIF}

        if IsVersionAllowed(FCurrentVersion, Manifest.Version,
          FConfig.AllowDowngrade and FConfig.AllowInsecureUnsignedManifests) and
          (Manifest.Version <> FCurrentVersion) then
        begin
          if Manifest.MinVersion.IsValid and
             (FCurrentVersion < Manifest.MinVersion) then
          begin
            ErrorMsg :=
              Format(
                'Cannot update from %s. Minimum required: %s',
                [FCurrentVersion.ToString,
                 Manifest.MinVersion.ToString]);

            QueueCheckCompletion(OperationGeneration,
              procedure
              begin
                SetState(usFailed, ErrorMsg);
                if OperationGeneration <> TInterlocked.Read(FCheckOperationGeneration) then
                  Exit;
                if Assigned(Callback) then
                  Callback(ucrError, Manifest, ErrorMsg);
              end);
            Exit;
          end;

          QueueCheckCompletion(OperationGeneration,
            procedure
            begin
              FLastManifest := Manifest;
              SetState(usAvailable, 'Update available');
              if OperationGeneration <> TInterlocked.Read(FCheckOperationGeneration) then
                Exit;
              if Assigned(Callback) then
                Callback(ucrUpdateAvailable, Manifest, '');
            end);
        end
        else
        begin
          QueueCheckCompletion(OperationGeneration,
            procedure
            begin
              SetState(usIdle, 'No updates');
              if OperationGeneration <> TInterlocked.Read(FCheckOperationGeneration) then
                Exit;
              if Assigned(Callback) then
                Callback(ucrNoUpdateAvailable, Manifest, '');
            end);
        end;

      except
        on E: Exception do
        begin
          QueueCheckCompletion(OperationGeneration,
            procedure
            begin
              SetState(usFailed, E.Message);
              if OperationGeneration <> TInterlocked.Read(FCheckOperationGeneration) then
                Exit;
              if Assigned(Callback) then
                Callback(ucrError, TUpdateManifest.Empty, E.Message);
            end);
        end;
      end;
    end
  );
  FCheckThread.FreeOnTerminate := False;
  FCheckThread.Start;
end;

procedure TUpdateEngine.SetOnSecurityWarning(const Value: TSecurityWarningEvent);
begin
  FOnSecurityWarning := Value;
  ReportSecurityWarnings;
end;

procedure TUpdateEngine.ReportSecurityWarnings;
begin
  if not FConfig.VerifyManifestSignature then
  begin
    OutputDebugString(
      'VittixAutoUpdater: INSECURE unsigned manifest mode is enabled.');
    if Assigned(FOnSecurityWarning) then
      FOnSecurityWarning(Self,
        'INSECURE unsigned manifest mode is enabled.');
  end;
  if (Trim(FConfig.ManifestPublicKey) = '') and
     (Length(FConfig.ManifestTrustedPublicKeys) = 0) then
  begin
    OutputDebugString(
      'VittixAutoUpdater: ManifestPublicKey is not configured.');
    if Assigned(FOnSecurityWarning) then
      FOnSecurityWarning(Self, 'ManifestPublicKey is not configured.');
  end;
  if FConfig.ManifestHmacKey <> '' then
  begin
    OutputDebugString(
      'VittixAutoUpdater: ManifestHmacKey is deprecated and ignored; '
      + 'a ManifestPublicKey is required for signed manifests.');
    if Assigned(FOnSecurityWarning) then
      FOnSecurityWarning(Self,
        'ManifestHmacKey is ignored; configure ManifestPublicKey.');
  end;
end;

function TUpdateEngine.DownloadUpdate(const Manifest: TUpdateManifest): Boolean;
begin
  Result := False;

  FStateLock.Acquire;
  try
    if FState <> usAvailable then
      Exit;
    FState := usDownloading;
  finally
    FStateLock.Release;
  end;

  if FConfig.RequireChecksum and (Trim(Manifest.Checksum) = '') then
  begin
    SetState(usFailed, 'Manifest has no checksum - refusing to download unverifiable update');
    Exit;
  end;

  FCancelRequested := False;
  if Assigned(FOnStateChange) then
    FOnStateChange(Self, usDownloading, 'Downloading update...');

  try
    FDownloadedFile := GetTempZipFile;

    Result :=
      FNetwork.DownloadFile(
        Manifest.DownloadUrl,
        FDownloadedFile,
        FOnDownloadProgress,
        Manifest.Checksum,
        Manifest.FileSize);

    if Result then
      SetState(usReady, 'Update ready to install')
    else if FCancelRequested or (FState = usCancelled) then
    begin
      SetState(usCancelled, 'Download cancelled');
      CleanupTempFiles;
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

function TUpdateEngine.ExtractUpdate(
  const ZipFile, DestPath: string): Boolean;
type
  TPlannedEntry = record
    Name: string;
    Path: string;
    IsDirectory: Boolean;
    Size: UInt64;
    CompressedSize: UInt64;
  end;
var
  ZipArchive: TZipFile;
  ZipCancellationObserver: TZipCancellationObserver;
  Entries: TArray<TPlannedEntry>;
  EntryName, EntryPath, ParentPath, Key, CurrentKey, ExistingKind: string;
  I, J, Depth: Integer;
  PreflightCount: Integer;
  Header: TZipHeader;
  InputStream: TStream;
  OutputHandle: THandle;
  BytesRead, Written: Cardinal;
  Buffer: array[0..65535] of Byte;
  TotalUncompressed, DeclaredTotal, ActualEntryBytes, ArchiveBytes: UInt64;
  Paths: TDictionary<string, string>;
  IsDirectory: Boolean;
  Attr: DWORD;
  UnixMode: UInt32;
  AvailableBytes, TotalBytes, TotalFreeBytes: UInt64;

  function FindPathKind(const Candidate: string; out Kind: string): Boolean;
  var
    MapKey: string;
  begin
    Result := False;
    for MapKey in Paths.Keys do
      if (Length(MapKey) = Length(Candidate)) and
         (CompareStringOrdinal(PChar(MapKey), Length(MapKey),
           PChar(Candidate), Length(Candidate), 1) = CSTR_EQUAL) then
      begin
        Result := Paths.TryGetValue(MapKey, Kind);
        Exit;
      end;
  end;

  procedure EnsureSafeDirectories(const Root, Target: string);
  var
    RootFull, TargetFull, RelativePath, CurrentPath, Part: string;
    K, PartStart: Integer;
    FileAttributes, ErrorCode: DWORD;
  begin
    RootFull := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Root));
    TargetFull := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Target));
    if (Length(TargetFull) = Length(RootFull)) and
       (CompareStringOrdinal(PChar(TargetFull), Length(TargetFull),
         PChar(RootFull), Length(RootFull), 1) = CSTR_EQUAL) then
    begin
      FileAttributes := GetFileAttributes(PChar(RootFull));
      if (FileAttributes = INVALID_FILE_ATTRIBUTES) or
         ((FileAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0) or
         ((FileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
        raise EFileSystemException.Create('Invalid payload root directory');
      Exit;
    end;
    if (Length(TargetFull) <= Length(RootFull)) or
       (CompareStringOrdinal(PChar(Copy(TargetFull, 1, Length(RootFull))),
          Length(RootFull), PChar(RootFull), Length(RootFull), 1) <> CSTR_EQUAL) or
       (TargetFull[Length(RootFull) + 1] <> PathDelim) then
      raise EFileSystemException.Create('Extraction directory is outside the payload root');
    CurrentPath := RootFull;
    RelativePath := Copy(TargetFull, Length(RootFull) + 2, MaxInt);
    PartStart := 1;
    for K := 1 to Length(RelativePath) + 1 do
      if (K > Length(RelativePath)) or (RelativePath[K] = PathDelim) then
      begin
        Part := Copy(RelativePath, PartStart, K - PartStart);
        if Part = '' then
          raise EFileSystemException.Create('Invalid extraction directory path');
        CurrentPath := IncludeTrailingPathDelimiter(CurrentPath) + Part;
        FileAttributes := GetFileAttributes(PChar(CurrentPath));
        if FileAttributes = INVALID_FILE_ATTRIBUTES then
        begin
          ErrorCode := GetLastError;
          if (ErrorCode <> ERROR_FILE_NOT_FOUND) and
             (ErrorCode <> ERROR_PATH_NOT_FOUND) then
            RaiseLastOSError;
          if not Windows.CreateDirectory(PChar(CurrentPath), nil) and
             (GetLastError <> ERROR_ALREADY_EXISTS) then
            RaiseLastOSError;
          FileAttributes := GetFileAttributes(PChar(CurrentPath));
        end;
        if (FileAttributes = INVALID_FILE_ATTRIBUTES) or
           ((FileAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0) or
           ((FileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
          raise EFileSystemException.Create('Reparse point or non-directory in extraction path');
        PartStart := K + 1;
      end;
  end;

begin
  Result := False;
  Paths := TDictionary<string, string>.Create;
  ZipCancellationObserver := TZipCancellationObserver.Create(Self);
  try
    if FCancelRequested then
      raise EAbort.Create('ZIP extraction cancelled');
    ZipArchive := TZipFile.Create;
    try
      if not TFile.Exists(ZipFile) then
        raise EFileSystemException.Create('ZIP package does not exist');
      ArchiveBytes := TFile.GetSize(ZipFile);
      if (FConfig.MaxArchiveBytes <= 0) or
         (ArchiveBytes > UInt64(FConfig.MaxArchiveBytes)) then
        raise EFileSystemException.Create('ZIP archive exceeds the configured size limit');
      PreflightZipArchive(ZipFile, FConfig.MaxArchiveBytes,
        FConfig.MaxArchiveEntryCount, PreflightCount);
      ZipArchive.Open(ZipFile, zmRead);
      ZipArchive.OnProgress := ZipCancellationObserver.OnProgress;
      if ZipArchive.FileCount <> PreflightCount then
        raise EFileSystemException.Create('ZIP entry count changed after preflight');
      if ZipArchive.FileCount = 0 then
        raise EFileSystemException.Create('Empty ZIP archives are not valid updates');
      if (FConfig.MaxArchiveTotalUncompressedBytes <= 0) or
         (FConfig.MaxArchiveSingleEntryBytes <= 0) or
         (FConfig.MaxArchivePathDepth <= 0) or
         (FConfig.MaxArchivePathLength <= 0) or
         (FConfig.MaxArchiveExpansionRatio <= 0) then
        raise EFileSystemException.Create('ZIP extraction limits are invalid');

      SetLength(Entries, ZipArchive.FileCount);
      DeclaredTotal := 0;
      // Validate the complete central directory before creating any payload.
      for I := 0 to ZipArchive.FileCount - 1 do
      begin
        if FCancelRequested then
          raise EAbort.Create('ZIP extraction cancelled');
        EntryName := ZipArchive.FileNames[I];
        if not IsSafeZipEntryPath(DestPath, EntryName, EntryPath) then
          raise EFileSystemException.CreateFmt(
            'Unsafe ZIP entry path rejected: "%s"', [EntryName]);
        Header := ZipArchive.FileInfo[I];
        if Header.IsEncrypted then
          raise EFileSystemException.Create('Encrypted ZIP entries are unsupported');
        if not (Header.CompressionMethod in [0, 8]) then
          raise EFileSystemException.Create('Unsupported ZIP compression method');
        IsDirectory := (EntryName[Length(EntryName)] = '/') or
          (EntryName[Length(EntryName)] = '\');
        if (TFileAttribute.faSymLink in Header.FileAttributes) or
           (TFileAttribute.faDevice in Header.FileAttributes) or
           ((Header.ExternalAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
          raise EFileSystemException.Create('ZIP links and reparse-point attributes are unsupported');
        if ((Header.MadeByVersion shr 8) = 0) and
           ((TFileAttribute.faDirectory in Header.FileAttributes) <> IsDirectory) then
          raise EFileSystemException.Create('ZIP directory metadata does not match its entry name');
        if (Header.MadeByVersion shr 8) = 3 then
        begin
          UnixMode := (Header.ExternalAttributes shr 16) and $F000;
          if not ((UnixMode = 0) or (UnixMode = $8000) or (UnixMode = $4000)) or
             ((UnixMode = $4000) and not IsDirectory) or
             ((UnixMode = $8000) and IsDirectory) then
            raise EFileSystemException.Create('Unsupported ZIP Unix entry type');
        end;
        if IsDirectory and
           ((Header.UncompressedSize64 <> 0) or (Header.CompressedSize64 <> 0)) then
          raise EFileSystemException.Create('ZIP directory entries must not contain data');
        if (Header.UncompressedSize64 > UInt64(FConfig.MaxArchiveSingleEntryBytes)) or
           (Header.UncompressedSize64 > UInt64(FConfig.MaxArchiveTotalUncompressedBytes) - DeclaredTotal) then
          raise EFileSystemException.Create('ZIP uncompressed size limit exceeded');
        Inc(DeclaredTotal, Header.UncompressedSize64);
        if (Header.UncompressedSize64 > 0) and
           ((Header.CompressedSize64 = 0) or
            (((Header.UncompressedSize64 - 1) div Header.CompressedSize64) + 1 >
             UInt64(FConfig.MaxArchiveExpansionRatio))) then
          raise EFileSystemException.Create('ZIP expansion ratio limit exceeded');

        Depth := 1;
        for J := 1 to Length(EntryName) do
          if EntryName[J] in ['/', '\'] then
            Inc(Depth);
        if IsDirectory then
          Dec(Depth);
        if (Depth > FConfig.MaxArchivePathDepth) or
           ((Length(EntryName) - Ord(IsDirectory)) > FConfig.MaxArchivePathLength) then
          raise EFileSystemException.Create('ZIP entry path exceeds configured limits');
        CurrentKey := StringReplace(EntryName, '/', '\', [rfReplaceAll]);
        if (CurrentKey <> '') and (CurrentKey[Length(CurrentKey)] = '\') then
          Delete(CurrentKey, Length(CurrentKey), 1);
        if FindPathKind(CurrentKey, ExistingKind) then
          raise EFileSystemException.CreateFmt('Duplicate ZIP destination: "%s"', [EntryName]);
        Paths.Add(CurrentKey, IfThen(IsDirectory, 'D', 'F'));
        ParentPath := ExtractFileDir(StringReplace(CurrentKey, '\', PathDelim, [rfReplaceAll]));
        while (ParentPath <> '.') and (ParentPath <> '') do
        begin
          if FindPathKind(StringReplace(ParentPath, PathDelim, '\', [rfReplaceAll]), ExistingKind) and
             (ExistingKind = 'F') then
            raise EFileSystemException.Create('ZIP file entry conflicts with a parent directory');
          ParentPath := ExtractFileDir(ParentPath);
        end;
        if not IsDirectory then
          for Key in Paths.Keys do
            if (Length(Key) > Length(CurrentKey)) and
               (Key[Length(CurrentKey) + 1] = '\') and
               (CompareStringOrdinal(PChar(Copy(Key, 1, Length(CurrentKey))),
                 Length(CurrentKey), PChar(CurrentKey), Length(CurrentKey), 1) = CSTR_EQUAL) then
              raise EFileSystemException.Create('ZIP file entry conflicts with child entries');
        Entries[I].Name := EntryName;
        Entries[I].Path := EntryPath;
        Entries[I].IsDirectory := IsDirectory;
        Entries[I].Size := Header.UncompressedSize64;
        Entries[I].CompressedSize := Header.CompressedSize64;
      end;

      {$IFDEF MSWINDOWS}
      if FCancelRequested then
        raise EAbort.Create('ZIP extraction cancelled');
      if not IsPathWithoutReparsePoints(ExtractFileDir(DestPath)) then
        raise EFileSystemException.Create(
          'Extraction parent contains a missing or redirected path component');
      if not GetDiskFreeSpaceEx(PChar(ExtractFileDir(DestPath)),
        @AvailableBytes, @TotalBytes, @TotalFreeBytes) or
         (AvailableBytes < DeclaredTotal) then
        raise EFileSystemException.Create('Insufficient disk space for ZIP extraction');
      if not CreatePrivateUpdateDirectory(DestPath) then
        raise EFileSystemException.CreateFmt(
          'Could not create private update directory "%s" (Windows error %d)',
          [DestPath, GetLastError]);
      if not IsPathWithoutReparsePoints(DestPath) then
        raise EFileSystemException.Create('Extraction root contains a reparse point');
      {$ELSE}
      TDirectory.CreateDirectory(DestPath);
      {$ENDIF}
      TotalUncompressed := 0;
      for I := 0 to High(Entries) do
      begin
        if FCancelRequested then
          raise EAbort.Create('ZIP extraction cancelled');
        EntryPath := Entries[I].Path;
        ParentPath := ExtractFileDir(EntryPath);
        if not Entries[I].IsDirectory then
        begin
          // Create missing parents one component at a time and reject any
          // reparse-point path observed before and after creation.
          EnsureSafeDirectories(DestPath, ParentPath);
{$IFDEF VITTIX_TEST_LOOPBACK}
          if Assigned(FOnZipBeforeCreateForTests) then
            FOnZipBeforeCreateForTests(Self);
{$ENDIF}
          // Recheck immediately before opening the destination. This narrows
          // the path-based race window; it does not eliminate same-identity
          // replacement after this check.
          if not IsPathWithoutReparsePoints(DestPath) or
             not IsPathWithoutReparsePoints(ParentPath) then
            raise EFileSystemException.Create(
              'Extraction path changed or contains a reparse point');
          OutputHandle := CreateFile(PChar(EntryPath), GENERIC_WRITE, 0, nil,
            CREATE_NEW, FILE_ATTRIBUTE_NORMAL or FILE_FLAG_OPEN_REPARSE_POINT, 0);
          if OutputHandle = INVALID_HANDLE_VALUE then
            RaiseLastOSError;
          InputStream := nil;
          ActualEntryBytes := 0;
          try
            ZipArchive.Read(I, InputStream, Header, True);
            repeat
              if FCancelRequested then
                raise EAbort.Create('ZIP extraction cancelled');
              BytesRead := InputStream.Read(Buffer, SizeOf(Buffer));
              if BytesRead = 0 then
                Break;
{$IFDEF VITTIX_TEST_LOOPBACK}
              if Assigned(FOnZipOutputForTests) then
                FOnZipOutputForTests(Self);
{$ENDIF}
              if FCancelRequested then
                raise EAbort.Create('ZIP extraction cancelled');
              if (UInt64(BytesRead) > UInt64(FConfig.MaxArchiveSingleEntryBytes) - ActualEntryBytes) or
                 (UInt64(BytesRead) > UInt64(FConfig.MaxArchiveTotalUncompressedBytes) - TotalUncompressed) then
                raise EFileSystemException.Create('ZIP streamed output limit exceeded');
              Inc(ActualEntryBytes, BytesRead);
              Inc(TotalUncompressed, BytesRead);
              if not WriteFile(OutputHandle, Buffer, BytesRead, Written, nil) or
                 (Written <> BytesRead) then
                RaiseLastOSError;
            until False;
            if ActualEntryBytes <> Entries[I].Size then
              raise EFileSystemException.Create('ZIP entry size did not match its header');
          finally
            InputStream.Free;
            CloseHandle(OutputHandle);
          end;
        end
        else
        begin
          EnsureSafeDirectories(DestPath, EntryPath);
          Attr := GetFileAttributes(PChar(EntryPath));
          if (Attr = INVALID_FILE_ATTRIBUTES) or ((Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) or
             ((Attr and FILE_ATTRIBUTE_DIRECTORY) = 0) then
            raise EFileSystemException.Create('Unsafe ZIP directory destination');
        end;
{$IFDEF VITTIX_TEST_LOOPBACK}
        if Assigned(FOnZipEntryCompleteForTests) then
          FOnZipEntryCompleteForTests(Self);
{$ENDIF}
      end;
{$IFDEF VITTIX_TEST_LOOPBACK}
      if Assigned(FOnZipBeforeCompleteForTests) then
        FOnZipBeforeCompleteForTests(Self);
{$ENDIF}
      if FCancelRequested then
        raise EAbort.Create('ZIP extraction cancelled');
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
  Paths.Free;
  ZipCancellationObserver.Free;
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
var
  TerminateAction: TThreadProcedure;
begin
  Result := False;

  FStateLock.Acquire;
  try
    if (FState <> usReady) or not IsSafeToApply then
      Exit;
    FState := usExtracting;
  finally
    FStateLock.Release;
  end;

  FCancelRequested := False;
  if Assigned(FOnStateChange) then
    FOnStateChange(Self, usExtracting, 'Extracting update...');

  try
    FExtractPath := GetTempExtractPath;

    if not ExtractUpdate(FDownloadedFile, FExtractPath) then
    begin
      CleanupTempFiles;
      Exit;
    end;

    SetState(usApplying, 'Installing update...');

{$IFDEF MSWINDOWS}
    Result := ApplyUpdateWindows(FExtractPath);
{$ELSE}
    raise EUpdaterException.Create(
      'VittixAutoUpdater is not supported on this platform (Windows only)');
{$ENDIF}

    if Result then
    begin
{$IFDEF MSWINDOWS}
      // The helper owns the private extracted tree after it is launched.
      // Prevent Destroy/CleanupTempFiles from racing its copy.
      FExtractPath := '';
      FDownloadedFile := '';
      FStagingPath := '';
      FStagingBase := '';
{$ENDIF}
      SetState(usComplete, 'Update installed successfully');
{$IFDEF MSWINDOWS}
      if FRestartAfterInstall then
      begin
        if Assigned(FOnRestartRequired) then
          FOnRestartRequired(Self)
        else if GetCurrentThreadId = MainThreadID then
        begin
          if Assigned(Application) then
            Application.Terminate
          else
            ExitProcess(0);
        end
        else
        begin
          TerminateAction := procedure
            begin
              if Assigned(Application) then
                Application.Terminate
              else
                ExitProcess(0);
            end;
          TThread.Synchronize(nil, TerminateAction);
        end;
      end;
{$ENDIF}
    end
    else
    begin
      SetState(usFailed, 'Failed to apply update');
      CleanupTempFiles;
    end;

  except
    on E: Exception do
    begin
      SetState(usFailed, 'Update error: ' + E.Message);
      CleanupTempFiles;
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
  AppExe, NewExe, AppDir, ExeName: string;
  TempName: array[0..MAX_PATH] of Char;
  CanWriteAppDir: Boolean;
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

  if FConfig.VerifyAuthenticode then
  begin
    var UpdateFiles := TDirectory.GetFiles(
      SourcePath, '*.*', TSearchOption.soAllDirectories);
    var UpdateFile: string;
    for UpdateFile in UpdateFiles do
      if (SameText(ExtractFileExt(UpdateFile), '.exe') or
          SameText(ExtractFileExt(UpdateFile), '.dll')) and
         not VerifyAuthenticodeFilePinned(
           UpdateFile, FConfig.PinnedPublisherThumbprints) then
        raise EUpdaterException.CreateFmt(
          'Authenticode or publisher pin verification failed: %s', [UpdateFile]);
  end;

  AppDir := ExcludeTrailingPathDelimiter(ExtractFilePath(AppExe));
  ExeName := ExtractFileName(AppExe);

  BatchFile := IncludeTrailingPathDelimiter(ExtractFileDir(SourcePath)) +
    'apply.cmd';

  BatchContent := TStringList.Create;
  try
    BatchContent.Add('@echo off');
    BatchContent.Add('setlocal');
    BatchContent.Add('set RETRIES=0');
    BatchContent.Add('');
    BatchContent.Add(':WAITLOOP');
    // Retry the rename instead of one fixed sleep - this is how we know
    // the old process actually released the file handle, rather than
    // hoping 2 seconds was long enough.
    BatchContent.Add(
      Format('ren "%s" "%s.old" 2>nul',
        [BatchPath(AppExe), BatchPath(ExeName)]));
    BatchContent.Add(
      Format('if exist "%s.old" goto RENAMED', [BatchPath(AppExe)]));
    BatchContent.Add('set /a RETRIES+=1');
    BatchContent.Add('if %RETRIES% GEQ 15 goto RENAME_FAILED');
    BatchContent.Add('timeout /t 1 /nobreak > nul');
    BatchContent.Add('goto WAITLOOP');
    BatchContent.Add('');
    BatchContent.Add(':RENAMED');
    BatchContent.Add(BuildBatchCopyCommand(SourcePath, AppDir));
    BatchContent.Add('if errorlevel 1 goto COPY_FAILED');
    BatchContent.Add(Format('if not exist "%s" goto COPY_FAILED', [BatchPath(AppExe)]));
    BatchContent.Add('');
    BatchContent.Add(Format('start "" "%s"', [BatchPath(AppExe)]));
    BatchContent.Add(Format('del "%s"',
      [BatchPath(IncludeTrailingPathDelimiter(ExtractFileDir(SourcePath)) + 'package.zip')]));
    BatchContent.Add(Format('rd /s /q "%s"',
      [BatchPath(SourcePath)]));
    BatchContent.Add('del "%~f0"');
    BatchContent.Add('exit /b 0');
    BatchContent.Add('');
    BatchContent.Add(':COPY_FAILED');
    // Files were only partially overwritten - restore the previous exe
    // and relaunch it rather than leaving the app missing or half-updated.
    // The extracted update in SourcePath is deliberately left on disk for
    // inspection/retry instead of being deleted.
    BatchContent.Add(Format('ren "%s.old" "%s"',
      [BatchPath(AppExe), BatchPath(ExeName)]));
    BatchContent.Add(Format('start "" "%s"', [BatchPath(AppExe)]));
    BatchContent.Add('del "%~f0"');
    BatchContent.Add('exit /b 1');
    BatchContent.Add('');
    BatchContent.Add(':RENAME_FAILED');
    // Couldn't get an exclusive lock on the exe in time. Nothing was
    // touched - old exe is untouched, update stays in SourcePath.
    BatchContent.Add('del "%~f0"');
    BatchContent.Add('exit /b 1');

    if not CreateExclusiveStagingFile(BatchFile) then
      raise EFileSystemException.CreateFmt(
        'Could not exclusively create update helper "%s" (Windows error %d)',
        [BatchFile, GetLastError]);
    BatchContent.SaveToFile(BatchFile);

    CanWriteAppDir := GetTempFileName(
      PChar(IncludeTrailingPathDelimiter(AppDir)), 'vau', 0, TempName) <> 0;
    if CanWriteAppDir then
      DeleteFile(TempName);

    if not CanWriteAppDir then
      raise EFileSystemException.Create(
        'Install location not writable; a signed elevated helper is required');

    // TODO: replace this non-elevated batch with a dedicated signed helper.
    if ShellExecute(0, 'open',
      PChar(BatchFile), nil, nil, SW_HIDE) <= 32 then
      Exit(False);
    Result := True;
  finally
    BatchContent.Free;
  end;
end;
{$ENDIF}

procedure TUpdateEngine.Cancel;
begin
  FStateLock.Acquire;
  try
    if FState in [usChecking, usDownloading, usExtracting] then
    begin
      FCancelRequested := True;
      TInterlocked.Increment(FCheckOperationGeneration);
    end;
  finally
    FStateLock.Release;
  end;
  if FCancelRequested and (FState in [usChecking, usDownloading, usExtracting]) then
  begin
    FNetwork.CancelCurrentOperation;
    SetState(usCancelled, 'Update cancelled');
  end;
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

  FCancelRequested := False;

  // Reset state to idle
  SetState(usIdle, 'Ready to check for updates');

  // Clear last manifest
  FLastManifest := TUpdateManifest.Empty;
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
