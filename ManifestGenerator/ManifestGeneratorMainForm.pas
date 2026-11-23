unit ManifestGeneratorMainForm;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Hash, System.JSON, System.IOUtils,
  Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs, Vcl.ComCtrls, Vcl.Graphics,
  Vcl.Controls, Vcl.Clipbrd, System.DateUtils;

type
  TManifestGeneratorForm = class(TForm)
    PanelTop: TPanel;
    BtnSelectZip: TButton;
    EditZip: TEdit;
    Label1: TLabel;

    GroupBox1: TGroupBox;
    Label2: TLabel;
    EditAppName: TEdit;
    Label3: TLabel;
    EditVersion: TEdit;
    Label4: TLabel;
    EditDownloadUrl: TEdit;
    Label5: TLabel;
    EditMinVersion: TEdit;
    LabelIssuedAt: TLabel;
    EditIssuedAt: TEdit;

    GroupBox2: TGroupBox;
    MemoNotes: TRichEdit;

    GroupBox3: TGroupBox;
    ComboSeverity: TComboBox;

    PanelBottom: TPanel;
    BtnGenerate: TButton;
    BtnSaveManifest: TButton;
    BtnValidate: TButton;
    BtnValidateSaved: TButton;
    BtnCopySigningCommand: TButton;
    LabelSigning: TLabel;
    SaveDialog1: TSaveDialog;

    OpenDialog1: TOpenDialog;
    PanelStatus: TPanel;
    LabelStatusIcon: TLabel;
    LabelStatusText: TLabel;

    procedure FormCreate(Sender: TObject);
    procedure BtnSelectZipClick(Sender: TObject);
    procedure BtnGenerateClick(Sender: TObject);
    procedure BtnSaveManifestClick(Sender: TObject);
    procedure BtnValidateClick(Sender: TObject);
    procedure BtnValidateSavedClick(Sender: TObject);
    procedure BtnCopySigningCommandClick(Sender: TObject);
    procedure AnyFieldChanged(Sender: TObject);

  private
    FChecksum: string;
    FFileSize: Int64;
    FLastValidationOK: Boolean;
    FSigningManifestPath: string;

    function IsValidUrl(const Url: string): Boolean;
    function ValidateManifest(const JsonText, ManifestPath: string; out Msg: string): Boolean;
    function CalcSHA256(AStream: TStream): string; overload;
    function CalcSHA256(const AFileName: string): string; overload;
    procedure ReadFileInfo(const FileName: string);
    function BuildManifestJSON: string;
    procedure SetStatusPanel(const Msg: string; OK: Boolean);
  end;

var
  ManifestGeneratorForm: TManifestGeneratorForm;

implementation

{$R *.dfm}

const
  UtcTimestampFormat = 'yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"';

procedure TManifestGeneratorForm.FormCreate(Sender: TObject);
begin
  ComboSeverity.Items.Add('optional');
  ComboSeverity.Items.Add('recommended');
  ComboSeverity.Items.Add('critical');
  ComboSeverity.ItemIndex := 1; // default recommended

  EditMinVersion.Text := '1.0.0.0';
  EditVersion.Text := '1.0.0.0';
  EditIssuedAt.Text := FormatDateTime(UtcTimestampFormat,
    TTimeZone.Local.ToUniversalTime(Now));

  SaveDialog1.Filter := 'JSON files|*.json';
  SaveDialog1.FileName := 'manifest.json';

  FLastValidationOK := False;
  BtnSaveManifest.Enabled := False; // start locked

  EditAppName.OnChange      := AnyFieldChanged;
  EditVersion.OnChange      := AnyFieldChanged;
  EditDownloadUrl.OnChange  := AnyFieldChanged;
  EditMinVersion.OnChange   := AnyFieldChanged;
  EditIssuedAt.OnChange     := AnyFieldChanged;
  MemoNotes.OnChange        := AnyFieldChanged;
  ComboSeverity.OnChange    := AnyFieldChanged;
  EditZip.OnChange          := AnyFieldChanged;

  PanelStatus.Color := clBtnFace;
  LabelStatusIcon.Caption := #$25FB;
  LabelStatusText.Caption := 'Not validated';
end;

