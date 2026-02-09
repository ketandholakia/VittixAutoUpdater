{******************************************************************************}
{                         VittixAutoUpdater Component                         }
{                              Vittix (c) 2026                                 }
{                                                                              }
{                         Demo Application - Console Example                  }
{                                                                              }
{******************************************************************************}
program VittixAutoUpdaterDemo;

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes,
  VittixAutoUpdater.Types,
  VittixAutoUpdater.Network,
  VittixAutoUpdater.Engine;

var
  Config: TUpdaterConfig;
  Engine: TUpdateEngine;
  Manifest: TUpdateManifest;
  UpdateAvailable: Boolean;

procedure OnStateChange(Sender: TObject; NewState: TUpdateState; 
  const StatusMessage: string);
begin
  WriteLn(Format('[%s] %s', [
    GetEnumName(TypeInfo(TUpdateState), Ord(NewState)),
    StatusMessage
  ]));
end;

procedure OnDownloadProgress(Sender: TObject; BytesReceived, TotalBytes: Int64;
  var Cancel: Boolean);
var
  Percent: Integer;
begin
  if TotalBytes > 0 then
  begin
    Percent := Round((BytesReceived / TotalBytes) * 100);
    Write(Format(#13'Downloading: %d%% (%d / %d bytes)', 
      [Percent, BytesReceived, TotalBytes]));
  end;
end;

begin
  WriteLn('=== VittixAutoUpdater Demo ===');
  WriteLn;
  
  // Configure updater
  Config := TUpdaterConfig.Default;
  Config.AppName := 'MyApplication';
  SetLength(Config.ManifestUrls, 1);
  Config.ManifestUrls[0] := 'https://updates.example.com/manifest.json';
  Config.CheckInterval := 24;
  Config.AutoDownload := False;
  Config.AutoInstall := False;
  Config.ConnectionTimeout := 30;
  Config.MaxRetries := 3;
  
  // Create update engine
  Engine := TUpdateEngine.Create(Config);
  try
    Engine.OnStateChange := OnStateChange;
    Engine.OnDownloadProgress := OnDownloadProgress;
    
    WriteLn(Format('Current Version: %s', [Engine.CurrentVersion.ToString]));
    WriteLn;
    
    // Check for updates
    WriteLn('Checking for updates...');
    UpdateAvailable := False;
    
    Engine.CheckForUpdate(procedure(Result: TUpdateCheckResult;
      const AManifest: TUpdateManifest; const ErrorMessage: string)
    begin
      case Result of
        ucrUpdateAvailable:
          begin
            WriteLn;
            WriteLn('Update Available!');
            WriteLn(Format('  Version: %s', [AManifest.Version.ToString]));
            WriteLn(Format('  Size: %d bytes', [AManifest.FileSize]));
            WriteLn(Format('  Release Notes: %s', [AManifest.ReleaseNotes]));
            
            Manifest := AManifest;
            UpdateAvailable := True;
          end;
          
        ucrNoUpdateAvailable:
          begin
            WriteLn('No updates available.');
          end;
          
        ucrError:
          begin
            WriteLn('Error checking for updates: ' + ErrorMessage);
          end;
      end;
    end);
    
    // Wait for check to complete
    while Engine.State = usChecking do
    begin
      Sleep(100);
    end;
    
    // If update available, ask user
    if UpdateAvailable then
    begin
      WriteLn;
      Write('Download and install update? (Y/N): ');
      if UpCase(ReadLn[1]) = 'Y' then
      begin
        WriteLn;
        
        // Download update
        if Engine.DownloadUpdate(Manifest) then
        begin
          WriteLn;
          WriteLn('Download complete!');
          WriteLn;
          
          // Apply update
          Write('Apply update now? (Y/N): ');
          if UpCase(ReadLn[1]) = 'Y' then
          begin
            if Engine.ApplyUpdate then
            begin
              WriteLn('Update applied successfully!');
              WriteLn('Application will restart...');
              // Application will be restarted by update script
            end
            else
            begin
              WriteLn('Failed to apply update.');
              Write('Rollback to previous version? (Y/N): ');
              if UpCase(ReadLn[1]) = 'Y' then
              begin
                if Engine.Rollback then
                  WriteLn('Rollback successful.')
                else
                  WriteLn('Rollback failed.');
              end;
            end;
          end;
        end
        else
        begin
          WriteLn;
          WriteLn('Download failed.');
        end;
      end;
    end;
    
  finally
    Engine.Free;
  end;
  
  WriteLn;
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
