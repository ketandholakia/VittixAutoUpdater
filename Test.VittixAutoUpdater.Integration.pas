unit Test.VittixAutoUpdater.Integration;

interface

uses
  DUnitX.TestFramework;

type
  {$M+}
  [TestFixture]
  TVittixAutoUpdaterIntegrationTests = class
  private
    procedure RaiseCheckException(Sender: TObject);
  published
    [Test] procedure EnginePersistsRollbackFloorAndRejectsReplayedManifest;
    [Test] procedure EngineRejectsBadMetadataBeforePackageRequest;
    [Test] procedure EngineDownloadsOnlyAfterExplicitRequest;
    [Test] procedure SignedZipDownloadIsValidatedBeforeExtractionAndUnsafeZipIsRejected;
    [Test] procedure ChecksumFailureCleansPrivateStaging;
    [Test] procedure CancellationCleansPrivateStaging;
    [Test] procedure NetworkFailureModesCleanPrivateStaging;
    [Test] procedure TimeoutCleansPrivateStaging;
    [Test] procedure RegistryCorruptionAndAccessFailureFailClosed;
    [Test] procedure VclComponentStreamsConfigAndDeliversEventsOnMainThread;
    [Test] procedure VisualComponentLoadsLegacyConfigData;
    [Test] procedure VclComponentSupportsDataModuleOwnershipAndRepeatedChecks;
    [Test] procedure EngineAllowsImmediateRecheckFromFailureCallback;
    [Test] procedure EngineCancelSuppressesQueuedCompletion;
    [Test] procedure EngineReportsExceptionAfterWorkerExits;
    [Test] procedure EngineRequiresInstalledVersionBeforeChecking;
    [Test] procedure OlderSignedManifestReturnsNoUpdateAndPersistsFloor;
    [Test] procedure IndependentEnginesCompleteChecksConcurrently;
    [Test] procedure VclDestroyWithQueuedCompletionDoesNotCallOwner;
    [Test] procedure VclCancelAndDestroyDuringActiveCheckDoNotCallDeadOwner;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.DateUtils,
  System.Hash,
  System.IOUtils,
  System.NetEncoding,
  System.SyncObjs,
  System.SysUtils,
  System.Threading,
  System.Types,
  System.Zip,
  Vcl.Forms,
  System.Win.Registry,
  VittixAutoUpdater.Types,
  VittixAutoUpdater.Network,
  VittixAutoUpdater.Engine,
  VittixAutoUpdater.Staging,
  VittixAutoUpdater.VisualComponent,
  IdHTTPServer,
  IdCustomHTTPServer,
  IdContext,
  IdGlobal,
  IdSocketHandle;

