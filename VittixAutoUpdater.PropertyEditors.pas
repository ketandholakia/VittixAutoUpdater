unit VittixAutoUpdater.PropertyEditors;

interface

uses
  Classes, SysUtils, TypInfo,
  Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs,
  {$IFDEF VER150} // Delphi 7
  DsgnIntf,
  {$ELSE}
  DesignEditors, DesignIntf,
  {$ENDIF}
  VittixAutoUpdater.Types, VittixAutoUpdater.Settings;

type
  // Property editor for TUpdaterConfig
  TUpdaterConfigPropertyEditor = class(TPropertyEditor)
  public
    procedure Edit; override;
    function GetAttributes: TPropertyAttributes; override;
    function GetValue: string; override;
  end;

  // Custom dialog for editing updater configuration
  TUpdaterConfigEditorForm = class(TForm)
    PageControl: TPageControl;
    TabGeneral: TTabSheet;
    TabUrls: TTabSheet;
    TabAdvanced: TTabSheet;
    ButtonPanel: TPanel;
    BtnOK: TButton;
    BtnCancel: TButton;

    // General tab
    LblAppName: TLabel;
    EditAppName: TEdit;
    LblCheckInterval: TLabel;
    EditCheckInterval: TEdit;
    ChkAutoDownload: TCheckBox;
    ChkAutoInstall: TCheckBox;

    // URLs tab
    LblUrls: TLabel;
    MemoUrls: TMemo;
    BtnAddUrl: TButton;
    BtnRemoveUrl: TButton;

    // Advanced tab
    LblTempFolder: TLabel;
    EditTempFolder: TEdit;
    BtnBrowse: TButton;
    LblTimeout: TLabel;
    EditTimeout: TEdit;
    LblRetries: TLabel;
    EditRetries: TEdit;

    procedure FormCreate(Sender: TObject);
    procedure BtnOKClick(Sender: TObject);
    procedure BtnAddUrlClick(Sender: TObject);
    procedure BtnRemoveUrlClick(Sender: TObject);
    procedure BtnBrowseClick(Sender: TObject);

  private
    FConfig: TUpdaterConfig;
    procedure LoadConfig(const Config: TUpdaterConfig);
    procedure SaveConfig(var Config: TUpdaterConfig);
    procedure UpdateControls;

  public
    class function EditConfig(var Config: TUpdaterConfig): Boolean;
  end;

implementation

uses
  Vcl.FileCtrl, VittixAutoUpdater.VisualComponent;

{ TUpdaterConfigPropertyEditor }

procedure TUpdaterConfigPropertyEditor.Edit;
var
  Config: TUpdaterConfig;
  Component: TPersistent;
begin
  Component := GetComponent(0);
  if Component is TVittixAutoUpdaterUI then
  begin
    Config := TVittixAutoUpdaterUI(Component).Config;

    if TUpdaterConfigEditorForm.EditConfig(Config) then
    begin
      TVittixAutoUpdaterUI(Component).Config := Config;
      Designer.Modified;
    end;
  end;
end;

function TUpdaterConfigPropertyEditor.GetAttributes: TPropertyAttributes;
begin
  Result := [paDialog, paReadOnly];
end;

function TUpdaterConfigPropertyEditor.GetValue: string;
var
  Config: TUpdaterConfig;
  Component: TPersistent;
begin
  Component := GetComponent(0);
  if Component is TVittixAutoUpdaterUI then
  begin
    Config := TVittixAutoUpdaterUI(Component).Config;
    if Config.AppName <> '' then
      Result := Format('%s (%d URLs)', [Config.AppName, Length(Config.ManifestUrls)])
    else
      Result := Format('(Config with %d URLs)', [Length(Config.ManifestUrls)]);
  end
  else
    Result := '(Config)';
end;

{ TManifestUrlsPropertyEditor }



{ TUpdaterConfigEditorForm }

