unit Test.VittixAutoUpdater;

interface

uses
  System.Classes,
  System.DateUtils,
  System.SyncObjs,
  System.SysUtils,
  VittixAutoUpdater.Types,
  DUnitX.TestFramework;

type
  {$M+}
  [TestFixture]
  TVittixAutoUpdaterTests = class
  private
    FSecurityWarnings: TStringList;
{$IFDEF VITTIX_TEST_LOOPBACK}
    FZipProgressEntered: TEvent;
    FZipProgressContinue: TEvent;
    FZipRacePath: string;
    FZipRaceMovedPath: string;
    FZipRaceTarget: string;
    FZipRaceReplacementMade: Boolean;
    procedure HoldZipProgress(Sender: TObject);
    procedure HoldZipOutput(Sender: TObject);
    procedure ReplaceExtractionParentWithJunction(Sender: TObject);
    procedure CancelAtZipBoundary(Sender: TObject);
    procedure CancelWhenExtracting(Sender: TObject; NewState: TUpdateState;
      const StatusMessage: string);
{$ENDIF}
    function ValidManifestJson(const IssuedAt: string): string;
    procedure HandleSecurityWarning(Sender: TObject; const WarningMessage: string);
{$IFDEF VITTIX_TEST_LOOPBACK}
    function TryExtractZip(const Config: TUpdaterConfig; const ArchivePath,
      DestPath: string; out FinalState: TUpdateState): Boolean;
{$ENDIF}
  published
    [Test] procedure AppVersionComparisonAndParsing;
    [Test] procedure AppVersionRejectsMalformedValues;
    [Test] procedure ManifestParserAcceptsValidDocument;
    [Test] procedure ManifestParserRejectsMissingFields;
    [Test] procedure ManifestParserRejectsMalformedDocuments;
    [Test] procedure UnsignedManifestSkipsIssuedAtAgeRule;
    [Test] procedure ManifestAgeRejectsStaleAndFutureDocuments;
    [Test] procedure ZipPathValidationAcceptsSafeEntry;
    [Test] procedure ZipPathValidationRejectsTraversalAndAbsoluteNames;
    [Test] procedure ZipPathValidationRejectsWindowsSpecialNames;
    [Test] procedure ZipPathValidationRejectsMixedSeparatorTraversal;
    [Test] procedure ArchiveLimitsHaveSecureDefaults;
{$IFDEF VITTIX_TEST_LOOPBACK}
    [Test] procedure ZipExtractionAcceptsSafeAndRejectsTraversalArchives;
    [Test] procedure ZipPreflightRejectsMalformedAndAmbiguousArchives;
    [Test] procedure ZipResourceLimitsEnforceBoundaries;
    [Test] procedure ZipExtractionRejectsReparsePointAncestorBeforeWrites;
    [Test] procedure ZipExtractionCancellationDuringDeflateIsPromptAndScoped;
    [Test] procedure ZipCancellationBeforeBetweenAndBeforeCompletion;
    [Test] procedure ConcurrentZipExtractionsAreIsolated;
    [Test] procedure ConcurrentZipCancellationDoesNotAffectOtherEngine;
    [Test] procedure ZipExtractionRejectsReparseReplacementBeforeWrite;
{$ENDIF}
    [Test] procedure SignatureVerifierAcceptsKnownGoodSignature;
    [Test] procedure SignatureVerifierRejectsTamperedMissingAndWrongKey;
    [Test] procedure SignatureEnvelopeRequiresKnownAlgorithmAndKeyId;
    [Test] procedure TrustedKeySetSupportsExplicitRotation;
    [Test] procedure SecureDefaultsRequireSignedMetadata;
    [Test] procedure VersionDowngradeRequiresOptIn;
    [Test] procedure ManifestRollbackFloorRejectsReplayAndDowngrade;
    [Test] procedure RollbackExecutableRestoresCurrentWhenBackupIsLocked;
    [Test] procedure ApplyUpdateRejectsInvalidState;
    [Test] procedure SecurityWarningsAreReported;
    [Test] procedure RequireSecureConfigBlocksUnsignedChecks;
    [Test] procedure HttpsAndRedirectRulesArePureAndStrict;
    [Test] procedure PublisherThumbprintComparisonIsNormalized;
    [Test] procedure ResumeRequiresMatchingRangeEtagAndSize;
    [Test] procedure RetryBackoffScheduleIsBounded;
    [Test] procedure DiskSpaceAndSizeCapRules;
{$IFDEF VITTIX_AUTH_FIXTURE}
    [Test] procedure AuthenticodeFixtureThumbprintAndPins;
{$ENDIF}
{$IFDEF VITTIX_TEST_LOOPBACK}
    [Test] procedure LoopbackHttpDownloadRetryResumeAndRedirects;
    [Test] procedure SignedManifestFetchRejectsTamperingAndUnknownKeys;
{$ENDIF}
    [Test] procedure BatchCopyIntegrationHandlesWindowsMetacharacters;
    [Test] procedure ApplyScriptDeletesStaleBackupBeforeRename;
    [Test] procedure ApplyScriptBacksUpRestoresAndPreservesFiles;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.NetEncoding,
  System.Hash,
  System.Zip,
  System.StrUtils,
  VittixAutoUpdater.Network,
  VittixAutoUpdater.Engine
{$IFDEF VITTIX_TEST_LOOPBACK}
  , IdHTTPServer, IdCustomHTTPServer, IdContext, IdGlobal, IdSocketHandle
{$ENDIF}
  ;

{$IFDEF VITTIX_TEST_LOOPBACK}
function BuildZipFixture(const ArchivePath: string;
  const EntryNames: TArray<string>; const Payload: TBytes;
  Compression: TZipCompression = zcStored): TBytes; forward;

function CreateTestJunction(const LinkPath, TargetPath: string): Boolean;
var
  Startup: TStartupInfo;
  ProcessInfo: TProcessInformation;
  SystemPath, CommandLine: string;
  ExitCode: DWORD;
begin
  SetLength(SystemPath, MAX_PATH);
  SetLength(SystemPath, GetSystemDirectory(PChar(SystemPath), MAX_PATH));
  CommandLine := Format('"%s\cmd.exe" /d /c mklink /J "%s" "%s" >nul',
    [SystemPath, LinkPath, TargetPath]);
  FillChar(Startup, SizeOf(Startup), 0);
  Startup.cb := SizeOf(Startup);
  FillChar(ProcessInfo, SizeOf(ProcessInfo), 0);
  Result := CreateProcess(nil, PChar(CommandLine), nil, nil, False,
    CREATE_NO_WINDOW, nil, nil, Startup, ProcessInfo);
  if not Result then Exit;
  try
    if WaitForSingleObject(ProcessInfo.hProcess, 15000) <> WAIT_OBJECT_0 then
      Exit(False);
    ExitCode := 1;
    GetExitCodeProcess(ProcessInfo.hProcess, ExitCode);
    Result := ExitCode = 0;
  finally
    CloseHandle(ProcessInfo.hThread);
    CloseHandle(ProcessInfo.hProcess);
  end;
end;

procedure TVittixAutoUpdaterTests.HoldZipProgress(Sender: TObject);
begin
  FZipProgressEntered.SetEvent;
  if FZipProgressContinue.WaitFor(15000) <> wrSignaled then
    raise Exception.Create('Timed out waiting to release the ZIP inflater test gate');
end;

procedure TVittixAutoUpdaterTests.HoldZipOutput(Sender: TObject);
begin
  FZipProgressEntered.SetEvent;
  if FZipProgressContinue.WaitFor(15000) <> wrSignaled then
    raise Exception.Create('Timed out waiting to release the ZIP output test gate');
end;

procedure TVittixAutoUpdaterTests.ReplaceExtractionParentWithJunction(
  Sender: TObject);
begin
  FZipRaceReplacementMade := MoveFile(PChar(FZipRacePath),
    PChar(FZipRaceMovedPath));
  if FZipRaceReplacementMade then
    FZipRaceReplacementMade := CreateTestJunction(FZipRacePath,
      FZipRaceTarget);
end;

procedure TVittixAutoUpdaterTests.CancelAtZipBoundary(Sender: TObject);
begin
  TUpdateEngine(Sender).Cancel;
end;

procedure TVittixAutoUpdaterTests.CancelWhenExtracting(Sender: TObject;
  NewState: TUpdateState; const StatusMessage: string);
begin
  if NewState = usExtracting then
    TUpdateEngine(Sender).Cancel;
end;

function TVittixAutoUpdaterTests.TryExtractZip(const Config: TUpdaterConfig;
  const ArchivePath, DestPath: string; out FinalState: TUpdateState): Boolean;
var
  Engine: TUpdateEngine;
begin
  Engine := TUpdateEngine.Create(Config);
  try
    Result := Engine.ExtractArchiveForTests(ArchivePath, DestPath);
    FinalState := Engine.State;
  finally
    Engine.Free;
  end;
end;

procedure TVittixAutoUpdaterTests.ZipExtractionRejectsReparsePointAncestorBeforeWrites;
var
  TempRoot, ArchivePath, TargetPath, JunctionPath, DestPath, SentinelPath: string;
  Payload: TBytes;
  Config: TUpdaterConfig;
  FinalState: TUpdateState;
begin
  TempRoot := TPath.Combine(TPath.GetTempPath, 'VauZipJunction-' +
    StringReplace(TGUID.NewGuid.ToString, '{', '', [rfReplaceAll]));
  TargetPath := TPath.Combine(TempRoot, 'outside-target');
  JunctionPath := TPath.Combine(TempRoot, 'redirect');
  ArchivePath := TPath.Combine(TempRoot, 'fixture.zip');
  DestPath := TPath.Combine(JunctionPath, 'payload');
  SentinelPath := TPath.Combine(TargetPath, 'sentinel.txt');
  TDirectory.CreateDirectory(TargetPath);
  try
    TFile.WriteAllText(SentinelPath, 'unchanged');
    Payload := TEncoding.ASCII.GetBytes('fixture');
    BuildZipFixture(ArchivePath, TArray<string>.Create('file.txt'), Payload);
    Assert.IsTrue(CreateTestJunction(JunctionPath, TargetPath),
      'Could not create disposable junction fixture');
    Config := TUpdaterConfig.Default;
    Assert.IsFalse(TryExtractZip(Config, ArchivePath, DestPath, FinalState),
      'Extraction must reject a redirected ancestor');
    Assert.AreEqual<TUpdateState>(usFailed, FinalState);
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(TargetPath, 'payload')),
      'No extraction directory may be created through the junction');
    Assert.AreEqual<string>('unchanged', TFile.ReadAllText(SentinelPath),
      'Outside sentinel must remain unchanged');
  finally
    if DirectoryExists(JunctionPath) then
      RemoveDirectory(PChar(JunctionPath));
    if TDirectory.Exists(TempRoot) then
      TDirectory.Delete(TempRoot, True);
  end;
end;