type
  TIntegrationHttpServer = class
  private
    FServer: TIdHTTPServer;
    FManifest: string;
    FSignature: string;
    FPackage: string;
    FPackageBytes: TBytes;
    FManifestRequests: Integer;
    FSignatureRequests: Integer;
    FPackageRequests: Integer;
    FPackageHeadRequests: Integer;
    FPackageGetRequests: Integer;
    FPackageFaultMode: string;
    FHoldManifest: Boolean;
    FManifestArrived: TEvent;
    FReleaseManifest: TEvent;
    FManifestCompleted: TEvent;
    FHoldPackage: Boolean;
    FPackageArrived: TEvent;
    FReleasePackage: TEvent;
    procedure HandleRequest(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    function GetPort: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function Url(const Path: string): string;
    function WaitForManifestRequest(Timeout: Cardinal): Boolean;
    procedure ArmManifestGate;
    procedure ReleaseManifest;
    procedure ArmPackageGate;
    procedure ReleasePackage;
    function WaitForPackageRequest(Timeout: Cardinal): Boolean;
    property Manifest: string read FManifest write FManifest;
    property Signature: string read FSignature write FSignature;
    property PackageBody: string read FPackage write FPackage;
    property PackageBytes: TBytes read FPackageBytes write FPackageBytes;
    property PackageFaultMode: string read FPackageFaultMode write FPackageFaultMode;
    property HoldManifest: Boolean read FHoldManifest write FHoldManifest;
    property ManifestRequests: Integer read FManifestRequests;
    property SignatureRequests: Integer read FSignatureRequests;
    property PackageRequests: Integer read FPackageRequests;
    property PackageHeadRequests: Integer read FPackageHeadRequests;
    property PackageGetRequests: Integer read FPackageGetRequests;
    property ManifestArrived: TEvent read FManifestArrived;
    property ManifestCompleted: TEvent read FManifestCompleted;
  end;

  TTestSigningKey = class
  private
    FAlgorithm: THandle;
    FKey: THandle;
    FPublicKey: string;
  public
    constructor Create;
    destructor Destroy; override;
    function Sign(const Bytes: TBytes): string;
    property PublicKey: string read FPublicKey;
  end;

  TIntegrationObserver = class
  public
    MainThreadId: Cardinal;
    StateCount: Integer;
    AvailableCount: Integer;
    FailedCount: Integer;
    DecisionCount: Integer;
    ProgressCount: Integer;
    LastError: string;
    StateHistory: string;
    RecheckUpdater: TVittixAutoUpdaterUI;
    RecheckOnIdle: Boolean;
    RecheckCount: Integer;
    RecheckBusyStateObserved: Boolean;
    procedure StateChanged(Sender: TObject; NewState: TUpdateState;
      const Status: string);
    procedure Progress(Sender: TObject; BytesRead, TotalBytes: Int64;
      var Abort: Boolean);
    procedure Decision(Sender: TObject; const Manifest: TUpdateManifest;
      var Accept: Boolean);
  end;

  TObservedUpdater = class(TVittixAutoUpdaterUI)
  public
    class var DestroyEntered: TEvent;
    destructor Destroy; override;
  end;

  TDownloadThread = class(TThread)
  private
    FEngine: TUpdateEngine;
    FManifest: TUpdateManifest;
  public
    DownloadResult: Boolean;
    constructor Create(Engine: TUpdateEngine; const Manifest: TUpdateManifest);
    procedure Execute; override;
  end;

const
  BCRYPT_ECDSA_P256_ALGORITHM = 'ECDSA_P256';
  BCRYPT_ECCPUBLIC_BLOB = 'ECCPUBLICBLOB';

type
  TBcryptEccKeyBlob = packed record
    Magic: Cardinal;
    KeyLength: Cardinal;
  end;

function BCryptOpenAlgorithmProvider(out Algorithm: THandle;
  AlgorithmId, ImplementationName: PWideChar; Flags: ULONG): LongInt; stdcall;
  external 'bcrypt.dll' name 'BCryptOpenAlgorithmProvider';
function BCryptCloseAlgorithmProvider(Algorithm: THandle;
  Flags: ULONG): LongInt; stdcall;
  external 'bcrypt.dll' name 'BCryptCloseAlgorithmProvider';
function BCryptGenerateKeyPair(Algorithm: THandle; out Key: THandle;
  Length, Flags: ULONG): LongInt; stdcall;
  external 'bcrypt.dll' name 'BCryptGenerateKeyPair';
function BCryptFinalizeKeyPair(Key: THandle; Flags: ULONG): LongInt; stdcall;
  external 'bcrypt.dll' name 'BCryptFinalizeKeyPair';
function BCryptExportKey(Key, ExportKey: THandle; BlobType: PWideChar;
  Output: PByte; OutputLength: ULONG; out ResultLength: ULONG;
  Flags: ULONG): LongInt; stdcall;
  external 'bcrypt.dll' name 'BCryptExportKey';
function BCryptSignHash(Key: THandle; PaddingInfo: Pointer;
  Hash: PByte; HashLength: ULONG; Signature: PByte;
  SignatureLength: ULONG; out ResultLength: ULONG; Flags: ULONG): LongInt; stdcall;
  external 'bcrypt.dll' name 'BCryptSignHash';
function BCryptDestroyKey(Key: THandle): LongInt; stdcall;
  external 'bcrypt.dll' name 'BCryptDestroyKey';

function NewTestRegistryScope: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := 'Software\VittixAutoUpdater\IntegrationTests\' +
    StringReplace(StringReplace(GUIDToString(G), '{', '', []), '}', '', []);
end;

procedure DeleteTestRegistryScope(const KeyName: string);
var
  Registry: TRegistry;
begin
  Registry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    if Registry.KeyExists(KeyName) then
      Registry.DeleteKey(KeyName);
  finally
    Registry.Free;
  end;
end;

function ReadTestFloor(const KeyName: string; out Floor: string): Boolean;
var
  Registry: TRegistry;
begin
  Floor := '';
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    Result := Registry.OpenKeyReadOnly(KeyName);
    if Result then
    begin
      try
        Result := Registry.ValueExists('Floor');
        if Result then
          Floor := Registry.ReadString('Floor');
      finally
        Registry.CloseKey;
      end;
    end;
  finally
    Registry.Free;
  end;
end;

procedure WriteTestFloor(const KeyName, Floor: string);
var
  Registry: TRegistry;
begin
  Registry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    Assert.IsTrue(Registry.OpenKey(KeyName, True));
    Registry.WriteString('Floor', Floor);
    Registry.CloseKey;
  finally
    Registry.Free;
  end;
end;

function IsoUtc(const Value: TDateTime): string;
var
  UtcValue: TDateTime;
begin
  UtcValue := TTimeZone.Local.ToUniversalTime(Value);
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', UtcValue);
end;

function BuildManifest(Server: TIntegrationHttpServer; const Version: string;
  IssuedAt: TDateTime; FileSize: Int64 = 3;
  const Checksum: string = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'): string;
begin
  Result := Format(
    '{"Demo":{"version":"%s","download_url":"%s",' +
    '"file_size":%d,"checksum":"sha256:%s","issued_at":"%s"}}',
    [Version, Server.Url('/package'), FileSize, Checksum, IsoUtc(IssuedAt)]);
end;

function NewEngine(Server: TIntegrationHttpServer; const PublicKey: string;
  const TempFolder: string = ''): TUpdateEngine;
var
  Config: TUpdaterConfig;
begin
  Config := TUpdaterConfig.Default;
  Config.AppName := 'Demo';
  Config.ManifestUrls := TArray<string>.Create(Server.Url('/signed-manifest'));
  Config.ManifestPublicKey := PublicKey;
  Config.MaxManifestAgeDays := 30;
  Config.MaxRetries := 1;
  Config.ConnectionTimeout := 5;
  Config.RequireHttps := False;
  if TempFolder <> '' then
    Config.TempFolder := IncludeTrailingPathDelimiter(TempFolder);
  Result := TUpdateEngine.Create(Config);
  Result.CurrentVersion := TAppVersion.Create('1.0.0.0');
  Result.EnableLoopbackHttpForTests;
end;

procedure SetSignedResponse(Server: TIntegrationHttpServer;
  Key: TTestSigningKey; const Manifest: string);
var
  Bytes: TBytes;
  SignatureEnvelope, SignatureText, KeyId: string;
begin
  Server.Manifest := Manifest;
  Bytes := TEncoding.UTF8.GetBytes(Manifest);
  SignatureEnvelope := Key.Sign(Bytes);
  Server.Signature := SignatureEnvelope;
  Assert.IsTrue(TryParseManifestSignatureEnvelope(SignatureEnvelope, KeyId,
    SignatureText), 'Generated test signature envelope must parse');
  Assert.IsTrue(VerifyManifestSignatureBytes(Bytes,
    TNetEncoding.Base64.DecodeStringToBytes(SignatureText), Key.PublicKey),
    'Generated CNG test signature must verify before it is served');
end;

function CompleteEngineCheck(Engine: TUpdateEngine;
  out Manifest: TUpdateManifest; out ErrorMessage: string): TUpdateCheckResult;
var
  Done: TEvent;
  Completed: Boolean;
  Deadline: UInt64;
  CapturedResult: TUpdateCheckResult;
  CapturedManifest: TUpdateManifest;
  CapturedError: string;
begin
  Done := TEvent.Create(nil, True, False, '');
  Completed := False;
  CapturedResult := ucrError;
  CapturedError := '';
  CapturedManifest := TUpdateManifest.Empty;
  try
    Engine.CheckForUpdate(
      procedure(CallbackResult: TUpdateCheckResult;
        const CallbackManifest: TUpdateManifest; const CallbackError: string)
      begin
        CapturedResult := CallbackResult;
        CapturedManifest := CallbackManifest;
        CapturedError := CallbackError;
        Completed := True;
        Done.SetEvent;
      end);
    Deadline := GetTickCount64 + 20000;
    while not Completed do
    begin
      CheckSynchronize(10);
      if Done.WaitFor(0) = wrSignaled then
        Break;
      if GetTickCount64 >= Deadline then
        raise Exception.Create('Timed out waiting for updater check callback');
    end;
  finally
    Done.Free;
  end;
  Result := CapturedResult;
  Manifest := CapturedManifest;
  ErrorMessage := CapturedError;
end;

procedure PumpUntil(const Predicate: TFunc<Boolean>; Timeout: Cardinal;
  const FailureMessage: string);
var
  Deadline: UInt64;
begin
  Deadline := GetTickCount64 + Timeout;
  while not Predicate() do
  begin
    CheckSynchronize(10);
    if Assigned(Application) then
      Application.ProcessMessages;
    if GetTickCount64 >= Deadline then
      raise Exception.Create(FailureMessage);
  end;
end;

{ TIntegrationHttpServer }

constructor TIntegrationHttpServer.Create;
var
  Binding: TIdSocketHandle;
begin
  inherited Create;
  FPackage := 'abc';
  FManifestArrived := TEvent.Create(nil, True, False, '');
  FReleaseManifest := TEvent.Create(nil, True, False, '');
  FManifestCompleted := TEvent.Create(nil, True, False, '');
  FPackageArrived := TEvent.Create(nil, True, False, '');
  FReleasePackage := TEvent.Create(nil, True, False, '');
  FServer := TIdHTTPServer.Create(nil);
  FServer.Bindings.Clear;
  Binding := FServer.Bindings.Add;
  Binding.IP := '127.0.0.1';
  Binding.Port := 0;
  FServer.DefaultPort := 0;
  FServer.OnCommandGet := HandleRequest;
  FServer.Active := True;
end;

destructor TIntegrationHttpServer.Destroy;
begin
  FReleaseManifest.SetEvent;
  FServer.Active := False;
  FServer.Free;
  FManifestCompleted.Free;
  FPackageArrived.Free;
  FReleasePackage.Free;
  FReleaseManifest.Free;
  FManifestArrived.Free;
  inherited Destroy;
end;

function TIntegrationHttpServer.Url(const Path: string): string;
begin
  Result := Format('http://127.0.0.1:%d%s', [GetPort, Path]);
end;

function TIntegrationHttpServer.GetPort: Integer;
begin
  Result := FServer.Bindings[0].Port;
end;

function TIntegrationHttpServer.WaitForManifestRequest(Timeout: Cardinal): Boolean;
begin
  Result := FManifestArrived.WaitFor(Timeout) = wrSignaled;
end;

procedure TIntegrationHttpServer.ReleaseManifest;
begin
  FReleaseManifest.SetEvent;
end;

procedure TIntegrationHttpServer.ArmManifestGate;
begin
  FHoldManifest := True;
  FManifestArrived.ResetEvent;
  FManifestCompleted.ResetEvent;
  FReleaseManifest.ResetEvent;
end;

procedure TIntegrationHttpServer.ArmPackageGate;
begin
  FHoldPackage := True;
  FPackageArrived.ResetEvent;
  FReleasePackage.ResetEvent;
end;

procedure TIntegrationHttpServer.ReleasePackage;
begin
  FReleasePackage.SetEvent;
end;

function TIntegrationHttpServer.WaitForPackageRequest(Timeout: Cardinal): Boolean;
begin
  Result := FPackageArrived.WaitFor(Timeout) = wrSignaled;
end;

procedure TIntegrationHttpServer.HandleRequest(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Body: string;
begin
  if SameText(ARequestInfo.Document, '/signed-manifest') then
  begin
    TInterlocked.Increment(FManifestRequests);
    FManifestArrived.SetEvent;
    if FHoldManifest then
      FReleaseManifest.WaitFor(30000);
    Body := FManifest;
    AResponseInfo.ContentType := 'application/json';
    AResponseInfo.ResponseNo := 200;
    AResponseInfo.ContentText := Body;
    AResponseInfo.ContentLength := Length(Body);
    FManifestCompleted.SetEvent;
    Exit;
  end;
  if SameText(ARequestInfo.Document, '/signed-manifest.sig') then
  begin
    TInterlocked.Increment(FSignatureRequests);
    Body := FSignature;
    AResponseInfo.ContentType := 'text/plain';
    AResponseInfo.ResponseNo := 200;
    AResponseInfo.ContentText := Body;
    AResponseInfo.ContentLength := Length(Body);
    Exit;
  end;
  if SameText(ARequestInfo.Document, '/package') then
  begin
    TInterlocked.Increment(FPackageRequests);
    if SameText(ARequestInfo.Command, 'HEAD') then
      TInterlocked.Increment(FPackageHeadRequests)
    else
    begin
      TInterlocked.Increment(FPackageGetRequests);
      if SameText(FPackageFaultMode, 'reset') then
      begin
        AContext.Connection.Disconnect;
        Exit;
      end;
      if FHoldPackage then
      begin
        FPackageArrived.SetEvent;
        FReleasePackage.WaitFor(30000);
      end;
    end;
    AResponseInfo.ContentType := 'application/octet-stream';
    AResponseInfo.ResponseNo := 200;
    if Length(FPackageBytes) > 0 then
    begin
      AResponseInfo.ContentLength := Length(FPackageBytes);
      if not SameText(ARequestInfo.Command, 'HEAD') then
      begin
        AResponseInfo.ContentStream := TBytesStream.Create(FPackageBytes);
        AResponseInfo.FreeContentStream := True;
      end;
    end
    else
    begin
      Body := FPackage;
      AResponseInfo.ContentText := Body;
      AResponseInfo.ContentLength := Length(Body);
    end;
    if SameText(FPackageFaultMode, 'truncated') then
      AResponseInfo.ContentLength := AResponseInfo.ContentLength + 17;
    Exit;
  end;
  AResponseInfo.ResponseNo := 404;
end;

constructor TDownloadThread.Create(Engine: TUpdateEngine;
  const Manifest: TUpdateManifest);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FEngine := Engine;
  FManifest := Manifest;
end;

procedure TDownloadThread.Execute;
begin
  DownloadResult := FEngine.DownloadUpdate(FManifest);
end;

{ TTestSigningKey }

constructor TTestSigningKey.Create;
var
  Blob: TBytes;
  PublicBytes: TBytes;
  Header: TBcryptEccKeyBlob;
  Written: ULONG;
  Status: LongInt;
begin
  inherited Create;
  FAlgorithm := 0;
  FKey := 0;
  Status := BCryptOpenAlgorithmProvider(FAlgorithm,
    PWideChar(WideString(BCRYPT_ECDSA_P256_ALGORITHM)), nil, 0);
  if Status <> 0 then
    raise Exception.CreateFmt('BCryptOpenAlgorithmProvider failed: %.8x', [Cardinal(Status)]);
  try
    Status := BCryptGenerateKeyPair(FAlgorithm, FKey, 256, 0);
    if Status <> 0 then
      raise Exception.CreateFmt('BCryptGenerateKeyPair failed: %.8x', [Cardinal(Status)]);
    Status := BCryptFinalizeKeyPair(FKey, 0);
    if Status <> 0 then
      raise Exception.CreateFmt('BCryptFinalizeKeyPair failed: %.8x', [Cardinal(Status)]);
    SetLength(Blob, SizeOf(TBcryptEccKeyBlob) + 64);
    Status := BCryptExportKey(FKey, 0,
      PWideChar(WideString(BCRYPT_ECCPUBLIC_BLOB)), @Blob[0], Length(Blob),
      Written, 0);
    if Status <> 0 then
      raise Exception.CreateFmt('BCryptExportKey failed: %.8x', [Cardinal(Status)]);
    Move(Blob[0], Header, SizeOf(Header));
    if (Header.KeyLength <> 32) or (Written <> Length(Blob)) then
      raise Exception.Create('CNG returned an unexpected P-256 public key blob');
    SetLength(PublicBytes, 64);
    Move(Blob[SizeOf(Header)], PublicBytes[0], Length(PublicBytes));
    FPublicKey := BytesToHex(PublicBytes);
  except
    if FKey <> 0 then
      BCryptDestroyKey(FKey);
    FKey := 0;
    BCryptCloseAlgorithmProvider(FAlgorithm, 0);
    FAlgorithm := 0;
    raise;
  end;
end;

destructor TTestSigningKey.Destroy;
begin
  if FKey <> 0 then
    BCryptDestroyKey(FKey);
  if FAlgorithm <> 0 then
    BCryptCloseAlgorithmProvider(FAlgorithm, 0);
  inherited Destroy;
end;

function TTestSigningKey.Sign(const Bytes: TBytes): string;
var
  Hash: THashSHA2;
  Digest, Signature: TBytes;
  Written: ULONG;
  KeyId: string;
  Status: LongInt;
begin
  Hash := THashSHA2.Create(SHA256);
  Hash.Update(Bytes);
  Digest := Hash.HashAsBytes;
  SetLength(Signature, 64);
  Status := BCryptSignHash(FKey, nil, @Digest[0], Length(Digest),
    @Signature[0], Length(Signature), Written, 0);
  if (Status <> 0) or (Written <> Length(Signature)) then
    raise Exception.CreateFmt('BCryptSignHash failed: %.8x', [Cardinal(Status)]);
  KeyId := ManifestSigningKeyId(FPublicKey);
  Result := 'VAU-ECDSA-P256-SHA256-v1:' + KeyId + ':' +
    StringReplace(StringReplace(
      TNetEncoding.Base64.EncodeBytesToString(Signature), #13, '', [rfReplaceAll]),
      #10, '', [rfReplaceAll]) + #10;
end;

{ TIntegrationObserver }

procedure TIntegrationObserver.StateChanged(Sender: TObject;
  NewState: TUpdateState; const Status: string);
begin
  Inc(StateCount);
  StateHistory := StateHistory + IntToStr(Ord(NewState)) + ',';
  if NewState = usAvailable then
    Inc(AvailableCount);
  if NewState = usFailed then
  begin
    Inc(FailedCount);
    LastError := Status;
  end;
  if GetCurrentThreadId <> MainThreadId then
    raise Exception.Create('VCL state callback did not run on the main thread');
  if RecheckOnIdle and (NewState = usIdle) then
  begin
    RecheckOnIdle := False;
    Inc(RecheckCount);
    RecheckUpdater.CheckForUpdates;
  end;
  if (RecheckCount > 0) and (NewState = usChecking) then
    RecheckBusyStateObserved := RecheckUpdater.IsUpdating;
end;

procedure TIntegrationObserver.Progress(Sender: TObject; BytesRead, TotalBytes: Int64;
  var Abort: Boolean);
begin
  Inc(ProgressCount);
  Assert.AreEqual<Cardinal>(MainThreadId, GetCurrentThreadId);
end;

procedure TIntegrationObserver.Decision(Sender: TObject;
  const Manifest: TUpdateManifest; var Accept: Boolean);
begin
  Inc(DecisionCount);
  if GetCurrentThreadId <> MainThreadId then
    raise Exception.Create('VCL decision callback did not run on the main thread');
  Accept := True;
end;

destructor TObservedUpdater.Destroy;
begin
  if Assigned(DestroyEntered) then
    DestroyEntered.SetEvent;
  inherited Destroy;
end;

procedure TVittixAutoUpdaterIntegrationTests.EnginePersistsRollbackFloorAndRejectsReplayedManifest;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope, Floor1, Floor2, ErrorMessage: string;
  Engine: TUpdateEngine;
  Manifest: TUpdateManifest;
  CheckResult: TUpdateCheckResult;
  NowUtc: TDateTime;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  try
    DeleteTestRegistryScope(Scope);
    NowUtc := TTimeZone.Local.ToUniversalTime(Now);
    SetSignedResponse(Server, Key, BuildManifest(Server, '2.0.0.0', NowUtc));
    Engine := NewEngine(Server, Key.PublicKey);
    try
      CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
      Assert.AreEqual<TUpdateCheckResult>(ucrUpdateAvailable, CheckResult,
        Format('%s; manifest=%d signature=%d package=%d', [ErrorMessage,
          Server.ManifestRequests, Server.SignatureRequests, Server.PackageRequests]));
      Assert.IsTrue(ReadTestFloor(Scope, Floor1), 'Accepted manifest must persist the rollback floor');
      Assert.IsTrue(Floor1.StartsWith('2.0.0.0|'));
      Assert.AreEqual(0, Server.PackageRequests, 'A check must not fetch the package');
    finally
      Engine.Free;
    end;

    SetSignedResponse(Server, Key, BuildManifest(Server, '1.9.9.9', NowUtc - EncodeTime(1, 0, 0, 0)));
    Engine := NewEngine(Server, Key.PublicKey);
    try
      CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
      Assert.AreEqual<TUpdateCheckResult>(ucrError, CheckResult);
      Assert.IsTrue(ErrorMessage.Contains('previously accepted version') or
        ErrorMessage.Contains('rolls back persistent update trust state'), ErrorMessage);
      Assert.IsTrue(ReadTestFloor(Scope, Floor2));
      Assert.AreEqual(Floor1, Floor2, 'Rejected replay must not advance or replace the floor');
      Assert.AreEqual(0, Server.PackageRequests);
    finally
      Engine.Free;
    end;

    SetSignedResponse(Server, Key, BuildManifest(Server, '2.0.1.0', NowUtc + EncodeTime(0, 1, 0, 0)));
    Engine := NewEngine(Server, Key.PublicKey);
    try
      CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
      Assert.AreEqual<TUpdateCheckResult>(ucrUpdateAvailable, CheckResult,
        Format('%s; manifest=%d signature=%d package=%d', [ErrorMessage,
          Server.ManifestRequests, Server.SignatureRequests, Server.PackageRequests]));
      Assert.IsTrue(ReadTestFloor(Scope, Floor2));
      Assert.AreNotEqual(Floor1, Floor2, 'New valid metadata must advance the floor');
      Assert.IsTrue(Floor2.StartsWith('2.0.1.0|'));
    finally
      Engine.Free;
    end;

    SetSignedResponse(Server, Key, BuildManifest(Server, '2.0.0.0', NowUtc));
    Engine := NewEngine(Server, Key.PublicKey);
    try
      CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
      Assert.AreEqual<TUpdateCheckResult>(ucrError, CheckResult);
      Assert.IsTrue(ReadTestFloor(Scope, Floor1));
      Assert.AreEqual(Floor2, Floor1, 'Restarted engine must retain the advanced floor');
      Assert.AreEqual(0, Server.PackageRequests);
    finally
      Engine.Free;
    end;
  finally
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.EngineRejectsBadMetadataBeforePackageRequest;
var
  CaseIndex: Integer;
  Key, WrongKey: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope, ManifestText, ErrorMessage, Floor, EngineKey: string;
  Engine: TUpdateEngine;
  Manifest: TUpdateManifest;
  CheckResult: TUpdateCheckResult;
  IssuedAt: TDateTime;
begin
  for CaseIndex := 0 to 6 do
  begin
    Key := TTestSigningKey.Create;
    WrongKey := nil;
    Server := TIntegrationHttpServer.Create;
    Scope := NewTestRegistryScope;
    SetRollbackRegistryTestScope(Scope);
    SetRollbackRegistryTestAccessFailure(False);
    try
      IssuedAt := TTimeZone.Local.ToUniversalTime(Now);
      ManifestText := BuildManifest(Server, '2.0.0.0', IssuedAt);
      SetSignedResponse(Server, Key, ManifestText);
      case CaseIndex of
        0: Server.Signature := '';
        1: Server.Manifest := StringReplace(Server.Manifest,
          '"version":"2.0.0.0"', '"version":"2.0.0.1"', []);
        2:
          begin
            WrongKey := TTestSigningKey.Create;
            SetRollbackRegistryTestScope(Scope);
          end;
        3: SetSignedResponse(Server, Key,
          BuildManifest(Server, '2.0.0.0', EncodeDateTime(2020, 1, 1, 0, 0, 0, 0)));
        4: SetSignedResponse(Server, Key,
          BuildManifest(Server, '2.0.0.0', EncodeDateTime(2099, 1, 1, 0, 0, 0, 0)));
        5: SetSignedResponse(Server, Key,
          BuildManifest(Server, '2.0.0.0', IssuedAt, 3, 'not-a-checksum'));
        6: SetSignedResponse(Server, Key,
          BuildManifest(Server, '2.0.0.0', IssuedAt, 0));
      end;
      if Assigned(WrongKey) then
        EngineKey := WrongKey.PublicKey
      else
        EngineKey := Key.PublicKey;
      Engine := NewEngine(Server, EngineKey);
      try
        CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
        Assert.AreEqual<TUpdateCheckResult>(ucrError, CheckResult,
          Format('Scenario %d must be rejected: %s', [CaseIndex, ErrorMessage]));
        Assert.IsTrue(Server.ManifestRequests > 0);
        Assert.IsTrue(Server.SignatureRequests > 0,
          Format('Scenario %d did not request the detached signature', [CaseIndex]));
        Assert.IsTrue(Server.PackageRequests = 0,
          Format('Scenario %d made a package request', [CaseIndex]));
        Assert.IsFalse(ReadTestFloor(Scope, Floor),
          Format('Scenario %d changed trust state despite rejection', [CaseIndex]));
      finally
        Engine.Free;
      end;
    finally
      SetRollbackRegistryTestScope('');
      SetRollbackRegistryTestAccessFailure(False);
      DeleteTestRegistryScope(Scope);
      Server.Free;
      WrongKey.Free;
      Key.Free;
    end;
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.EngineDownloadsOnlyAfterExplicitRequest;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope, ErrorMessage, TempFolder: string;
  Engine: TUpdateEngine;
  Observer: TIntegrationObserver;
  Worker: TDownloadThread;
  Manifest: TUpdateManifest;
  CheckResult: TUpdateCheckResult;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  TempFolder := AllocatePrivateStagingDirectory(GetPrivateStagingBase(''));
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  try
    SetSignedResponse(Server, Key, BuildManifest(Server, '2.0.0.0',
      TTimeZone.Local.ToUniversalTime(Now)));
    Engine := NewEngine(Server, Key.PublicKey, TempFolder);
    Observer := TIntegrationObserver.Create;
    Worker := nil;
    try
      CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
      Assert.AreEqual<TUpdateCheckResult>(ucrUpdateAvailable, CheckResult, ErrorMessage);
      Assert.AreEqual(0, Server.PackageRequests,
        'Metadata acceptance alone must not fetch the package');
      Assert.IsFalse(Engine.SynchronizeEvents);
      Engine.SynchronizeEvents := True;
      Observer.MainThreadId := GetCurrentThreadId;
      Engine.OnStateChange := Observer.StateChanged;
      Engine.OnDownloadProgress := Observer.Progress;
      Worker := TDownloadThread.Create(Engine, Manifest);
      Worker.Start;
      Assert.AreEqual<DWORD>(WAIT_OBJECT_0, WaitForSingleObject(Worker.Handle, 10000));
      Assert.AreEqual(0, Observer.StateCount);
      Assert.AreEqual(0, Observer.ProgressCount);
      CheckSynchronize(0);
      Assert.IsTrue(Worker.DownloadResult,
        'Explicit download of the accepted package should succeed');
      Assert.AreEqual(2, Observer.StateCount);
      Assert.IsTrue(Observer.ProgressCount > 0);
      Assert.IsTrue(Server.PackageRequests >= 1,
        'Package endpoint must be reached by explicit DownloadUpdate only');
      Assert.AreEqual(1, Server.PackageHeadRequests,
        'Download should probe package metadata once');
      Assert.AreEqual(1, Server.PackageGetRequests,
        'Download should retrieve package bytes once');
    finally
      Worker.Free;
      Engine.Free;
      Observer.Free;
    end;
  finally
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
    SafeDeletePrivateStagingDirectory(TempFolder, GetPrivateStagingBase(''));
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.SignedZipDownloadIsValidatedBeforeExtractionAndUnsafeZipIsRejected;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope, TempRoot, ArchivePath, ExtractedPath, ErrorMessage, Checksum: string;
  Engine: TUpdateEngine;
  Manifest: TUpdateManifest;
  CheckResult: TUpdateCheckResult;
  Zip: TZipFile;
  Payload: TBytes;
  Hash: THashSHA2;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  Scope := NewTestRegistryScope;
  TempRoot := TPath.Combine(TPath.GetTempPath, 'VauSignedZip-' +
    StringReplace(TGUID.NewGuid.ToString, '{', '', [rfReplaceAll]));
  TDirectory.CreateDirectory(TempRoot);
  ArchivePath := TPath.Combine(TempRoot, 'package.zip');
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  try
    Payload := TEncoding.UTF8.GetBytes('signed archive payload');
    Zip := TZipFile.Create;
    try
      Zip.Open(ArchivePath, zmWrite);
      Zip.Add(Payload, 'bin/example.dat', zcStored);
      Zip.Close;
    finally
      Zip.Free;
    end;
    Server.PackageBytes := TFile.ReadAllBytes(ArchivePath);
    Hash := THashSHA2.Create(SHA256);
    Hash.Update(Server.PackageBytes);
    Checksum := Hash.HashAsString;
    SetSignedResponse(Server, Key, BuildManifest(Server, '2.0.0.0',
      TTimeZone.Local.ToUniversalTime(Now), Length(Server.PackageBytes), Checksum));
    Engine := NewEngine(Server, Key.PublicKey);
    try
      CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
      Assert.AreEqual<TUpdateCheckResult>(ucrUpdateAvailable, CheckResult, ErrorMessage);
      Assert.AreEqual(0, Server.PackageRequests,
        'Manifest authentication must not itself download the ZIP');
      Assert.IsTrue(Engine.DownloadUpdate(Manifest), 'Signed ZIP package must download and hash successfully');
      Assert.AreEqual(2, Server.PackageRequests,
        'Only the explicit download may issue package HEAD and GET requests');
      Assert.AreEqual(1, Server.PackageHeadRequests);
      Assert.AreEqual(1, Server.PackageGetRequests);
      Assert.IsTrue(Engine.ExtractDownloadedPackageForTests(ExtractedPath),
        'Authenticated ZIP package must extract without invoking installation');
      Assert.IsTrue(TFile.Exists(TPath.Combine(ExtractedPath, 'bin/example.dat')));
    finally
      Engine.Free;
    end;

    Zip := TZipFile.Create;
    try
      Zip.Open(ArchivePath, zmWrite);
      Zip.Add(Payload, '..\escaped.dat', zcStored);
      Zip.Close;
    finally
      Zip.Free;
    end;
    Server.PackageBytes := TFile.ReadAllBytes(ArchivePath);
    Hash := THashSHA2.Create(SHA256);
    Hash.Update(Server.PackageBytes);
    Checksum := Hash.HashAsString;
    SetSignedResponse(Server, Key, BuildManifest(Server, '2.0.1.0',
      TTimeZone.Local.ToUniversalTime(Now), Length(Server.PackageBytes), Checksum));
    Engine := NewEngine(Server, Key.PublicKey);
    try
      CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
      Assert.AreEqual<TUpdateCheckResult>(ucrUpdateAvailable, CheckResult, ErrorMessage);
      Assert.IsTrue(Engine.DownloadUpdate(Manifest), 'Signed malicious ZIP must pass package hash before archive validation');
      Assert.IsFalse(Engine.ExtractDownloadedPackageForTests(ExtractedPath),
        'Signed archive path traversal must be rejected');
      Assert.AreEqual<TUpdateState>(usFailed, Engine.State);
      Assert.IsFalse(TDirectory.Exists(ExtractedPath),
        'Failed archive validation must clean the current private staging context');
      Assert.IsFalse(TFile.Exists(TPath.Combine(
        TPath.GetDirectoryName(ExtractedPath), 'escaped.dat')),
        'No archive entry may escape the operation-owned payload directory');
    finally
      Engine.Free;
    end;
  finally
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
    TDirectory.Delete(TempRoot, True);
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.ChecksumFailureCleansPrivateStaging;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope, TempFolder, ErrorMessage: string;
  Engine: TUpdateEngine;
  Manifest: TUpdateManifest;
  CheckResult: TUpdateCheckResult;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  TempFolder := AllocatePrivateStagingDirectory(GetPrivateStagingBase(''));
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  try
    Server.PackageBody := 'abc';
    SetSignedResponse(Server, Key, BuildManifest(Server, '2.0.0.0',
      TTimeZone.Local.ToUniversalTime(Now), 3, StringOfChar('0', 64)));
    Engine := NewEngine(Server, Key.PublicKey, TempFolder);
    try
      CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
      Assert.AreEqual<TUpdateCheckResult>(ucrUpdateAvailable, CheckResult, ErrorMessage);
      Assert.IsFalse(Engine.DownloadUpdate(Manifest),
        'A package with a checksum mismatch must fail');
      Assert.AreEqual<Integer>(0, Length(TDirectory.GetDirectories(TempFolder)),
        'Checksum failure must remove only the operation staging directory');
    finally
      Engine.Free;
    end;
  finally
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
    SafeDeletePrivateStagingDirectory(TempFolder, GetPrivateStagingBase(''));
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.CancellationCleansPrivateStaging;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope, TempFolder, ErrorMessage: string;
  Engine: TUpdateEngine;
  Manifest: TUpdateManifest;
  CheckResult: TUpdateCheckResult;
  Worker: TDownloadThread;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  TempFolder := AllocatePrivateStagingDirectory(GetPrivateStagingBase(''));
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  Engine := nil;
  Worker := nil;
  try
    SetSignedResponse(Server, Key, BuildManifest(Server, '2.0.0.0',
      TTimeZone.Local.ToUniversalTime(Now)));
    Engine := NewEngine(Server, Key.PublicKey, TempFolder);
    CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
    Assert.AreEqual<TUpdateCheckResult>(ucrUpdateAvailable, CheckResult, ErrorMessage);
    Server.ArmPackageGate;
    Worker := TDownloadThread.Create(Engine, Manifest);
    Worker.Start;
    Assert.IsTrue(Server.WaitForPackageRequest(10000),
      'Expected download GET to reach the loopback server');
    Engine.Cancel;
    Server.ReleasePackage;
    Worker.WaitFor;
    Assert.IsFalse(Worker.DownloadResult,
      'Cancelled package download must not complete successfully');
    Assert.AreEqual<TUpdateState>(usCancelled, Engine.State,
      'Cancellation must report the cancelled state');
    Assert.AreEqual<Integer>(0, Length(TDirectory.GetDirectories(TempFolder)),
      'Cancellation must remove the private operation directory');
  finally
    Server.ReleasePackage;
    if Assigned(Worker) then
      Worker.Free;
    Engine.Free;
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
    SafeDeletePrivateStagingDirectory(TempFolder, GetPrivateStagingBase(''));
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.NetworkFailureModesCleanPrivateStaging;
var
  Key: TTestSigningKey;
  Server, PackageServer: TIntegrationHttpServer;
  Scope, TempFolder, PeerStage, ErrorMessage, ManifestText: string;
  Engine: TUpdateEngine;
  Manifest: TUpdateManifest;
  CheckResult: TUpdateCheckResult;

  procedure RunCase(const FaultMode: string);
  begin
    if FaultMode = 'refused' then
    begin
      PackageServer := TIntegrationHttpServer.Create;
      try
        ManifestText := BuildManifest(PackageServer, '2.0.0.0',
          TTimeZone.Local.ToUniversalTime(Now));
      finally
        PackageServer.Free;
        PackageServer := nil;
      end;
    end
    else
    begin
      Server.PackageFaultMode := FaultMode;
      ManifestText := BuildManifest(Server, '2.0.0.0',
        TTimeZone.Local.ToUniversalTime(Now));
    end;
    SetSignedResponse(Server, Key, ManifestText);
    Engine := NewEngine(Server, Key.PublicKey, TempFolder);
    try
      CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
      Assert.AreEqual<TUpdateCheckResult>(ucrUpdateAvailable, CheckResult, ErrorMessage);
      Assert.IsFalse(Engine.DownloadUpdate(Manifest),
        'Fault mode ' + FaultMode + ' must not produce a completed package');
      Assert.AreEqual<TUpdateState>(usFailed, Engine.State,
        'Fault mode ' + FaultMode + ' must report a failed state');
      Assert.AreEqual<Integer>(1, Length(TDirectory.GetDirectories(TempFolder)),
        'Fault mode ' + FaultMode + ' must remove only its owned directory');
      Assert.IsTrue(TDirectory.Exists(PeerStage),
        'Fault cleanup must not remove another operation staging');
    finally
      Engine.Free;
    end;
    Server.PackageFaultMode := '';
  end;

begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  PackageServer := nil;
  TempFolder := AllocatePrivateStagingDirectory(GetPrivateStagingBase(''));
  PeerStage := AllocatePrivateStagingDirectory(TempFolder);
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  try
    RunCase('refused');
    RunCase('reset');
    RunCase('truncated');
  finally
    if Assigned(PackageServer) then
      PackageServer.Free;
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
    SafeDeletePrivateStagingDirectory(PeerStage, TempFolder);
    SafeDeletePrivateStagingDirectory(TempFolder, GetPrivateStagingBase(''));
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.TimeoutCleansPrivateStaging;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope, TempFolder, ErrorMessage: string;
  Engine: TUpdateEngine;
  Manifest: TUpdateManifest;
  CheckResult: TUpdateCheckResult;
  Worker: TDownloadThread;
  Config: TUpdaterConfig;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  TempFolder := AllocatePrivateStagingDirectory(GetPrivateStagingBase(''));
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  Engine := nil;
  Worker := nil;
  try
    SetSignedResponse(Server, Key, BuildManifest(Server, '2.0.0.0',
      TTimeZone.Local.ToUniversalTime(Now)));
    Engine := NewEngine(Server, Key.PublicKey, TempFolder);
    Config := Engine.Config;
    Config.ConnectionTimeout := 1;
    Engine.Config := Config;
    CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
    Assert.AreEqual<TUpdateCheckResult>(ucrUpdateAvailable, CheckResult, ErrorMessage);
    Server.ArmPackageGate;
    Worker := TDownloadThread.Create(Engine, Manifest);
    Worker.Start;
    Assert.IsTrue(Server.WaitForPackageRequest(5000),
      'Expected package GET to enter the controlled timeout gate');
    Worker.WaitFor;
    Server.ReleasePackage;
    Assert.IsFalse(Worker.DownloadResult,
      'Response timeout must not complete a package download');
    Assert.AreEqual<TUpdateState>(usFailed, Engine.State);
    Assert.AreEqual<Integer>(0, Length(TDirectory.GetDirectories(TempFolder)),
      'Timeout must clean the operation-owned staging directory');
  finally
    Server.ReleasePackage;
    if Assigned(Worker) then
      Worker.Free;
    Engine.Free;
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
    SafeDeletePrivateStagingDirectory(TempFolder, GetPrivateStagingBase(''));
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.RegistryCorruptionAndAccessFailureFailClosed;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope, ErrorMessage, Floor: string;
  Engine: TUpdateEngine;
  Manifest: TUpdateManifest;
  CheckResult: TUpdateCheckResult;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  try
    DeleteTestRegistryScope(Scope);
    WriteTestFloor(Scope, 'corrupt-state');
    SetSignedResponse(Server, Key, BuildManifest(Server, '2.0.0.0',
      TTimeZone.Local.ToUniversalTime(Now)));
    Engine := NewEngine(Server, Key.PublicKey);
    try
      CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
      Assert.AreEqual<TUpdateCheckResult>(ucrError, CheckResult);
      Assert.IsTrue(ErrorMessage.Contains('malformed'), Format('%s; manifest=%d signature=%d',
        [ErrorMessage, Server.ManifestRequests, Server.SignatureRequests]));
      Assert.IsTrue(ReadTestFloor(Scope, Floor));
      Assert.AreEqual('corrupt-state', Floor, 'Malformed state must not be overwritten');
      Assert.AreEqual(0, Server.PackageRequests);
    finally
      Engine.Free;
    end;

    DeleteTestRegistryScope(Scope);
    SetRollbackRegistryTestAccessFailure(True);
    Engine := NewEngine(Server, Key.PublicKey);
    try
      CheckResult := CompleteEngineCheck(Engine, Manifest, ErrorMessage);
      Assert.AreEqual<TUpdateCheckResult>(ucrError, CheckResult);
      Assert.IsTrue(ErrorMessage.Contains('Could not'), ErrorMessage);
      Assert.IsFalse(ReadTestFloor(Scope, Floor), 'Injected registry-open failure wrote trust state');
      Assert.AreEqual(0, Server.PackageRequests);
    finally
      Engine.Free;
    end;
  finally
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.VisualComponentLoadsLegacyConfigData;
var
  ConfigBytes, Binary: TMemoryStream;
  Text: TStringStream;
  Writer: TWriter;
  Updater: TVittixAutoUpdaterUI;
  Bytes: TBytes;
  Version: Integer;
begin
  for Version := 1 to 3 do
  begin
    ConfigBytes := TMemoryStream.Create;
    Binary := TMemoryStream.Create;
    Updater := TVittixAutoUpdaterUI.Create(nil);
    try
      Writer := TWriter.Create(ConfigBytes, 1024);
      try
        Writer.WriteInteger(Version);
        Writer.WriteString('Legacy');
        Writer.WriteInteger(0); // ManifestUrls count
        Writer.WriteInteger(30);
        Writer.WriteBoolean(False); // AutoDownload
        Writer.WriteBoolean(False); // AutoInstall
        Writer.WriteBoolean(False); // AllowDowngrade
        Writer.WriteString('');
        Writer.WriteInteger(30);
        Writer.WriteInteger(3);
        Writer.WriteInteger(30);
        Writer.WriteString('Legacy updater');
        Writer.WriteBoolean(True); // RequireChecksum
        Writer.WriteBoolean(True); // RequireHttps
        Writer.WriteBoolean(False); // Discarded RequireSecureConfig
        Writer.WriteBoolean(True); // VerifyManifestSignature
        Writer.WriteBoolean(False); // VerifyAuthenticode
        Writer.WriteInteger(0); // PinnedPublisherThumbprints count
        Writer.WriteString('');
        Writer.WriteInteger(0); // ManifestTrustedPublicKeys count
        Writer.WriteBoolean(False); // AllowInsecureUnsignedManifests
        Writer.WriteString('discarded legacy key');
        if Version >= 2 then
        begin
          Writer.WriteString('12345678');
          Writer.WriteInteger(25);
          Writer.WriteString('345678');
          Writer.WriteString('123456');
          Writer.WriteInteger(12);
          Writer.WriteInteger(200);
          Writer.WriteInteger(80);
        end;
        if Version >= 3 then
        begin
          Writer.WriteInteger(1);
          Writer.WriteString('config/settings.ini');
        end;
      finally
        Writer.Free;
      end;
      SetLength(Bytes, ConfigBytes.Size);
      ConfigBytes.Position := 0;
      ConfigBytes.ReadBuffer(Bytes[0], Length(Bytes));
      Text := TStringStream.Create('object Updater: TVittixAutoUpdaterUI' + sLineBreak +
        '  ConfigData = {' + BytesToHex(Bytes) + '}' + sLineBreak + 'end', TEncoding.ASCII);
      try
        ObjectTextToBinary(Text, Binary);
      finally
        Text.Free;
      end;
      Binary.Position := 0;
      Binary.ReadComponent(Updater);
      Assert.AreEqual('Legacy', Updater.Config.AppName);
      Assert.IsTrue(Updater.Config.VerifyManifestSignature);
      Assert.IsFalse(Updater.Config.AllowInsecureUnsignedManifests);
      if Version >= 2 then
        Assert.AreEqual(25, Updater.Config.MaxArchiveEntryCount);
      if Version < 3 then
        Assert.AreEqual(0, Length(Updater.Config.PreserveFiles))
      else
        Assert.AreEqual('config/settings.ini', Updater.Config.PreserveFiles[0]);
    finally
      Updater.Free;
      Binary.Free;
      ConfigBytes.Free;
    end;
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.VclComponentStreamsConfigAndDeliversEventsOnMainThread;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope: string;
  Config: TUpdaterConfig;
  Form: TForm;
  Updater, Streamed, StreamSource: TVittixAutoUpdaterUI;
  Stream: TMemoryStream;
  Observer: TIntegrationObserver;
  Deadline: UInt64;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  Form := nil;
  Updater := nil;
  Streamed := nil;
  StreamSource := nil;
  Observer := TIntegrationObserver.Create;
  Observer.MainThreadId := GetCurrentThreadId;
  try
    SetSignedResponse(Server, Key, BuildManifest(Server, '2.0.0.0',
      TTimeZone.Local.ToUniversalTime(Now)));
    Config := TUpdaterConfig.Default;
    Config.AppName := 'Demo';
    Config.ManifestUrls := TArray<string>.Create(Server.Url('/signed-manifest'));
    Config.ManifestPublicKey := Key.PublicKey;
    Config.RequireHttps := False;
    Config.MaxManifestAgeDays := 30;
    Config.MaxArchiveEntryCount := 777;
    Config.MaxArchiveSingleEntryBytes := 123456;
    Config.PreserveFiles := TArray<string>.Create('config/settings.ini');
    Form := TForm.CreateNew(nil);
    Assert.IsTrue(Form.Handle <> 0, 'Test form window handle must be created');
    Form.Show;
    Form.Hide;
    try
      Updater := TVittixAutoUpdaterUI.Create(Form);
    except
      on E: Exception do
        raise Exception.Create('VCL component construction failed: ' + E.Message);
    end;
    Updater.Parent := Form;
    Updater.Config := Config;
    Updater.Engine.CurrentVersion := TAppVersion.Create('1.0.0.0');
    Updater.Engine.EnableLoopbackHttpForTests;
    Assert.AreEqual(Key.PublicKey, Updater.Engine.Config.ManifestPublicKey,
      'Configured trusted key must propagate to engine/network configuration');
    Updater.OnStateChange := Observer.StateChanged;
    Updater.OnUpdateDecision := Observer.Decision;

    RegisterClass(TVittixAutoUpdaterUI);
    Stream := TMemoryStream.Create;
    try
      StreamSource := TVittixAutoUpdaterUI.Create(nil);
      StreamSource.Config := Config;
      try
        try
          Stream.WriteComponentRes('VAU_TEST_COMPONENT', StreamSource);
        except
          on E: Exception do
            raise Exception.Create('Writing component stream failed: ' + E.Message);
        end;
      finally
        StreamSource.Free;
        StreamSource := nil;
      end;
      Stream.Position := 0;
      try
        Streamed := TVittixAutoUpdaterUI(Stream.ReadComponentRes(nil));
      except
        on E: Exception do
          raise Exception.Create('Reading component stream failed: ' + E.Message);
      end;
      Assert.IsNotNull(Streamed);
      Streamed.Parent := Form;
      Assert.AreEqual(Key.PublicKey, Streamed.Config.ManifestPublicKey);
      Assert.IsTrue(Streamed.Config.VerifyManifestSignature);
      Assert.IsFalse(Streamed.Config.AllowInsecureUnsignedManifests);
      Assert.AreEqual(777, Streamed.Config.MaxArchiveEntryCount);
      Assert.AreEqual('config/settings.ini', Streamed.Config.PreserveFiles[0]);
      Assert.AreEqual(Int64(123456), Streamed.Config.MaxArchiveSingleEntryBytes);
      Assert.AreEqual(uisStandard, Streamed.UIStyle);
      Assert.AreEqual(ubsBoth, Streamed.ButtonStyle);
      Assert.IsFalse(Streamed.AutoCheck);
    finally
      Streamed.Free;
      StreamSource.Free;
      Stream.Free;
      UnRegisterClass(TVittixAutoUpdaterUI);
    end;

    Updater.CheckForUpdates;
    Deadline := GetTickCount64 + 20000;
    while (Observer.DecisionCount = 0) and (GetTickCount64 < Deadline) do
    begin
      CheckSynchronize(10);
      Application.ProcessMessages;
    end;
    Assert.AreEqual(1, Observer.DecisionCount,
      'Valid signed metadata must trigger update decision event');
    Assert.AreEqual(1, Observer.AvailableCount);
    Assert.AreEqual(0, Server.PackageRequests,
      'VCL check must not begin package download');
    Assert.AreEqual(GetCurrentThreadId, Observer.MainThreadId);

    Updater.Free;
    Updater := nil;
    Server.Signature := 'malformed-envelope';
    Updater := TVittixAutoUpdaterUI.Create(Form);
    Updater.Parent := Form;
    Updater.Config := Config;
    Updater.Engine.CurrentVersion := TAppVersion.Create('1.0.0.0');
    Updater.Engine.EnableLoopbackHttpForTests;
    Updater.OnStateChange := Observer.StateChanged;
    Updater.CheckForUpdates;
    Deadline := GetTickCount64 + 20000;
    while (Observer.FailedCount = 0) and (GetTickCount64 < Deadline) do
    begin
      CheckSynchronize(10);
      Application.ProcessMessages;
    end;
    Assert.AreEqual(1, Observer.FailedCount,
      'Invalid signature must be reported as a component error state');
    Assert.IsTrue(Observer.LastError <> '');
    Assert.AreEqual(0, Server.PackageRequests);
  finally
    Updater.Free;
    Form.Free;
    Observer.Free;
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.VclComponentSupportsDataModuleOwnershipAndRepeatedChecks;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope: string;
  Config: TUpdaterConfig;
  DataModule: TDataModule;
  Form: TForm;
  Updater: TVittixAutoUpdaterUI;
  Observer: TIntegrationObserver;
  Deadline: UInt64;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  DataModule := nil;
  Form := nil;
  Observer := TIntegrationObserver.Create;
  Observer.MainThreadId := GetCurrentThreadId;
  try
    SetSignedResponse(Server, Key, BuildManifest(Server, '1.0.0.0',
      TTimeZone.Local.ToUniversalTime(Now)));
    Config := TUpdaterConfig.Default;
    Config.AppName := 'Demo';
    Config.ManifestUrls := TArray<string>.Create(Server.Url('/signed-manifest'));
    Config.ManifestPublicKey := Key.PublicKey;
    Config.RequireHttps := False;
    DataModule := TDataModule.CreateNew(nil);
    Form := TForm.CreateNew(nil);
    Assert.IsTrue(Form.Handle <> 0, 'Test form window handle must be created');
    Form.Show;
    Form.Hide;
    try
      Updater := TVittixAutoUpdaterUI.Create(DataModule);
    except
      on E: Exception do
        raise Exception.Create('Data-module-owned component construction failed: ' + E.Message);
    end;
    Updater.Parent := Form;
    Updater.Config := Config;
    Updater.Engine.CurrentVersion := TAppVersion.Create('1.0.0.0');
    Updater.Engine.EnableLoopbackHttpForTests;
    Updater.OnStateChange := Observer.StateChanged;
    Observer.RecheckUpdater := Updater;
    Observer.RecheckOnIdle := True;
    Updater.CheckForUpdates;
    Deadline := GetTickCount64 + 20000;
    while (Server.ManifestRequests = 0) or (Observer.StateCount < 2) do
    begin
      CheckSynchronize(10);
      Application.ProcessMessages;
      if GetTickCount64 >= Deadline then
        raise Exception.Create('Data-module hosted check timed out');
    end;
    Deadline := GetTickCount64 + 20000;
    while Updater.IsUpdating do
    begin
      CheckSynchronize(10);
      Application.ProcessMessages;
      if GetTickCount64 >= Deadline then
        raise Exception.Create('First data-module check did not complete');
    end;
    Deadline := GetTickCount64 + 20000;
    while (Server.ManifestRequests < 2) or
          (Observer.RecheckCount = 0) or (Observer.StateCount < 4) do
    begin
      CheckSynchronize(10);
      Application.ProcessMessages;
      if GetTickCount64 >= Deadline then
        raise Exception.CreateFmt(
          'Immediate data-module recheck timed out (manifest=%d, states=%d [%s], failures=%d, error=%s, rechecks=%d, updating=%s, engine-state=%d)',
          [Server.ManifestRequests, Observer.StateCount, Observer.StateHistory,
           Observer.FailedCount,
           Observer.LastError, Observer.RecheckCount,
           BoolToStr(Updater.IsUpdating, True), Ord(Updater.Engine.State)]);
    end;
    Assert.AreEqual(1, Observer.RecheckCount,
      'The first terminal state callback must initiate exactly one immediate recheck');
    Assert.IsTrue(Observer.RecheckBusyStateObserved,
      'A stale completion event must not clear busy state for the newer check');
    Assert.AreEqual(2, Server.ManifestRequests,
      'Immediate recheck from the terminal callback must reach the server');
    Assert.IsTrue(Observer.StateCount >= 4,
      'Both checks must deliver checking and terminal state events');
    Server.ArmManifestGate;
    Updater.CheckForUpdates;
    Updater.CheckForUpdates;
    Updater.CheckForUpdates;
    Assert.IsTrue(Server.WaitForManifestRequest(10000),
      'Rapid repeated checks did not start their single accepted request');
    Assert.AreEqual(3, Server.ManifestRequests,
      'Rapid requests while a check is active must not start duplicate operations');
    Server.ReleaseManifest;
    Deadline := GetTickCount64 + 20000;
    while Updater.IsUpdating or (Observer.StateCount < 6) do
    begin
      CheckSynchronize(10);
      Application.ProcessMessages;
      if GetTickCount64 >= Deadline then
        raise Exception.Create('Rapid repeated check did not complete cleanly');
    end;
    Assert.AreEqual(3, Server.ManifestRequests,
      'Only one additional check may be accepted from the rapid request burst');
    Assert.AreEqual(0, Observer.AvailableCount);
    Assert.AreEqual(0, Server.PackageRequests);
    Form.Free;
    Form := nil;
    DataModule.Free;
    DataModule := nil;
  finally
    DataModule.Free;
    Form.Free;
    Observer.Free;
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.EngineAllowsImmediateRecheckFromFailureCallback;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope: string;
  Engine: TUpdateEngine;
  Done: TEvent;
  Deadline: UInt64;
  TerminalCount, FirstThreadId, SecondThreadId, CancelledCallbackCount: Integer;
  FirstResult, SecondResult: TUpdateCheckResult;
  FirstState, SecondState: TUpdateState;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  Done := TEvent.Create(nil, True, False, '');
  Engine := nil;
  TerminalCount := 0;
  FirstThreadId := 0;
  SecondThreadId := 0;
  CancelledCallbackCount := 0;
  try
    DeleteTestRegistryScope(Scope);
    SetSignedResponse(Server, Key,
      BuildManifest(Server, '1.0.0.0', TTimeZone.Local.ToUniversalTime(Now)));
    Server.Signature := 'malformed-signature-envelope';
    Engine := NewEngine(Server, Key.PublicKey);

    Engine.CheckForUpdate(
      procedure(CallbackResult: TUpdateCheckResult;
        const CallbackManifest: TUpdateManifest; const CallbackError: string)
      begin
        Inc(TerminalCount);
        FirstThreadId := GetCurrentThreadId;
        FirstResult := CallbackResult;
        FirstState := Engine.State;
        SetSignedResponse(Server, Key,
          BuildManifest(Server, '1.0.0.0', TTimeZone.Local.ToUniversalTime(Now)));
        Engine.CheckForUpdate(
          procedure(NextResult: TUpdateCheckResult;
            const NextManifest: TUpdateManifest; const NextError: string)
          begin
            Inc(TerminalCount);
            SecondThreadId := GetCurrentThreadId;
            SecondResult := NextResult;
            SecondState := Engine.State;
            Done.SetEvent;
          end);
      end);

    Deadline := GetTickCount64 + 20000;
    while Done.WaitFor(0) <> wrSignaled do
    begin
      CheckSynchronize(10);
      Application.ProcessMessages;
      if GetTickCount64 >= Deadline then
        raise Exception.Create('Immediate engine recheck callback timed out');
    end;
    Assert.AreEqual(2, TerminalCount, 'Each accepted check must complete exactly once');
    Assert.AreEqual<TUpdateCheckResult>(ucrError, FirstResult);
    Assert.AreEqual<TUpdateState>(usFailed, FirstState,
      'The failure callback must observe a terminal failed state');
    Assert.AreEqual<TUpdateCheckResult>(ucrNoUpdateAvailable, SecondResult);
    Assert.AreEqual<TUpdateState>(usIdle, SecondState,
      'The second callback must observe its terminal idle state');
    Assert.AreEqual<Integer>(GetCurrentThreadId, FirstThreadId,
      'First completion callback must run on the main thread');
    Assert.AreEqual<Integer>(GetCurrentThreadId, SecondThreadId,
      'Reentrant completion callback must run on the main thread');
    Assert.AreEqual(2, Server.ManifestRequests,
      'The reentrant request must perform a second manifest retrieval');

    Server.ArmManifestGate;
    Engine.CheckForUpdate(
      procedure(CancelResult: TUpdateCheckResult;
        const CancelManifest: TUpdateManifest; const CancelError: string)
      begin
        Inc(CancelledCallbackCount);
      end);
    Assert.IsTrue(Server.WaitForManifestRequest(10000),
      'Cancelled-check fixture did not start network activity');
    Engine.Cancel;
    Server.ReleaseManifest;
    Assert.IsTrue(Server.ManifestCompleted.WaitFor(10000) = wrSignaled,
      'Cancelled-check response was not released');
    Assert.AreEqual<TUpdateState>(usCancelled, Engine.State,
      'Cancellation must establish a terminal cancelled state');
    Done.ResetEvent;
    Engine.CheckForUpdate(
      procedure(AfterCancelResult: TUpdateCheckResult;
        const AfterCancelManifest: TUpdateManifest; const AfterCancelError: string)
      begin
        Inc(TerminalCount);
        Done.SetEvent;
      end);
    Deadline := GetTickCount64 + 20000;
    while Done.WaitFor(0) <> wrSignaled do
    begin
      CheckSynchronize(10);
      Application.ProcessMessages;
      if GetTickCount64 >= Deadline then
        raise Exception.Create('Check after cancellation timed out');
    end;
    Assert.AreEqual(3, TerminalCount,
      'The accepted post-cancellation check must complete exactly once');
    Assert.AreEqual(0, CancelledCallbackCount,
      'The cancelled operation must not deliver a stale completion callback');
    Assert.AreEqual(4, Server.ManifestRequests,
      'The canceled request and post-cancellation retry must both reach the fixture');
  finally
    Engine.Free;
    Done.Free;
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.EngineRequiresInstalledVersionBeforeChecking;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Engine: TUpdateEngine;
  Manifest: TUpdateManifest;
  FileName, ErrorMessage: string;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  Engine := nil;
  FileName := TPath.GetTempFileName;
  try
    TFile.WriteAllText(FileName, 'No version resource');
    Engine := NewEngine(Server, Key.PublicKey);
    Engine.SetCurrentVersionFromFileForTests(FileName);
    Assert.AreEqual<TUpdateCheckResult>(ucrError,
      CompleteEngineCheck(Engine, Manifest, ErrorMessage));
    Assert.IsTrue(Pos('version resource', ErrorMessage) > 0);
    Assert.AreEqual<TUpdateState>(usFailed, Engine.State);
    Assert.AreEqual(0, Server.ManifestRequests);
  finally
    TFile.Delete(FileName);
    Engine.Free;
    Server.Free;
    Key.Free;
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.OlderSignedManifestReturnsNoUpdateAndPersistsFloor;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Engine: TUpdateEngine;
  Manifest: TUpdateManifest;
  Scope, ErrorMessage, Floor: string;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  Engine := nil;
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  try
    SetSignedResponse(Server, Key, BuildManifest(Server, '1.0.0.0',
      TTimeZone.Local.ToUniversalTime(Now)));
    Engine := NewEngine(Server, Key.PublicKey);
    Engine.CurrentVersion := TAppVersion.Create('2.0.0.0');
    Assert.AreEqual<TUpdateCheckResult>(ucrNoUpdateAvailable,
      CompleteEngineCheck(Engine, Manifest, ErrorMessage), ErrorMessage);
    Assert.AreEqual<TUpdateState>(usIdle, Engine.State);
    Assert.IsTrue(ReadTestFloor(Scope, Floor));
    Assert.IsTrue(Floor.StartsWith('1.0.0.0|'));
    Assert.AreEqual(0, Server.PackageRequests);
  finally
    Engine.Free;
    SetRollbackRegistryTestScope('');
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.RaiseCheckException(Sender: TObject);
begin
  raise Exception.Create('Forced manifest worker exception');
end;

procedure TVittixAutoUpdaterIntegrationTests.EngineReportsExceptionAfterWorkerExits;
var
  Engine: TUpdateEngine;
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  ReportedError: string;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  Engine := nil;
  try
    Engine := NewEngine(Server, Key.PublicKey);
    Engine.BeforeManifestFetchForTests := RaiseCheckException;
    Engine.CheckForUpdate(
      procedure(R: TUpdateCheckResult; const M: TUpdateManifest; const E: string)
      begin
        Assert.AreEqual<TUpdateCheckResult>(ucrError, R);
        ReportedError := E;
      end);
    Assert.IsTrue(Engine.WaitForCheckWorkerForTests(10000));
    CheckSynchronize(0);
    Assert.AreEqual<TUpdateState>(usFailed, Engine.State);
    Assert.AreEqual('Forced manifest worker exception', ReportedError);
  finally
    Engine.Free;
    Server.Free;
    Key.Free;
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.EngineCancelSuppressesQueuedCompletion;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope: string;
  Engine: TUpdateEngine;
  CompletionCount: Integer;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  Engine := nil;
  CompletionCount := 0;
  try
    DeleteTestRegistryScope(Scope);
    SetSignedResponse(Server, Key,
      BuildManifest(Server, '1.0.0.0', TTimeZone.Local.ToUniversalTime(Now)));
    Server.ArmManifestGate;
    Engine := NewEngine(Server, Key.PublicKey);
    Engine.CheckForUpdate(
      procedure(R: TUpdateCheckResult; const M: TUpdateManifest; const E: string)
      begin
        Inc(CompletionCount);
      end);
    Assert.IsTrue(Server.WaitForManifestRequest(10000),
      'Manifest request did not reach the loopback server');
    Server.ReleaseManifest;
    Assert.IsTrue(Server.ManifestCompleted.WaitFor(10000) = wrSignaled,
      'Manifest response did not complete');
    Assert.IsTrue(Engine.WaitForCheckWorkerForTests(10000),
      'Worker did not finish queuing the terminal completion');
    Assert.AreEqual<TUpdateState>(usChecking, Engine.State,
      'Terminal completion must still be pending main-thread dispatch');

    Engine.Cancel;
    CheckSynchronize(0);
    Application.ProcessMessages;
    Assert.AreEqual<TUpdateState>(usCancelled, Engine.State);
    Assert.AreEqual(0, CompletionCount,
      'Cancellation must invalidate an already queued completion');
  finally
    Engine.Free;
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.IndependentEnginesCompleteChecksConcurrently;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope: string;
  FirstEngine, SecondEngine: TUpdateEngine;
  Done: TEvent;
  CallbackCount: Integer;
  Deadline: UInt64;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  FirstEngine := nil;
  SecondEngine := nil;
  Done := TEvent.Create(nil, True, False, '');
  CallbackCount := 0;
  try
    DeleteTestRegistryScope(Scope);
    SetSignedResponse(Server, Key,
      BuildManifest(Server, '1.0.0.0', TTimeZone.Local.ToUniversalTime(Now)));
    FirstEngine := NewEngine(Server, Key.PublicKey);
    SecondEngine := NewEngine(Server, Key.PublicKey);
    FirstEngine.CheckForUpdate(
      procedure(R: TUpdateCheckResult; const M: TUpdateManifest; const E: string)
      begin
        if TInterlocked.Increment(CallbackCount) = 2 then
          Done.SetEvent;
      end);
    SecondEngine.CheckForUpdate(
      procedure(R: TUpdateCheckResult; const M: TUpdateManifest; const E: string)
      begin
        if TInterlocked.Increment(CallbackCount) = 2 then
          Done.SetEvent;
      end);
    Deadline := GetTickCount64 + 20000;
    while Done.WaitFor(0) <> wrSignaled do
    begin
      CheckSynchronize(10);
      Application.ProcessMessages;
      if GetTickCount64 >= Deadline then
        raise Exception.Create('Independent updater checks did not both complete');
    end;
    Assert.AreEqual(2, CallbackCount,
      'Each independent engine must receive exactly one terminal callback');
    Assert.AreEqual(2, Server.ManifestRequests,
      'Both independent engines must retrieve the manifest');
    Assert.AreEqual<TUpdateState>(usIdle, FirstEngine.State);
    Assert.AreEqual<TUpdateState>(usIdle, SecondEngine.State);
  finally
    FirstEngine.Free;
    SecondEngine.Free;
    Done.Free;
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.VclDestroyWithQueuedCompletionDoesNotCallOwner;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope: string;
  Config: TUpdaterConfig;
  Form: TForm;
  Updater: TObservedUpdater;
  Observer: TIntegrationObserver;
  DestroySignal: TEvent;
  StateCountBeforeDestroy: Integer;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  Form := nil;
  Updater := nil;
  Observer := TIntegrationObserver.Create;
  Observer.MainThreadId := GetCurrentThreadId;
  DestroySignal := TEvent.Create(nil, True, False, '');
  TObservedUpdater.DestroyEntered := DestroySignal;
  try
    SetSignedResponse(Server, Key,
      BuildManifest(Server, '2.0.0.0', TTimeZone.Local.ToUniversalTime(Now)));
    Server.ArmManifestGate;
    Config := TUpdaterConfig.Default;
    Config.AppName := 'Demo';
    Config.ManifestUrls := TArray<string>.Create(Server.Url('/signed-manifest'));
    Config.ManifestPublicKey := Key.PublicKey;
    Config.RequireHttps := False;
    Form := TForm.CreateNew(nil);
    Assert.IsTrue(Form.Handle <> 0);
    Updater := TObservedUpdater.Create(Form);
    Updater.Parent := Form;
    Updater.Config := Config;
    Updater.Engine.EnableLoopbackHttpForTests;
    Updater.OnStateChange := Observer.StateChanged;
    Updater.CheckForUpdates;
    Assert.IsTrue(Server.WaitForManifestRequest(10000),
      'Manifest request did not start');
    StateCountBeforeDestroy := Observer.StateCount;
    Server.ReleaseManifest;
    Assert.IsTrue(Server.ManifestCompleted.WaitFor(10000) = wrSignaled,
      'Manifest response did not complete');
    Assert.IsTrue(Updater.Engine.WaitForCheckWorkerForTests(10000),
      'Check worker did not finish queuing its completion');

    Form.Free;
    Form := nil;
    Updater := nil;
    Assert.IsTrue(DestroySignal.WaitFor(0) = wrSignaled,
      'The form-owned updater must be destroyed');
    CheckSynchronize(0);
    Application.ProcessMessages;
    Assert.AreEqual(StateCountBeforeDestroy, Observer.StateCount,
      'Queued engine completion must not invoke callbacks after component destruction');
    Assert.AreEqual(0, Server.PackageRequests);
  finally
    TObservedUpdater.DestroyEntered := nil;
    Form.Free;
    Observer.Free;
    DestroySignal.Free;
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
  end;
end;

procedure TVittixAutoUpdaterIntegrationTests.VclCancelAndDestroyDuringActiveCheckDoNotCallDeadOwner;
var
  Key: TTestSigningKey;
  Server: TIntegrationHttpServer;
  Scope: string;
  Config: TUpdaterConfig;
  Form: TForm;
  Updater: TObservedUpdater;
  Observer: TIntegrationObserver;
  ReleaseThread: TThread;
  DestroySignal: TEvent;
  StateCountBeforeDestroy: Integer;
begin
  Key := TTestSigningKey.Create;
  Server := TIntegrationHttpServer.Create;
  Scope := NewTestRegistryScope;
  SetRollbackRegistryTestScope(Scope);
  SetRollbackRegistryTestAccessFailure(False);
  Form := nil;
  Updater := nil;
  ReleaseThread := nil;
  Observer := TIntegrationObserver.Create;
  Observer.MainThreadId := GetCurrentThreadId;
  DestroySignal := TEvent.Create(nil, True, False, '');
  TObservedUpdater.DestroyEntered := DestroySignal;
  try
    SetSignedResponse(Server, Key, BuildManifest(Server, '2.0.0.0',
      TTimeZone.Local.ToUniversalTime(Now)));
    Server.ArmManifestGate;
    Config := TUpdaterConfig.Default;
    Config.AppName := 'Demo';
    Config.ManifestUrls := TArray<string>.Create(Server.Url('/signed-manifest'));
    Config.ManifestPublicKey := Key.PublicKey;
    Config.RequireHttps := False;
    Form := TForm.CreateNew(nil);
    Assert.IsTrue(Form.Handle <> 0, 'Test form window handle must be created');
    Form.Show;
    Form.Hide;
    try
      Updater := TObservedUpdater.Create(Form);
    except
      on E: Exception do
        raise Exception.Create('Active-check component construction failed: ' + E.Message);
    end;
    Updater.Parent := Form;
    Updater.Config := Config;
    Updater.Engine.EnableLoopbackHttpForTests;
    Updater.OnStateChange := Observer.StateChanged;
    Updater.OnUpdateDecision := Observer.Decision;
    DestroySignal.ResetEvent;
    Updater.CheckForUpdates;
    Assert.IsTrue(Server.WaitForManifestRequest(10000),
      'Loopback server did not receive active manifest request');
    Updater.CancelOperation;
    Server.ReleaseManifest;
    Assert.IsTrue(Server.ManifestCompleted.WaitFor(10000) = wrSignaled,
      'Held manifest response was not released');

    Updater.ResetToInitialState;
    Updater.Free;
    Updater := nil;
    Server.ArmManifestGate;
    Updater := TObservedUpdater.Create(Form);
    Updater.Parent := Form;
    Updater.Config := Config;
    Updater.Engine.EnableLoopbackHttpForTests;
    Updater.OnStateChange := Observer.StateChanged;
    Updater.OnUpdateDecision := Observer.Decision;
    DestroySignal.ResetEvent;
    Updater.CheckForUpdates;
    Assert.IsTrue(Server.WaitForManifestRequest(10000),
      'Second active manifest request did not arrive');
    TObservedUpdater.DestroyEntered := DestroySignal;
    ReleaseThread := TThread.CreateAnonymousThread(
      procedure
      begin
        if DestroySignal.WaitFor(10000) = wrSignaled then
          Server.ReleaseManifest;
      end);
    ReleaseThread.FreeOnTerminate := False;
    ReleaseThread.Start;
    StateCountBeforeDestroy := Observer.StateCount;
    Form.Free;
    Form := nil;
    Updater := nil;
    ReleaseThread.WaitFor;
    ReleaseThread.Free;
    ReleaseThread := nil;
    Assert.IsTrue(Server.ManifestCompleted.WaitFor(10000) = wrSignaled);
    CheckSynchronize(0);
    Application.ProcessMessages;
    Assert.AreEqual(StateCountBeforeDestroy, Observer.StateCount,
      'Queued state callbacks must not reach the destroyed component');
    Assert.AreEqual(0, Server.PackageRequests);
  finally
    TObservedUpdater.DestroyEntered := nil;
    if Assigned(ReleaseThread) then
    begin
      DestroySignal.SetEvent;
      Server.ReleaseManifest;
      ReleaseThread.WaitFor;
      ReleaseThread.Free;
    end;
    if Assigned(Form) then
      Form.Free
    else
      Updater.Free;
    Observer.Free;
    DestroySignal.Free;
    SetRollbackRegistryTestScope('');
    SetRollbackRegistryTestAccessFailure(False);
    DeleteTestRegistryScope(Scope);
    Server.Free;
    Key.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TVittixAutoUpdaterIntegrationTests);

end.
