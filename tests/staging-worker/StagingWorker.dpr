program StagingWorker;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  VittixAutoUpdater.Staging in '..\..\VittixAutoUpdater.Staging.pas';

var
  BaseDirectory, Action, StagePath: string;
  HoldMs: Cardinal;
begin
  ExitCode := 0;
  try
    if ParamCount < 3 then
      raise Exception.Create('Usage: StagingWorker <base> <hold-ms> <cleanup|keep|delete> [path]');
    BaseDirectory := ParamStr(1);
    HoldMs := StrToIntDef(ParamStr(2), 0);
    Action := ParamStr(3);
    if SameText(Action, 'delete') then
    begin
      if ParamCount <> 4 then
        raise Exception.Create('delete action requires an owned staging path');
      StagePath := ParamStr(4);
    end
    else
    begin
      StagePath := AllocatePrivateStagingDirectory(BaseDirectory);
      TFile.WriteAllText(TPath.Combine(StagePath, 'worker.pid'),
        IntToStr(GetCurrentProcessId));
    end;

    Writeln('PID=', GetCurrentProcessId);
    Writeln('STAGE=', StagePath);
    Flush(Output);
    if HoldMs > 0 then
      Sleep(HoldMs);

    if SameText(Action, 'cleanup') or SameText(Action, 'delete') then
    begin
      if not SafeDeletePrivateStagingDirectory(StagePath, BaseDirectory) then
        raise Exception.Create('Safe staging cleanup failed');
      Writeln('CLEANED=1');
      Flush(Output);
    end
    else if not SameText(Action, 'keep') then
      raise Exception.Create('Unknown worker action')
    else
    begin
      Writeln('COMPLETE=1');
      Flush(Output);
    end;
  except
    on E: Exception do
    begin
      Writeln('ERROR=', E.ClassName, ':', E.Message);
      ExitCode := 1;
    end;
  end;
end.