procedure TVittixAutoUpdaterTests.ZipExtractionCancellationDuringDeflateIsPromptAndScoped;
var
  TempRoot, ArchivePath, DestPath, OtherRoot: string;
  OperationStagingPath: string;
  Payload: TBytes;
  Config: TUpdaterConfig;
  Engine: TUpdateEngine;
  Zip: TZipFile;
  Worker: TThread;
  Extracted: Boolean;
  ApplyResult: Boolean;
  I: Integer;

  procedure RunCase(const UseOutputGate: Boolean; const Suffix: string);
  begin
    DestPath := TPath.Combine(TempRoot, Suffix);
    FZipProgressEntered.ResetEvent;
    FZipProgressContinue.ResetEvent;
    if UseOutputGate then
      Engine.OnZipOutputForTests := HoldZipOutput
    else
      Engine.OnZipProgressForTests := HoldZipProgress;
    Extracted := True;
    Worker := TThread.CreateAnonymousThread(
      procedure
      begin
        Extracted := Engine.ExtractArchiveForTests(ArchivePath, DestPath);
      end);
    Worker.FreeOnTerminate := False;
    Worker.Start;
    try
      Assert.AreEqual<TWaitResult>(wrSignaled,
        FZipProgressEntered.WaitFor(15000),
        'Test must synchronize inside the active decompression/output operation');
      Engine.Cancel;
      Engine.Cancel;
    finally
      FZipProgressContinue.SetEvent;
      Worker.WaitFor;
      Worker.Free;
      Engine.OnZipProgressForTests := nil;
      Engine.OnZipOutputForTests := nil;
    end;
    Assert.IsFalse(Extracted, 'Cancellation must abort the extraction');
    Assert.AreEqual<TUpdateState>(usCancelled, Engine.State);
    Assert.IsTrue(TFile.Exists(TPath.Combine(OtherRoot, 'sentinel.txt')),
      'Cancellation must not clean another operation directory');
    if TDirectory.Exists(DestPath) then
      TDirectory.Delete(DestPath, True);
    Engine.Reset;
  end;

begin
  TempRoot := TPath.Combine(TPath.GetTempPath, 'VauZipCancel-' +
    StringReplace(TGUID.NewGuid.ToString, '{', '', [rfReplaceAll]));
  TDirectory.CreateDirectory(TempRoot);
  ArchivePath := TPath.Combine(TempRoot, 'large-deflate.zip');
  OtherRoot := TPath.Combine(TempRoot, 'unrelated-operation');
  TDirectory.CreateDirectory(OtherRoot);
  TFile.WriteAllText(TPath.Combine(OtherRoot, 'sentinel.txt'), 'keep');
  SetLength(Payload, 32 * 1024 * 1024);
  for I := 0 to High(Payload) do
    Payload[I] := Byte((I * 73 + (I shr 8) * 19 + 41) and $FF);
  Zip := TZipFile.Create;
  try
    Zip.Open(ArchivePath, zmWrite);
    Zip.Add(Payload, 'payload.bin', zcDeflate);
    Zip.Close;
  finally
    Zip.Free;
  end;
  Config := TUpdaterConfig.Default;
  Engine := TUpdateEngine.Create(Config);
  FZipProgressEntered := TEvent.Create(nil, True, False, '');
  FZipProgressContinue := TEvent.Create(nil, True, False, '');
  try
    RunCase(False, 'cancel-inflater');
    RunCase(True, 'cancel-output');

    FZipProgressEntered.ResetEvent;
    FZipProgressContinue.ResetEvent;
    Engine.OnZipProgressForTests := HoldZipProgress;
    ApplyResult := True;
    OperationStagingPath := '';
    Worker := TThread.CreateAnonymousThread(
      procedure
      begin
        ApplyResult := Engine.ApplyArchiveForTests(ArchivePath,
          OperationStagingPath);
      end);
    Worker.FreeOnTerminate := False;
    Worker.Start;
    try
      Assert.AreEqual<TWaitResult>(wrSignaled,
        FZipProgressEntered.WaitFor(15000),
        'ApplyUpdate must enter active Deflate processing');
      Engine.Cancel;
    finally
      FZipProgressContinue.SetEvent;
      Worker.WaitFor;
      Worker.Free;
      Engine.OnZipProgressForTests := nil;
    end;
    Assert.IsFalse(ApplyResult,
      'Cancelled extraction must not proceed to installer handoff');
    Assert.AreEqual<TUpdateState>(usCancelled, Engine.State);
    Assert.IsFalse(TDirectory.Exists(OperationStagingPath),
      'ApplyUpdate cancellation must clean only its own staging context');
  finally
    Engine.Free;
    FZipProgressContinue.Free;
    FZipProgressEntered.Free;
    if TDirectory.Exists(TempRoot) then
      TDirectory.Delete(TempRoot, True);
  end;
end;

procedure TVittixAutoUpdaterTests.ZipCancellationBeforeBetweenAndBeforeCompletion;
var
  TempRoot, ArchivePath, DestPath: string;
  Payload: TBytes;
  Config: TUpdaterConfig;
  Engine: TUpdateEngine;
  Zip: TZipFile;
begin
  TempRoot := TPath.Combine(TPath.GetTempPath, 'VauZipCancelEdges-' +
    StringReplace(TGUID.NewGuid.ToString, '{', '', [rfReplaceAll]));
  TDirectory.CreateDirectory(TempRoot);
  ArchivePath := TPath.Combine(TempRoot, 'two-entries.zip');
  Payload := TEncoding.ASCII.GetBytes('entry payload');
  Zip := TZipFile.Create;
  try
    Zip.Open(ArchivePath, zmWrite);
    Zip.Add(Payload, 'first.bin', zcStored);
    Zip.Add(Payload, 'second.bin', zcStored);
    Zip.Close;
  finally
    Zip.Free;
  end;
  Config := TUpdaterConfig.Default;
  Engine := TUpdateEngine.Create(Config);
  try
    DestPath := TPath.Combine(TempRoot, 'cancel-before');
    Engine.OnStateChange := CancelWhenExtracting;
    Assert.IsFalse(Engine.ExtractArchiveForTests(ArchivePath, DestPath));
    Assert.AreEqual<TUpdateState>(usCancelled, Engine.State);
    Assert.IsFalse(TDirectory.Exists(DestPath),
      'Cancellation before extraction must not create the payload root');

    Engine.OnStateChange := nil;
    Engine.Reset;
    DestPath := TPath.Combine(TempRoot, 'cancel-between');
    Engine.OnZipEntryCompleteForTests := CancelAtZipBoundary;
    Assert.IsFalse(Engine.ExtractArchiveForTests(ArchivePath, DestPath));
    Assert.AreEqual<TUpdateState>(usCancelled, Engine.State);
    Assert.IsTrue(TFile.Exists(TPath.Combine(DestPath, 'first.bin')),
      'The first completed entry may exist in the operation staging context');
    Assert.IsFalse(TFile.Exists(TPath.Combine(DestPath, 'second.bin')));
    TDirectory.Delete(DestPath, True);

    Engine.OnZipEntryCompleteForTests := nil;
    Engine.Reset;
    DestPath := TPath.Combine(TempRoot, 'cancel-before-complete');
    Engine.OnZipBeforeCompleteForTests := CancelAtZipBoundary;
    Assert.IsFalse(Engine.ExtractArchiveForTests(ArchivePath, DestPath));
    Assert.AreEqual<TUpdateState>(usCancelled, Engine.State);
    Assert.IsTrue(TFile.Exists(TPath.Combine(DestPath, 'second.bin')),
      'The hook runs after the final entry, but cancellation must prevent success');
    TDirectory.Delete(DestPath, True);
  finally
    Engine.Free;
    if TDirectory.Exists(TempRoot) then
      TDirectory.Delete(TempRoot, True);
  end;
end;

procedure TVittixAutoUpdaterTests.ConcurrentZipExtractionsAreIsolated;
var
  TempRoot, ArchivePath, DestOne, DestTwo: string;
  Payload: TBytes;
  Config: TUpdaterConfig;
  EngineOne, EngineTwo: TUpdateEngine;
  ReadyOne, ReadyTwo, StartGate: TEvent;
  WorkerOne, WorkerTwo: TThread;
  ResultOne, ResultTwo: Boolean;
  I: Integer;
  Zip: TZipFile;
begin
  TempRoot := TPath.Combine(TPath.GetTempPath, 'VauZipParallel-' +
    StringReplace(TGUID.NewGuid.ToString, '{', '', [rfReplaceAll]));
  TDirectory.CreateDirectory(TempRoot);
  ArchivePath := TPath.Combine(TempRoot, 'fixture.zip');
  DestOne := TPath.Combine(TempRoot, 'extract-one');
  DestTwo := TPath.Combine(TempRoot, 'extract-two');
  SetLength(Payload, 4 * 1024 * 1024);
  for I := 0 to High(Payload) do
    Payload[I] := Byte((I * 31 + (I shr 7) * 11 + 7) and $FF);
  Zip := TZipFile.Create;
  try
    Zip.Open(ArchivePath, zmWrite);
    Zip.Add(Payload, 'nested/payload.bin', zcDeflate);
    Zip.Close;
  finally
    Zip.Free;
  end;
  Config := TUpdaterConfig.Default;
  EngineOne := TUpdateEngine.Create(Config);
  EngineTwo := TUpdateEngine.Create(Config);
  ReadyOne := TEvent.Create(nil, True, False, '');
  ReadyTwo := TEvent.Create(nil, True, False, '');
  StartGate := TEvent.Create(nil, True, False, '');
  try
    ResultOne := False;
    ResultTwo := False;
    WorkerOne := TThread.CreateAnonymousThread(
      procedure
      begin
        ReadyOne.SetEvent;
        StartGate.WaitFor(INFINITE);
        ResultOne := EngineOne.ExtractArchiveForTests(ArchivePath, DestOne);
      end);
    WorkerTwo := TThread.CreateAnonymousThread(
      procedure
      begin
        ReadyTwo.SetEvent;
        StartGate.WaitFor(INFINITE);
        ResultTwo := EngineTwo.ExtractArchiveForTests(ArchivePath, DestTwo);
      end);
    WorkerOne.FreeOnTerminate := False;
    WorkerTwo.FreeOnTerminate := False;
    WorkerOne.Start;
    WorkerTwo.Start;
    try
      Assert.AreEqual<TWaitResult>(wrSignaled, ReadyOne.WaitFor(10000));
      Assert.AreEqual<TWaitResult>(wrSignaled, ReadyTwo.WaitFor(10000));
      StartGate.SetEvent;
      WorkerOne.WaitFor;
      WorkerTwo.WaitFor;
    finally
      StartGate.SetEvent;
      WorkerOne.WaitFor;
      WorkerTwo.WaitFor;
      WorkerOne.Free;
      WorkerTwo.Free;
    end;
    Assert.IsTrue(ResultOne, 'First independent extraction must complete');
    Assert.IsTrue(ResultTwo, 'Second independent extraction must complete');
    Assert.IsTrue(TFile.Exists(TPath.Combine(DestOne, 'nested\payload.bin')));
    Assert.IsTrue(TFile.Exists(TPath.Combine(DestTwo, 'nested\payload.bin')));
    Assert.AreEqual<Int64>(Length(Payload), TFile.GetSize(TPath.Combine(DestOne,
      'nested\payload.bin')));
    Assert.AreEqual<Int64>(Length(Payload), TFile.GetSize(TPath.Combine(DestTwo,
      'nested\payload.bin')));
  finally
    EngineOne.Free;
    EngineTwo.Free;
    StartGate.Free;
    ReadyTwo.Free;
    ReadyOne.Free;
    if TDirectory.Exists(TempRoot) then
      TDirectory.Delete(TempRoot, True);
  end;
end;

procedure TVittixAutoUpdaterTests.ZipExtractionRejectsReparseReplacementBeforeWrite;
var
  TempRoot, ArchivePath, DestPath, OutsidePath, SentinelPath: string;
  Payload: TBytes;
  Config: TUpdaterConfig;
  Engine: TUpdateEngine;
  Zip: TZipFile;
