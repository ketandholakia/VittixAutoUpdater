program VittixAutoUpdaterEnhancedDemo;

uses
  Vcl.Forms,
  VittixAutoUpdaterEnhancedDemo in 'VittixAutoUpdaterEnhancedDemo.pas' {EnhancedDemoForm},
  VittixAutoUpdater.Types in 'VittixAutoUpdater.Types.pas',
  VittixAutoUpdater.Engine in 'VittixAutoUpdater.Engine.pas',
  VittixAutoUpdater.Network in 'VittixAutoUpdater.Network.pas',
  VittixAutoUpdater.VisualComponent in 'VittixAutoUpdater.VisualComponent.pas',
  VittixAutoUpdater.Settings in 'VittixAutoUpdater.Settings.pas' {UpdateSettingsForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'VittixAutoUpdater Enhanced Demo';
  Application.CreateForm(TEnhancedDemoForm, EnhancedDemoForm);
  Application.Run;
end.
