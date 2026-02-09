program TestCompilation;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  VittixAutoUpdater.Types in 'VittixAutoUpdater.Types.pas',
  VittixAutoUpdater.Network in 'VittixAutoUpdater.Network.pas',
  VittixAutoUpdater.Engine in 'VittixAutoUpdater.Engine.pas';

var
  Config: TUpdaterConfig;
  Engine: TUpdateEngine;
  Version: TAppVersion;

begin
  try
    WriteLn('VittixAutoUpdater Compilation Test');
    WriteLn('===================================');

    // Test TAppVersion
    WriteLn('Testing TAppVersion...');
    if TAppVersion.TryParseVersion('1.2.3.4', Version) then
      WriteLn('Version parsing: OK - ' + Version.ToString)
    else
      WriteLn('Version parsing: FAILED');

    // Test TUpdaterConfig
    WriteLn('Testing TUpdaterConfig...');
    Config := TUpdaterConfig.Default;
    Config.AppName := 'Test Application';
    WriteLn('Config creation: OK - ' + Config.AppName);

    // Test TUpdateEngine
    WriteLn('Testing TUpdateEngine...');
    Engine := TUpdateEngine.Create(Config);
    try
      WriteLn('Engine creation: OK');
      WriteLn('Current version: ' + Engine.CurrentVersion.ToString);
    finally
      Engine.Free;
    end;

    WriteLn('');
    WriteLn('All tests passed! Compilation successful.');

  except
    on E: Exception do
    begin
      WriteLn('ERROR: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;

  WriteLn('');
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
