unit VittixAutoUpdater.Network;

{$IFDEF FPC}
  {$mode delphi}
{$ENDIF}

interface

uses
  Classes, SysUtils, StrUtils,
  VittixAutoUpdater.Types;

type
  TNetworkLogEvent = reference to procedure(const Msg: string);

  // Network manager for all HTTP operations
  TUpdateNetworkManager = class
  private
    FConnectionTimeout: Integer;
    FMaxRetries: Integer;
    FMaxManifestAgeDays: Integer;
    FUserAgent: string;
    FProxy: string;
    FOnLog: TNetworkLogEvent;
    FLastError: string;
    FHmacKey: string;
    FRequireHttps: Boolean;
{$IFDEF VITTIX_TEST_LOOPBACK}
    FAllowLoopbackHttpForTests: Boolean;
{$ENDIF}
    FVerifyManifestSignature: Boolean;
    FManifestPublicKey: string;
    FManifestTrustedPublicKeys: TArray<string>;
    FAllowInsecureUnsignedManifests: Boolean;

    // State for progress callback
    FOnProgress: TDownloadProgressEvent;
    FCancelDownload: Boolean;
    FLastProgressTick: Cardinal;
    FExpectedDownloadSize: Int64;
    FDownloadOffset: Int64;
    FSizeLimitExceeded: Boolean;

    function NormalizeChecksum(const Value: string): string;
    function CalculateSHA256(const FileName: string): string;
    function LoopbackHttpAllowedForTests: Boolean;

    procedure Log(const Msg: string);
    procedure WaitBeforeRetry(DelayMs: Integer);
    procedure ReceiveDataHandler(
      const Sender: TObject;
      AContentLength, AReadCount: Int64;
      var Abort: Boolean);

    // Fetches <ManifestUrl>.sig and validates its ECDSA P-256 signature.
    procedure VerifyManifestSignature(
      Client: TObject; // actually THttpClient; kept as TObject so this
                        // declaration doesn't need System.Net.HttpClient
                        // in the interface uses clause (see CreateHttpClient)
      const ManifestUrl: string;
      const ManifestBytes: TBytes);

  protected
    function CreateHttpClient: TObject; // returns THttpClient or FPC client

  public
    constructor Create;

    // Fetch update manifest from URL (tries multiple mirrors)
    function FetchManifest(const Urls: TArray<string>;
      const AppName: string;
      out Manifest: TUpdateManifest): Boolean;

    // Download file with progress tracking
    function DownloadFile(const Url, SavePath: string;
      OnProgress: TDownloadProgressEvent;
      const ExpectedChecksum: string = '';
      const ExpectedSize: Int64 = -1): Boolean;

    procedure CancelCurrentOperation;

    // Properties
    property ConnectionTimeout: Integer read FConnectionTimeout write FConnectionTimeout;
    property MaxRetries: Integer read FMaxRetries write FMaxRetries;
    property MaxManifestAgeDays: Integer
      read FMaxManifestAgeDays write FMaxManifestAgeDays;
    property UserAgent: string read FUserAgent write FUserAgent;
    property Proxy: string read FProxy write FProxy;
    property LastError: string read FLastError;
    property OnLog: TNetworkLogEvent read FOnLog write FOnLog;

    // Deprecated compatibility property; HMAC is no longer used to validate
    // manifests. Configure ManifestPublicKey and VerifyManifestSignatures.
    property HmacKey: string read FHmacKey write FHmacKey;
    property RequireHttps: Boolean read FRequireHttps write FRequireHttps;
{$IFDEF VITTIX_TEST_LOOPBACK}
    // Exists only in the DUnitX test build; production binaries have no switch.
    property AllowLoopbackHttpForTests: Boolean
      read FAllowLoopbackHttpForTests write FAllowLoopbackHttpForTests;
{$ENDIF}
    property VerifyManifestSignatures: Boolean
      read FVerifyManifestSignature write FVerifyManifestSignature;
    property ManifestPublicKey: string
      read FManifestPublicKey write FManifestPublicKey;
    property ManifestTrustedPublicKeys: TArray<string>
      read FManifestTrustedPublicKeys write FManifestTrustedPublicKeys;
    property AllowInsecureUnsignedManifests: Boolean
      read FAllowInsecureUnsignedManifests write FAllowInsecureUnsignedManifests;
  end;

// Legacy HMAC helpers retained for source compatibility; manifest validation
// uses ECDSA P-256 through CNG.
function BytesToHex(const Data: TBytes): string;
function ComputeHMACSHA256(const Key, Data: TBytes): TBytes;
function VerifyManifestSignatureBytes(const ManifestBytes, Signature: TBytes;
  const PublicKeyHex: string): Boolean;
function ManifestSigningKeyId(const PublicKeyHex: string): string;
function TryParseManifestSignatureEnvelope(const Envelope: string;
  out KeyId, SignatureBase64: string): Boolean;
function IsTrustedManifestKeyId(const KeyId: string;
  const TrustedPublicKeys: TArray<string>): Boolean;
function ConstantTimeEquals(const LeftValue, RightValue: string): Boolean;
function IsAllowedUpdateUrl(const Url: string; RequireHttps: Boolean): Boolean;
function TryResolveSecureRedirect(const BaseUrl, Location: string;
  out ResolvedUrl: string): Boolean;
function IsSecureRedirectHopAllowed(RedirectCount: Integer): Boolean;
function IsRangeResumeSupported(const AcceptRanges, ETag: string;
  RemoteSize, ExpectedSize: Int64): Boolean;
function CanResumeDownload(const AcceptRanges, ETag, PreviousETag,
  CurrentUrl, PreviousUrl: string; RemoteSize, PreviousRemoteSize,
  ExpectedSize, PartialSize: Int64): Boolean;
function DownloadRetryDelayMs(Attempt: Integer): Integer;
function HasEnoughDiskSpace(AvailableBytes: UInt64; ExpectedSize: Int64): Boolean;
function IsDownloadWithinSizeCap(Offset, Received, ExpectedSize,
  Margin: Int64): Boolean;
function IsManifestWithinAge(const IssuedAtUtc, CurrentUtc: TDateTime;
  MaxAgeDays: Integer): Boolean;
function TryParseManifestJson(const JsonText, AppName: string;
  MaxAgeDays: Integer; CurrentUtc: TDateTime; RequireIssuedAt: Boolean;
  out Manifest: TUpdateManifest; out ErrorMessage: string): Boolean;

implementation

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  System.Net.HttpClient,
  System.Net.URLClient,
  System.Hash,
  System.JSON,
  System.NetEncoding,
  VittixAutoUpdater.Staging,
  System.DateUtils,
  System.IOUtils;

type
  TBoundedMemoryStream = class(TMemoryStream)
  private
    FLimit: Int64;
  public
    constructor Create(ALimit: Int64);
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

constructor TBoundedMemoryStream.Create(ALimit: Int64);
begin
  inherited Create;
  FLimit := ALimit;