begin
  TempRoot := TPath.Combine(TPath.GetTempPath, 'VauZipRace-' +
    StringReplace(TGUID.NewGuid.ToString, '{', '', [rfReplaceAll]));
  TDirectory.CreateDirectory(TempRoot);
  ArchivePath := TPath.Combine(TempRoot, 'fixture.zip');
  DestPath := TPath.Combine(TempRoot, 'payload');
  OutsidePath := TPath.Combine(TempRoot, 'outside');
  SentinelPath := TPath.Combine(OutsidePath, 'sentinel.txt');
  FZipRacePath := TPath.Combine(DestPath, 'nested');
  FZipRaceMovedPath := TPath.Combine(DestPath, 'nested-original');
  FZipRaceTarget := OutsidePath;
  FZipRaceReplacementMade := False;
  TDirectory.CreateDirectory(OutsidePath);
  TFile.WriteAllText(SentinelPath, 'unchanged');
  Payload := TEncoding.ASCII.GetBytes('race fixture');
  Zip := TZipFile.Create;
  try
    Zip.Open(ArchivePath, zmWrite);
    Zip.Add(Payload, 'nested/payload.txt', zcStored);
    Zip.Close;
  finally
    Zip.Free;
  end;
  Config := TUpdaterConfig.Default;
  Engine := TUpdateEngine.Create(Config);
  try
    Engine.OnZipBeforeCreateForTests := ReplaceExtractionParentWithJunction;
    Assert.IsFalse(Engine.ExtractArchiveForTests(ArchivePath, DestPath),
      'The replacement must be detected before the destination file is opened');
    Assert.IsTrue(FZipRaceReplacementMade,
      'The deterministic fixture must replace the checked parent directory');
    Assert.AreEqual<string>('unchanged', TFile.ReadAllText(SentinelPath));
    Assert.IsFalse(TFile.Exists(TPath.Combine(OutsidePath, 'payload.txt')),
      'No archive output may be redirected outside the payload root');
  finally
    Engine.Free;
    if DirectoryExists(FZipRacePath) then
      RemoveDirectory(PChar(FZipRacePath));
    if TDirectory.Exists(TempRoot) then
      TDirectory.Delete(TempRoot, True);
  end;
end;

procedure TVittixAutoUpdaterTests.ConcurrentZipCancellationDoesNotAffectOtherEngine;
var
  TempRoot, ArchivePath, BadArchivePath, DestOne, DestTwo, FailedDest: string;
  Payload: TBytes;
  Config: TUpdaterConfig;
  EngineOne, EngineTwo, FailureEngine: TUpdateEngine;
  ReadyOne, ReadyTwo, StartGate: TEvent;
  WorkerOne, WorkerTwo: TThread;
  ResultOne, ResultTwo: Boolean;
  I: Integer;
  Zip: TZipFile;
begin
  TempRoot := TPath.Combine(TPath.GetTempPath, 'VauZipCancelParallel-' +
    StringReplace(TGUID.NewGuid.ToString, '{', '', [rfReplaceAll]));
  TDirectory.CreateDirectory(TempRoot);
  ArchivePath := TPath.Combine(TempRoot, 'fixture.zip');
  BadArchivePath := TPath.Combine(TempRoot, 'invalid.zip');
  DestOne := TPath.Combine(TempRoot, 'cancelled');
  DestTwo := TPath.Combine(TempRoot, 'survivor');
  FailedDest := TPath.Combine(TempRoot, 'failed');
  SetLength(Payload, 16 * 1024 * 1024);
  for I := 0 to High(Payload) do
    Payload[I] := Byte((I * 89 + (I shr 6) * 23 + 13) and $FF);
  Zip := TZipFile.Create;
  try
    Zip.Open(ArchivePath, zmWrite);
    Zip.Add(Payload, 'payload.bin', zcDeflate);
    Zip.Close;
  finally
    Zip.Free;
  end;
  Config := TUpdaterConfig.Default;
  EngineOne := TUpdateEngine.Create(Config);
  EngineTwo := TUpdateEngine.Create(Config);
  FailureEngine := TUpdateEngine.Create(Config);
  TFile.WriteAllBytes(BadArchivePath, TBytes.Create(1, 2, 3, 4, 5));
  ReadyOne := TEvent.Create(nil, True, False, '');
  ReadyTwo := TEvent.Create(nil, True, False, '');
  StartGate := TEvent.Create(nil, True, False, '');
  FZipProgressEntered := TEvent.Create(nil, True, False, '');
  FZipProgressContinue := TEvent.Create(nil, True, False, '');
  try
    EngineOne.OnZipProgressForTests := HoldZipProgress;
    ResultOne := True;
    ResultTwo := False;
    WorkerOne := TThread.CreateAnonymousThread(
      procedure
      begin
        ReadyOne.SetEvent;
        StartGate.WaitFor(INFINITE);
        ResultOne := EngineOne.ExtractArchiveForTests(ArchivePath, DestOne);
      end);
    WorkerTwo := TThread.CreateAnonymousThread(
      procedure
      begin
        ReadyTwo.SetEvent;
        StartGate.WaitFor(INFINITE);
        ResultTwo := EngineTwo.ExtractArchiveForTests(ArchivePath, DestTwo);
      end);
    WorkerOne.FreeOnTerminate := False;
    WorkerTwo.FreeOnTerminate := False;
    WorkerOne.Start;
    WorkerTwo.Start;
    try
      Assert.AreEqual<TWaitResult>(wrSignaled, ReadyOne.WaitFor(10000));
      Assert.AreEqual<TWaitResult>(wrSignaled, ReadyTwo.WaitFor(10000));
      StartGate.SetEvent;
      Assert.AreEqual<TWaitResult>(wrSignaled,
        FZipProgressEntered.WaitFor(15000),
        'Cancelled operation must reach active Deflate processing');
      Assert.IsFalse(FailureEngine.ExtractArchiveForTests(BadArchivePath,
        FailedDest), 'Malformed concurrent operation must fail independently');
      EngineOne.Cancel;
      FZipProgressContinue.SetEvent;
      WorkerOne.WaitFor;
      WorkerTwo.WaitFor;
    finally
      StartGate.SetEvent;
      FZipProgressContinue.SetEvent;
      WorkerOne.WaitFor;
      WorkerTwo.WaitFor;
      WorkerOne.Free;
      WorkerTwo.Free;
      EngineOne.OnZipProgressForTests := nil;
    end;
    Assert.IsFalse(ResultOne, 'The requested operation must cancel');
    Assert.IsTrue(ResultTwo, 'The other engine must finish independently');
    Assert.AreEqual<TUpdateState>(usCancelled, EngineOne.State);
    Assert.AreEqual<TUpdateState>(usFailed, FailureEngine.State);
    Assert.IsTrue(TFile.Exists(TPath.Combine(DestTwo, 'payload.bin')));
  finally
    FailureEngine.Free;
    EngineOne.Free;
    EngineTwo.Free;
    FZipProgressContinue.Free;
    FZipProgressEntered.Free;
    StartGate.Free;
    ReadyTwo.Free;
    ReadyOne.Free;
    if TDirectory.Exists(TempRoot) then
      TDirectory.Delete(TempRoot, True);
  end;
end;
{$ENDIF}

const
  FixturePublicKey =
    '6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296'
    + '4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5';
  FixtureSignature =
    'TbWuUPkzsKqTokpibqo5O4CgTWoPZ4x6fvOFWdaOQC7zeVcVgEURXUwc1xJ4jofl/hLU0ITRc1MLPowxnPURxg==';
  FixtureKeyId =
    'd875db7def232236aec738c6b0bb3e80142f5d0fd8f4df24fed6eef5cbb50d9f';
  FixtureManifest = '{"demo":"signed fixture"}';

{$IFDEF VITTIX_TEST_LOOPBACK}
function BuildZipFixture(const ArchivePath: string;
  const EntryNames: TArray<string>; const Payload: TBytes;
  Compression: TZipCompression): TBytes;
var
  ZipFile: TZipFile;
  I: Integer;
begin
  ZipFile := TZipFile.Create;
  try
    ZipFile.Open(ArchivePath, zmWrite);
    for I := 0 to High(EntryNames) do
      ZipFile.Add(Payload, EntryNames[I], Compression);
    ZipFile.Close;
  finally
    ZipFile.Free;
  end;
  Result := TFile.ReadAllBytes(ArchivePath);
end;

function FindZipSignature(const Bytes: TBytes; Signature: UInt32;
  StartAt: Integer = 0): Integer;
var
  I: Integer;
  Value: UInt32;
begin
  Result := -1;
  if StartAt < 0 then
    StartAt := 0;
  for I := StartAt to Length(Bytes) - 4 do
  begin
    Move(Bytes[I], Value, SizeOf(Value));
    if Value = Signature then
      Exit(I);
  end;
end;

function ReadZipUInt16(const Bytes: TBytes; Offset: Integer): UInt32;
begin
  Result := UInt32(Bytes[Offset]) or (UInt32(Bytes[Offset + 1]) shl 8);
end;

function ReadZipUInt32(const Bytes: TBytes; Offset: Integer): UInt32;
begin
  Result := UInt32(Bytes[Offset]) or (UInt32(Bytes[Offset + 1]) shl 8) or
    (UInt32(Bytes[Offset + 2]) shl 16) or (UInt32(Bytes[Offset + 3]) shl 24);
end;

procedure WriteZipUInt16(var Bytes: TBytes; Offset: Integer; Value: UInt32);
begin
  Bytes[Offset] := Byte(Value);
  Bytes[Offset + 1] := Byte(Value shr 8);
end;

procedure WriteZipUInt32(var Bytes: TBytes; Offset: Integer; Value: UInt32);
begin
  Bytes[Offset] := Byte(Value);
  Bytes[Offset + 1] := Byte(Value shr 8);
  Bytes[Offset + 2] := Byte(Value shr 16);
  Bytes[Offset + 3] := Byte(Value shr 24);
end;

