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
    FUserAgent: string;
    FProxy: string;
    FOnLog: TNetworkLogEvent;

    // State for progress callback
    FOnProgress: TDownloadProgressEvent;
    FCancelDownload: Boolean;
    FLastProgressTick: Cardinal;

    function NormalizeChecksum(const Value: string): string;
    function CalculateSHA256(const FileName: string): string;

    procedure Log(const Msg: string);
    procedure ReceiveDataHandler(
      const Sender: TObject;
      AContentLength, AReadCount: Int64;
      var Abort: Boolean);

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
      const ExpectedChecksum: string = ''): Boolean;

    // Properties
    property ConnectionTimeout: Integer read FConnectionTimeout write FConnectionTimeout;
    property MaxRetries: Integer read FMaxRetries write FMaxRetries;
    property UserAgent: string read FUserAgent write FUserAgent;
    property Proxy: string read FProxy write FProxy;
    property OnLog: TNetworkLogEvent read FOnLog write FOnLog;
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
  FUserAgent := 'VI_CON-AutoUpdater/1.0';
  FProxy := '';
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
begin
  CurrentTick := GetTickCount;

  if (CurrentTick - FLastProgressTick >= 33) or
     (AReadCount = AContentLength) then
  begin
    if Assigned(FOnProgress) then
      FOnProgress(Sender, AReadCount, AContentLength, FCancelDownload);

    FLastProgressTick := CurrentTick;
    Abort := FCancelDownload;
  end;
end;

function TUpdateNetworkManager.FetchManifest(
  const Urls: TArray<string>;
  const AppName: string;
  out Manifest: TUpdateManifest): Boolean;
var
  Url: string;
  Stream: TMemoryStream;
  JsonStr: string;
  JsonObj, AppObj: TJSONObject;
  JsonVal: TJSONValue;
  Client: THttpClient;
  Response: IHTTPResponse;
  Retry: Integer;
begin
  Result := False;
  FillChar(Manifest, SizeOf(Manifest), 0);

  for Url in Urls do
  begin
    Log('Trying manifest URL: ' + Url);

    Stream := TMemoryStream.Create;
    try
      for Retry := 1 to FMaxRetries do
      begin
        Client := THttpClient(CreateHttpClient);
        try
          Stream.Size := 0;
          Stream.Position := 0;

          try
            Response := Client.Get(Url, Stream);

            if (Response.StatusCode >= 200) and
               (Response.StatusCode < 300) then
            begin
              Stream.Position := 0;
              SetLength(JsonStr, Stream.Size);
              Stream.Read(JsonStr[1], Stream.Size);

              JsonObj := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
              try
                JsonVal := JsonObj.GetValue(AppName);

                if JsonVal is TJSONObject then
                begin
                  AppObj := JsonVal as TJSONObject;

                  Manifest.AppName := AppName;

                  if AppObj.TryGetValue<string>('version', JsonStr) then
                    Manifest.Version := TAppVersion.Create(JsonStr)
                  else
                    raise Exception.Create('Missing version field');

                  if not AppObj.TryGetValue<string>(
                    'download_url', Manifest.DownloadUrl) then
                    raise Exception.Create('Missing download_url');

                  AppObj.TryGetValue<string>(
                    'release_notes', Manifest.ReleaseNotes);

                  AppObj.TryGetValue<Int64>(
                    'file_size', Manifest.FileSize);

                  AppObj.TryGetValue<string>(
                    'checksum', Manifest.Checksum);

                  if AppObj.TryGetValue<string>('min_version', JsonStr) then
                    Manifest.MinVersion := TAppVersion.Create(JsonStr);

                  if AppObj.TryGetValue<string>('severity', JsonStr) then
                  begin
                    if SameText(JsonStr, 'critical') then
                      Manifest.Severity := usCritical
                    else if SameText(JsonStr, 'recommended') then
                      Manifest.Severity := usRecommended
                    else
                      Manifest.Severity := usOptional;
                  end;

                  if Manifest.IsValid then
                  begin
                    Result := True;
                    Exit;
                  end;
                end;
              finally
                JsonObj.Free;
              end;
            end;

          except
            on E: Exception do
            begin
              Log(Format('Manifest attempt %d failed: %s',
                [Retry, E.Message]));

              if Retry = FMaxRetries then
                Break;

              TThread.Sleep(1000 * Retry);
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
  const ExpectedChecksum: string): Boolean;
var
  HttpClient: THttpClient;
  FileStream: TFileStream;
  Response: IHTTPResponse;
  ActualChecksum, CleanExpected: string;
begin
  Result := False;
  FOnProgress := OnProgress;
  FCancelDownload := False;
  FLastProgressTick := GetTickCount;

  Log('Downloading: ' + Url);

  FileStream := TFileStream.Create(SavePath, fmCreate);
  try
    HttpClient := THttpClient(CreateHttpClient);
    try
      HttpClient.OnReceiveData := ReceiveDataHandler;

      Response := HttpClient.Get(Url, FileStream);

      if (Response.StatusCode < 200) or
         (Response.StatusCode >= 300) then
        raise ENetworkException.CreateFmt(
          'HTTP error %d: %s',
          [Response.StatusCode, Response.StatusText]);

      if (Response.ContentLength > 0) and
         (FileStream.Size <> Response.ContentLength) then
        raise ENetworkException.Create('Downloaded file size mismatch');

      if ExpectedChecksum <> '' then
      begin
        CleanExpected := NormalizeChecksum(ExpectedChecksum);
        ActualChecksum := CalculateSHA256(SavePath);

        if not SameText(ActualChecksum, CleanExpected) then
          raise ENetworkException.CreateFmt(
            'Checksum mismatch: expected %s, got %s',
            [CleanExpected, ActualChecksum]);
      end;

      Result := not FCancelDownload;

    finally
      HttpClient.Free;
    end;
  except
    on E: Exception do
    begin
      Log('Download failed: ' + E.Message);

      if FileExists(SavePath) then
        SysUtils.DeleteFile(SavePath);

      raise;
    end;
  end;

  FileStream.Free;
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
