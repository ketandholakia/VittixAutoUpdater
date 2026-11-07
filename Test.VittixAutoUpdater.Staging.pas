unit Test.VittixAutoUpdater.Staging;

interface

uses
  DUnitX.TestFramework;

type
  {$M+}
  [TestFixture]
  TVittixAutoUpdaterStagingTests = class
  private
    FBaseDirectory: string;
    procedure DeleteTestBase;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
  published
    [Test] procedure AllocationsAreUniqueAndUseProtectedAcl;
    [Test] procedure ConcurrentAllocationsAreIsolated;
    [Test] procedure CleanupRemovesOnlyOwnedStagingTree;
    [Test] procedure InvalidBaseFailsClosed;
    [Test] procedure ExistingStagingFileIsNotReused;
    [Test] procedure CollisionRetriesWithoutTouchingExistingDirectory;
    [Test] procedure RetryLimitFailsWithoutTouchingExistingDirectory;
    [Test] procedure IdentifierFailureCreatesNoDirectory;
    [Test] procedure AllocationRejectsJunctionBase;
    [Test] procedure CleanupRemovesJunctionWithoutTraversingTarget;
    [Test] procedure CleanupRejectsReparsePointReplacingStagingRoot;
    [Test] procedure NetworkRejectsReparseDownloadDestination;
    [Test] procedure AllocationRejectsDirectorySymbolicLink;
    [Test] procedure CleanupRemovesDirectorySymbolicLinkWithoutTraversal;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  System.SysUtils,
  VittixAutoUpdater.Types,
  VittixAutoUpdater.Staging,
  VittixAutoUpdater.Network;

type
  TStagingAllocationThread = class(TThread)
  private
    FBaseDirectory: string;
    FResults: TStrings;
    FLock: TCriticalSection;
  protected
    procedure Execute; override;
  public
    constructor Create(const BaseDirectory: string; Results: TStrings;
      Lock: TCriticalSection);
  end;

constructor TStagingAllocationThread.Create(const BaseDirectory: string;
  Results: TStrings; Lock: TCriticalSection);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FBaseDirectory := BaseDirectory;
  FResults := Results;
  FLock := Lock;
end;

procedure TStagingAllocationThread.Execute;
var
  NewPath: string;
begin
  NewPath := AllocatePrivateStagingDirectory(FBaseDirectory);
  FLock.Acquire;
  try
    FResults.Add(NewPath);
  finally
    FLock.Release;
  end;
end;

function GetFileSecurityW(FileName: PWideChar; RequestedInformation: DWORD;
  SecurityDescriptor: Pointer; Length: DWORD; var LengthNeeded: DWORD): BOOL;
  stdcall; external 'advapi32.dll' name 'GetFileSecurityW';
function GetSecurityDescriptorControl(SecurityDescriptor: Pointer;
  var Control: WORD; var Revision: DWORD): BOOL; stdcall;
  external 'advapi32.dll' name 'GetSecurityDescriptorControl';
function GetSecurityDescriptorDacl(SecurityDescriptor: Pointer;
  var DaclPresent: BOOL; var Dacl: PACL; var DaclDefaulted: BOOL): BOOL;
  stdcall; external 'advapi32.dll' name 'GetSecurityDescriptorDacl';
function ConvertStringSidToSidW(StringSid: PWideChar; var Sid: PSID): BOOL;
  stdcall; external 'advapi32.dll' name 'ConvertStringSidToSidW';

type
  TAclSizeInformation = packed record
    AceCount: DWORD;
    AclBytesInUse: DWORD;
    AclBytesFree: DWORD;
  end;
  TAceHeader = packed record
    AceType: Byte;
    AceFlags: Byte;
    AceSize: Word;
  end;
  PAceHeader = ^TAceHeader;

function GetAclInformation(Acl: PACL; AclInformation: Pointer;
  AclInformationLength, AclInformationClass: DWORD): BOOL; stdcall;
  external 'advapi32.dll' name 'GetAclInformation';