end;

function TBoundedMemoryStream.Write(const Buffer; Count: Longint): Longint;
begin
  if (Count < 0) or (Size > FLimit - Count) then
    raise EStreamError.Create('HTTP response exceeds its configured size limit');
  Result := inherited Write(Buffer, Count);
end;

{$IFDEF MSWINDOWS}
type
  TSharedDownloadStream = class(THandleStream)
  public
    destructor Destroy; override;
  end;

destructor TSharedDownloadStream.Destroy;
begin
  if Handle <> INVALID_HANDLE_VALUE then
    FileClose(Handle);
  inherited Destroy;
end;
{$ENDIF}

function CreateDownloadStream(const FileName: string;
  CreateNew: Boolean): TStream;
{$IFDEF MSWINDOWS}
var
  FileHandle: THandle;
  CreationDisposition: DWORD;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  if CreateNew then
    CreationDisposition := CREATE_NEW
  else
    CreationDisposition := OPEN_EXISTING;
  FileHandle := CreateFile(PChar(FileName), GENERIC_READ or GENERIC_WRITE,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    CreationDisposition, FILE_ATTRIBUTE_NORMAL, 0);
  if FileHandle = INVALID_HANDLE_VALUE then
    raise EFCreateError.CreateFmt('Cannot open download file "%s": %s',
      [FileName, SysErrorMessage(GetLastError)]);
  Result := TSharedDownloadStream.Create(FileHandle);
{$ELSE}
  if CreateNew then
    Result := TFileStream.Create(FileName, fmCreate)
  else
    Result := TFileStream.Create(FileName, fmOpenReadWrite or fmShareDenyNone);
{$ENDIF}
end;

{$IFDEF MSWINDOWS}
function BCryptOpenAlgorithmProvider(out Algorithm: THandle;
  AlgorithmId, ImplementationName: PWideChar; Flags: ULONG): LongInt; stdcall;
  external 'bcrypt.dll' name 'BCryptOpenAlgorithmProvider';
function BCryptCloseAlgorithmProvider(Algorithm: THandle;
  Flags: ULONG): LongInt; stdcall;
  external 'bcrypt.dll' name 'BCryptCloseAlgorithmProvider';
function BCryptImportKeyPair(Algorithm, ImportKey: THandle;
  BlobType: PWideChar; out Key: THandle; Input: PByte;
  InputLength, Flags: ULONG): LongInt; stdcall;
  external 'bcrypt.dll' name 'BCryptImportKeyPair';
function BCryptDestroyKey(Key: THandle): LongInt; stdcall;
  external 'bcrypt.dll' name 'BCryptDestroyKey';
function BCryptVerifySignature(Key: THandle; PaddingInfo: Pointer;
  Hash: PByte; HashLength: ULONG; Signature: PByte;
  SignatureLength, Flags: ULONG): LongInt; stdcall;
  external 'bcrypt.dll' name 'BCryptVerifySignature';

type
  TBcryptEccKeyBlob = packed record
    Magic: Cardinal;
    KeyLength: Cardinal;
  end;

const
  BCRYPT_ECDSA_P256_ALGORITHM = 'ECDSA_P256';
  BCRYPT_ECCPUBLIC_BLOB = 'ECCPUBLICBLOB';
  BCRYPT_ECDSA_PUBLIC_P256_MAGIC = $31534345;
{$ENDIF}

{ Standalone helpers }

function BytesToHex(const Data: TBytes): string;
const
  HexChars: array[0..15] of Char = '0123456789abcdef';
var
  I: Integer;
begin
  SetLength(Result, Length(Data) * 2);
  for I := 0 to High(Data) do
  begin
    Result[I * 2 + 1] := HexChars[Data[I] shr 4];
    Result[I * 2 + 2] := HexChars[Data[I] and $0F];
  end;
end;

// HMAC-SHA256 per RFC 2104, built on top of System.Hash's plain SHA-256
// (Delphi's System.Hash does not expose HMAC directly).
function ComputeHMACSHA256(const Key, Data: TBytes): TBytes;
const
  BlockSize = 64; // SHA-256 block size in bytes
var
  KeyBlock, InnerPad, OuterPad, InnerHash: TBytes;
  Hash: THashSHA2;
  I: Integer;
begin
  SetLength(KeyBlock, BlockSize);
  FillChar(KeyBlock[0], BlockSize, 0);

  if Length(Key) > BlockSize then
  begin
    Hash := THashSHA2.Create(SHA256);
    Hash.Update(Key);
    Move(Hash.HashAsBytes[0], KeyBlock[0], Length(Hash.HashAsBytes));
  end
  else if Length(Key) > 0 then
    Move(Key[0], KeyBlock[0], Length(Key));

  SetLength(InnerPad, BlockSize);
  SetLength(OuterPad, BlockSize);
  for I := 0 to BlockSize - 1 do
  begin
    InnerPad[I] := Byte(KeyBlock[I] xor $36);
    OuterPad[I] := Byte(KeyBlock[I] xor $5C);
  end;

  Hash := THashSHA2.Create(SHA256);
  Hash.Update(InnerPad);
  Hash.Update(Data);
  InnerHash := Hash.HashAsBytes;

  Hash := THashSHA2.Create(SHA256);
  Hash.Update(OuterPad);
  Hash.Update(InnerHash);
  Result := Hash.HashAsBytes;
end;

{$IFDEF VITTIX_TEST_LOOPBACK}
function IsLoopbackHttpUrl(const Url: string): Boolean;
var
  Uri: TURI;
begin
  try
    Uri := TURI.Create(Trim(Url));
    Result := SameText(Uri.Scheme, 'http') and
      (SameText(Uri.Host, '127.0.0.1') or SameText(Uri.Host, 'localhost'));
  except
    Result := False;
  end;
end;
{$ENDIF}

function IsAllowedRequestUrl(const Url: string; RequireHttps,
  AllowLoopbackHttp: Boolean): Boolean;
begin
  Result := IsAllowedUpdateUrl(Url, RequireHttps);
{$IFDEF VITTIX_TEST_LOOPBACK}
  if not Result and RequireHttps and AllowLoopbackHttp then
    Result := IsLoopbackHttpUrl(Url);
{$ENDIF}
end;

function IsAllowedUpdateUrl(const Url: string; RequireHttps: Boolean): Boolean;
var
  NormalizedUrl: string;
  Uri: TURI;
begin
  NormalizedUrl := Trim(Url);
  try
    Uri := TURI.Create(NormalizedUrl);
    Result := (Uri.Host <> '') and
      (SameText(Uri.Scheme, 'https') or
       (not RequireHttps and SameText(Uri.Scheme, 'http')));
  except
    Result := False;
  end;
end;

function TryResolveSecureRedirect(const BaseUrl, Location: string;
  out ResolvedUrl: string): Boolean;
var
  BaseUri, ResolvedUri: TURI;
