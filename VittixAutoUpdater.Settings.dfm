object UpdateSettingsForm: TUpdateSettingsForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Update Settings'
  ClientHeight = 520
  ClientWidth = 640
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object PageControl: TPageControl
    Left = 8
    Top = 8
    Width = 624
    Height = 465
    ActivePage = TabGeneral
    TabOrder = 0
    object TabGeneral: TTabSheet
      Caption = 'General'
      object GroupGeneral: TGroupBox
        Left = 8
        Top = 8
        Width = 600
        Height = 185
        Caption = 'General Settings'
        TabOrder = 0
        object LblAppName: TLabel
          Left = 16
          Top = 24
          Width = 92
          Height = 13
          Caption = 'Application Name:'
        end
        object LblCheckInterval: TLabel
          Left = 16
          Top = 56
          Width = 119
          Height = 13
          Caption = 'Check for updates every:'
        end
        object LblCheckIntervalUnit: TLabel
          Left = 216
          Top = 56
          Width = 28
          Height = 13
          Caption = 'hours'
        end
        object EditAppName: TEdit
          Left = 144
          Top = 21
          Width = 200
          Height = 21
          TabOrder = 0
          OnChange = OnControlChanged
        end
        object SpinCheckInterval: TSpinEdit
          Left = 144
          Top = 53
          Width = 65
          Height = 22
          MaxValue = 168
          MinValue = 1
          TabOrder = 1
          Value = 24
          OnChange = OnControlChanged
        end
        object ChkAutoDownload: TCheckBox
          Left = 16
          Top = 88
          Width = 200
          Height = 17
          Caption = 'Automatically download updates'
          TabOrder = 2
          OnClick = SetModified
        end
        object ChkAutoInstall: TCheckBox
          Left = 16
          Top = 111
          Width = 200
          Height = 17
          Caption = 'Automatically install updates'
          TabOrder = 3
          OnClick = SetModified
        end
        object ChkAllowDowngrade: TCheckBox
          Left = 16
          Top = 134
          Width = 200
          Height = 17
          Caption = 'Allow version downgrades'
          TabOrder = 4
          OnClick = SetModified
        end
        object ChkStartWithWindows: TCheckBox
          Left = 16
          Top = 157
          Width = 200
          Height = 17
          Caption = 'Start with Windows'
          TabOrder = 5
          OnClick = SetModified
        end
      end
      object GroupNotifications: TGroupBox
        Left = 8
        Top = 208
        Width = 600
        Height = 113
        Caption = 'Notifications'
        TabOrder = 1
        object ChkShowNotifications: TCheckBox
          Left = 16
          Top = 24
          Width = 200
          Height = 17
          Caption = 'Show update notifications'
          Checked = True
          State = cbChecked
          TabOrder = 0
          OnClick = SetModified
        end
        object ChkSoundNotifications: TCheckBox
          Left = 16
          Top = 47
          Width = 200
          Height = 17
          Caption = 'Play notification sounds'
          TabOrder = 1
          OnClick = SetModified
        end
        object ChkMinimizeToTray: TCheckBox
          Left = 16
          Top = 70
          Width = 200
          Height = 17
          Caption = 'Minimize to system tray'
          TabOrder = 2
          OnClick = SetModified
        end
      end
    end
    object TabNetwork: TTabSheet
      Caption = 'Network'
      ImageIndex = 1
      object GroupUrls: TGroupBox
        Left = 8
        Top = 8
        Width = 600
        Height = 169
        Caption = 'Manifest URLs'
        TabOrder = 0
        object LblManifestUrls: TLabel
          Left = 16
          Top = 24
          Width = 73
          Height = 13
          Caption = 'Manifest URLs:'
        end
        object ListManifestUrls: TListBox
          Left = 16
          Top = 43
          Width = 448
          Height = 89
          ItemHeight = 13
          TabOrder = 0
          OnClick = ListManifestUrlsClick
        end
        object EditManifestUrl: TEdit
          Left = 16
          Top = 138
          Width = 350
          Height = 21
          TabOrder = 1
          OnKeyPress = EditManifestUrlKeyPress
        end
        object BtnAddUrl: TButton
          Left = 372
          Top = 136
          Width = 45
          Height = 25
          Caption = 'Add'
          TabOrder = 2
          OnClick = BtnAddUrlClick
        end
        object BtnRemoveUrl: TButton
          Left = 480
          Top = 43
          Width = 65
          Height = 25
          Caption = 'Remove'
          Enabled = False
          TabOrder = 3
          OnClick = BtnRemoveUrlClick
        end
        object BtnEditUrl: TButton
          Left = 480
          Top = 74
          Width = 65
          Height = 25
          Caption = 'Edit'
          Enabled = False
          TabOrder = 4
          OnClick = BtnEditUrlClick
        end
        object BtnTestUrl: TButton
          Left = 480
          Top = 105
          Width = 65
          Height = 25
          Caption = 'Test'
          Enabled = False
          TabOrder = 5
          OnClick = BtnTestUrlClick
        end
      end
      object GroupNetwork: TGroupBox
        Left = 8
        Top = 192
        Width = 280
        Height = 129
        Caption = 'Network Settings'
        TabOrder = 1
        object LblConnectionTimeout: TLabel
          Left = 16
          Top = 24
          Width = 103
          Height = 13
          Caption = 'Connection timeout:'
        end
        object LblTimeoutUnit: TLabel
          Left = 216
          Top = 24
          Width = 40
          Height = 13
          Caption = 'seconds'
        end
        object LblMaxRetries: TLabel
          Left = 16
          Top = 56
          Width = 62
          Height = 13
          Caption = 'Max retries:'
        end
        object LblUserAgent: TLabel
          Left = 16
          Top = 88
          Width = 61
          Height = 13
          Caption = 'User Agent:'
        end
        object SpinConnectionTimeout: TSpinEdit
          Left = 144
          Top = 21
          Width = 65
          Height = 22
          MaxValue = 300
          MinValue = 5
          TabOrder = 0
          Value = 30
          OnChange = OnControlChanged
        end
        object SpinMaxRetries: TSpinEdit
          Left = 144
          Top = 53
          Width = 65
          Height = 22
          MaxValue = 10
          MinValue = 0
          TabOrder = 1
          Value = 3
          OnChange = OnControlChanged
        end
        object EditUserAgent: TEdit
          Left = 16
          Top = 104
          Width = 240
          Height = 21
          TabOrder = 2
          OnChange = OnControlChanged
        end
      end
      object GroupProxy: TGroupBox
        Left = 304
        Top = 192
        Width = 304
        Height = 129
        Caption = 'Proxy Settings'
        TabOrder = 2
        object LblProxyHost: TLabel
          Left = 16
          Top = 48
          Width = 26
          Height = 13
          Caption = 'Host:'
          Enabled = False
        end
        object LblProxyPort: TLabel
          Left = 16
          Top = 75
          Width = 24
          Height = 13
          Caption = 'Port:'
          Enabled = False
        end
        object LblProxyUser: TLabel
          Left = 144
          Top = 48
          Width = 52
          Height = 13
          Caption = 'Username:'
          Enabled = False
        end
        object LblProxyPassword: TLabel
          Left = 144
          Top = 75
          Width = 50
          Height = 13
          Caption = 'Password:'
          Enabled = False
        end
        object ChkUseProxy: TCheckBox
          Left = 16
          Top = 24
          Width = 97
          Height = 17
          Caption = 'Use proxy server'
          TabOrder = 0
          OnClick = ChkUseProxyClick
        end
        object EditProxyHost: TEdit
          Left = 48
          Top = 45
          Width = 80
          Height = 21
          Enabled = False
          TabOrder = 1
          OnChange = OnControlChanged
        end
        object SpinProxyPort: TSpinEdit
          Left = 48
          Top = 72
          Width = 80
          Height = 22
          Enabled = False
          MaxValue = 65535
          MinValue = 1
          TabOrder = 2
          Value = 8080
          OnChange = OnControlChanged
        end
        object EditProxyUser: TEdit
          Left = 200
          Top = 45
          Width = 90
          Height = 21
          Enabled = False
          TabOrder = 3
          OnChange = OnControlChanged
        end
        object EditProxyPassword: TEdit
          Left = 200
          Top = 72
          Width = 90
          Height = 21
          Enabled = False
          PasswordChar = '*'
          TabOrder = 4
          OnChange = OnControlChanged
        end
      end
    end
    object TabAdvanced: TTabSheet
      Caption = 'Advanced'
      ImageIndex = 2
      object GroupPaths: TGroupBox
        Left = 8
        Top = 8
        Width = 600
        Height = 89
        Caption = 'File Paths'
        TabOrder = 0
        object LblTempFolder: TLabel
          Left = 16
          Top = 24
          Width = 90
          Height = 13
          Caption = 'Temporary folder:'
        end
        object LblBackupFolder: TLabel
          Left = 16
          Top = 56
          Width = 74
          Height = 13
          Caption = 'Backup folder:'
        end
        object EditTempFolder: TEdit
          Left = 120
          Top = 21
          Width = 400
          Height = 21
          TabOrder = 0
          OnChange = OnControlChanged
        end
        object BtnBrowseTempFolder: TButton
          Left = 526
          Top = 19
          Width = 60
          Height = 25
          Caption = 'Browse...'
          TabOrder = 1
          OnClick = BtnBrowseTempFolderClick
        end
        object EditBackupFolder: TEdit
          Left = 120
          Top = 53
          Width = 400
          Height = 21
          TabOrder = 2
          OnChange = OnControlChanged
        end
        object BtnBrowseBackupFolder: TButton
          Left = 526
          Top = 51
          Width = 60
          Height = 25
          Caption = 'Browse...'
          TabOrder = 3
          OnClick = BtnBrowseBackupFolderClick
        end
      end
      object GroupSecurity: TGroupBox
        Left = 8
        Top = 112
        Width = 292
        Height = 217
        Caption = 'Security'
        TabOrder = 1
        object LblTrustedPublishers: TLabel
          Left = 16
          Top = 88
          Width = 93
          Height = 13
          Caption = 'Trusted Publishers:'
        end
        object ChkVerifySignature: TCheckBox
          Left = 16
          Top = 24
          Width = 200
          Height = 17
          Caption = 'Verify digital signatures'
          Checked = True
          State = cbChecked
          TabOrder = 0
          OnClick = SetModified
        end
        object ChkVerifyChecksum: TCheckBox
          Left = 16
          Top = 43
          Width = 200
          Height = 17
          Caption = 'Verify file checksums'
          Checked = True
          State = cbChecked
          TabOrder = 1
          OnClick = SetModified
        end
        object ChkRequireHttps: TCheckBox
          Left = 16
          Top = 62
          Width = 200
          Height = 17
          Caption = 'Require HTTPS connections'
          Checked = True
          State = cbChecked
          TabOrder = 2
          OnClick = SetModified
        end
        object ListTrustedPublishers: TCheckListBox
          Left = 16
          Top = 107
          Width = 200
          Height = 73
          ItemHeight = 13
          TabOrder = 3
          OnClick = UpdateControlStates
        end
        object BtnAddPublisher: TButton
          Left = 222
          Top = 107
          Width = 60
          Height = 25
          Caption = 'Add'
          TabOrder = 4
          OnClick = BtnAddPublisherClick
        end
        object BtnRemovePublisher: TButton
          Left = 222
          Top = 138
          Width = 60
          Height = 25
          Caption = 'Remove'
          Enabled = False
          TabOrder = 5
          OnClick = BtnRemovePublisherClick
        end
      end
      object GroupLogging: TGroupBox
        Left = 320
        Top = 112
        Width = 288
        Height = 217
        Caption = 'Logging'
        TabOrder = 2
        object LblLogLevel: TLabel
          Left = 16
          Top = 48
          Width = 52
          Height = 13
          Caption = 'Log Level:'
          Enabled = False
        end
        object LblLogFile: TLabel
          Left = 16
          Top = 80
          Width = 42
          Height = 13
          Caption = 'Log File:'
          Enabled = False
        end
        object LblMaxLogSize: TLabel
          Left = 16
          Top = 112
          Width = 67
          Height = 13
          Caption = 'Max log size:'
          Enabled = False
        end
        object LblLogSizeUnit: TLabel
          Left = 152
          Top = 112
          Width = 14
          Height = 13
          Caption = 'MB'
          Enabled = False
        end
        object ChkEnableLogging: TCheckBox
          Left = 16
          Top = 24
          Width = 97
          Height = 17
          Caption = 'Enable logging'
          TabOrder = 0
          OnClick = ChkEnableLoggingClick
        end
        object ComboLogLevel: TComboBox
          Left = 96
          Top = 45
          Width = 100
          Height = 21
          Style = csDropDownList
          Enabled = False
          ItemHeight = 13
          TabOrder = 1
          OnChange = OnControlChanged
        end
        object EditLogFile: TEdit
          Left = 16
          Top = 96
          Width = 200
          Height = 21
          Enabled = False
          TabOrder = 2
          OnChange = OnControlChanged
        end
        object BtnBrowseLogFile: TButton
          Left = 222
          Top = 94
          Width = 50
          Height = 25
          Caption = 'Browse'
          Enabled = False
          TabOrder = 3
          OnClick = BtnBrowseLogFileClick
        end
        object SpinMaxLogSize: TSpinEdit
          Left = 96
          Top = 109
          Width = 50
          Height = 22
          Enabled = False
          MaxValue = 100
          MinValue = 1
          TabOrder = 4
          Value = 10
          OnChange = OnControlChanged
        end
      end
    end
  end
  object ButtonPanel: TPanel
    Left = 0
    Top = 479
    Width = 640
    Height = 41
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object BtnOK: TButton
      Left = 391
      Top = 8
      Width = 75
      Height = 25
      Caption = 'OK'
      Default = True
      ModalResult = 1
      TabOrder = 0
      OnClick = BtnOKClick
    end
    object BtnCancel: TButton
      Left = 472
      Top = 8
      Width = 75
      Height = 25
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 1
      OnClick = BtnCancelClick
    end
    object BtnApply: TButton
      Left = 553
      Top = 8
      Width = 75
      Height = 25
      Caption = 'Apply'
      Enabled = False
      TabOrder = 2
      OnClick = BtnApplyClick
    end
    object BtnReset: TButton
      Left = 8
      Top = 8
      Width = 75
      Height = 25
      Caption = 'Reset'
      TabOrder = 3
      OnClick = BtnResetClick
    end
  end
  object OpenDialog: TOpenDialog
    Filter = 'All Files (*.*)|*.*'
    Left = 32
    Top = 400
  end
  object SaveDialog: TSaveDialog
    Filter = 'All Files (*.*)|*.*'
    Left = 88
    Top = 400
  end
  object FolderDialog: TFileOpenDialog
    FavoriteLinks = <>
    FileTypes = <>
    Options = [fdoPickFolders, fdoPathMustExist]
    Left = 144
    Top = 400
  end
end