procedure TUpdaterConfigEditorForm.FormCreate(Sender: TObject);
begin
  Caption := 'Updater Configuration Editor';
  Width := 500;
  Height := 400;
  Position := poScreenCenter;
  BorderStyle := bsDialog;

  // Create page control
  PageControl := TPageControl.Create(Self);
  PageControl.Parent := Self;
  PageControl.Left := 8;
  PageControl.Top := 8;
  PageControl.Width := ClientWidth - 16;
  PageControl.Height := ClientHeight - 50;
  PageControl.Anchors := [akLeft, akTop, akRight, akBottom];

  // Create tabs
  TabGeneral := TTabSheet.Create(Self);
  TabGeneral.Caption := 'General';
  TabGeneral.PageControl := PageControl;

  TabUrls := TTabSheet.Create(Self);
  TabUrls.Caption := 'URLs';
  TabUrls.PageControl := PageControl;

  TabAdvanced := TTabSheet.Create(Self);
  TabAdvanced.Caption := 'Advanced';
  TabAdvanced.PageControl := PageControl;

  // Create button panel
  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Left := 0;
  ButtonPanel.Top := ClientHeight - 42;
  ButtonPanel.Width := ClientWidth;
  ButtonPanel.Height := 42;
  ButtonPanel.Align := alBottom;
  ButtonPanel.BevelOuter := bvNone;

  BtnOK := TButton.Create(Self);
  BtnOK.Parent := ButtonPanel;
  BtnOK.Caption := 'OK';
  BtnOK.Left := ClientWidth - 170;
  BtnOK.Top := 8;
  BtnOK.Width := 75;
  BtnOK.Height := 25;
  BtnOK.Anchors := [akTop, akRight];
  BtnOK.Default := True;
  BtnOK.ModalResult := mrOK;
  BtnOK.OnClick := BtnOKClick;

  BtnCancel := TButton.Create(Self);
  BtnCancel.Parent := ButtonPanel;
  BtnCancel.Caption := 'Cancel';
  BtnCancel.Left := ClientWidth - 85;
  BtnCancel.Top := 8;
  BtnCancel.Width := 75;
  BtnCancel.Height := 25;
  BtnCancel.Anchors := [akTop, akRight];
  BtnCancel.Cancel := True;
  BtnCancel.ModalResult := mrCancel;

  // General tab controls
  LblAppName := TLabel.Create(Self);
  LblAppName.Parent := TabGeneral;
  LblAppName.Caption := 'Application Name:';
  LblAppName.Left := 16;
  LblAppName.Top := 16;

  EditAppName := TEdit.Create(Self);
  EditAppName.Parent := TabGeneral;
  EditAppName.Left := 16;
  EditAppName.Top := 32;
  EditAppName.Width := 200;

  LblCheckInterval := TLabel.Create(Self);
  LblCheckInterval.Parent := TabGeneral;
  LblCheckInterval.Caption := 'Check Interval (hours):';
  LblCheckInterval.Left := 16;
  LblCheckInterval.Top := 64;

  EditCheckInterval := TEdit.Create(Self);
  EditCheckInterval.Parent := TabGeneral;
  EditCheckInterval.Left := 16;
  EditCheckInterval.Top := 80;
  EditCheckInterval.Width := 100;
  EditCheckInterval.Text := '24';

  ChkAutoDownload := TCheckBox.Create(Self);
  ChkAutoDownload.Parent := TabGeneral;
  ChkAutoDownload.Caption := 'Auto Download';
  ChkAutoDownload.Left := 16;
  ChkAutoDownload.Top := 112;

  ChkAutoInstall := TCheckBox.Create(Self);
  ChkAutoInstall.Parent := TabGeneral;
  ChkAutoInstall.Caption := 'Auto Install';
  ChkAutoInstall.Left := 16;
  ChkAutoInstall.Top := 136;

  // URLs tab controls
  LblUrls := TLabel.Create(Self);
  LblUrls.Parent := TabUrls;
  LblUrls.Caption := 'Manifest URLs (one per line):';
  LblUrls.Left := 16;
  LblUrls.Top := 16;

  MemoUrls := TMemo.Create(Self);
  MemoUrls.Parent := TabUrls;
  MemoUrls.Left := 16;
  MemoUrls.Top := 32;
  MemoUrls.Width := TabUrls.Width - 120;
  MemoUrls.Height := TabUrls.Height - 80;
  MemoUrls.Anchors := [akLeft, akTop, akRight, akBottom];
  MemoUrls.ScrollBars := ssVertical;

  BtnAddUrl := TButton.Create(Self);
  BtnAddUrl.Parent := TabUrls;
  BtnAddUrl.Caption := 'Add URL';
  BtnAddUrl.Left := TabUrls.Width - 90;
  BtnAddUrl.Top := 32;
  BtnAddUrl.Width := 75;
  BtnAddUrl.Anchors := [akTop, akRight];
  BtnAddUrl.OnClick := BtnAddUrlClick;

  BtnRemoveUrl := TButton.Create(Self);
  BtnRemoveUrl.Parent := TabUrls;
  BtnRemoveUrl.Caption := 'Remove';
  BtnRemoveUrl.Left := TabUrls.Width - 90;
  BtnRemoveUrl.Top := 64;
  BtnRemoveUrl.Width := 75;
  BtnRemoveUrl.Anchors := [akTop, akRight];
  BtnRemoveUrl.OnClick := BtnRemoveUrlClick;

  // Advanced tab controls
  LblTempFolder := TLabel.Create(Self);
  LblTempFolder.Parent := TabAdvanced;
  LblTempFolder.Caption := 'Temporary Folder:';
  LblTempFolder.Left := 16;
  LblTempFolder.Top := 16;

  EditTempFolder := TEdit.Create(Self);
  EditTempFolder.Parent := TabAdvanced;
  EditTempFolder.Left := 16;
  EditTempFolder.Top := 32;
  EditTempFolder.Width := 250;

  BtnBrowse := TButton.Create(Self);
  BtnBrowse.Parent := TabAdvanced;
  BtnBrowse.Caption := 'Browse...';
  BtnBrowse.Left := 275;
  BtnBrowse.Top := 30;
  BtnBrowse.Width := 75;
  BtnBrowse.OnClick := BtnBrowseClick;

  LblTimeout := TLabel.Create(Self);
  LblTimeout.Parent := TabAdvanced;
  LblTimeout.Caption := 'Connection Timeout (sec):';
  LblTimeout.Left := 16;
  LblTimeout.Top := 64;

  EditTimeout := TEdit.Create(Self);
  EditTimeout.Parent := TabAdvanced;
  EditTimeout.Left := 16;
  EditTimeout.Top := 80;
  EditTimeout.Width := 100;
  EditTimeout.Text := '30';

  LblRetries := TLabel.Create(Self);
  LblRetries.Parent := TabAdvanced;
  LblRetries.Caption := 'Max Retries:';
  LblRetries.Left := 150;
  LblRetries.Top := 64;

  EditRetries := TEdit.Create(Self);
  EditRetries.Parent := TabAdvanced;
  EditRetries.Left := 150;
  EditRetries.Top := 80;
  EditRetries.Width := 100;
  EditRetries.Text := '3';
