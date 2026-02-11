unit ManifestGeneratorMainForm;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Hash, System.JSON, System.IOUtils,
  Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs, Vcl.ComCtrls, Vcl.Graphics,
  Vcl.Controls;

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

    GroupBox2: TGroupBox;
    MemoNotes: TRichEdit;

    GroupBox3: TGroupBox;
    ComboSeverity: TComboBox;

    PanelBottom: TPanel;
    BtnGenerate: TButton;
    BtnSaveManifest: TButton;
    BtnValidate: TButton;
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
    procedure AnyFieldChanged(Sender: TObject);

  private
    FChecksum: string;
    FFileSize: Int64;
    FLastValidationOK: Boolean;

    function IsValidUrl(const Url: string): Boolean;
    function ValidateManifest(const JsonText: string): string;
    function CalcSHA256(AStream: TStream): string; overload;
    function CalcSHA256(const AFileName: string): string; overload;
    procedure ReadFileInfo(const FileName: string);
    function BuildManifestJSON: string;
    function ExtractChecksumFromManifest(const JsonText: string): string;
    function ExtractFileSizeFromManifest(const JsonText: string): Int64;
    procedure AddColoredLine(const Text: string; Color: TColor);
    procedure SetStatusPanel(const Msg: string; OK: Boolean);
  end;

var
  ManifestGeneratorForm: TManifestGeneratorForm;

implementation

{$R *.dfm}

procedure TManifestGeneratorForm.FormCreate(Sender: TObject);
begin
  ComboSeverity.Items.Add('optional');
  ComboSeverity.Items.Add('recommended');
  ComboSeverity.Items.Add('critical');
  ComboSeverity.ItemIndex := 1; // default recommended

  EditMinVersion.Text := '1.0.0.0';
  EditVersion.Text := '1.0.0.0';

  SaveDialog1.Filter := 'JSON files|*.json';
  SaveDialog1.FileName := 'manifest.json';

  FLastValidationOK := False;
  BtnSaveManifest.Enabled := False; // start locked

  EditAppName.OnChange      := AnyFieldChanged;
  EditVersion.OnChange      := AnyFieldChanged;
  EditDownloadUrl.OnChange  := AnyFieldChanged;
  EditMinVersion.OnChange   := AnyFieldChanged;
  MemoNotes.OnChange        := AnyFieldChanged;
  ComboSeverity.OnChange    := AnyFieldChanged;
  EditZip.OnChange          := AnyFieldChanged;

  PanelStatus.Color := clBtnFace;
  LabelStatusIcon.Caption := '◻';
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

function TManifestGeneratorForm.ExtractChecksumFromManifest(
  const JsonText: string): string;
var
  Root, AppObj: TJSONObject;
  LChecksumValue: string;
begin
  Result := '';
  try
    Root := TJSONObject.ParseJSONValue(JsonText) as TJSONObject;
    try
      AppObj := Root.GetValue(EditAppName.Text) as TJSONObject;
      if Assigned(AppObj) then
      begin
        if AppObj.TryGetValue<string>('checksum', LChecksumValue) then
          Result := LChecksumValue;
      end;
    finally
      Root.Free;
    end;
  except
    on E: Exception do
      Result := ''; // Silently fail on parse error
  end;
end;

function TManifestGeneratorForm.ExtractFileSizeFromManifest(
  const JsonText: string): Int64;
var
  Root, AppObj: TJSONObject;
  LFileSizeValue: Int64;
begin
  Result := 0;
  try
    Root := TJSONObject.ParseJSONValue(JsonText) as TJSONObject;
    try
      AppObj := Root.GetValue(EditAppName.Text) as TJSONObject;
      if Assigned(AppObj) then
      begin
        if AppObj.TryGetValue<Int64>('file_size', LFileSizeValue) then
          Result := LFileSizeValue;
      end;
    finally
      Root.Free;
    end;
  except
    on E: Exception do
      Result := 0; // Silently fail on parse error
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
    AppObj.AddPair(
      'release_date',
      DateTimeToStr(Now)
    );

    Root.AddPair(EditAppName.Text, AppObj);

    Result := Root.Format;
  finally
    Root.Free;
  end;
end;

procedure TManifestGeneratorForm.BtnGenerateClick(Sender: TObject);
begin
  MemoNotes.Lines.Add('');
  MemoNotes.Lines.Add('--- MANIFEST PREVIEW ---');
  MemoNotes.Lines.Add(BuildManifestJSON);
end;

procedure TManifestGeneratorForm.BtnSaveManifestClick(Sender: TObject);
begin
  if not FLastValidationOK then
  begin
    ShowMessage('Please validate the manifest first.');
    Exit;
  end;

  if SaveDialog1.Execute then
  begin
    TFile.WriteAllText(
      SaveDialog1.FileName,
      BuildManifestJSON,
      TEncoding.UTF8
    );
    ShowMessage('manifest.json saved successfully!');
  end;
end;