function TManifestGeneratorForm.CalcSHA256(AStream: TStream): string;
begin
  Result := 'sha256:' + THashSHA2.GetHashString(AStream, SHA256);
end;

function TManifestGeneratorForm.CalcSHA256(const AFileName: string): string;
var
  LStream: TFileStream;
begin
  LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := CalcSHA256(LStream);
  finally
    LStream.Free;
  end;
end;

procedure TManifestGeneratorForm.ReadFileInfo(const FileName: string);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    FFileSize := FS.Size;
    Application.ProcessMessages;

    FS.Position := 0;
    FChecksum := CalcSHA256(FS);
  finally
    FS.Free;
  end;
end;

procedure TManifestGeneratorForm.BtnSelectZipClick(Sender: TObject);
begin
  OpenDialog1.Filter := 'ZIP files|*.zip';
  if OpenDialog1.Execute then
  begin
    EditZip.Text := OpenDialog1.FileName;
    ReadFileInfo(OpenDialog1.FileName);
  end;
end;

function TManifestGeneratorForm.BuildManifestJSON: string;
var
  Root, AppObj: TJSONObject;
begin
  Root := TJSONObject.Create;
  AppObj := TJSONObject.Create;
  try
    AppObj.AddPair('version', EditVersion.Text);
    AppObj.AddPair('download_url', EditDownloadUrl.Text);
    AppObj.AddPair('file_size', TJSONNumber.Create(FFileSize));
    AppObj.AddPair('checksum', FChecksum);
    AppObj.AddPair('release_notes', MemoNotes.Text);
    AppObj.AddPair('min_version', EditMinVersion.Text);
    AppObj.AddPair('severity', ComboSeverity.Text);
    if Trim(EditIssuedAt.Text) <> '' then
    begin
      AppObj.AddPair('issued_at', Trim(EditIssuedAt.Text));
      AppObj.AddPair('release_date', Trim(EditIssuedAt.Text));
    end;

    Root.AddPair(EditAppName.Text, AppObj);

    Result := Root.Format;
  finally
    Root.Free;
  end;
end;

procedure TManifestGeneratorForm.BtnGenerateClick(Sender: TObject);
begin
  ShowMessage(BuildManifestJSON);
end;

procedure TManifestGeneratorForm.BtnSaveManifestClick(Sender: TObject);
begin
  if not FLastValidationOK then
  begin
    ShowMessage('Please validate the draft first.');
    Exit;
  end;

  if SaveDialog1.Execute then
  begin
    TFile.WriteAllBytes(SaveDialog1.FileName,
      TEncoding.UTF8.GetBytes(BuildManifestJSON));
    FSigningManifestPath := ExpandFileName(SaveDialog1.FileName);
    BtnCopySigningCommand.Enabled := True;
    ShowMessage('Manifest saved. Run the copied signing command before publishing.');
  end;
end;

procedure TManifestGeneratorForm.BtnCopySigningCommandClick(Sender: TObject);
begin
  Clipboard.AsText := 'python generate_manifest.py --signing-key ' +
    QuotedStr('C:\path\to\private-key.pem') + ' --sign-existing ' +
    QuotedStr(FSigningManifestPath);
  ShowMessage('Command copied. Replace the key path and run it in PowerShell from the updater repository.');
end;

procedure TManifestGeneratorForm.BtnValidateClick(Sender: TObject);
var
  Msg: string;
  OK: Boolean;
begin
  OK := ValidateManifest(BuildManifestJSON, '', Msg);
  SetStatusPanel(Msg, OK);
end;

procedure TManifestGeneratorForm.BtnValidateSavedClick(Sender: TObject);
var
  ManifestPath, Msg: string;
begin
  OpenDialog1.Filter := 'JSON files|*.json';
  if not OpenDialog1.Execute then
    Exit;
  ManifestPath := OpenDialog1.FileName;
  try
    ValidateManifest(TFile.ReadAllText(ManifestPath, TEncoding.UTF8), ManifestPath, Msg);
    ShowMessage(Msg);
  except
    on E: Exception do
      ShowMessage('Cannot validate the saved manifest. ' + E.Message);
  end;
end;

function TManifestGeneratorForm.IsValidUrl(const Url: string): Boolean;
begin
  Result := Url.StartsWith('http://') or Url.StartsWith('https://');
end;