begin
  Result := False;
  ResolvedUrl := '';
  if not IsAllowedUpdateUrl(BaseUrl, True) or (Trim(Location) = '') then
    Exit;
  try
    BaseUri := TURI.Create(Trim(BaseUrl));
    ResolvedUrl := TURI.PathRelativeToAbs(Trim(Location), BaseUri);
    ResolvedUri := TURI.Create(ResolvedUrl);
    Result := SameText(ResolvedUri.Scheme, 'https') and
      (ResolvedUri.Host <> '');
    if not Result then
      ResolvedUrl := '';
  except
    ResolvedUrl := '';
    Result := False;
  end;
end;

function TryResolveRequestRedirect(const BaseUrl, Location: string;
  AllowLoopbackHttp: Boolean; out ResolvedUrl: string): Boolean;
{$IFDEF VITTIX_TEST_LOOPBACK}
var
  BaseUri: TURI;
{$ENDIF}
begin
  Result := TryResolveSecureRedirect(BaseUrl, Location, ResolvedUrl);
{$IFDEF VITTIX_TEST_LOOPBACK}
  if not Result and AllowLoopbackHttp and IsLoopbackHttpUrl(BaseUrl) then
  begin
    try
      BaseUri := TURI.Create(BaseUrl);
      ResolvedUrl := TURI.PathRelativeToAbs(Trim(Location), BaseUri);
      Result := IsLoopbackHttpUrl(ResolvedUrl);
      if not Result then
        ResolvedUrl := '';
    except
      ResolvedUrl := '';
      Result := False;
    end;
  end;
{$ELSE}
  if not Result then
    ResolvedUrl := '';
{$ENDIF}
end;

function IsSecureRedirectHopAllowed(RedirectCount: Integer): Boolean;
begin
  Result := (RedirectCount >= 0) and (RedirectCount < 5);
end;

function IsRangeResumeSupported(const AcceptRanges, ETag: string;
  RemoteSize, ExpectedSize: Int64): Boolean;
begin
  Result := SameText(Trim(AcceptRanges), 'bytes') and (Trim(ETag) <> '') and
    not StartsText('W/', Trim(ETag)) and (RemoteSize > 0) and
    ((ExpectedSize <= 0) or (ExpectedSize = RemoteSize));
end;

function CanResumeDownload(const AcceptRanges, ETag, PreviousETag,
  CurrentUrl, PreviousUrl: string; RemoteSize, PreviousRemoteSize,
  ExpectedSize, PartialSize: Int64): Boolean;
begin
  Result := IsRangeResumeSupported(AcceptRanges, ETag, RemoteSize, ExpectedSize) and
    ConstantTimeEquals(ETag, PreviousETag) and
    (RemoteSize = PreviousRemoteSize) and SameText(CurrentUrl, PreviousUrl) and
    (PartialSize > 0) and (PartialSize < RemoteSize);
end;

function DownloadRetryDelayMs(Attempt: Integer): Integer;
var
  I: Integer;
begin
  if Attempt <= 0 then
    Exit(0);
  Result := 500;
  for I := 2 to Attempt do
  begin
    if Result >= 5000 then
      Exit(5000);
    Result := Result * 2;
  end;
  if Result > 5000 then
    Result := 5000;
end;

function HasEnoughDiskSpace(AvailableBytes: UInt64; ExpectedSize: Int64): Boolean;
begin
  Result := (ExpectedSize <= 0) or
    (AvailableBytes >= UInt64(ExpectedSize));
end;

function IsDownloadWithinSizeCap(Offset, Received, ExpectedSize,
  Margin: Int64): Boolean;
var
  Limit: Int64;
begin
  if (Offset < 0) or (Received < 0) then
    Exit(False);
  if ExpectedSize <= 0 then
    Exit(True);
  Limit := ExpectedSize;
  if Margin > 0 then
  begin
    if ExpectedSize > High(Int64) - Margin then
      Limit := High(Int64)
    else
      Inc(Limit, Margin);
  end;
  Result := (Offset <= Limit) and (Received <= Limit - Offset);
end;

function HttpGetFollowingSecureRedirects(Client: THttpClient;
  const Url: string; Stream: TStream; RequireHttps: Boolean;
  const RequestHeaders: TNetHeaders = nil;
  AllowLoopbackHttp: Boolean = False): IHTTPResponse;
const
  MaxSecureRedirects = 5;
var
  CurrentUrl, Location, NextUrl: string;
  Hop, I: Integer;
  StartSize: Int64;
  IsRedirect: Boolean;
begin
  CurrentUrl := Url;
  StartSize := Stream.Size;
  Client.HandleRedirects := not RequireHttps;
  for Hop := 0 to MaxSecureRedirects do
  begin
    if not IsAllowedRequestUrl(CurrentUrl, RequireHttps, AllowLoopbackHttp) then
      raise ENetworkFatalException.Create('Insecure update URL rejected');
    // Discard the previous hop body while retaining any resumed prefix.
    Stream.Size := StartSize;
    Stream.Position := StartSize;
    Result := Client.Get(CurrentUrl, Stream, RequestHeaders);
    IsRedirect := RequireHttps and
      ((Result.StatusCode = 301) or (Result.StatusCode = 302) or
       (Result.StatusCode = 303) or (Result.StatusCode = 307) or
       (Result.StatusCode = 308));
    if not IsRedirect then
      Exit;
    if not IsSecureRedirectHopAllowed(Hop) then
      raise ENetworkFatalException.Create('Too many HTTPS redirects (maximum 5)');
    Location := '';
    for I := 0 to High(Result.Headers) do
      if SameText(Result.Headers[I].Name, 'Location') then
      begin
        Location := Result.Headers[I].Value;
        Break;
      end;
    if not TryResolveRequestRedirect(
      CurrentUrl, Location, AllowLoopbackHttp, NextUrl) then
      raise ENetworkFatalException.Create(
        'HTTPS redirect rejected: invalid target or HTTPS downgrade');
    CurrentUrl := NextUrl;
  end;
end;

function HttpHeadFollowingSecureRedirects(Client: THttpClient;
  const Url: string; RequireHttps: Boolean; out FinalUrl: string;
  AllowLoopbackHttp: Boolean = False): IHTTPResponse;
const
  MaxSecureRedirects = 5;
var
  CurrentUrl, Location, NextUrl: string;
  Hop, I: Integer;
  IsRedirect: Boolean;
