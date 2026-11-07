program TestCompilation;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Vcl.Forms,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  Test.VittixAutoUpdater in 'Test.VittixAutoUpdater.pas',
  Test.VittixAutoUpdater.Integration in 'Test.VittixAutoUpdater.Integration.pas',
  Test.VittixAutoUpdater.Staging in 'Test.VittixAutoUpdater.Staging.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
begin
  try
    Application.Initialize;
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := True;
    Logger := TDUnitXConsoleLogger.Create(
      TDUnitX.Options.ConsoleMode = TDUnitXConsoleMode.Quiet);
    Runner.AddLogger(Logger);
    Results := Runner.Execute;
    if not Results.AllPassed then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
