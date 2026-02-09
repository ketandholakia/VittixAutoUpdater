{******************************************************************************}
{                         VittixAutoUpdater Component                         }
{                              Vittix (c) 2026                                 }
{                                                                              }
{                  A modern auto-updater for Delphi/Pascal applications       }
{                                                                              }
{******************************************************************************}
unit VittixAutoUpdater.Network;

{$IFDEF FPC}
  {$mode delphi}
{$ENDIF}

interface

uses
  Classes, SysUtils, VittixAutoUpdater.Types;

type
  // Network manager for all HTTP operations
  TUpdateNetworkManager = class
  private
    FConnectionTimeout: Integer;
    FMaxRetries: Integer;
    FUserAgent: string;
    
    function TryGetStream(const Url: string; Stream: TStream): Boolean;
    function CalculateSHA256(const FileName: string): string;
  public
    constructor Create;
    
    // Fetch update manifest from URL (tries multiple mirrors)
    function FetchManifest(const Urls: TArray<string>; 
      const AppName: string; 
      out Manifest: TUpdateManifest): Boolean;
    
    // Download file with progress tracking
    function DownloadFile(const Url, SavePath: string;
      OnProgress: TDownloadProgressEvent;
      const ExpectedChecksum: string = ''): Boolean;
    
    // Properties
    property ConnectionTimeout: Integer read FConnectionTimeout write FConnectionTimeout;
    property MaxRetries: Integer read FMaxRetries write FMaxRetries;
    property UserAgent: string read FUserAgent write FUserAgent;
  end;

implementation

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF}
  System.Net.HttpClient, 
  System.Net.URLClient,
  System.Hash,
  System.JSON;

{ TUpdateNetworkManager }

constructor TUpdateNetworkManager.Create;
begin
  inherited Create;
  FConnectionTimeout := 30000; // 30 seconds
  FMaxRetries := 3;
  FUserAgent := 'AppUpdater/1.0';
end;

function TUpdateNetworkManager.TryGetStream(const Url: string; 
  Stream: TStream): Boolean;
var
  HttpClient: THttpClient;
  Response: IHTTPResponse;
  Retry: Integer;
begin
  Result := False;
  
  for Retry := 1 to FMaxRetries do
  begin
    HttpClient := THttpClient.Create;
    try
      HttpClient.UserAgent := FUserAgent;
      HttpClient.ConnectionTimeout := FConnectionTimeout;
      HttpClient.ResponseTimeout := FConnectionTimeout;
      
      try
        Response := HttpClient.Get(Url, Stream);
        
        if (Response.StatusCode >= 200) and (Response.StatusCode < 300) then
        begin
          Result := True;
          Break;
        end;
        
      except
        on E: Exception do
        begin
          // Log error and retry
          if Retry = FMaxRetries then
            raise ENetworkException.CreateFmt(
              'Failed to download from %s after %d attempts: %s', 
              [Url, FMaxRetries, E.Message]);
          
          Sleep(1000 * Retry); // Exponential backoff
        end;
      end;
      
    finally
      HttpClient.Free;
    end;
  end;
end;

function TUpdateNetworkManager.FetchManifest(const Urls: TArray<string>;
  const AppName: string; out Manifest: TUpdateManifest): Boolean;
var
  Url: string;
  Stream: TMemoryStream;
  JsonStr: string;
  JsonObj, AppObj: TJSONObject;
  JsonVal: TJSONValue;