type
  TLoopbackUpdateServer = class
  private
    FServer: TIdHTTPServer;
    FBody: string;
    FManifestBody: string;
    FSignatureBody: string;
    FDropCount: Integer;
    FResumeDropCount: Integer;
    FResumeCount: Integer;
    FMismatchDropCount: Integer;
    FMismatchRangeCount: Integer;
    FFullAfterMismatchCount: Integer;
    procedure HandleRequest(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure SendDrop(AContext: TIdContext; AResponseInfo: TIdHTTPResponseInfo);
    function GetPort: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function Url(const Path: string): string;
    property Body: string read FBody;
    property ManifestBody: string read FManifestBody write FManifestBody;
    property SignatureBody: string read FSignatureBody write FSignatureBody;
    property Port: Integer read GetPort;
    property DropCount: Integer read FDropCount;
    property ResumeCount: Integer read FResumeCount;
    property MismatchRangeCount: Integer read FMismatchRangeCount;
    property FullAfterMismatchCount: Integer read FFullAfterMismatchCount;
  end;
{$ENDIF}

{$IFDEF VITTIX_TEST_LOOPBACK}
constructor TLoopbackUpdateServer.Create;
var
  Binding: TIdSocketHandle;
begin
  inherited Create;
  FBody := StringOfChar('U', 4096);
  FManifestBody := '{"Demo":{"version":"1.0.0.1","download_url":"https://updates.example.test/pkg.zip",' +
    '"file_size":3,"checksum":"sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",' +
    '"issued_at":"2020-01-01T00:00:00Z","severity":"optional"}}';
  FSignatureBody := 'VAU-ECDSA-P256-SHA256-v1:' +
    'd875db7def232236aec738c6b0bb3e80142f5d0fd8f4df24fed6eef5cbb50d9f:' +
    'qwRvegCJAFGJUqsEFri6ahdEvfUmA2behjhcsSz9NbFcpI9BBHb8/se8wGnhk9OyFZ0llrqOWgiu1L9ll+hUJA==' + #10;
  FServer := TIdHTTPServer.Create(nil);
  FServer.Bindings.Clear;
  Binding := FServer.Bindings.Add;
  Binding.IP := '127.0.0.1';
  Binding.Port := 0;
  FServer.DefaultPort := 0;
  FServer.OnCommandGet := HandleRequest;
  FServer.Active := True;
end;

destructor TLoopbackUpdateServer.Destroy;
begin
  FServer.Active := False;
  FServer.Free;
  inherited Destroy;
end;

function TLoopbackUpdateServer.Url(const Path: string): string;
begin
  Result := Format('http://127.0.0.1:%d%s',
    [FServer.Bindings[0].Port, Path]);
end;

function TLoopbackUpdateServer.GetPort: Integer;
begin
  Result := FServer.Bindings[0].Port;
end;

procedure TLoopbackUpdateServer.SendDrop(AContext: TIdContext;
  AResponseInfo: TIdHTTPResponseInfo);
begin
  AResponseInfo.ResponseNo := 200;
  AResponseInfo.ContentLength := Length(FBody);
  AResponseInfo.CloseConnection := True;
  AResponseInfo.WriteHeader;
  AContext.Connection.IOHandler.Write(
    Copy(FBody, 1, Length(FBody) div 2), IndyTextEncoding_ASCII);
  AContext.Connection.Disconnect;
end;

procedure TLoopbackUpdateServer.HandleRequest(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Document, RangeValue, ETag: string;
  RangeStart, DashPos, Hop, ChainLength: Integer;
  IsResumeRoute, IsMismatchRoute, IsHead: Boolean;
  RouteBody: string;

  procedure SendBody(const ABody, AETag: string; StatusCode: Integer = 200;
    const ContentRange: string = '');
  begin
    AResponseInfo.ResponseNo := StatusCode;
    AResponseInfo.ContentType := 'application/octet-stream';
    AResponseInfo.ContentLength := Length(ABody);
    if AETag <> '' then
      AResponseInfo.CustomHeaders.Values['ETag'] := AETag;
    if ContentRange <> '' then
      AResponseInfo.CustomHeaders.Values['Content-Range'] := ContentRange;
    if not IsHead then
      AResponseInfo.ContentText := ABody;
  end;

  procedure SendRange(const ATag: string; WrongETag: Boolean);
  begin
    RangeValue := ARequestInfo.RawHeaders.Values['Range'];
    DashPos := Pos('-', RangeValue);
    RangeStart := StrToIntDef(Copy(RangeValue,
      Pos('=', RangeValue) + 1, DashPos - Pos('=', RangeValue) - 1), -1);
    if (RangeStart < 0) or (RangeStart >= Length(FBody)) then
    begin
      AResponseInfo.ResponseNo := 416;
      Exit;
    end;
    if IsMismatchRoute then
      TInterlocked.Increment(FMismatchRangeCount)
    else
      TInterlocked.Increment(FResumeCount);
    if WrongETag then
      ETag := '"different"'
    else
      ETag := ATag;
    RouteBody := Copy(FBody, RangeStart + 1, MaxInt);
    SendBody(RouteBody, ETag, 206,
      Format('bytes %d-%d/%d', [RangeStart, Length(FBody) - 1, Length(FBody)]));
  end;

begin
  Document := ARequestInfo.Document;
  IsHead := ARequestInfo.CommandType = hcHEAD;
  IsResumeRoute := SameText(Document, '/resume');
  IsMismatchRoute := SameText(Document, '/mismatch');
  RouteBody := FBody;

  if StartsText('/chain', Document) then
  begin
    Hop := StrToIntDef(Copy(Document, LastDelimiter('/', Document) + 1, MaxInt), 0);
    if Pos('/chain5/', Document) = 1 then
      ChainLength := 5
    else
      ChainLength := 6;
    if Hop < ChainLength then
    begin
      AResponseInfo.ResponseNo := 302;
      AResponseInfo.CustomHeaders.Values['Location'] :=
        Format('/chain%d/%d', [ChainLength, Hop + 1]);
    end
    else
      SendBody(FBody, '"chain-v1"');
    Exit;
  end;

  if SameText(Document, '/downgrade') then
  begin
    AResponseInfo.ResponseNo := 302;
    AResponseInfo.CustomHeaders.Values['Location'] :=
      'http://localhost:' + IntToStr(FServer.Bindings[0].Port) + '/success';
    Exit;
  end;

  if SameText(Document, '/signed-manifest') then
  begin
    SendBody(FManifestBody, '');
    Exit;
  end;

  if SameText(Document, '/signed-manifest.sig') then
  begin
    SendBody(FSignatureBody, '');
    Exit;
  end;

  if SameText(Document, '/overrun') then
    RouteBody := StringOfChar('O', 70000);

  if IsHead then
  begin
    AResponseInfo.ResponseNo := 200;
    AResponseInfo.ContentLength := Length(RouteBody);
    if IsResumeRoute or IsMismatchRoute then
    begin
      AResponseInfo.CustomHeaders.Values['Accept-Ranges'] := 'bytes';
      AResponseInfo.CustomHeaders.Values['ETag'] := '"stable-v1"';
    end;
    Exit;
  end;

  RangeValue := ARequestInfo.RawHeaders.Values['Range'];
  if RangeValue <> '' then
  begin
    SendRange('"stable-v1"', IsMismatchRoute);
    Exit;
  end;

  if SameText(Document, '/retry') then
  begin
    if TInterlocked.Increment(FDropCount) = 1 then
      SendDrop(AContext, AResponseInfo)
    else
      SendBody(FBody, '');
    Exit;
  end;

  if IsResumeRoute then
  begin
    if TInterlocked.Increment(FResumeDropCount) = 1 then
      SendDrop(AContext, AResponseInfo)
    else
      SendBody(FBody, '"stable-v1"');
    Exit;
  end;

  if IsMismatchRoute then
  begin
    if TInterlocked.Increment(FMismatchDropCount) = 1 then
      SendDrop(AContext, AResponseInfo)
    else
    begin
      TInterlocked.Increment(FFullAfterMismatchCount);
      SendBody(FBody, '"stable-v1"');
    end;
    Exit;
  end;

  SendBody(RouteBody, '');
end;
{$ENDIF}

function TVittixAutoUpdaterTests.ValidManifestJson(const IssuedAt: string): string;
begin
  Result := Format(
    '{"Demo":{"version":"2.0.0.0","download_url":"https://example.invalid/app.zip",' +
    '"issued_at":"%s","file_size":123,"checksum":"sha256:abc"}}',
    [IssuedAt]);
end;

procedure TVittixAutoUpdaterTests.HandleSecurityWarning(Sender: TObject;
  const WarningMessage: string);
begin
  FSecurityWarnings.Add(WarningMessage);
end;

procedure TVittixAutoUpdaterTests.AppVersionComparisonAndParsing;
var
  LowerVersion, HigherVersion: TAppVersion;
begin
  Assert.IsTrue(TAppVersion.TryParse('1.2.3.4', LowerVersion));
  Assert.IsTrue(TAppVersion.TryParse('1.2.4.0', HigherVersion));
  Assert.IsTrue(HigherVersion > LowerVersion);
  Assert.IsTrue(LowerVersion < HigherVersion);
  Assert.IsTrue(LowerVersion <> HigherVersion);
  Assert.AreEqual('1.2.3.4', LowerVersion.ToString);
end;

procedure TVittixAutoUpdaterTests.AppVersionRejectsMalformedValues;
var
  Version: TAppVersion;
begin
  Assert.IsFalse(TAppVersion.TryParse('', Version));
  Assert.IsFalse(TAppVersion.TryParse('x.y.z', Version));
  Assert.IsFalse(TAppVersion.TryParse('-1.0.0.0', Version));
  Assert.IsFalse(TAppVersion.TryParse('1.2.3.65536', Version));
  Assert.IsFalse(TAppVersion.TryParse('1.2.3.4.5', Version));
  Assert.IsFalse(TAppVersion.TryParse('1.2.', Version));
  Assert.IsTrue(TAppVersion.TryParse('65535.0.0.0', Version));
  Assert.WillRaise(
    procedure begin TAppVersion.Create('not-a-version'); end,
    EVersionException);
end;

procedure TVittixAutoUpdaterTests.ManifestParserAcceptsValidDocument;
var
  Manifest: TUpdateManifest;
  ErrorMessage: string;
begin
  Assert.IsTrue(TryParseManifestJson(
    ValidManifestJson('2026-10-20T12:00:00Z'), 'Demo', 30,
    EncodeDateTime(2026, 10, 20, 12, 0, 1, 0), True,
    Manifest, ErrorMessage),
    ErrorMessage);
  Assert.AreEqual('2.0.0.0', Manifest.Version.ToString);
  Assert.AreEqual<Int64>(123, Manifest.FileSize);
end;

procedure TVittixAutoUpdaterTests.ManifestParserRejectsMissingFields;
var
  Manifest: TUpdateManifest;
  ErrorMessage: string;
  JsonText: string;
begin
  JsonText := '{"Demo":{"version":"1.0.0.0","issued_at":"2026-10-20T12:00:00Z"}}';
  Assert.IsFalse(TryParseManifestJson(JsonText, 'Demo', 30,
    EncodeDateTime(2026, 10, 20, 12, 1, 0, 0), True,
    Manifest, ErrorMessage));
  Assert.IsTrue(Pos('download_url', ErrorMessage) > 0);
end;

procedure TVittixAutoUpdaterTests.ManifestParserRejectsMalformedDocuments;
var
  Manifest: TUpdateManifest;
  ErrorMessage: string;
begin
  Assert.IsFalse(TryParseManifestJson('{broken', 'Demo', 30, Now,
    True, Manifest, ErrorMessage));
  Assert.IsFalse(TryParseManifestJson(
    '{"Demo":{"version":"bad","download_url":"https://x",' +
    '"issued_at":"2026-10-20T12:00:00Z"}}', 'Demo', 30,
    EncodeDateTime(2026, 10, 20, 12, 0, 1, 0), True,
    Manifest, ErrorMessage));
end;

procedure TVittixAutoUpdaterTests.UnsignedManifestSkipsIssuedAtAgeRule;
var
  Manifest: TUpdateManifest;
  ErrorMessage: string;
  CurrentUtc: TDateTime;
begin
  CurrentUtc := EncodeDateTime(2026, 10, 20, 12, 0, 0, 0);
  Assert.IsTrue(TryParseManifestJson(
    '{"Demo":{"version":"1.0.0.0","download_url":"https://x"}}',
    'Demo', 30, CurrentUtc, False, Manifest, ErrorMessage), ErrorMessage);
  Assert.IsTrue(TryParseManifestJson(
    ValidManifestJson('2020-01-01T00:00:00Z'), 'Demo', 30,
    CurrentUtc, False, Manifest, ErrorMessage), ErrorMessage);
  Assert.IsFalse(TryParseManifestJson(
    ValidManifestJson('2020-01-01T00:00:00Z'), 'Demo', 30,
    CurrentUtc, True, Manifest, ErrorMessage));
end;

procedure TVittixAutoUpdaterTests.ManifestAgeRejectsStaleAndFutureDocuments;
var
  NowUtc: TDateTime;
begin
  NowUtc := EncodeDateTime(2026, 10, 20, 12, 0, 0, 0);
  Assert.IsTrue(IsManifestWithinAge(NowUtc - 7, NowUtc, 7));
  Assert.IsFalse(IsManifestWithinAge(NowUtc - 7.01, NowUtc, 7));
  Assert.IsFalse(IsManifestWithinAge(NowUtc + 1, NowUtc, 30));
end;

procedure TVittixAutoUpdaterTests.ZipPathValidationAcceptsSafeEntry;
var
  FullPath: string;
begin
  Assert.IsTrue(IsSafeZipEntryPath('C:\Temp\Updater', 'nested\image.dll', FullPath));
  Assert.IsTrue(StartsText('C:\Temp\Updater\', FullPath));
end;

procedure TVittixAutoUpdaterTests.ZipPathValidationRejectsTraversalAndAbsoluteNames;
var
  FullPath: string;
begin
  Assert.IsFalse(IsSafeZipEntryPath('C:\Temp\Updater', '..\outside.dll', FullPath));
  Assert.IsFalse(IsSafeZipEntryPath('C:\Temp\Updater', 'C:\outside.dll', FullPath));
  Assert.IsFalse(IsSafeZipEntryPath('C:\Temp\Updater', 'nested:stream', FullPath));
  Assert.IsFalse(IsSafeZipEntryPath('C:\Temp\Updater', '\\server\share\x', FullPath));
end;

procedure TVittixAutoUpdaterTests.ZipPathValidationRejectsWindowsSpecialNames;
var
  FullPath: string;
  Name: string;
begin
  for Name in ['C:payload.exe', 'file.txt:stream', '\\server\share\x',
    '\\.\device', '\\?\C:\payload', 'NUL.txt', 'COM1.dll',
    'folder\name. ', 'folder\name.', 'folder\bad?.txt'] do
    Assert.IsFalse(IsSafeZipEntryPath('C:\Temp\Updater', Name, FullPath), Name);
end;

procedure TVittixAutoUpdaterTests.ZipPathValidationRejectsMixedSeparatorTraversal;
var
  FullPath: string;
begin
  Assert.IsFalse(IsSafeZipEntryPath('C:\Temp\Updater', 'safe/..\outside.dll', FullPath));
  Assert.IsFalse(IsSafeZipEntryPath('C:\Temp\Updater', 'safe\../outside.dll', FullPath));
end;

procedure TVittixAutoUpdaterTests.ArchiveLimitsHaveSecureDefaults;
var
  Config: TUpdaterConfig;
begin
  Config := TUpdaterConfig.Default;
  Assert.IsTrue(Config.MaxArchiveBytes > 0);
  Assert.IsTrue(Config.MaxArchiveEntryCount > 0);
  Assert.IsTrue(Config.MaxArchiveTotalUncompressedBytes > 0);
  Assert.IsTrue(Config.MaxArchiveSingleEntryBytes > 0);
  Assert.IsTrue(Config.MaxArchivePathDepth > 0);
  Assert.IsTrue(Config.MaxArchivePathLength > 0);
  Assert.IsTrue(Config.MaxArchiveExpansionRatio > 0);
end;

{$IFDEF VITTIX_TEST_LOOPBACK}
procedure TVittixAutoUpdaterTests.ZipExtractionAcceptsSafeAndRejectsTraversalArchives;
var
  Config: TUpdaterConfig;
  Engine: TUpdateEngine;
  Zip: TZipFile;
  TempRoot, ArchivePath, DestPath, OutsidePath: string;
  Data: TBytes;
begin
  TempRoot := TPath.Combine(TPath.GetTempPath, 'VauZipTest-' +
    StringReplace(TGUID.NewGuid.ToString, '{', '', [rfReplaceAll]));
  TDirectory.CreateDirectory(TempRoot);
  ArchivePath := TPath.Combine(TempRoot, 'fixture.zip');
  DestPath := TPath.Combine(TempRoot, 'extract');
  OutsidePath := TPath.Combine(TempRoot, 'escaped.txt');
  Data := TEncoding.UTF8.GetBytes('safe fixture');
  Zip := TZipFile.Create;
  try
    Zip.Open(ArchivePath, zmWrite);
    Zip.Add(Data, 'nested/file.txt', zcStored);
    Zip.Close;
  finally
    Zip.Free;
  end;
  Config := TUpdaterConfig.Default;
  Engine := TUpdateEngine.Create(Config);
  try
    Assert.IsTrue(Engine.ExtractArchiveForTests(ArchivePath, DestPath));
    Assert.IsTrue(TFile.Exists(TPath.Combine(DestPath, 'nested/file.txt')));
  finally
    Engine.Free;
  end;

  Config.MaxArchiveSingleEntryBytes := 2;
  Engine := TUpdateEngine.Create(Config);
  try
    Assert.IsFalse(Engine.ExtractArchiveForTests(ArchivePath,
      TPath.Combine(TempRoot, 'extract-oversized')));
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(TempRoot, 'extract-oversized')),
      'Metadata rejection must occur before destination creation');
  finally
    Engine.Free;
  end;
  Config := TUpdaterConfig.Default;

  ArchivePath := TPath.Combine(TempRoot, 'duplicate.zip');
  Zip := TZipFile.Create;
  try
    Zip.Open(ArchivePath, zmWrite);
    Zip.Add(Data, 'Payload.dll', zcStored);
    Zip.Add(Data, 'payload.DLL', zcStored);
    Zip.Close;
  finally
    Zip.Free;
  end;
  Engine := TUpdateEngine.Create(Config);
  try
    Assert.IsFalse(Engine.ExtractArchiveForTests(ArchivePath,
      TPath.Combine(TempRoot, 'extract-duplicate')));
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(TempRoot, 'extract-duplicate')),
      'Duplicate destinations must be rejected before extraction');
  finally
    Engine.Free;
  end;

  ArchivePath := TPath.Combine(TempRoot, 'traversal.zip');
  Zip := TZipFile.Create;
  try
    Zip.Open(ArchivePath, zmWrite);
    Zip.Add(Data, '..\escaped.txt', zcStored);
    Zip.Close;
  finally
    Zip.Free;
  end;
  Engine := TUpdateEngine.Create(Config);
  try
    Assert.IsFalse(Engine.ExtractArchiveForTests(ArchivePath,
      TPath.Combine(TempRoot, 'extract-bad')));
    Assert.IsFalse(TFile.Exists(OutsidePath));
  finally
    Engine.Free;
  end;
  TDirectory.Delete(TempRoot, True);