begin
  CurrentUrl := Url;
  Client.HandleRedirects := not RequireHttps;
  for Hop := 0 to MaxSecureRedirects do
  begin
    if not IsAllowedRequestUrl(CurrentUrl, RequireHttps, AllowLoopbackHttp) then
      raise ENetworkFatalException.Create('Insecure update URL rejected');
    Result := Client.Head(CurrentUrl);
    IsRedirect := RequireHttps and
      ((Result.StatusCode = 301) or (Result.StatusCode = 302) or
       (Result.StatusCode = 303) or (Result.StatusCode = 307) or
       (Result.StatusCode = 308));
    if not IsRedirect then
    begin
      FinalUrl := CurrentUrl;
      Exit;
    end;
    if not IsSecureRedirectHopAllowed(Hop) then
      raise ENetworkFatalException.Create('Too many HTTPS redirects (maximum 5)');
    Location := '';
    for I := 0 to High(Result.Headers) do
      if SameText(Result.Headers[I].Name, 'Location') then
      begin
        Location := Result.Headers[I].Value;
        Break;
      end;
    if not TryResolveRequestRedirect(
      CurrentUrl, Location, AllowLoopbackHttp, NextUrl) then
      raise ENetworkFatalException.Create(
        'HTTPS redirect rejected: invalid target or HTTPS downgrade');
    CurrentUrl := NextUrl;
  end;
  FinalUrl := CurrentUrl;
end;

function ResponseHeaderValue(const Response: IHTTPResponse;
  const HeaderName: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Response.Headers) do
    if SameText(Response.Headers[I].Name, HeaderName) then
      Exit(Response.Headers[I].Value);
end;

function GetLocalFileSize(const FileName: string): Int64;
var
  Stream: TFileStream;
begin
  if not FileExists(FileName) then
    Exit(0);
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    Result := Stream.Size;
  finally
    Stream.Free;
  end;
end;

function ConstantTimeEquals(const LeftValue, RightValue: string): Boolean;
var
  I, MaxLength, Difference: Integer;
  LeftChar, RightChar: Byte;
begin
  MaxLength := Length(LeftValue);
  if Length(RightValue) > MaxLength then
    MaxLength := Length(RightValue);
  Difference := Length(LeftValue) xor Length(RightValue);
  for I := 1 to MaxLength do
  begin
    LeftChar := 0;
    RightChar := 0;
    if I <= Length(LeftValue) then
      LeftChar := Ord(LeftValue[I]);
    if I <= Length(RightValue) then
      RightChar := Ord(RightValue[I]);
    Difference := Difference or (LeftChar xor RightChar);
  end;
  Result := Difference = 0;
end;

function IsManifestWithinAge(const IssuedAtUtc, CurrentUtc: TDateTime;
  MaxAgeDays: Integer): Boolean;
begin
  Result := (IssuedAtUtc > 0) and (MaxAgeDays >= 0) and
    (IssuedAtUtc <= CurrentUtc) and
    ((CurrentUtc - IssuedAtUtc) <= MaxAgeDays);
end;

function VerifyManifestSignatureBytes(const ManifestBytes, Signature: TBytes;
  const PublicKeyHex: string): Boolean;
{$IFDEF MSWINDOWS}
var
  Algorithm, Key: THandle;
  PublicBlob: TBytes;
  Digest: TBytes;
  BlobHeader: TBcryptEccKeyBlob;
  I, KeyOffset: Integer;
  HexValue: Integer;
  Hash: THashSHA2;
  Status: LongInt;
{$ENDIF}
begin
  Result := False;
{$IFDEF MSWINDOWS}
  if (Length(PublicKeyHex) <> 128) or (Length(Signature) <> 64) then
    Exit;

  SetLength(PublicBlob, SizeOf(TBcryptEccKeyBlob) + 64);
  BlobHeader.Magic := BCRYPT_ECDSA_PUBLIC_P256_MAGIC;
  BlobHeader.KeyLength := 32;
  Move(BlobHeader, PublicBlob[0], SizeOf(BlobHeader));
  KeyOffset := SizeOf(BlobHeader);
  for I := 0 to 63 do
  begin
    HexValue := StrToIntDef('$' + Copy(PublicKeyHex, I * 2 + 1, 2), -1);
    if HexValue < 0 then
      Exit;
    PublicBlob[KeyOffset + I] := Byte(HexValue);
  end;

  Hash := THashSHA2.Create(SHA256);
  Hash.Update(ManifestBytes);
  Digest := Hash.HashAsBytes;
  Algorithm := 0;
  Key := 0;
  Status := BCryptOpenAlgorithmProvider(
    Algorithm, PWideChar(WideString(BCRYPT_ECDSA_P256_ALGORITHM)), nil, 0);
  if Status <> 0 then
    Exit;
  try
    Status := BCryptImportKeyPair(Algorithm, 0,
      PWideChar(WideString(BCRYPT_ECCPUBLIC_BLOB)), Key,
      @PublicBlob[0], Length(PublicBlob), 0);
    if Status <> 0 then
      Exit;
    try
      Result := BCryptVerifySignature(Key, nil, @Digest[0], Length(Digest),
        @Signature[0], Length(Signature), 0) = 0;
    finally
      BCryptDestroyKey(Key);
    end;
  finally
    BCryptCloseAlgorithmProvider(Algorithm, 0);
  end;
{$ENDIF}
end;

function ManifestSigningKeyId(const PublicKeyHex: string): string;
var
  PublicBytes, Digest: TBytes;
  I, HexValue: Integer;
  Hash: THashSHA2;
begin
  Result := '';
  if Length(PublicKeyHex) <> 128 then
    Exit;
  SetLength(PublicBytes, 64);
  for I := 0 to 63 do
  begin
    HexValue := StrToIntDef('$' + Copy(PublicKeyHex, I * 2 + 1, 2), -1);
    if HexValue < 0 then
      Exit;
    PublicBytes[I] := Byte(HexValue);
  end;
  Hash := THashSHA2.Create(SHA256);
  Hash.Update(PublicBytes);
  Digest := Hash.HashAsBytes;
  Result := LowerCase(BytesToHex(Digest));
end;

function TryParseManifestSignatureEnvelope(const Envelope: string;
  out KeyId, SignatureBase64: string): Boolean;
const
  Prefix = 'VAU-ECDSA-P256-SHA256-v1:';
var
  S: string;
  Sep: Integer;
  I: Integer;
begin
  Result := False;
  KeyId := '';
  SignatureBase64 := '';
  S := Trim(Envelope);
  if Copy(S, 1, Length(Prefix)) <> Prefix then
    Exit;
  Delete(S, 1, Length(Prefix));
  Sep := Pos(':', S);
  if Sep <> 65 then
    Exit;
  KeyId := Copy(S, 1, 64);
  for I := 1 to Length(KeyId) do
    if not CharInSet(KeyId[I], ['0'..'9', 'a'..'f']) then
      Exit;
  SignatureBase64 := Copy(S, Sep + 1, MaxInt);
  if (Length(SignatureBase64) <> 88) or
     (Copy(SignatureBase64, 87, 2) <> '==') then
    Exit;
  for I := 1 to 86 do
    if not CharInSet(SignatureBase64[I],
      ['A'..'Z', 'a'..'z', '0'..'9', '+', '/']) then
      Exit;
  Result := True;
end;

function IsTrustedManifestKeyId(const KeyId: string;
  const TrustedPublicKeys: TArray<string>): Boolean;