begin
  Result := False;
  Manifest := Default(TUpdateManifest);
  
  // Try each URL until one succeeds
  for Url in Urls do
  begin
    Stream := TMemoryStream.Create;
    try
      if TryGetStream(Url, Stream) then
      begin
        // Parse JSON manifest
        Stream.Position := 0;
        SetLength(JsonStr, Stream.Size);
        Stream.Read(JsonStr[1], Stream.Size);
        
        try
          JsonObj := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
          try
            // Look for app-specific section
            JsonVal := JsonObj.GetValue(AppName);
            if JsonVal is TJSONObject then
            begin
              AppObj := JsonVal as TJSONObject;
              
              // Extract manifest data
              Manifest.AppName := AppName;
              
              // Version (required)
              if AppObj.TryGetValue<string>('version', JsonStr) then
                Manifest.Version := TAppVersion.Create(JsonStr)
              else
                Continue;
              
              // Download URL (required)
              if not AppObj.TryGetValue<string>('download_url', Manifest.DownloadUrl) then
                Continue;
              
              // Optional fields
              AppObj.TryGetValue<string>('release_notes', Manifest.ReleaseNotes);
              AppObj.TryGetValue<Int64>('file_size', Manifest.FileSize);
              AppObj.TryGetValue<string>('checksum', Manifest.Checksum);
              
              // Min version
              if AppObj.TryGetValue<string>('min_version', JsonStr) then
                Manifest.MinVersion := TAppVersion.Create(JsonStr);
              
              // Severity
              if AppObj.TryGetValue<string>('severity', JsonStr) then
              begin
                if SameText(JsonStr, 'critical') then
                  Manifest.Severity := usCritical
                else if SameText(JsonStr, 'recommended') then
                  Manifest.Severity := usRecommended
                else
                  Manifest.Severity := usOptional;
              end;
              
              // Validate manifest
              if Manifest.IsValid then
              begin
                Result := True;
                Break;
              end;
            end;
          finally
            JsonObj.Free;
          end;
        except
          on E: Exception do
            Continue; // Try next URL
        end;
      end;
    finally
      Stream.Free;
    end;
  end;
end;

function TUpdateNetworkManager.DownloadFile(const Url, SavePath: string;
  OnProgress: TDownloadProgressEvent; 
  const ExpectedChecksum: string): Boolean;
var
  HttpClient: THttpClient;
  FileStream: TFileStream;
  Response: IHTTPResponse;
  LastProgressUpdate: Cardinal;
  ActualChecksum: string;
  Cancel: Boolean;
begin
  Result := False;
  Cancel := False;
  
  // Create file stream
  FileStream := TFileStream.Create(SavePath, fmCreate);
  try
    HttpClient := THttpClient.Create;
    try
      HttpClient.UserAgent := FUserAgent;
      HttpClient.ConnectionTimeout := FConnectionTimeout;
      HttpClient.ResponseTimeout := FConnectionTimeout * 10; // Longer for downloads
      
      // Set up progress callback
      if Assigned(OnProgress) then
      begin
        LastProgressUpdate := GetTickCount;
        
        HttpClient.OnReceiveData := procedure(const Sender: TObject; 
          AContentLength, AReadCount: Int64; var Abort: Boolean)
        var
          CurrentTick: Cardinal;
        begin
          CurrentTick := GetTickCount;
          
          // Throttle updates to 30 FPS
          if (CurrentTick - LastProgressUpdate >= 33) or 
             (AReadCount = AContentLength) then
          begin
            OnProgress(Sender, AReadCount, AContentLength, Cancel);
            LastProgressUpdate := CurrentTick;
            Abort := Cancel;
          end;
        end;
      end;
      
      try
        // Download file
        Response := HttpClient.Get(Url, FileStream);
        
        if (Response.StatusCode >= 200) and (Response.StatusCode < 300) then
        begin
          // Verify size
          if (Response.ContentLength > 0) and 
             (FileStream.Size <> Response.ContentLength) then
            raise ENetworkException.Create('Downloaded file size mismatch');
          
          // Verify checksum if provided
          if not ExpectedChecksum.IsEmpty then
          begin
            ActualChecksum := CalculateSHA256(SavePath);
            if not SameText(ActualChecksum, ExpectedChecksum) then
              raise ENetworkException.CreateFmt(
                'Checksum mismatch: expected %s, got %s', 
                [ExpectedChecksum, ActualChecksum]);
          end;
          
          Result := not Cancel;
        end
        else
          raise ENetworkException.CreateFmt(
            'HTTP error %d: %s', 
            [Response.StatusCode, Response.StatusText]);
        
      except
        on E: Exception do
        begin
          // Delete partial download
          if FileExists(SavePath) then
            DeleteFile(SavePath);
          raise;
        end;
      end;
      
    finally
      HttpClient.Free;
    end;
  finally
    FileStream.Free;
  end;
end;

function TUpdateNetworkManager.CalculateSHA256(const FileName: string): string;
var
  FileStream: TFileStream;
begin
  FileStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := THashSHA2.GetHashString(FileStream, SHA256);
  finally
    FileStream.Free;
  end;
end;

end.