function GetAce(Acl: PACL; AceIndex: DWORD; var Ace: Pointer): BOOL;
  stdcall; external 'advapi32.dll' name 'GetAce';
function EqualSid(Sid1, Sid2: PSID): BOOL; stdcall;
  external 'advapi32.dll' name 'EqualSid';

procedure AssertPrivateAcl(const Path: string; RequireProtectedDacl: Boolean);
var
  Needed, Revision: DWORD;
  Control: WORD;
  Descriptor: TBytes;
  Dacl: PACL;
  DaclPresent, DaclDefaulted: BOOL;
  AclInfo: TAclSizeInformation;
  Ace: Pointer;
  AceHeader: PAceHeader;
  AceSid: PSID;
  OwnerRightsSid, SystemSid: PSID;
  I, OwnerRightsCount, SystemCount: Integer;
begin
  Needed := 0;
  GetFileSecurityW(PWideChar(Path), DACL_SECURITY_INFORMATION,
    nil, 0, Needed);
  Assert.IsTrue(Needed > 0, 'Expected explicit security descriptor for ' + Path);
  SetLength(Descriptor, Needed);
  Assert.IsTrue(GetFileSecurityW(PWideChar(Path), DACL_SECURITY_INFORMATION,
    @Descriptor[0], Needed, Needed));
  Assert.IsTrue(GetSecurityDescriptorControl(@Descriptor[0], Control, Revision));
  if RequireProtectedDacl then
    Assert.IsTrue((Control and $1000) <> 0, 'Directory DACL must be protected');
  Dacl := nil;
  Assert.IsTrue(GetSecurityDescriptorDacl(@Descriptor[0], DaclPresent,
    Dacl, DaclDefaulted));
  Assert.IsTrue(DaclPresent and (Dacl <> nil));
  FillChar(AclInfo, SizeOf(AclInfo), 0);
  Assert.IsTrue(GetAclInformation(Dacl, @AclInfo, SizeOf(AclInfo), 2));
  Assert.AreEqual<Integer>(2, AclInfo.AceCount,
    'Private DACL should contain only owner-rights and SYSTEM grants');
  OwnerRightsSid := nil;
  SystemSid := nil;
  Assert.IsTrue(ConvertStringSidToSidW('S-1-3-4', OwnerRightsSid));
  Assert.IsTrue(ConvertStringSidToSidW('S-1-5-18', SystemSid));
  OwnerRightsCount := 0;
  SystemCount := 0;
  try
    for I := 0 to AclInfo.AceCount - 1 do
    begin
      Ace := nil;
      Assert.IsTrue(GetAce(Dacl, I, Ace));
      AceHeader := PAceHeader(Ace);
      Assert.AreEqual<Byte>(0, AceHeader.AceType,
        'Unexpected non-allow ACE in protected staging DACL');
      AceSid := PSID(PByte(Ace) + SizeOf(TAceHeader) + SizeOf(DWORD));
      if EqualSid(AceSid, OwnerRightsSid) then
        Inc(OwnerRightsCount)
      else if EqualSid(AceSid, SystemSid) then
        Inc(SystemCount)
      else
        Assert.Fail('Unexpected principal in protected staging DACL');
    end;
  finally
    FreeSid(OwnerRightsSid);
    FreeSid(SystemSid);
  end;
  Assert.AreEqual<Integer>(1, OwnerRightsCount);
  Assert.AreEqual<Integer>(1, SystemCount);
end;

function CreateJunction(const LinkPath, TargetPath: string): Boolean;
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
  if not Result then
    Exit;
  try
    WaitForSingleObject(ProcessInfo.hProcess, 15000);
    ExitCode := 1;
    GetExitCodeProcess(ProcessInfo.hProcess, ExitCode);
    Result := ExitCode = 0;
  finally
    CloseHandle(ProcessInfo.hThread);
    CloseHandle(ProcessInfo.hProcess);
  end;