end;

procedure TVittixAutoUpdaterTests.ZipPreflightRejectsMalformedAndAmbiguousArchives;
var
  TempRoot, ArchivePath, DestPath: string;
  Payload, Bytes: TBytes;
  Config: TUpdaterConfig;
  FinalState: TUpdateState;
  EOCD, Central, Central2, Local, NameLen, ExtraLen, CommentLen: Integer;
  OriginalSize: Integer;
  EntryNames: TArray<string>;

  procedure Reject(const CaseName: string; const Fixture: TBytes);
  begin
    TFile.WriteAllBytes(ArchivePath, Fixture);
    DestPath := TPath.Combine(TempRoot, 'dest-' + CaseName);
    Assert.IsFalse(TryExtractZip(Config, ArchivePath, DestPath, FinalState), CaseName);
    Assert.AreEqual<TUpdateState>(usFailed, FinalState, CaseName);
  end;

begin
  TempRoot := TPath.Combine(TPath.GetTempPath, 'VauMalformedZip-' +
    StringReplace(TGUID.NewGuid.ToString, '{', '', [rfReplaceAll]));
  TDirectory.CreateDirectory(TempRoot);
  ArchivePath := TPath.Combine(TempRoot, 'fixture.zip');
  Payload := TEncoding.ASCII.GetBytes('hostile-fixture-data');
  Config := TUpdaterConfig.Default;
  try
    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('entry.bin'), Payload);
    EOCD := FindZipSignature(Bytes, $06054B50);
    Assert.IsTrue(EOCD >= 0);
    SetLength(Bytes, Length(Bytes) - 7);
    Reject('truncated-eocd', Bytes);

    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('entry.bin'), Payload);
    EOCD := FindZipSignature(Bytes, $06054B50);
    WriteZipUInt32(Bytes, EOCD + 16, $FFFFFFFF);
    Reject('bad-central-offset', Bytes);

    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('entry.bin'), Payload);
    Central := FindZipSignature(Bytes, $02014B50);
    Local := FindZipSignature(Bytes, $04034B50);
    Assert.IsTrue((Central >= 0) and (Local >= 0));
    WriteZipUInt32(Bytes, Central + 16, ReadZipUInt32(Bytes, Central + 16) xor 1);
    WriteZipUInt32(Bytes, Local + 14, ReadZipUInt32(Bytes, Local + 14) xor 1);
    Reject('incorrect-crc', Bytes);

    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('entry.bin'), Payload);
    Central := FindZipSignature(Bytes, $02014B50);
    Local := FindZipSignature(Bytes, $04034B50);
    WriteZipUInt32(Bytes, Central + 24, UInt32(Length(Payload) - 1));
    WriteZipUInt32(Bytes, Local + 22, UInt32(Length(Payload) - 1));
    Reject('inconsistent-expanded-size', Bytes);

    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('entry.bin'), Payload);
    Central := FindZipSignature(Bytes, $02014B50);
    Local := FindZipSignature(Bytes, $04034B50);
    WriteZipUInt32(Bytes, Central + 20, UInt32(Length(Payload) - 1));
    WriteZipUInt32(Bytes, Local + 18, UInt32(Length(Payload) - 1));
    Reject('inconsistent-compressed-size', Bytes);

    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('entry.bin'), Payload, zcDeflate);
    Central := FindZipSignature(Bytes, $02014B50);
    Local := FindZipSignature(Bytes, $04034B50);
    WriteZipUInt32(Bytes, Central + 20, ReadZipUInt32(Bytes, Central + 20) - 1);
    WriteZipUInt32(Bytes, Local + 18, ReadZipUInt32(Bytes, Local + 18) - 1);
    Reject('truncated-deflate-stream', Bytes);

    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('entry.bin'), Payload);
    Central := FindZipSignature(Bytes, $02014B50);
    Local := FindZipSignature(Bytes, $04034B50);
    WriteZipUInt16(Bytes, Central + 10, 99);
    WriteZipUInt16(Bytes, Local + 8, 99);
    Reject('unsupported-compression', Bytes);

    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('entry.bin'), Payload);
    Central := FindZipSignature(Bytes, $02014B50);
    Local := FindZipSignature(Bytes, $04034B50);
    WriteZipUInt16(Bytes, Central + 8, ReadZipUInt16(Bytes, Central + 8) or 1);
    WriteZipUInt16(Bytes, Local + 6, ReadZipUInt16(Bytes, Local + 6) or 1);
    Reject('encrypted-entry', Bytes);

    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('entry.bin'), Payload);
    Central := FindZipSignature(Bytes, $02014B50);
    Local := FindZipSignature(Bytes, $04034B50);
    Bytes[Local + 30] := Ord('x');
    Reject('local-central-name-mismatch', Bytes);

    EntryNames := TArray<string>.Create('same.bin', 'same.bin');
    Bytes := BuildZipFixture(ArchivePath, EntryNames, Payload);
    Central := FindZipSignature(Bytes, $02014B50);
    NameLen := ReadZipUInt16(Bytes, Central + 28);
    ExtraLen := ReadZipUInt16(Bytes, Central + 30);
    CommentLen := ReadZipUInt16(Bytes, Central + 32);
    Central2 := Central + 46 + NameLen + ExtraLen + CommentLen;
    WriteZipUInt32(Bytes, Central2 + 42, ReadZipUInt32(Bytes, Central + 42));
    Reject('overlapping-local-records', Bytes);

    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('entry.bin'), Payload);
    EOCD := FindZipSignature(Bytes, $06054B50);
    WriteZipUInt16(Bytes, EOCD + 10, $FFFF);
    Reject('malformed-zip64-sentinel', Bytes);

    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('entry.bin'), Payload);
    Central := FindZipSignature(Bytes, $02014B50);
    Bytes[Central] := 0;
    Reject('invalid-central-signature', Bytes);
  finally
    TDirectory.Delete(TempRoot, True);
  end;
end;