var
  I: Integer;
  CandidateId: string;
begin
  Result := False;
  if Length(KeyId) <> 64 then
    Exit;
  for I := 0 to High(TrustedPublicKeys) do
  begin
    CandidateId := ManifestSigningKeyId(TrustedPublicKeys[I]);
    if (CandidateId <> '') and SameText(CandidateId, KeyId) then
      Exit(True);
  end;
end;

{ TUpdateNetworkManager }

constructor TUpdateNetworkManager.Create;
begin
  inherited Create;
    FConnectionTimeout := 30000; // 30 seconds
  FMaxRetries := 3;
  FUserAgent := 'VI_CON-AutoUpdater/1.0';
  FProxy := '';
  FHmacKey := '';
  FRequireHttps := True;
  FVerifyManifestSignature := True;
  FAllowInsecureUnsignedManifests := False;
  FMaxManifestAgeDays := 30;
{$IFDEF VITTIX_TEST_LOOPBACK}
  FAllowLoopbackHttpForTests := False;
{$ENDIF}
  FCancelDownload := False;
end;

function TUpdateNetworkManager.LoopbackHttpAllowedForTests: Boolean;
begin
{$IFDEF VITTIX_TEST_LOOPBACK}
  Result := FAllowLoopbackHttpForTests;
{$ELSE}
  Result := False;
{$ENDIF}
end;

procedure TUpdateNetworkManager.VerifyManifestSignature(
  Client: TObject;
  const ManifestUrl: string;
  const ManifestBytes: TBytes);
var
  HttpClient: THttpClient;
  SigStream: TMemoryStream;
  SigResponse: IHTTPResponse;
  SigBytes: TBytes;
  KeyId, EnvelopeText, SignatureText, TrustedKey: string;
  TrustedKeys: TArray<string>;
  I: Integer;
begin
  HttpClient := THttpClient(Client);
  SigStream := TBoundedMemoryStream.Create(1024);
  try
    FExpectedDownloadSize := 1024;
    FDownloadOffset := 0;
    FSizeLimitExceeded := False;
    FOnProgress := nil;
    HttpClient.OnReceiveData := ReceiveDataHandler;
    SigResponse := HttpGetFollowingSecureRedirects(
      HttpClient, ManifestUrl + '.sig', SigStream, FRequireHttps, nil,
      LoopbackHttpAllowedForTests);

    if (SigResponse.StatusCode < 200) or (SigResponse.StatusCode >= 300) then
      raise ENetworkException.CreateFmt(
        'Could not fetch manifest signature (HTTP %d) - refusing unsigned manifest',
        [SigResponse.StatusCode]);

    SigStream.Position := 0;
    SetLength(SigBytes, SigStream.Size);
    if SigStream.Size > 0 then
      SigStream.ReadBuffer(SigBytes[0], SigStream.Size);

    if FSizeLimitExceeded or (Length(SigBytes) > 1024) then
      raise ENetworkFatalException.Create('Manifest signature envelope is too large');
    EnvelopeText := TEncoding.UTF8.GetString(SigBytes);
    if not TryParseManifestSignatureEnvelope(
      EnvelopeText, KeyId, SignatureText) then
      raise ENetworkFatalException.Create(
        'Manifest signature envelope is malformed or uses an unsupported algorithm');
    TrustedKeys := Copy(FManifestTrustedPublicKeys);
    if Trim(FManifestPublicKey) <> '' then
    begin
      SetLength(TrustedKeys, Length(TrustedKeys) + 1);
      TrustedKeys[High(TrustedKeys)] := FManifestPublicKey;
    end;
    if Length(TrustedKeys) = 0 then
      raise ENetworkFatalException.Create(
        'Manifest signature verification is enabled but no public key is configured');
    if not IsTrustedManifestKeyId(KeyId, TrustedKeys) then
      raise ENetworkFatalException.CreateFmt(
        'Unknown manifest signing key identifier: %s', [KeyId]);
    TrustedKey := '';
    for I := 0 to High(TrustedKeys) do
      if SameText(ManifestSigningKeyId(TrustedKeys[I]), KeyId) then
      begin
        TrustedKey := TrustedKeys[I];
        Break;
      end;
    try
      SigBytes := TNetEncoding.Base64.DecodeStringToBytes(SignatureText);
    except
      raise ENetworkFatalException.Create('Manifest signature is not valid Base64');
    end;
    if not VerifyManifestSignatureBytes(ManifestBytes, SigBytes, TrustedKey) then
      raise ENetworkFatalException.Create(
        'Manifest signature verification failed - refusing untrusted manifest');

    Log('Manifest signature verified OK');
  finally
    SigStream.Free;
  end;
end;

procedure TUpdateNetworkManager.Log(const Msg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Msg);
end;

function TUpdateNetworkManager.NormalizeChecksum(const Value: string): string;
begin
  Result := Trim(Value);

  if (Length(Result) > 7) and
     (CompareText(Copy(Result, 1, 7), 'sha256:') = 0) then
    Result := Copy(Result, 8, MaxInt);
end;

function TUpdateNetworkManager.CreateHttpClient: TObject;
var
  Client: THttpClient;
begin
  Client := THttpClient.Create;
  Client.UserAgent := FUserAgent;
  Client.ConnectionTimeout := FConnectionTimeout;
  Client.ResponseTimeout := FConnectionTimeout * 10;

  if FProxy <> '' then
    Client.ProxySettings := TProxySettings.Create(FProxy, 8080);

  Result := Client;
end;

procedure TUpdateNetworkManager.ReceiveDataHandler(
  const Sender: TObject;
  AContentLength, AReadCount: Int64;
  var Abort: Boolean);
var
  CurrentTick: Cardinal;
  SizeMargin: Int64;
begin
  CurrentTick := Cardinal(GetTickCount64);

  if FExpectedDownloadSize > 0 then
  begin
    if FExpectedDownloadSize < 64 * 1024 then
      SizeMargin := 0
    else
      SizeMargin := 64 * 1024;
    if not IsDownloadWithinSizeCap(FDownloadOffset, AReadCount,
      FExpectedDownloadSize, SizeMargin) then
    begin
      FSizeLimitExceeded := True;
      Abort := True;
      Exit;
    end;
  end;

  if (CurrentTick - FLastProgressTick >= 33) or
     (AReadCount = AContentLength) then
  begin
    if Assigned(FOnProgress) then
      if FExpectedDownloadSize > 0 then
        FOnProgress(Sender, FDownloadOffset + AReadCount,
          FExpectedDownloadSize, FCancelDownload)
      else
        FOnProgress(Sender, FDownloadOffset + AReadCount,
          FDownloadOffset + AContentLength, FCancelDownload);

    FLastProgressTick := CurrentTick;
    Abort := FCancelDownload;
  end;
end;

procedure TUpdateNetworkManager.WaitBeforeRetry(DelayMs: Integer);
var
  SliceMs: Integer;