end;

function CreateSymbolicLinkW(LinkName, TargetName: PWideChar;
  Flags: DWORD): BOOL; stdcall; external 'kernel32.dll' name 'CreateSymbolicLinkW';

function CreateDirectorySymbolicLink(const LinkPath, TargetPath: string): Boolean;
begin
  Result := CreateSymbolicLinkW(PWideChar(LinkPath), PWideChar(TargetPath),
    1 or 2);
end;

procedure TVittixAutoUpdaterStagingTests.Setup;
begin
  FBaseDirectory := AllocatePrivateStagingDirectory(GetPrivateStagingBase(''));
end;

procedure TVittixAutoUpdaterStagingTests.DeleteTestBase;
begin
  if FBaseDirectory <> '' then
  begin
    SafeDeletePrivateStagingDirectory(
      FBaseDirectory, GetPrivateStagingBase(''));
    FBaseDirectory := '';
  end;
end;

procedure TVittixAutoUpdaterStagingTests.TearDown;
begin
  DeleteTestBase;
end;

procedure TVittixAutoUpdaterStagingTests.AllocationsAreUniqueAndUseProtectedAcl;
var
  FirstPath, SecondPath: string;
begin
  FirstPath := AllocatePrivateStagingDirectory(FBaseDirectory);
  SecondPath := AllocatePrivateStagingDirectory(FBaseDirectory);
  try
    Assert.AreNotEqual(FirstPath, SecondPath);
    AssertPrivateAcl(FirstPath, True);
  finally
    Assert.IsTrue(SafeDeletePrivateStagingDirectory(FirstPath, FBaseDirectory));
    Assert.IsTrue(SafeDeletePrivateStagingDirectory(SecondPath, FBaseDirectory));
  end;
end;

procedure TVittixAutoUpdaterStagingTests.ConcurrentAllocationsAreIsolated;
const
  THREAD_COUNT = 12;
var
  Threads: array[0..THREAD_COUNT - 1] of TThread;
  Paths: TStringList;
  Lock: TCriticalSection;
  I, J: Integer;
begin
  Lock := TCriticalSection.Create;
  Paths := TStringList.Create;
  try
    for I := 0 to THREAD_COUNT - 1 do
    begin
      Threads[I] := TStagingAllocationThread.Create(
        FBaseDirectory, Paths, Lock);
      Threads[I].Start;
    end;
    for I := 0 to THREAD_COUNT - 1 do
      Threads[I].WaitFor;
    Assert.AreEqual(THREAD_COUNT, Paths.Count);
    for I := 0 to THREAD_COUNT - 1 do
    begin
      Assert.IsNotEmpty(Paths[I]);
      for J := I + 1 to THREAD_COUNT - 1 do
        Assert.AreNotEqual(Paths[I], Paths[J]);
    end;
  finally
    for I := 0 to THREAD_COUNT - 1 do
      if Assigned(Threads[I]) then
        Threads[I].Free;
    for I := 0 to Paths.Count - 1 do
      SafeDeletePrivateStagingDirectory(Paths[I], FBaseDirectory);
    Paths.Free;
    Lock.Free;
  end;
end;

procedure TVittixAutoUpdaterStagingTests.CleanupRemovesOnlyOwnedStagingTree;
var
  OwnedPath, ForeignPath: string;
begin
  OwnedPath := AllocatePrivateStagingDirectory(FBaseDirectory);
  ForeignPath := TPath.Combine(FBaseDirectory, 'foreign');
  TDirectory.CreateDirectory(ForeignPath);
  TFile.WriteAllText(TPath.Combine(OwnedPath, 'package.part-1'), 'partial');
  TDirectory.CreateDirectory(TPath.Combine(OwnedPath, 'payload'));
  TFile.WriteAllText(TPath.Combine(OwnedPath, 'payload\entry.bin'), 'data');
  try
    Assert.IsTrue(SafeDeletePrivateStagingDirectory(OwnedPath, FBaseDirectory));
    Assert.IsFalse(TDirectory.Exists(OwnedPath));
    Assert.IsTrue(TDirectory.Exists(ForeignPath));
  finally
    if TDirectory.Exists(ForeignPath) then
      TDirectory.Delete(ForeignPath, True);
  end;
