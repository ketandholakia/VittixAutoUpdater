unit VittixAutoUpdater.ComponentReg;

interface

procedure Register;

implementation

uses
  Classes, DesignEditors, DesignIntf,
  VittixAutoUpdater.Types,
  VittixAutoUpdater.VisualComponent,
  VittixAutoUpdater.PropertyEditors;

procedure Register;
begin
  // Register components on palette
  RegisterComponents('VittixAutoUpdater', [TVittixAutoUpdaterUI]);

  // Register property editors (simplified for compatibility)
  RegisterPropertyEditor(TypeInfo(TUpdaterConfig), TVittixAutoUpdaterUI, 'Config',
    TUpdaterConfigPropertyEditor);
end;

end.