begin
  while (DelayMs > 0) and not FCancelDownload do
  begin
    SliceMs := DelayMs;
    if SliceMs > 100 then
      SliceMs := 100;
    TThread.Sleep(SliceMs);
    Dec(DelayMs, SliceMs);
  end;
end;

procedure TUpdateNetworkManager.CancelCurrentOperation;
begin
  FCancelDownload := True;
end;

function TryParseManifestJson(const JsonText, AppName: string;
  MaxAgeDays: Integer; CurrentUtc: TDateTime; RequireIssuedAt: Boolean;
  out Manifest: TUpdateManifest; out ErrorMessage: string): Boolean;
var
  JsonObj: TJSONObject;
  AppObj: TJSONObject;
  JsonValue: TJSONValue;
  Value: string;
begin
  Result := False;
  Manifest := TUpdateManifest.Empty;
  ErrorMessage := '';
  JsonObj := nil;
  try
    JsonValue := TJSONObject.ParseJSONValue(JsonText);
    if not (JsonValue is TJSONObject) then
    begin
      JsonValue.Free;
      raise ENetworkException.Create('Invalid manifest JSON object');
    end;
    JsonObj := TJSONObject(JsonValue);
    JsonValue := JsonObj.GetValue(AppName);
    if not (JsonValue is TJSONObject) then
      raise ENetworkException.CreateFmt(
        'Manifest has no object for application "%s"', [AppName]);
    AppObj := TJSONObject(JsonValue);
    Manifest.AppName := AppName;

    if AppObj.TryGetValue<string>('issued_at', Value) then
    begin
      if not TryISO8601ToDate(Value, Manifest.IssuedAt, True) then
      begin
        if RequireIssuedAt then
          raise ENetworkException.Create('Invalid issued_at timestamp');
        Manifest.IssuedAt := 0;
      end;
    end
    else if RequireIssuedAt then
      raise ENetworkException.Create('Missing issued_at timestamp');
    if RequireIssuedAt and not IsManifestWithinAge(
      Manifest.IssuedAt, CurrentUtc, MaxAgeDays) then
      raise ENetworkException.CreateFmt(
        'Manifest is expired or has an invalid future issued_at '
        + '(maximum age %d days)', [MaxAgeDays]);

    if not AppObj.TryGetValue<string>('version', Value) then
      raise ENetworkException.Create('Missing version field');
    Manifest.Version := TAppVersion.Create(Value);
    if not AppObj.TryGetValue<string>('download_url', Manifest.DownloadUrl) then
      raise ENetworkException.Create('Missing download_url');

    AppObj.TryGetValue<string>('release_notes', Manifest.ReleaseNotes);
    AppObj.TryGetValue<Int64>('file_size', Manifest.FileSize);
    AppObj.TryGetValue<string>('checksum', Manifest.Checksum);
    if AppObj.TryGetValue<string>('release_date', Value) then
      TryStrToDateTime(Value, Manifest.ReleaseDate);
    if AppObj.TryGetValue<string>('min_version', Value) then
      Manifest.MinVersion := TAppVersion.Create(Value);
    if AppObj.TryGetValue<string>('severity', Value) then
    begin
      if SameText(Value, 'critical') then
        Manifest.Severity := usCritical
      else if SameText(Value, 'recommended') then
        Manifest.Severity := usRecommended
      else
        Manifest.Severity := usOptional;
    end;

    if not Manifest.IsValid then
      raise ENetworkException.Create('Manifest is missing required fields');
    Result := True;
  except
    on E: Exception do
    begin
      ErrorMessage := E.Message;
      Manifest := TUpdateManifest.Empty;
    end;
  end;
  JsonObj.Free;
end;

function TUpdateNetworkManager.FetchManifest(
  const Urls: TArray<string>;
  const AppName: string;
  out Manifest: TUpdateManifest): Boolean;
var
  Url: string;
  Stream: TMemoryStream;
  RawBytes: TBytes;
  JsonStr: string;
  Client: THttpClient;
  Response: IHTTPResponse;
  Retry: Integer;
  CurrentUtc: TDateTime;
  ErrorMessage: string;
  Checksum: string;
  I: Integer;
  TrustedKeys: TArray<string>;

  procedure FailConfiguration(const Msg: string);
  begin
    FLastError := Msg;
    raise ENetworkFatalException.Create(Msg);
  end;

begin
  Result := False;
  Manifest := TUpdateManifest.Empty;
  FLastError := '';
  FCancelDownload := False;

  if not FVerifyManifestSignature and not FAllowInsecureUnsignedManifests then
    FailConfiguration(
      'Manifest signature verification is mandatory; unsigned mode requires '
      + 'AllowInsecureUnsignedManifests=True');

  if FVerifyManifestSignature then
  begin
    TrustedKeys := Copy(FManifestTrustedPublicKeys);
    if Trim(FManifestPublicKey) <> '' then
    begin
      SetLength(TrustedKeys, Length(TrustedKeys) + 1);
      TrustedKeys[High(TrustedKeys)] := FManifestPublicKey;
    end;
    if Length(TrustedKeys) = 0 then
      FailConfiguration(
        'Manifest signature verification is enabled but no public key is configured');
    for I := 0 to High(TrustedKeys) do
      if ManifestSigningKeyId(TrustedKeys[I]) = '' then
        FailConfiguration(
          'Manifest trusted key configuration is malformed');
  end;

  if Length(Urls) = 0 then
    FLastError := 'No manifest URLs are configured'
  else if FMaxRetries < 1 then
    FLastError := 'No manifest attempts are configured';

  for Url in Urls do
  begin
    if FCancelDownload then
      Exit(False);

    Log('Trying manifest URL: ' + Url);

    Stream := TBoundedMemoryStream.Create(1024 * 1024);
    try
      for Retry := 1 to FMaxRetries do
      begin
        if FCancelDownload then
          Break;

        Client := THttpClient(CreateHttpClient);
        try
          Client.HandleRedirects := not FRequireHttps;

          Stream.Size := 0;
          Stream.Position := 0;
          FExpectedDownloadSize := 1024 * 1024 - 64 * 1024;
          FDownloadOffset := 0;
          FSizeLimitExceeded := False;
          FOnProgress := nil;
          Client.OnReceiveData := ReceiveDataHandler;

          try
            Response := HttpGetFollowingSecureRedirects(
              Client, Url, Stream, FRequireHttps, nil,
              LoopbackHttpAllowedForTests);

            if FRequireHttps and
               (Response.StatusCode >= 300) and (Response.StatusCode < 400) then
              raise ENetworkFatalException.Create(
                'HTTPS redirect rejected; configure the final HTTPS manifest URL');

            if (Response.StatusCode >= 200) and
               (Response.StatusCode < 300) then
            begin
              if FSizeLimitExceeded then
                raise ENetworkFatalException.Create(
                  'Manifest exceeds the configured response size limit');
              if Stream.Size > 1024 * 1024 then
                raise ENetworkFatalException.Create(
                  'Manifest exceeds the 1 MiB size limit');
              if FCancelDownload then
                Break;

              // Pull out the raw bytes first: this is what gets hashed for
              // signature verification below, and it's also the correct
              // way to turn an HTTP body into a `string` (a byte-for-byte
              // copy into a UnicodeString buffer, which is what this used
              // to do, silently mangles anything but trivial ASCII text).
              Stream.Position := 0;
              SetLength(RawBytes, Stream.Size);
              if Stream.Size > 0 then
                Stream.ReadBuffer(RawBytes[0], Stream.Size);

              if FVerifyManifestSignature then
                VerifyManifestSignature(Client, Url, RawBytes);

              JsonStr := TEncoding.UTF8.GetString(RawBytes);

              CurrentUtc := TTimeZone.Local.ToUniversalTime(Now);
              if not TryParseManifestJson(JsonStr, AppName,
                FMaxManifestAgeDays, CurrentUtc, FVerifyManifestSignature,
                Manifest, ErrorMessage) then
                raise ENetworkFatalException.Create(ErrorMessage);
              if FVerifyManifestSignature then
              begin
                Checksum := NormalizeChecksum(Manifest.Checksum);
                if Manifest.FileSize <= 0 then
                  raise ENetworkFatalException.Create(
                    'Signed manifest must include a positive package file_size');
                if Length(Checksum) <> 64 then
                  raise ENetworkFatalException.Create(
                    'Signed manifest must include a SHA-256 package checksum');
                for I := 1 to Length(Checksum) do
                  if not CharInSet(Checksum[I], ['0'..'9', 'a'..'f', 'A'..'F']) then
                    raise ENetworkFatalException.Create(
                      'Signed manifest package checksum is malformed');
              end;
              FLastError := '';
              Result := True;
              Exit;
            end;
            raise ENetworkException.CreateFmt('Manifest HTTP error %d: %s',
              [Response.StatusCode, Response.StatusText]);

          except
            on E: Exception do
            begin
              FLastError := E.Message;
              Log(Format('Manifest attempt %d failed: %s',
                [Retry, E.Message]));

              if (E is ENetworkFatalException) or (Retry = FMaxRetries) then
                Break;

              WaitBeforeRetry(1000 * Retry);
            end;
          end;
        finally
          Client.Free;
        end;
      end;
    finally
      Stream.Free;
    end;
  end;