procedure TVittixAutoUpdaterTests.ZipResourceLimitsEnforceBoundaries;
var
  TempRoot, ArchivePath, DestPath: string;
  Payload, Bytes, LargePayload: TBytes;
  Config: TUpdaterConfig;
  FinalState: TUpdateState;
  Names: TArray<string>;

  procedure Reject(const CaseName: string; const Fixture: TBytes;
    const CaseConfig: TUpdaterConfig);
  begin
    TFile.WriteAllBytes(ArchivePath, Fixture);
    DestPath := TPath.Combine(TempRoot, 'limit-' + CaseName);
    Assert.IsFalse(TryExtractZip(CaseConfig, ArchivePath, DestPath, FinalState), CaseName);
    Assert.AreEqual<TUpdateState>(usFailed, FinalState, CaseName);
  end;

begin
  TempRoot := TPath.Combine(TPath.GetTempPath, 'VauZipLimits-' +
    StringReplace(TGUID.NewGuid.ToString, '{', '', [rfReplaceAll]));
  TDirectory.CreateDirectory(TempRoot);
  ArchivePath := TPath.Combine(TempRoot, 'fixture.zip');
  Payload := TEncoding.ASCII.GetBytes('12345');
  try
    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('a.txt'), Payload);
    Config := TUpdaterConfig.Default;
    Config.MaxArchiveBytes := Length(Bytes);
    Config.MaxArchiveEntryCount := 1;
    Config.MaxArchiveTotalUncompressedBytes := Length(Payload);
    Config.MaxArchiveSingleEntryBytes := Length(Payload);
    Config.MaxArchivePathDepth := 1;
    Config.MaxArchivePathLength := Length('a.txt');
    Config.MaxArchiveExpansionRatio := 1;
    TFile.WriteAllBytes(ArchivePath, Bytes);
    DestPath := TPath.Combine(TempRoot, 'limit-exact');
    Assert.IsTrue(TryExtractZip(Config, ArchivePath, DestPath, FinalState),
      'Exact configured limits must be accepted');
    Assert.IsTrue(TFile.Exists(TPath.Combine(DestPath, 'a.txt')));

    Config.MaxArchiveBytes := Length(Bytes) - 1;
    Reject('archive-bytes-one-over', Bytes, Config);

    Names := TArray<string>.Create('a', 'b');
    Bytes := BuildZipFixture(ArchivePath, Names, TEncoding.ASCII.GetBytes('x'));
    Config := TUpdaterConfig.Default;
    Config.MaxArchiveEntryCount := 1;
    Reject('entry-count-one-over', Bytes, Config);
    Config.MaxArchiveEntryCount := 2;
    Config.MaxArchiveTotalUncompressedBytes := 1;
    Reject('total-output-one-over', Bytes, Config);

    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('a.txt'), Payload);
    Config := TUpdaterConfig.Default;
    Config.MaxArchiveSingleEntryBytes := Length(Payload) - 1;
    Reject('single-entry-one-over', Bytes, Config);
    Config := TUpdaterConfig.Default;
    Config.MaxArchivePathDepth := 1;
    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('a\b\c'), Payload);
    Reject('path-depth-one-over', Bytes, Config);
    Config := TUpdaterConfig.Default;
    Config.MaxArchivePathLength := 4;
    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('a.txt'), Payload);
    Reject('path-length-one-over', Bytes, Config);

    SetLength(LargePayload, 32768);
    FillChar(LargePayload[0], Length(LargePayload), Ord('A'));
    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('packed.bin'), LargePayload, zcDeflate);
    Config := TUpdaterConfig.Default;
    Config.MaxArchiveExpansionRatio := 1;
    Reject('expansion-ratio-one-over', Bytes, Config);

    // Keep central and local metadata mutually consistent but lie about output
    // length. The streaming cap must reject bytes produced beyond that value.
    Bytes := BuildZipFixture(ArchivePath, TArray<string>.Create('stream.bin'), LargePayload, zcDeflate);
    var Central := FindZipSignature(Bytes, $02014B50);
    var Local := FindZipSignature(Bytes, $04034B50);
    WriteZipUInt32(Bytes, Central + 24, 1);
    WriteZipUInt32(Bytes, Local + 22, 1);
    Config := TUpdaterConfig.Default;
    Config.MaxArchiveSingleEntryBytes := 128;
    Config.MaxArchiveTotalUncompressedBytes := 128;
    Config.MaxArchiveExpansionRatio := 2000;
    Reject('dishonest-expanded-size-stream-cap', Bytes, Config);
  finally
    TDirectory.Delete(TempRoot, True);
  end;
end;
{$ENDIF}

procedure TVittixAutoUpdaterTests.SignatureVerifierAcceptsKnownGoodSignature;
var
  Signature: TBytes;
begin
  Signature := TNetEncoding.Base64.DecodeStringToBytes(FixtureSignature);
  Assert.IsTrue(VerifyManifestSignatureBytes(
    TEncoding.UTF8.GetBytes(FixtureManifest), Signature, FixturePublicKey));
end;

procedure TVittixAutoUpdaterTests.SignatureVerifierRejectsTamperedMissingAndWrongKey;
var
  Signature, TamperedSignature: TBytes;
  ManifestBytes: TBytes;
  WrongKey: string;
begin
  Signature := TNetEncoding.Base64.DecodeStringToBytes(FixtureSignature);
  ManifestBytes := TEncoding.UTF8.GetBytes(FixtureManifest + '!');
  Assert.IsFalse(VerifyManifestSignatureBytes(
    ManifestBytes, Signature, FixturePublicKey));
  Assert.IsFalse(VerifyManifestSignatureBytes(
    TEncoding.UTF8.GetBytes(FixtureManifest), nil, FixturePublicKey));
  WrongKey := FixturePublicKey;
  WrongKey[1] := '0';
  Assert.IsFalse(VerifyManifestSignatureBytes(
    TEncoding.UTF8.GetBytes(FixtureManifest), Signature, WrongKey));
  TamperedSignature := Copy(Signature);
  TamperedSignature[0] := TamperedSignature[0] xor 1;
  Assert.IsFalse(VerifyManifestSignatureBytes(
    TEncoding.UTF8.GetBytes(FixtureManifest), TamperedSignature, FixturePublicKey));
end;

procedure TVittixAutoUpdaterTests.SignatureEnvelopeRequiresKnownAlgorithmAndKeyId;
var
  Envelope, KeyId, SignatureText: string;
begin
  KeyId := ManifestSigningKeyId(FixturePublicKey);
  Assert.AreEqual(FixtureKeyId, KeyId);
  Assert.AreEqual(64, Length(KeyId));
  Envelope := 'VAU-ECDSA-P256-SHA256-v1:' + KeyId + ':' + FixtureSignature;
  Assert.IsTrue(TryParseManifestSignatureEnvelope(
    Envelope, KeyId, SignatureText));
  Assert.AreEqual(64, Length(KeyId));
  Assert.AreEqual(FixtureSignature, SignatureText);
  Assert.IsFalse(TryParseManifestSignatureEnvelope(
    'VAU-RSA-SHA256-v1:' + KeyId + ':' + FixtureSignature,
    KeyId, SignatureText));
  Assert.IsFalse(TryParseManifestSignatureEnvelope(
    'vau-ecdsa-p256-sha256-v1:' + FixtureKeyId + ':' + FixtureSignature,
    KeyId, SignatureText));
  Assert.IsFalse(TryParseManifestSignatureEnvelope(
    'VAU-ECDSA-P256-SHA256-v1:' + FixtureKeyId + ':***',
    KeyId, SignatureText));
  Assert.IsFalse(TryParseManifestSignatureEnvelope(
    'VAU-ECDSA-P256-SHA256-v1:unknown:' + FixtureSignature,
    KeyId, SignatureText));
  Assert.IsFalse(TryParseManifestSignatureEnvelope(
    'VAU-ECDSA-P256-SHA256-v1:' + StringOfChar('z', 64) + ':' + FixtureSignature,
    KeyId, SignatureText));
  Assert.IsFalse(TryParseManifestSignatureEnvelope(
    'VAU-ECDSA-P256-SHA256-v1:' + UpperCase(FixtureKeyId) + ':' + FixtureSignature,
    KeyId, SignatureText));
end;

procedure TVittixAutoUpdaterTests.TrustedKeySetSupportsExplicitRotation;
var
  TrustedKeys: TArray<string>;
  OldKeyId, NewKeyId: string;
begin
  OldKeyId := ManifestSigningKeyId(FixturePublicKey);
  SetLength(TrustedKeys, 1);
  TrustedKeys[0] := FixturePublicKey;
  Assert.IsTrue(IsTrustedManifestKeyId(OldKeyId, TrustedKeys));
  NewKeyId := ManifestSigningKeyId(
    '7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978'
    + '07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1');
  Assert.IsFalse(IsTrustedManifestKeyId(NewKeyId, TrustedKeys));
  SetLength(TrustedKeys, 2);
  TrustedKeys[1] :=
    '7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978'
    + '07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1';
  Assert.IsTrue(IsTrustedManifestKeyId(NewKeyId, TrustedKeys));
  Assert.IsFalse(IsTrustedManifestKeyId(StringOfChar('f', 64), TrustedKeys));
end;

procedure TVittixAutoUpdaterTests.SecureDefaultsRequireSignedMetadata;
var
  Config: TUpdaterConfig;
  Manager: TUpdateNetworkManager;
  Raised: Boolean;
  Urls: TArray<string>;
  Manifest: TUpdateManifest;
begin
  Config := TUpdaterConfig.Default;
  Assert.IsTrue(Config.VerifyManifestSignature);
  Assert.IsTrue(Config.RequireSecureConfig);
  Assert.IsFalse(Config.AllowInsecureUnsignedManifests);
  Manager := TUpdateNetworkManager.Create;
  SetLength(Urls, 0);
  try
    Raised := False;
    try
      Manager.FetchManifest(Urls, 'Demo', Manifest);
    except
      on ENetworkException do Raised := True;
    end;
    Assert.IsTrue(Raised, 'missing trusted keys must fail closed');

    Manager.VerifyManifestSignatures := False;
    Raised := False;
    try
      Manager.FetchManifest(Urls, 'Demo', Manifest);
    except
      on ENetworkException do Raised := True;
    end;
    Assert.IsTrue(Raised,
      'unsigned checks must require an explicit insecure opt-in');
    Manager.AllowInsecureUnsignedManifests := True;
    Assert.IsFalse(Manager.FetchManifest(Urls, 'Demo', Manifest));
  finally
    Manager.Free;
  end;
end;

procedure TVittixAutoUpdaterTests.VersionDowngradeRequiresOptIn;
var
  CurrentVersion, Candidate: TAppVersion;
begin
  CurrentVersion := TAppVersion.Create('2.0.0.0');
  Candidate := TAppVersion.Create('1.9.9.9');
  Assert.IsFalse(IsVersionAllowed(CurrentVersion, Candidate, False));
  Assert.IsTrue(IsVersionAllowed(CurrentVersion, Candidate, True));
  Assert.IsTrue(IsVersionAllowed(CurrentVersion,
    TAppVersion.Create('2.0.0.1'), False));
end;

procedure TVittixAutoUpdaterTests.ManifestRollbackFloorRejectsReplayAndDowngrade;
var
  ErrorMessage: string;
  Stored: string;
begin
  Stored := '2.0.0.0|1000|sha256:aa';
  Assert.IsTrue(IsManifestRollbackAllowed(
    TAppVersion.Create('2.0.0.0'), 1000, 'sha256:aa', Stored, ErrorMessage));
  Assert.IsFalse(IsManifestRollbackAllowed(
    TAppVersion.Create('1.9.9.9'), 2000, 'sha256:bb', Stored, ErrorMessage));
  Assert.IsFalse(IsManifestRollbackAllowed(
    TAppVersion.Create('2.0.0.0'), 999, 'sha256:aa', Stored, ErrorMessage));
  Assert.IsFalse(IsManifestRollbackAllowed(
    TAppVersion.Create('2.0.0.0'), 1000, 'sha256:bb', Stored, ErrorMessage));
  Assert.IsTrue(IsManifestRollbackAllowed(
    TAppVersion.Create('2.0.0.1'), 1001, 'sha256:cc', Stored, ErrorMessage));
  Assert.IsFalse(IsManifestRollbackAllowed(
    TAppVersion.Create('2.0.0.0'), 1000, 'sha256:aa', 'corrupt', ErrorMessage));