end;

procedure TVittixAutoUpdaterStagingTests.InvalidBaseFailsClosed;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    AllocatePrivateStagingDirectory(TPath.Combine(FBaseDirectory, 'missing'));
  except
    on E: Exception do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'A missing staging base must be rejected');
end;

procedure TVittixAutoUpdaterStagingTests.ExistingStagingFileIsNotReused;
var
  Stage, FileName: string;
begin
  Stage := AllocatePrivateStagingDirectory(FBaseDirectory);
  FileName := TPath.Combine(Stage, 'helper.cmd');
  try
    Assert.IsTrue(CreateExclusiveStagingFile(FileName));
    Assert.IsFalse(CreateExclusiveStagingFile(FileName));
    AssertPrivateAcl(FileName, False);
  finally
    SafeDeletePrivateStagingDirectory(Stage, FBaseDirectory);
  end;
end;

procedure TVittixAutoUpdaterStagingTests.CollisionRetriesWithoutTouchingExistingDirectory;
var
  CollisionPath, AllocatedPath: string;
begin
  CollisionPath := TPath.Combine(FBaseDirectory,
    'VittixAutoUpdater-' + StringOfChar('A', 32));
  Assert.IsTrue(CreateDirectory(PChar(CollisionPath), nil));
  SetStagingTestIdentifiers(TArray<string>.Create(
    StringOfChar('A', 32), StringOfChar('B', 32)));
  try
    AllocatedPath := AllocatePrivateStagingDirectory(FBaseDirectory);
    try
      Assert.AreEqual(TPath.Combine(FBaseDirectory,
        'VittixAutoUpdater-' + StringOfChar('B', 32)), AllocatedPath);
      Assert.IsTrue(TDirectory.Exists(CollisionPath));
    finally
      Assert.IsTrue(SafeDeletePrivateStagingDirectory(
        AllocatedPath, FBaseDirectory));
    end;
  finally
    SetStagingTestIdentifiers(nil);
    RemoveDirectory(PChar(CollisionPath));
  end;
end;

procedure TVittixAutoUpdaterStagingTests.RetryLimitFailsWithoutTouchingExistingDirectory;
var
  CollisionPath: string;
  Identifiers: TArray<string>;
  I: Integer;
  Raised: Boolean;
begin
  CollisionPath := TPath.Combine(FBaseDirectory,
    'VittixAutoUpdater-' + StringOfChar('C', 32));
  Assert.IsTrue(CreateDirectory(PChar(CollisionPath), nil));
  SetLength(Identifiers, 16);
  for I := 0 to High(Identifiers) do
    Identifiers[I] := StringOfChar('C', 32);
  SetStagingTestIdentifiers(Identifiers);
  Raised := False;
  try
    try
      AllocatePrivateStagingDirectory(FBaseDirectory);
    except
      on E: EOSError do
        Raised := True;
    end;
    Assert.IsTrue(Raised, 'Allocation must fail after the bounded retry count');
    Assert.IsTrue(TDirectory.Exists(CollisionPath),
      'An unrelated colliding directory must remain intact');
  finally
    SetStagingTestIdentifiers(nil);
    RemoveDirectory(PChar(CollisionPath));
  end;
end;

procedure TVittixAutoUpdaterStagingTests.IdentifierFailureCreatesNoDirectory;
var
  BeforeCount: Integer;
  Raised: Boolean;
