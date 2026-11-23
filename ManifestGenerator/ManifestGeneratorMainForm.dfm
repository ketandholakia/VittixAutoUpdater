object ManifestGeneratorForm: TManifestGeneratorForm
  Left = 0
  Top = 0
  Caption = 'Vittix Manifest Generator'
  ClientHeight = 572
  ClientWidth = 760
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Segoe UI'
  Font.Style = []
  OldCreateOrder = True
  Position = poScreenCenter
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object PanelTop: TPanel
    Left = 0
    Top = 0
    Width = 760
    Height = 56
    Align = alTop
    TabOrder = 0
    object Label1: TLabel
      Left = 16
      Top = 20
      Width = 80
      Height = 13
      Caption = 'Update ZIP File:'
    end
    object EditZip: TEdit
      Left = 100
      Top = 16
      Width = 520
      Height = 21
      TabOrder = 0
    end
    object BtnSelectZip: TButton
      Left = 630
      Top = 14
      Width = 110
      Height = 25
      Caption = 'Select ZIP...'
      TabOrder = 1
      OnClick = BtnSelectZipClick
    end
  end
  object GroupBox1: TGroupBox
    Left = 8
    Top = 64
    Width = 744
    Height = 150
    Caption = 'Application Information'
    TabOrder = 1
    object Label2: TLabel
      Left = 16
      Top = 28
      Width = 53
      Height = 13
      Caption = 'App Name'
    end
    object Label3: TLabel
      Left = 16
      Top = 60
      Width = 38
      Height = 13
      Caption = 'Version'
    end
    object Label4: TLabel
      Left = 16
      Top = 92
      Width = 77
      Height = 13
      Caption = 'Download URL'
    end
    object Label5: TLabel
      Left = 16
      Top = 124
      Width = 61
      Height = 13
      Caption = 'Min Version'
    end
    object EditAppName: TEdit
      Left = 120
      Top = 24
      Width = 600
      Height = 21
      TabOrder = 0
      Text = 'MyApp'
    end
    object EditVersion: TEdit
      Left = 120
      Top = 56
      Width = 200
      Height = 21
      TabOrder = 1
      Text = '1.0.0.0'
    end
    object EditDownloadUrl: TEdit
      Left = 120
      Top = 88
      Width = 600
      Height = 21
      TabOrder = 2
      Text = 'https://updates.yourserver.com/MyApp_update.zip'
    end
    object EditMinVersion: TEdit
      Left = 120
      Top = 120
      Width = 200
      Height = 21
      TabOrder = 3
      Text = '1.0.0.0'
    end
    object LabelIssuedAt: TLabel
      Left = 368
      Top = 124
      Width = 86
      Height = 13
      Caption = 'Issued at (UTC)'
      FocusControl = EditIssuedAt
    end
    object EditIssuedAt: TEdit
      Left = 464
      Top = 120
      Width = 256
      Height = 21
      TabOrder = 4
    end
  end
  object GroupBox2: TGroupBox
    Left = 8
    Top = 218
    Width = 520
    Height = 212
    Caption = 'Release Notes'
    TabOrder = 2
    object MemoNotes: TRichEdit
      Left = 8
      Top = 24
      Width = 504
      Height = 180
      ScrollBars = ssVertical
      TabOrder = 0
    end
  end
  object GroupBox3: TGroupBox
    Left = 536
    Top = 218
    Width = 216
    Height = 120
    Caption = 'Severity'
    TabOrder = 3
    object ComboSeverity: TComboBox
      Left = 16
      Top = 48
      Width = 180
      Height = 21
      Style = csDropDownList
      TabOrder = 0
    end
  end
  object PanelBottom: TPanel
    Left = 0
    Top = 434
    Width = 760
    Height = 138
    Align = alBottom
    TabOrder = 4
    object BtnGenerate: TButton
      Left = 580
      Top = 12
      Width = 160
      Height = 25
      Caption = 'Preview Manifest'
      TabOrder = 1
      OnClick = BtnGenerateClick
    end
    object BtnSaveManifest: TButton
      Left = 580
      Top = 40
      Width = 160
      Height = 25
      Caption = 'Save manifest.json'
      TabOrder = 2
      OnClick = BtnSaveManifestClick
    end
    object BtnValidate: TButton
      Left = 580
      Top = 68
      Width = 160
      Height = 25
      Caption = 'Validate draft'
      TabOrder = 3
      OnClick = BtnValidateClick
    end
    object BtnValidateSaved: TButton
      Left = 580
      Top = 96
      Width = 160
      Height = 25
      Caption = 'Validate saved manifest...'
      TabOrder = 4
      OnClick = BtnValidateSavedClick
    end
    object BtnCopySigningCommand: TButton
      Left = 16
      Top = 92
      Width = 162
      Height = 25
      Caption = 'Copy signing command'
      Enabled = False
      TabOrder = 5
      OnClick = BtnCopySigningCommandClick
    end
    object LabelSigning: TLabel
      Left = 16
      Top = 66
      Width = 540
      Height = 16
      Caption = 'Sign the saved manifest in PowerShell with the copied command before publishing.'
    end
    object PanelStatus: TPanel
      Left = 16
      Top = 12
      Width = 540
      Height = 44
      BevelOuter = bvNone
      TabOrder = 0
      object LabelStatusIcon: TLabel
        Left = 8
        Top = 6
        Width = 39
        Height = 26
        Caption = #226#8212#187
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -19
        Font.Name = 'Segoe UI Emoji'
        Font.Style = []
        ParentFont = False
      end
      object LabelStatusText: TLabel
        Left = 59
        Top = 10
        Width = 470
        Height = 32
        AutoSize = False
        Caption = 'Not validated'
        WordWrap = True
      end
    end
  end
  object SaveDialog1: TSaveDialog
    FileName = 'manifest.json'
    Filter = 'JSON files|*.json'
    Left = 680
    Top = 200
  end
  object OpenDialog1: TOpenDialog
    Filter = 'ZIP files|*.zip'
    Left = 640
    Top = 200
  end
end