end;

function TUpdateNetworkManager.DownloadFile(
  const Url, SavePath: string;
  OnProgress: TDownloadProgressEvent;
  const ExpectedChecksum: string;
  const ExpectedSize: Int64): Boolean;
var
  HttpClient: THttpClient;
  FileStream: TStream;
  Response, HeadResponse: IHTTPResponse;
  ActualChecksum, CleanExpected: string;
  AvailableBytes, TotalBytes, TotalFreeBytes: UInt64;
  Attempt, Attempts, BackoffMs: Integer;
  RemoteSize, ExistingSize, PreviousRemoteSize: Int64;
  ETag, PreviousETag, AcceptRanges, ContentRange, FinalUrl,
    PreviousFinalUrl, WorkingPath, PreviousPartialPath: string;
  RequestHeaders: TNetHeaders;
  CanResume, Resuming, PreservePartial, RetryFailed: Boolean;
begin
  Result := False;
  FOnProgress := OnProgress;
  FCancelDownload := False;
  FExpectedDownloadSize := ExpectedSize;
  FSizeLimitExceeded := False;
  FLastProgressTick := Cardinal(GetTickCount64);

  Log('Downloading: ' + Url);

{$IFDEF MSWINDOWS}
  if not IsPathWithoutReparsePoints(ExtractFilePath(SavePath)) then
    raise EFileSystemException.Create(
      'Download destination is missing, inaccessible, or traverses a reparse point');
{$ENDIF}

  if not IsAllowedRequestUrl(Url, FRequireHttps,
    LoopbackHttpAllowedForTests) then
    raise ENetworkException.Create(
      'Download URL must use HTTPS');

  if ExpectedSize > 0 then
  begin
    if not GetDiskFreeSpaceEx(PChar(ExtractFilePath(SavePath)),
      AvailableBytes, TotalBytes, @TotalFreeBytes) then
      raise EFileSystemException.CreateFmt(
        'Could not determine free disk space for "%s"', [SavePath]);
    if not HasEnoughDiskSpace(AvailableBytes, ExpectedSize) then
      raise EFileSystemException.CreateFmt(
        'Insufficient disk space: update requires %d bytes, only %d available',
        [ExpectedSize, AvailableBytes]);
  end;

  Attempts := FMaxRetries;
  if Attempts < 1 then
    Attempts := 1;
  PreviousETag := '';
  PreviousFinalUrl := '';
  PreviousRemoteSize := 0;
  PreviousPartialPath := '';
  if FileExists(SavePath) then
    SysUtils.DeleteFile(SavePath);
  for Attempt := 1 to Attempts do
  begin
    if FCancelDownload then
      Break;
    HttpClient := THttpClient(CreateHttpClient);
    FileStream := nil;
    WorkingPath := SavePath + '.part-' + IntToStr(Attempt);
    RemoteSize := 0;
    CanResume := False;
    PreservePartial := False;
    RetryFailed := False;
    try
      try
      HttpClient.OnReceiveData := ReceiveDataHandler;

      HeadResponse := HttpHeadFollowingSecureRedirects(
        HttpClient, Url, FRequireHttps, FinalUrl,
        LoopbackHttpAllowedForTests);
      ETag := ResponseHeaderValue(HeadResponse, 'ETag');
      AcceptRanges := ResponseHeaderValue(HeadResponse, 'Accept-Ranges');
      RemoteSize := HeadResponse.ContentLength;
      CanResume := (HeadResponse.StatusCode >= 200) and
        (HeadResponse.StatusCode < 300) and
        IsRangeResumeSupported(AcceptRanges, ETag, RemoteSize, ExpectedSize);

      ExistingSize := 0;
      if (PreviousPartialPath <> '') and FileExists(PreviousPartialPath) then
      begin
        ExistingSize := GetLocalFileSize(PreviousPartialPath);
      end;
      Resuming := CanResumeDownload(AcceptRanges, ETag, PreviousETag,
        FinalUrl, PreviousFinalUrl, RemoteSize, PreviousRemoteSize,
        ExpectedSize, ExistingSize);

      if Resuming then
      begin
        WorkingPath := PreviousPartialPath;
        FDownloadOffset := ExistingSize;
        FileStream := CreateDownloadStream(WorkingPath, False);
        FileStream.Position := FileStream.Size;
        SetLength(RequestHeaders, 2);
        RequestHeaders[0] := TNetHeader.Create(
          'Range', Format('bytes=%d-', [ExistingSize]));
        RequestHeaders[1] := TNetHeader.Create('If-Range', ETag);
      end
      else
      begin
        FDownloadOffset := 0;
        RequestHeaders := nil;
        if FileExists(WorkingPath) then
          SysUtils.DeleteFile(WorkingPath);
        try
          FileStream := CreateDownloadStream(WorkingPath, True);
        except
          on E: Exception do
          begin
            Log(Format('Could not create attempt file "%s": %s',
              [WorkingPath, E.Message]));
            raise;
          end;
        end;
      end;

      PreviousETag := '';
      PreviousFinalUrl := '';
      if CanResume then
      begin
        PreviousETag := ETag;
        PreviousFinalUrl := FinalUrl;
        PreviousRemoteSize := RemoteSize;
      end;

      Response := HttpGetFollowingSecureRedirects(
        HttpClient, FinalUrl, FileStream, FRequireHttps, RequestHeaders,
        LoopbackHttpAllowedForTests);
      if FCancelDownload then
        Break;
      if FSizeLimitExceeded then
        raise ENetworkException.CreateFmt(
          'Download exceeded expected size of %d bytes', [ExpectedSize]);

      if Resuming then
      begin
        ContentRange := ResponseHeaderValue(Response, 'Content-Range');
        if (Response.StatusCode <> 206) or
           not ConstantTimeEquals(ResponseHeaderValue(Response, 'ETag'), ETag) or
           not StartsText('bytes ' + IntToStr(ExistingSize) + '-', ContentRange) or
           not EndsText('/' + IntToStr(RemoteSize), ContentRange) then
        begin
          Response := nil;
          FileStream.Free;
          FileStream := nil;
          SysUtils.DeleteFile(WorkingPath);
          PreviousPartialPath := '';
          WorkingPath := SavePath + '.restart-' + IntToStr(Attempt);
          FDownloadOffset := 0;
          FileStream := CreateDownloadStream(WorkingPath, True);
          Response := HttpGetFollowingSecureRedirects(
            HttpClient, FinalUrl, FileStream, FRequireHttps, nil,
            LoopbackHttpAllowedForTests);
          if (Response.StatusCode < 200) or (Response.StatusCode >= 300) then
            raise ENetworkException.CreateFmt('HTTP error %d: %s',
              [Response.StatusCode, Response.StatusText]);
        end;
      end
      else if (Response.StatusCode < 200) or (Response.StatusCode >= 300) then
        raise ENetworkException.CreateFmt('HTTP error %d: %s',
          [Response.StatusCode, Response.StatusText]);

      if (Response.ContentLength > 0) and not Resuming and
         (FileStream.Size <> Response.ContentLength) then
        raise ENetworkException.Create('Downloaded file size mismatch');
      if (ExpectedSize > 0) and (FileStream.Size <> ExpectedSize) then
        raise ENetworkException.CreateFmt(
          'Downloaded file size mismatch: expected %d bytes, received %d',
          [ExpectedSize, FileStream.Size]);
      if CanResume and (FileStream.Size <> RemoteSize) then
        raise ENetworkException.CreateFmt(
          'Downloaded file size mismatch: server advertised %d bytes, received %d',
          [RemoteSize, FileStream.Size]);

      // Close the response and output stream before hashing the completed file.
      Response := nil;
      HeadResponse := nil;
      HttpClient.Free;
      HttpClient := nil;
      FileStream.Free;
      FileStream := nil;

      if ExpectedChecksum <> '' then
      begin
        CleanExpected := NormalizeChecksum(ExpectedChecksum);
        ActualChecksum := CalculateSHA256(WorkingPath);
        if not ConstantTimeEquals(LowerCase(ActualChecksum),
          LowerCase(CleanExpected)) then
          raise ENetworkException.CreateFmt(
            'Checksum mismatch: expected %s, got %s',
            [CleanExpected, ActualChecksum]);
      end;

      Result := not FCancelDownload;
    except
      on E: Exception do
      begin
        if FCancelDownload or FSizeLimitExceeded then
        begin
          if FSizeLimitExceeded then
            Log('Download aborted after exceeding manifest file size')
          else
            Log('Download cancelled');
          Result := False;
          Break;
        end;
        Log(Format('Download attempt %d/%d failed: %s',
          [Attempt, Attempts, E.Message]));
        if E is ENetworkFatalException then
          Break;
        PreservePartial := CanResume and Assigned(FileStream) and
          FileExists(WorkingPath) and
          (GetLocalFileSize(WorkingPath) < RemoteSize);
        if PreservePartial then
          PreviousPartialPath := WorkingPath;
        RetryFailed := True;
        Response := nil;
        HeadResponse := nil;
        HttpClient.Free;
        HttpClient := nil;
        FileStream.Free;
        FileStream := nil;
      end;
      end;
    finally
      Response := nil;
      HeadResponse := nil;
      if Assigned(HttpClient) then
        HttpClient.Free;
      if Assigned(FileStream) then
        FileStream.Free;
    end;

    if Result then
    begin
      if FileExists(SavePath) then
        SysUtils.DeleteFile(SavePath);
      if RenameFile(WorkingPath, SavePath) then
      begin
        PreviousPartialPath := '';
        Break;
      end;
      Log('Could not move the verified completed download into place');
      Result := False;
      RetryFailed := True;
    end;

    if RetryFailed and not PreservePartial and FileExists(WorkingPath) then
      if not SysUtils.DeleteFile(WorkingPath) then
        Log(Format('Could not delete partial download "%s" after attempt %d '
          + '(Windows error %d)', [WorkingPath, Attempt, GetLastError]));
    if RetryFailed and not PreservePartial then
      PreviousPartialPath := '';

    if not Result and (Attempt < Attempts) and not FCancelDownload and
       not FSizeLimitExceeded then
    begin
      BackoffMs := DownloadRetryDelayMs(Attempt);
      WaitBeforeRetry(BackoffMs);
    end;
  end;

  FExpectedDownloadSize := -1;
  FDownloadOffset := 0;
  if not Result then
  begin
    if (PreviousPartialPath <> '') and FileExists(PreviousPartialPath) then
      SysUtils.DeleteFile(PreviousPartialPath);
    for Attempt := 1 to Attempts do
    begin
      WorkingPath := SavePath + '.part-' + IntToStr(Attempt);
      if FileExists(WorkingPath) then
        SysUtils.DeleteFile(WorkingPath);
      WorkingPath := SavePath + '.restart-' + IntToStr(Attempt);
      if FileExists(WorkingPath) then
        SysUtils.DeleteFile(WorkingPath);
    end;
    if FileExists(SavePath) then
      SysUtils.DeleteFile(SavePath);
  end;
end;

function TUpdateNetworkManager.CalculateSHA256(
  const FileName: string): string;
var
  FileStream: TFileStream;
begin
  FileStream := TFileStream.Create(
    FileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := THashSHA2.GetHashString(FileStream, SHA256);
  finally
    FileStream.Free;
  end;
end;

end.