end;

procedure TUpdaterConfigEditorForm.LoadConfig(const Config: TUpdaterConfig);
var
  i: Integer;
begin
  FConfig := Config;

  // General
  EditAppName.Text := Config.AppName;
  EditCheckInterval.Text := IntToStr(Config.CheckInterval);
  ChkAutoDownload.Checked := Config.AutoDownload;
  ChkAutoInstall.Checked := Config.AutoInstall;

  // URLs
  MemoUrls.Lines.Clear;
  for i := 0 to Length(Config.ManifestUrls) - 1 do
    MemoUrls.Lines.Add(Config.ManifestUrls[i]);

  // Advanced
  EditTempFolder.Text := Config.TempFolder;
  EditTimeout.Text := IntToStr(Config.ConnectionTimeout);
  EditRetries.Text := IntToStr(Config.MaxRetries);
end;

procedure TUpdaterConfigEditorForm.SaveConfig(var Config: TUpdaterConfig);
var
  i: Integer;
begin
  // General
  Config.AppName := EditAppName.Text;
  Config.CheckInterval := StrToIntDef(EditCheckInterval.Text, 24);
  Config.AutoDownload := ChkAutoDownload.Checked;
  Config.AutoInstall := ChkAutoInstall.Checked;

  // URLs
  SetLength(Config.ManifestUrls, MemoUrls.Lines.Count);
  for i := 0 to MemoUrls.Lines.Count - 1 do
    Config.ManifestUrls[i] := Trim(MemoUrls.Lines[i]);

  // Advanced
  Config.TempFolder := EditTempFolder.Text;
  Config.ConnectionTimeout := StrToIntDef(EditTimeout.Text, 30);
  Config.MaxRetries := StrToIntDef(EditRetries.Text, 3);
end;

procedure TUpdaterConfigEditorForm.UpdateControls;
begin
  BtnRemoveUrl.Enabled := MemoUrls.Lines.Count > 0;
end;

procedure TUpdaterConfigEditorForm.BtnOKClick(Sender: TObject);
begin
  SaveConfig(FConfig);
end;

procedure TUpdaterConfigEditorForm.BtnAddUrlClick(Sender: TObject);
var
  Url: string;
begin
  if InputQuery('Add URL', 'Enter manifest URL:', Url) then
  begin
    if Trim(Url) <> '' then
      MemoUrls.Lines.Add(Trim(Url));
    UpdateControls;
  end;
end;

procedure TUpdaterConfigEditorForm.BtnRemoveUrlClick(Sender: TObject);
begin
  if (MemoUrls.SelStart >= 0) and (MemoUrls.Lines.Count > 0) then
  begin
    MemoUrls.Lines.Delete(MemoUrls.CaretPos.Y);
    UpdateControls;
  end;
end;

procedure TUpdaterConfigEditorForm.BtnBrowseClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := EditTempFolder.Text;
  if SelectDirectory('Select Temporary Folder', '', Dir) then
    EditTempFolder.Text := Dir;
end;

class function TUpdaterConfigEditorForm.EditConfig(var Config: TUpdaterConfig): Boolean;
begin
  with TUpdaterConfigEditorForm.Create(nil) do
  try
    LoadConfig(Config);
    Result := ShowModal = mrOK;
    if Result then
      Config := FConfig;
  finally
    Free;
  end;
end;

end.