begin
  BeforeCount := Length(TDirectory.GetDirectories(FBaseDirectory));
  SetStagingTestRandomFailure(True);
  Raised := False;
  try
    try
      AllocatePrivateStagingDirectory(FBaseDirectory);
    except
      on E: EOSError do
        Raised := True;
    end;
  finally
    SetStagingTestRandomFailure(False);
  end;
  Assert.IsTrue(Raised);
  Assert.AreEqual<Integer>(BeforeCount,
    Length(TDirectory.GetDirectories(FBaseDirectory)));
end;

procedure TVittixAutoUpdaterStagingTests.AllocationRejectsJunctionBase;
var
  TargetPath, JunctionPath: string;
  Raised: Boolean;
begin
  TargetPath := TPath.Combine(FBaseDirectory, 'junction-target');
  JunctionPath := TPath.Combine(FBaseDirectory, 'junction-base');
  TDirectory.CreateDirectory(TargetPath);
  Assert.IsTrue(CreateJunction(JunctionPath, TargetPath),
    'Could not create disposable junction fixture');
  Raised := False;
  try
    try
      AllocatePrivateStagingDirectory(JunctionPath);
    except
      on E: EOSError do
        Raised := True;
    end;
    Assert.IsTrue(Raised, 'Allocation must reject a reparse-point base');
    Assert.IsTrue(TDirectory.Exists(TargetPath));
  finally
    RemoveDirectory(PChar(JunctionPath));
    TDirectory.Delete(TargetPath, True);
  end;
end;

procedure TVittixAutoUpdaterStagingTests.CleanupRemovesJunctionWithoutTraversingTarget;
var
  StagePath, TargetPath, LinkPath, SentinelPath: string;
begin
  StagePath := AllocatePrivateStagingDirectory(FBaseDirectory);
  TargetPath := TPath.Combine(FBaseDirectory, 'outside-target');
  TDirectory.CreateDirectory(TargetPath);
  SentinelPath := TPath.Combine(TargetPath, 'sentinel.txt');
  TFile.WriteAllText(SentinelPath, 'keep');
  LinkPath := TPath.Combine(StagePath, 'redirected-child');
  try
    Assert.IsTrue(CreateJunction(LinkPath, TargetPath),
      'Could not create disposable child junction fixture');
    Assert.IsTrue(SafeDeletePrivateStagingDirectory(StagePath, FBaseDirectory));
    Assert.IsTrue(TDirectory.Exists(TargetPath));
    Assert.AreEqual('keep', TFile.ReadAllText(SentinelPath));
  finally
    if TDirectory.Exists(StagePath) then
      SafeDeletePrivateStagingDirectory(StagePath, FBaseDirectory);
    if TDirectory.Exists(TargetPath) then
      TDirectory.Delete(TargetPath, True);
  end;
end;

procedure TVittixAutoUpdaterStagingTests.CleanupRejectsReparsePointReplacingStagingRoot;
var
  StagePath, TargetPath, SentinelPath: string;
begin
  StagePath := AllocatePrivateStagingDirectory(FBaseDirectory);
  TargetPath := TPath.Combine(FBaseDirectory, 'root-target');
  TDirectory.CreateDirectory(TargetPath);
  SentinelPath := TPath.Combine(TargetPath, 'sentinel.txt');
  TFile.WriteAllText(SentinelPath, 'keep');
  try
    Assert.IsTrue(RemoveDirectory(PChar(StagePath)));
    Assert.IsTrue(CreateJunction(StagePath, TargetPath),
      'Could not replace staging root with disposable junction');
    Assert.IsFalse(SafeDeletePrivateStagingDirectory(StagePath, FBaseDirectory),
      'Cleanup must fail closed when the staging root has become a junction');
    Assert.AreEqual('keep', TFile.ReadAllText(SentinelPath));
  finally
    RemoveDirectory(PChar(StagePath));
    if TDirectory.Exists(TargetPath) then
      TDirectory.Delete(TargetPath, True);
  end;
end;