procedure TManifestGeneratorForm.BtnValidateClick(Sender: TObject);
var
  JsonText, Msg: string;
begin
  JsonText := BuildManifestJSON;
  Msg := ValidateManifest(JsonText);

  if Msg.StartsWith('✅') then
    SetStatusPanel(Msg, True)
  else
    SetStatusPanel(Msg, False);

  // Also keep a record in Memo (optional)
  MemoNotes.Lines.Add('');
  MemoNotes.Lines.Add('--- VALIDATION RESULT ---');
  MemoNotes.Lines.Add(Msg);
end;

function TManifestGeneratorForm.IsValidUrl(const Url: string): Boolean;
begin
  Result :=
    Url.StartsWith('http://') or
    Url.StartsWith('https://');
end;

function TManifestGeneratorForm.ValidateManifest(
  const JsonText: string): string;
var
  Root, AppObj: TJSONObject;
  Val: TJSONValue;
  sValue: string;
  iValue: Int64;
  ManifestChecksum: string;
  ManifestSize: Int64;
  RealChecksum: string;
  RealSize: Int64;
  LStream: TFileStream;
begin
  Result := '';

  try
    Root := TJSONObject.ParseJSONValue(JsonText) as TJSONObject;
    try
      if not Assigned(Root) then
        Exit('❌ Invalid JSON format.');

      Val := Root.GetValue(EditAppName.Text);
      if not Assigned(Val) then
        Exit('❌ App name not found in manifest.');

      if not (Val is TJSONObject) then
        Exit('❌ App node is not a JSON object.');

      AppObj := Val as TJSONObject;

      // ---- Basic field checks ----
      if not AppObj.TryGetValue<string>('version', sValue) then
        Exit('❌ Missing: version');

      if not AppObj.TryGetValue<string>('download_url', sValue) then
        Exit('❌ Missing: download_url');

      if not IsValidUrl(sValue) then
        Exit('❌ Invalid download_url (must start with http/https)');

      if not AppObj.TryGetValue<Int64>('file_size', iValue) then
        Exit('❌ Missing or invalid: file_size');

      if not AppObj.TryGetValue<string>('checksum', sValue) then
        Exit('❌ Missing: checksum');

      if AppObj.TryGetValue<string>('severity', sValue) then
      begin
        if not ((sValue = 'optional') or (sValue = 'recommended') or (sValue = 'critical')) then
          Exit('❌ severity must be: optional / recommended / critical');
      end;

      // ---- CROSS-CHECK WITH REAL ZIP ----
      if not FileExists(EditZip.Text) then
        Exit('⚠ ZIP file not selected — cannot cross-check size/checksum.');

      LStream := TFileStream.Create(EditZip.Text, fmOpenRead or fmShareDenyWrite);
      try
        RealSize := LStream.Size;
        RealChecksum := CalcSHA256(LStream);
      finally
        LStream.Free;
      end;

      ManifestChecksum := ExtractChecksumFromManifest(JsonText);
      ManifestSize := ExtractFileSizeFromManifest(JsonText);

      if ManifestSize <> RealSize then
        Exit(Format(
          '❌ File size mismatch:'#13#10 +
          'Manifest: %d bytes'#13#10 +
          'Actual ZIP: %d bytes',
          [ManifestSize, RealSize]));

      if not SameText(ManifestChecksum, RealChecksum) then
        Exit(
          '❌ Checksum mismatch:'#13#10 +
          'Manifest: ' + ManifestChecksum + #13#10 +
          'Actual:   ' + RealChecksum);

      Result := '✅ Manifest is VALID.' + sLineBreak +
                'File size and checksum match the ZIP.';

    finally
      Root.Free;
    end;

  except
    on E: Exception do
      Result := '❌ JSON parse error: ' + E.Message;
  end;
end;

procedure TManifestGeneratorForm.AddColoredLine(
  const Text: string; Color: TColor);
begin
  MemoNotes.SelStart := Length(MemoNotes.Text);
  MemoNotes.SelAttributes.Color := Color;
  MemoNotes.Lines.Add(Text);
end;

procedure TManifestGeneratorForm.AnyFieldChanged(Sender: TObject);
begin
  FLastValidationOK := False;
  BtnSaveManifest.Enabled := False;

  PanelStatus.Color := clBtnFace;
  LabelStatusIcon.Caption := '◻';
  LabelStatusText.Caption := 'Not validated';
end;

procedure TManifestGeneratorForm.SetStatusPanel(const Msg: string; OK: Boolean);
begin
  if OK then
  begin
    PanelStatus.Color := clMoneyGreen;   // big green bar
    LabelStatusIcon.Caption := '✔';
  end
  else
  begin
    PanelStatus.Color := $00C6E7FF;      // light red/pink
    LabelStatusIcon.Caption := '❌';
  end;

  LabelStatusText.Caption := Msg;
  FLastValidationOK := OK;
  BtnSaveManifest.Enabled := OK;
end;

end.