end;

procedure TVittixAutoUpdaterTests.ApplyUpdateRejectsInvalidState;
var
  Engine: TUpdateEngine;
begin
  Engine := TUpdateEngine.Create(TUpdaterConfig.Default);
  try
    Assert.AreEqual<TUpdateState>(usIdle, Engine.State);
    Assert.IsFalse(Engine.ApplyUpdate);
  finally
    Engine.Free;
  end;
end;

procedure TVittixAutoUpdaterTests.SecurityWarningsAreReported;
var
  Config: TUpdaterConfig;
  Engine: TUpdateEngine;
begin
  Config := TUpdaterConfig.Default;
  Config.ManifestHmacKey := 'legacy-shared-secret';
  Engine := TUpdateEngine.Create(Config);
  FSecurityWarnings := TStringList.Create;
  try
    Engine.OnSecurityWarning := HandleSecurityWarning;
    Assert.AreEqual(2, FSecurityWarnings.Count);
    Assert.IsTrue(Pos('ManifestPublicKey', FSecurityWarnings[0]) > 0);
    Assert.IsTrue(Pos('ignored', FSecurityWarnings[1]) > 0);
  finally
    FSecurityWarnings.Free;
    FSecurityWarnings := nil;
    Engine.Free;
  end;
end;

procedure TVittixAutoUpdaterTests.RequireSecureConfigBlocksUnsignedChecks;
var
  Config: TUpdaterConfig;
  Engine: TUpdateEngine;
  CallbackResult: TUpdateCheckResult;
begin
  Config := TUpdaterConfig.Default;
  Config.RequireSecureConfig := True;
  Engine := TUpdateEngine.Create(Config);
  try
    CallbackResult := ucrUpdateAvailable;
    Engine.CheckForUpdate(
      procedure(Result: TUpdateCheckResult; const Manifest: TUpdateManifest;
        const ErrorMessage: string)
      begin
        CallbackResult := Result;
      end);
    Assert.AreEqual<TUpdateCheckResult>(ucrError, CallbackResult);
    Assert.AreEqual<TUpdateState>(usFailed, Engine.State);
  finally
    Engine.Free;
  end;
end;

procedure TVittixAutoUpdaterTests.HttpsAndRedirectRulesArePureAndStrict;
var
  Target: string;
begin
  Assert.IsTrue(IsAllowedUpdateUrl('https://updates.example.test/manifest', True));
  Assert.IsFalse(IsAllowedUpdateUrl('http://updates.example.test/manifest', True));
  Assert.IsTrue(TryResolveSecureRedirect(
    'https://updates.example.test/a/manifest.json', '../v2/manifest.json', Target));
  Assert.IsTrue(StartsText('https://', Target));
  Assert.IsFalse(TryResolveSecureRedirect(
    'https://updates.example.test/manifest.json',
    'http://updates.example.test/manifest.json', Target));
  Assert.IsTrue(IsSecureRedirectHopAllowed(0));
  Assert.IsTrue(IsSecureRedirectHopAllowed(4));
  Assert.IsFalse(IsSecureRedirectHopAllowed(5));
end;

procedure TVittixAutoUpdaterTests.PublisherThumbprintComparisonIsNormalized;
var
  Pins: TArray<string>;
begin
  SetLength(Pins, 2);
  Pins[0] := 'AA:BB CC';
  Pins[1] := '1234';
  Assert.IsTrue(IsThumbprintPinned('aabbcc', Pins));
  Assert.IsTrue(IsThumbprintPinned('12:34', Pins));
  Assert.IsFalse(IsThumbprintPinned('aabbcd', Pins));
  SetLength(Pins, 0);
  Assert.IsFalse(IsThumbprintPinned('aabbcc', Pins));
end;

procedure TVittixAutoUpdaterTests.ResumeRequiresMatchingRangeEtagAndSize;
begin
  Assert.IsTrue(CanResumeDownload('bytes', '"v1"', '"v1"',
    'https://cdn.test/file', 'https://cdn.test/file', 100, 100, 100, 40));
  Assert.IsFalse(CanResumeDownload('none', '"v1"', '"v1"',
    'https://cdn.test/file', 'https://cdn.test/file', 100, 100, 100, 40));
  Assert.IsFalse(CanResumeDownload('bytes', '"v2"', '"v1"',
    'https://cdn.test/file', 'https://cdn.test/file', 100, 100, 100, 40));
  Assert.IsFalse(CanResumeDownload('bytes', '"v1"', '"v1"',
    'https://cdn.test/file', 'https://cdn.test/other', 100, 100, 100, 40));
  Assert.IsFalse(CanResumeDownload('bytes', '"v1"', '"v1"',
    'https://cdn.test/file', 'https://cdn.test/file', 101, 100, 100, 40));
  Assert.IsFalse(CanResumeDownload('bytes', '"v1"', '"v1"',
    'https://cdn.test/file', 'https://cdn.test/file', 100, 100, 100, 100));
  Assert.IsFalse(CanResumeDownload('bytes', 'W/"v1"', 'W/"v1"',
    'https://cdn.test/file', 'https://cdn.test/file', 100, 100, 100, 40));
end;

procedure TVittixAutoUpdaterTests.RetryBackoffScheduleIsBounded;
begin
  Assert.AreEqual(0, DownloadRetryDelayMs(0));
  Assert.AreEqual(500, DownloadRetryDelayMs(1));
  Assert.AreEqual(1000, DownloadRetryDelayMs(2));
  Assert.AreEqual(2000, DownloadRetryDelayMs(3));
  Assert.AreEqual(4000, DownloadRetryDelayMs(4));
  Assert.AreEqual(5000, DownloadRetryDelayMs(5));
  Assert.AreEqual(5000, DownloadRetryDelayMs(20));
end;

procedure TVittixAutoUpdaterTests.DiskSpaceAndSizeCapRules;
begin
  Assert.IsTrue(HasEnoughDiskSpace(100, 100));
  Assert.IsFalse(HasEnoughDiskSpace(99, 100));
  Assert.IsTrue(HasEnoughDiskSpace(0, 0));
  Assert.IsTrue(IsDownloadWithinSizeCap(0, 110, 100, 10));
  Assert.IsFalse(IsDownloadWithinSizeCap(0, 111, 100, 10));
  Assert.IsTrue(IsDownloadWithinSizeCap(50, 60, 100, 10));
  Assert.IsFalse(IsDownloadWithinSizeCap(50, 61, 100, 10));
  Assert.IsFalse(IsDownloadWithinSizeCap(-1, 1, 100, 10));
  Assert.IsTrue(IsDownloadWithinSizeCap(0, High(Int64), High(Int64), 64));
end;

{$IFDEF VITTIX_AUTH_FIXTURE}
procedure TVittixAutoUpdaterTests.AuthenticodeFixtureThumbprintAndPins;
var
  FileName, ExpectedThumbprint, ActualThumbprint: string;
  Pins: TArray<string>;
begin
  FileName := GetEnvironmentVariable('VITTIX_AUTHENTICODE_FIXTURE');
  ExpectedThumbprint := GetEnvironmentVariable('VITTIX_AUTHENTICODE_SHA256');
  Assert.IsTrue(FileExists(FileName), 'signed test executable fixture is required');
  Assert.IsTrue(TryGetAuthenticodeThumbprint(FileName, ActualThumbprint));
  Assert.AreEqual(UpperCase(ExpectedThumbprint), UpperCase(ActualThumbprint));
  SetLength(Pins, 1);
  Pins[0] := ExpectedThumbprint;
  Assert.IsTrue(IsThumbprintPinned(ActualThumbprint, Pins));
  Pins[0] := StringOfChar('0', 64);
  Assert.IsFalse(IsThumbprintPinned(ActualThumbprint, Pins));
end;
{$ENDIF}

{$IFDEF VITTIX_TEST_LOOPBACK}
procedure TVittixAutoUpdaterTests.LoopbackHttpDownloadRetryResumeAndRedirects;
var
  Server: TLoopbackUpdateServer;
  Manager: TUpdateNetworkManager;
  Root, FileName, Hash: string;
  ExpectedBody: string;

  function Download(const Route, FilePart: string; Size: Int64): Boolean;
  begin
    FileName := TPath.Combine(Root, FilePart);
    Result := Manager.DownloadFile(Server.Url(Route), FileName, nil,
      'sha256:' + Hash, Size);
  end;

begin
  Server := TLoopbackUpdateServer.Create;
  Manager := TUpdateNetworkManager.Create;
  Root := TPath.Combine(TPath.GetTempPath, 'Vittix-local-http-tests');
  TDirectory.CreateDirectory(Root);
  ExpectedBody := Server.Body;
  Hash := THashSHA2.GetHashString(ExpectedBody, SHA256);
  try
    Manager.RequireHttps := True;
    Manager.MaxRetries := 2;
    {$IFDEF VITTIX_TEST_LOOPBACK}
    Manager.AllowLoopbackHttpForTests := True;
    {$ENDIF}

    Assert.IsTrue(Download('/retry', 'retry.bin', Length(ExpectedBody)),
      'retry download failed from ' + Server.Url('/retry'));
    Assert.AreEqual(2, Server.DropCount,
      'first full response should drop; the retry should restart cleanly');
    Assert.AreEqual(ExpectedBody, TFile.ReadAllText(FileName));

    Assert.IsTrue(Download('/resume', 'resume.bin', Length(ExpectedBody)),
      'Range resume download failed');
    Assert.AreEqual(1, Server.ResumeCount,
      'resume should use a Range request after the first dropped response');
    Assert.AreEqual(ExpectedBody, TFile.ReadAllText(FileName));

    Assert.IsTrue(Download('/mismatch', 'etag.bin', Length(ExpectedBody)),
      'mismatched ETag full restart failed');
    Assert.AreEqual(1, Server.MismatchRangeCount);
    Assert.AreEqual(1, Server.FullAfterMismatchCount,
      'a mismatched ETag must discard the partial and perform a full restart');
    Assert.AreEqual(ExpectedBody, TFile.ReadAllText(FileName));

    Assert.IsFalse(Download('/overrun', 'overrun.bin', 10));
    Assert.IsFalse(TFile.Exists(FileName), 'overrun partial file must be deleted');
    Assert.IsFalse(TFile.Exists(FileName + '.part-1'),
      'overrun attempt file must be deleted');

    Assert.IsTrue(Download('/chain5/0', 'redirect5.bin', Length(ExpectedBody)),
      'five HTTPS-policy loopback redirects should be followed in test mode');
    Assert.AreEqual(ExpectedBody, TFile.ReadAllText(FileName));
    Assert.IsFalse(Download('/chain6/0', 'redirect6.bin', Length(ExpectedBody)),
      'a sixth redirect must be rejected');
    Assert.IsFalse(TFile.Exists(FileName));

    Assert.IsFalse(TryResolveSecureRedirect(
      'https://updates.test:' + IntToStr(Server.Port) + '/secure',
      'http://127.0.0.1:' + IntToStr(Server.Port) + '/success',
      FileName), 'HTTPS to HTTP downgrade must be rejected');
  finally
    Manager.Free;
    Server.Free;
    if TDirectory.Exists(Root) then
      TDirectory.Delete(Root, True);
  end;
end;
{$ENDIF}