function TManifestGeneratorForm.ValidateManifest(const JsonText,
  ManifestPath: string; out Msg: string): Boolean;
var
  Root, AppValue: TJSONValue;
  AppObj: TJSONObject;
  Value, ManifestChecksum, RealChecksum: string;
  ManifestSize, RealSize: Int64;
  IssuedAt: TDateTime;
  Stream: TFileStream;
  Checks: TStringList;
begin
  Result := False;
  Checks := TStringList.Create;
  try
    if ManifestPath = '' then
      Checks.Add('Sign the saved draft before publishing.')
    else if not FileExists(ManifestPath + '.sig') then
      Checks.Add('Warning. The detached .sig file is missing.');

    Root := TJSONObject.ParseJSONValue(JsonText);
    try
      try
        if not (Root is TJSONObject) then
          raise EConvertError.Create('Invalid JSON object.');
        AppValue := TJSONObject(Root).GetValue(EditAppName.Text);
        if not (AppValue is TJSONObject) then
          raise EConvertError.Create('The selected application is missing from the manifest.');
        AppObj := TJSONObject(AppValue);

        if not AppObj.TryGetValue<string>('issued_at', Value) or (Value = '') then
          raise EConvertError.Create('Warning. The issued_at field is missing.');
        if not TryISO8601ToDate(Value, IssuedAt, True) or
           (FormatDateTime(UtcTimestampFormat, IssuedAt) <> Value) then
          raise EConvertError.Create('Use a whole-second UTC timestamp for issued_at.');
        if not AppObj.TryGetValue<string>('version', Value) or (Value = '') then
          raise EConvertError.Create('Missing version.');
        if not AppObj.TryGetValue<string>('download_url', Value) or not IsValidUrl(Value) then
          raise EConvertError.Create('Missing or invalid download URL.');
        if not AppObj.TryGetValue<Int64>('file_size', ManifestSize) or (ManifestSize <= 0) then
          raise EConvertError.Create('Missing or invalid file size.');
        if not AppObj.TryGetValue<string>('checksum', ManifestChecksum) then
          raise EConvertError.Create('Missing checksum.');
        if AppObj.TryGetValue<string>('severity', Value) and
           (Value <> 'optional') and (Value <> 'recommended') and (Value <> 'critical') then
          raise EConvertError.Create('Severity must be optional, recommended, or critical.');
        if not FileExists(EditZip.Text) then
          raise EConvertError.Create('Select the ZIP file to check its size and checksum.');

        Stream := TFileStream.Create(EditZip.Text, fmOpenRead or fmShareDenyWrite);
        try
          RealSize := Stream.Size;
          RealChecksum := CalcSHA256(Stream);
        finally
          Stream.Free;
        end;
        if ManifestSize <> RealSize then
          raise EConvertError.CreateFmt('ZIP file size mismatch. Expected %d bytes, found %d.',
            [ManifestSize, RealSize]);
        if not SameText(ManifestChecksum, RealChecksum) then
          raise EConvertError.Create('ZIP checksum mismatch.');

        Checks.Insert(0, 'Manifest fields, ZIP size and checksum match.');
        Result := True;
      except
        on E: Exception do
          Checks.Insert(0, E.Message);
      end;
    finally
      Root.Free;
    end;
    Msg := TrimRight(Checks.Text);
  finally
    Checks.Free;
  end;
end;

procedure TManifestGeneratorForm.AnyFieldChanged(Sender: TObject);
begin
  FLastValidationOK := False;
  BtnSaveManifest.Enabled := False;

  PanelStatus.Color := clBtnFace;
  LabelStatusIcon.Caption := #$25FB;
  LabelStatusText.Caption := 'Not validated';
end;

procedure TManifestGeneratorForm.SetStatusPanel(const Msg: string; OK: Boolean);
begin
  if OK then
  begin
    PanelStatus.Color := clMoneyGreen;   // big green bar
    LabelStatusIcon.Caption := #$2714;
  end
  else
  begin
    PanelStatus.Color := $00C6E7FF;      // light red/pink
    LabelStatusIcon.Caption := #$274C;
  end;

  LabelStatusText.Caption := Msg;
  FLastValidationOK := OK;
  BtnSaveManifest.Enabled := OK;
end;

end.