procedure TVittixAutoUpdaterStagingTests.NetworkRejectsReparseDownloadDestination;
var
  TargetPath, JunctionPath, DestinationPath: string;
  Network: TUpdateNetworkManager;
  Rejected: Boolean;
begin
  TargetPath := TPath.Combine(FBaseDirectory, 'download-target');
  JunctionPath := TPath.Combine(FBaseDirectory, 'download-junction');
  TDirectory.CreateDirectory(TargetPath);
  Assert.IsTrue(CreateJunction(JunctionPath, TargetPath),
    'Could not create disposable download junction fixture');
  DestinationPath := TPath.Combine(JunctionPath, 'package.zip');
  Network := TUpdateNetworkManager.Create;
  try
{$IFDEF VITTIX_TEST_LOOPBACK}
    Network.AllowLoopbackHttpForTests := True;
{$ENDIF}
    Network.RequireHttps := False;
    Rejected := False;
    try
      Network.DownloadFile('http://127.0.0.1:1/package', DestinationPath,
        nil, '', 1);
    except
      on E: EFileSystemException do
        Rejected := True;
    end;
    Assert.IsTrue(Rejected,
      'Downloader must reject a destination whose parent resolves through a junction');
    Assert.IsFalse(TFile.Exists(TPath.Combine(TargetPath, 'package.zip')),
      'Redirected destination must not create a file outside staging');
  finally
    Network.Free;
    RemoveDirectory(PChar(JunctionPath));
    if TDirectory.Exists(TargetPath) then
      TDirectory.Delete(TargetPath, True);
  end;
end;

procedure TVittixAutoUpdaterStagingTests.AllocationRejectsDirectorySymbolicLink;
var
  TargetPath, LinkPath: string;
  Raised: Boolean;
begin
  TargetPath := TPath.Combine(FBaseDirectory, 'symlink-target');
  LinkPath := TPath.Combine(FBaseDirectory, 'symlink-base');
  TDirectory.CreateDirectory(TargetPath);
  Assert.IsTrue(CreateDirectorySymbolicLink(LinkPath, TargetPath),
    'Could not create disposable directory symbolic-link fixture');
  try
    Raised := False;
    try
      AllocatePrivateStagingDirectory(LinkPath);
    except
      on E: EOSError do
        Raised := True;
    end;
    Assert.IsTrue(Raised, 'Allocation must reject a symbolic-link base');
    Assert.IsTrue(TDirectory.Exists(TargetPath));
  finally
    RemoveDirectory(PChar(LinkPath));
    TDirectory.Delete(TargetPath, True);
  end;
end;

procedure TVittixAutoUpdaterStagingTests.CleanupRemovesDirectorySymbolicLinkWithoutTraversal;
var
  StagePath, TargetPath, LinkPath, SentinelPath: string;
begin
  StagePath := AllocatePrivateStagingDirectory(FBaseDirectory);
  TargetPath := TPath.Combine(FBaseDirectory, 'symlink-child-target');
  TDirectory.CreateDirectory(TargetPath);
  SentinelPath := TPath.Combine(TargetPath, 'sentinel.txt');
  TFile.WriteAllText(SentinelPath, 'keep');
  LinkPath := TPath.Combine(StagePath, 'redirected-symlink');
  try
    Assert.IsTrue(CreateDirectorySymbolicLink(LinkPath, TargetPath),
      'Could not create disposable child symbolic-link fixture');
    Assert.IsTrue(SafeDeletePrivateStagingDirectory(StagePath, FBaseDirectory));
    Assert.IsTrue(TDirectory.Exists(TargetPath));
    Assert.AreEqual('keep', TFile.ReadAllText(SentinelPath));
  finally
    if TDirectory.Exists(StagePath) then
      SafeDeletePrivateStagingDirectory(StagePath, FBaseDirectory);
    if TDirectory.Exists(TargetPath) then
      TDirectory.Delete(TargetPath, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TVittixAutoUpdaterStagingTests);

end.