{$IFDEF VITTIX_TEST_LOOPBACK}
procedure TVittixAutoUpdaterTests.SignedManifestFetchRejectsTamperingAndUnknownKeys;
var
  Server: TLoopbackUpdateServer;
  Manager: TUpdateNetworkManager;
  Urls: TArray<string>;
  TrustedKeys: TArray<string>;
  Manifest: TUpdateManifest;
  WrongKey: string;
begin
  Server := TLoopbackUpdateServer.Create;
  Manager := TUpdateNetworkManager.Create;
  try
    Manager.RequireHttps := True;
    Manager.AllowLoopbackHttpForTests := True;
    Manager.VerifyManifestSignatures := True;
    Manager.ManifestPublicKey := FixturePublicKey;
    Manager.MaxRetries := 1;
    Manager.MaxManifestAgeDays := 36500;
    SetLength(Urls, 1);
    Urls[0] := Server.Url('/signed-manifest');

    Assert.IsTrue(Manager.FetchManifest(Urls, 'Demo', Manifest),
      'the fixed signed vector should be accepted');
    Assert.AreEqual('1.0.0.1', Manifest.Version.ToString);

    SetLength(TrustedKeys, 2);
    TrustedKeys[0] := FixturePublicKey;
    TrustedKeys[1] :=
      '7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978'
      + '07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1';
    Manager.ManifestPublicKey := '';
    Manager.ManifestTrustedPublicKeys := TrustedKeys;
    Server.SignatureBody := 'VAU-ECDSA-P256-SHA256-v1:' +
      'd07aeb134840b15242e12d4a06ce3ab493cbd020ebc3bd5aaecd822f51e0c3d8:' +
      'IT/6ye13pYZr+EOoiz7FrR1a/XSZdwB8zJ6cXRtJ25LrBk6KpsDVzgl5crVQMQVUJ3Vi98OK0C5flnxVOqtoAQ==';
    Assert.IsTrue(Manager.FetchManifest(Urls, 'Demo', Manifest),
      'a pre-provisioned rotating key should verify');
    SetLength(TrustedKeys, 1);
    TrustedKeys[0] := FixturePublicKey;
    Manager.ManifestTrustedPublicKeys := TrustedKeys;
    Assert.IsFalse(Manager.FetchManifest(Urls, 'Demo', Manifest),
      'a rotation key not provisioned in advance must be rejected');

    Manager.ManifestPublicKey := FixturePublicKey;
    SetLength(TrustedKeys, 0);
    Manager.ManifestTrustedPublicKeys := TrustedKeys;
    Server.SignatureBody := 'VAU-ECDSA-P256-SHA256-v1:' + FixtureKeyId + ':' +
      'qwRvegCJAFGJUqsEFri6ahdEvfUmA2behjhcsSz9NbFcpI9BBHb8/se8wGnhk9OyFZ0llrqOWgiu1L9ll+hUJA==';
    Server.ManifestBody := StringReplace(Server.ManifestBody,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      'ca7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', []);
    Assert.IsFalse(Manager.FetchManifest(Urls, 'Demo', Manifest),
      'a package checksum modified after signing must be rejected');
    Server.ManifestBody := StringReplace(Server.ManifestBody,
      'ca7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', []);

    Server.SignatureBody := StringReplace(Server.SignatureBody,
      FixtureKeyId, StringOfChar('f', 64), []);
    Assert.IsFalse(Manager.FetchManifest(Urls, 'Demo', Manifest),
      'an unknown key identifier must be rejected');
    Server.SignatureBody := '';
    Assert.IsFalse(Manager.FetchManifest(Urls, 'Demo', Manifest),
      'a missing signature must be rejected');

    Manager.ManifestPublicKey := FixturePublicKey;
    WrongKey := FixturePublicKey;
    WrongKey[1] := '0';
    Manager.ManifestPublicKey := WrongKey;
    Server.SignatureBody := 'VAU-ECDSA-P256-SHA256-v1:' +
      ManifestSigningKeyId(Manager.ManifestPublicKey) + ':' +
      'qwRvegCJAFGJUqsEFri6ahdEvfUmA2behjhcsSz9NbFcpI9BBHb8/se8wGnhk9OyFZ0llrqOWgiu1L9ll+hUJA==';
    Assert.IsFalse(Manager.FetchManifest(Urls, 'Demo', Manifest),
      'a signature verified by a different public key must be rejected');

    Manager.ManifestPublicKey := FixturePublicKey;
    Server.SignatureBody := 'VAU-ECDSA-P256-SHA256-v1:' + FixtureKeyId + ':' +
      'qwRvegCJAFGJUqsEFri6ahdEvfUmA2behjhcsSz9NbFcpI9BBHb8/se8wGnhk9OyFZ0llrqOWgiu1L9ll+hUJA==';
    Server.ManifestBody := StringOfChar('X', 1024 * 1024 + 1);
    Assert.IsFalse(Manager.FetchManifest(Urls, 'Demo', Manifest),
      'oversized metadata must be rejected at the bounded response stream');
    Server.ManifestBody := '{"Demo":{"version":"1.0.0.1"}}';
    Server.SignatureBody := StringOfChar('A', 1025);
    Assert.IsFalse(Manager.FetchManifest(Urls, 'Demo', Manifest),
      'oversized detached signature metadata must be rejected');
  finally
    Manager.Free;
    Server.Free;
  end;
end;
{$ENDIF}

procedure TVittixAutoUpdaterTests.BatchCopyIntegrationHandlesWindowsMetacharacters;
var
  Root, SourcePath, DestinationPath, ScriptPath, CommandLine, SourceFile: string;
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  ExitCode: DWORD;
  Script: TStringList;
begin
  Root := TPath.Combine(TPath.GetTempPath,
    'Vittix updater (integration) & 100% path');
  SourcePath := IncludeTrailingPathDelimiter(TPath.Combine(Root, 'source'));
  DestinationPath := IncludeTrailingPathDelimiter(TPath.Combine(Root, 'destination'));
  ScriptPath := TPath.Combine(TPath.GetTempPath, 'vittix-copy-integration.bat');
  SourceFile := TPath.Combine(SourcePath, 'payload.txt');
  TDirectory.CreateDirectory(SourcePath);
  TDirectory.CreateDirectory(DestinationPath);
  TFile.WriteAllText(SourceFile, 'copy integration payload');
  Script := TStringList.Create;
  try
    Script.Add('@echo off');
    Script.Add(BuildBatchCopyCommand(SourcePath, DestinationPath));
    Script.SaveToFile(ScriptPath, TEncoding.ASCII);
  finally
    Script.Free;
  end;
  try
    FillChar(StartupInfo, SizeOf(StartupInfo), 0);
    StartupInfo.cb := SizeOf(StartupInfo);
    FillChar(ProcessInfo, SizeOf(ProcessInfo), 0);
    CommandLine := Format('cmd.exe /d /c ""%s""', [ScriptPath]);
    Assert.IsTrue(CreateProcess(nil, PChar(CommandLine), nil, nil, False,
      CREATE_NO_WINDOW, nil, nil, StartupInfo, ProcessInfo),
      'Could not start the generated copy script');
    try
      Assert.AreEqual< DWORD >(WAIT_OBJECT_0,
        WaitForSingleObject(ProcessInfo.hProcess, 30000));
      Assert.IsTrue(GetExitCodeProcess(ProcessInfo.hProcess, ExitCode));
      Assert.AreEqual<DWORD>(0, ExitCode);
    finally
      CloseHandle(ProcessInfo.hThread);
      CloseHandle(ProcessInfo.hProcess);
    end;
    Assert.IsTrue(TFile.Exists(TPath.Combine(DestinationPath, 'payload.txt')));
    Assert.AreEqual('copy integration payload',
      TFile.ReadAllText(TPath.Combine(DestinationPath, 'payload.txt')));
    Assert.IsFalse(Pos(PathDelim + '" /E',
      BuildBatchCopyCommand(SourcePath, DestinationPath)) > 0,
      'Generated destination must not end in a backslash inside quotes');
  finally
    if TFile.Exists(ScriptPath) then
      TFile.Delete(ScriptPath);
    if TDirectory.Exists(Root) then
      TDirectory.Delete(Root, True);
  end;
end;

procedure TVittixAutoUpdaterTests.ApplyScriptDeletesStaleBackupBeforeRename;
var
  Script: string;
  DeleteAt, RenameAt, CheckAt: Integer;
begin
  Script := BuildApplyScript('C:\App\App.exe', 'C:\Stage\extract', 'C:\App', ['App.exe'], nil);
  DeleteAt := Pos('del /f /q "C:\App\App.exe.old" 2>nul', Script);
  RenameAt := Pos('ren "C:\App\App.exe" "App.exe.old" 2>nul', Script);
  CheckAt := Pos('if not exist "C:\App\App.exe" goto RENAMED', Script);
  Assert.IsTrue(Pos(':WAITLOOP', Script) > 0);
  Assert.IsTrue(DeleteAt > Pos(':WAITLOOP', Script));
  Assert.IsTrue(RenameAt > DeleteAt);
  Assert.IsTrue(CheckAt > RenameAt);
end;

procedure TVittixAutoUpdaterTests.ApplyScriptBacksUpRestoresAndPreservesFiles;
var
  Script: string;
  BackupAt, CopyAt, RestoreAt: Integer;
begin
  Script := BuildApplyScript('C:\App\App.exe', 'C:\Stage\extract', 'C:\App',
    ['App.exe', 'config\data.bin', 'config\settings.ini'], ['config/settings.ini']);
  BackupAt := Pos('xcopy "C:\App\config\data.bin" "C:\Stage\backup\files\config"', Script);
  CopyAt := Pos('xcopy "C:\Stage\extract\config\data.bin" "C:\App\config" /Y /R', Script);
  RestoreAt := Pos('xcopy "C:\Stage\backup\files\config\data.bin" "C:\App\config"', Script);
  Assert.AreEqual(1, Pos('chcp 65001 >nul', Script));
  Assert.IsTrue(BackupAt > 0);
  Assert.IsTrue(CopyAt > BackupAt);
  Assert.IsTrue(RestoreAt > CopyAt);
  Assert.IsTrue(Pos('if exist "C:\Stage\backup\preserve-2\" goto COPIED_2', Script) > 0);
  Assert.IsTrue(Pos('del /f /q "C:\App\App.exe" 2>nul', Script) > CopyAt);
end;

procedure TVittixAutoUpdaterTests.RollbackExecutableRestoresCurrentWhenBackupIsLocked;
var
  Root, CurrentExe, BackupExe: string;
  LockedFile: TFileStream;
begin
  Root := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  TDirectory.CreateDirectory(Root);
  try
    CurrentExe := TPath.Combine(Root, 'test.exe');
    BackupExe := CurrentExe + '.old';
    TFile.WriteAllText(CurrentExe, 'current');
    TFile.WriteAllText(BackupExe, 'previous');
    LockedFile := TFileStream.Create(CurrentExe, fmOpenRead or fmShareExclusive);
    try
      Assert.IsFalse(RollbackExecutable(CurrentExe));
    finally
      LockedFile.Free;
    end;
    LockedFile := TFileStream.Create(BackupExe, fmOpenRead or fmShareExclusive);
    try
      Assert.IsFalse(RollbackExecutable(CurrentExe));
      Assert.AreEqual('current', TFile.ReadAllText(CurrentExe));
    finally
      LockedFile.Free;
    end;
    Assert.IsTrue(RollbackExecutable(CurrentExe));
    Assert.AreEqual('previous', TFile.ReadAllText(CurrentExe));
    Assert.IsFalse(FileExists(BackupExe));
  finally
    TDirectory.Delete(Root, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TVittixAutoUpdaterTests);

end.
