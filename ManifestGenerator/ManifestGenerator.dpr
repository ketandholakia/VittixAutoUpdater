program ManifestGenerator;

uses
  Vcl.Forms,
  ManifestGeneratorMainForm in 'ManifestGeneratorMainForm.pas' {ManifestGeneratorForm};


{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TManifestGeneratorForm, ManifestGeneratorForm);
  Application.Run;
end.
