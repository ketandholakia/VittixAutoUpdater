object EnhancedDemoForm: TEnhancedDemoForm
  Left = 0
  Top = 0
  Caption = 'VittixAutoUpdater Enhanced Demo'
  ClientHeight = 700
  ClientWidth = 800
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Menu = MainMenu
  OldCreateOrder = False
  Position = poScreenCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object MainPanel: TPanel
    Left = 0
    Top = 26
    Width = 800
    Height = 655
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 0
    object LogSplitter: TSplitter
      Left = 0
      Top = 502
      Width = 800
      Height = 3
      Cursor = crVSplit
      Align = alBottom
      Color = clBtnFace
      ParentColor = False
      Visible = False
      ExplicitTop = 475
      ExplicitWidth = 624
    end
    object InfoPanel: TPanel
      Left = 0
      Top = 0
      Width = 800
      Height = 65
      Align = alTop
      BevelOuter = bvLowered
      Color = clWindow
      ParentBackground = False
      TabOrder = 0
      object LblAppTitle: TLabel
        Left = 16
        Top = 8
        Width = 200
        Height = 16
        Caption = 'VittixAutoUpdater Demo'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -13
        Font.Name = 'Tahoma'
        Font.Style = [fsBold]
        ParentFont = False
      end
      object LblVersion: TLabel
        Left = 16
        Top = 28
        Width = 78
        Height = 13
        Caption = 'Version: 1.0.0.0'
      end
      object LblStatus: TLabel
        Left = 16
        Top = 45
        Width = 32
        Height = 13
        Caption = 'Ready'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGreen
        Font.Height = -11
        Font.Name = 'Tahoma'
        Font.Style = []
        ParentFont = False
      end
    end
    object UpdaterUI: TVittixAutoUpdaterUI
      Left = 0
      Top = 65
      Width = 800
      Height = 437
      Align = alClient
      Color = clBtnFace
      ParentColor = False
      TabOrder = 1
    end
    object LogPanel: TPanel
      Left = 0
      Top = 505
      Width = 800
      Height = 150
      Align = alBottom
      BevelOuter = bvNone
      TabOrder = 2
      Visible = False
      object LblLog: TLabel
        Left = 8
        Top = 8
        Width = 67
        Height = 13
        Caption = 'Activity Log:'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Tahoma'
        Font.Style = [fsBold]
        ParentFont = False
      end
      object MemoLog: TMemo
        Left = 8
        Top = 24
        Width = 784
        Height = 118
        Anchors = [akLeft, akTop, akRight, akBottom]
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Courier New'
        Font.Style = []
        ParentFont = False
        ReadOnly = True
        ScrollBars = ssVertical
        TabOrder = 0
        WordWrap = False
      end
    end
  end
  object ToolBar: TToolBar
    Left = 0
    Top = 0
    Width = 800
    Height = 26
    ButtonHeight = 21
    ButtonWidth = 50
    Caption = 'ToolBar'
    Images = ImageList
    TabOrder = 1
    object ToolBtnCheck: TToolButton
      Left = 0
      Top = 0
      Action = ActCheckNow
      Caption = 'Check'
      ImageIndex = 0
    end
    object ToolBtnSeparator1: TToolButton
      Left = 50
      Top = 0
      Width = 8
      Caption = 'ToolBtnSeparator1'
      ImageIndex = 1
      Style = tbsSeparator
    end
    object ToolBtnSettings: TToolButton
      Left = 58
      Top = 0
      Action = ActSettings
      Caption = 'Settings'
      ImageIndex = 1
    end
    object ToolBtnSeparator2: TToolButton
      Left = 108
      Top = 0
      Width = 8
      Caption = 'ToolBtnSeparator2'
      ImageIndex = 2
      Style = tbsSeparator
    end
    object ToolBtnViewCompact: TToolButton
      Left = 116
      Top = 0
      Action = ActViewCompact
      Caption = 'Compact'
      ImageIndex = 2
      Style = tbsCheck
    end
    object ToolBtnViewStandard: TToolButton
      Left = 166
      Top = 0
      Action = ActViewStandard
      Caption = 'Standard'
      ImageIndex = 3
      Style = tbsCheck
    end
    object ToolBtnViewDetailed: TToolButton
      Left = 216
      Top = 0
      Action = ActViewDetailed
      Caption = 'Detailed'
      ImageIndex = 4
      Style = tbsCheck
    end
  end
  object StatusBar: TStatusBar
    Left = 0
    Top = 681
    Width = 800
    Height = 19
    Panels = <
      item
        Text = 'Ready'
        Width = 300
      end
      item
        Text = 'No updates available'
        Width = 200
      end
      item
        Width = 50
      end>
  end
  object MainMenu: TMainMenu
    Left = 32
    Top = 120
    object MenuFile: TMenuItem
      Caption = '&File'
      object MenuCheckNow: TMenuItem
        Action = ActCheckNow
      end
      object N1: TMenuItem
        Caption = '-'
      end
      object MenuExit: TMenuItem
        Action = ActExit
      end
    end
    object MenuEdit: TMenuItem
      Caption = '&Edit'
      object MenuSettings: TMenuItem
        Action = ActSettings
      end
    end
    object MenuView: TMenuItem
      Caption = '&View'
      object MenuViewStyle: TMenuItem
        Caption = 'UI Style'
        object MenuCompact: TMenuItem
          Action = ActViewCompact
          AutoCheck = True
          GroupIndex = 1
          RadioItem = True
        end
        object MenuStandard: TMenuItem
          Action = ActViewStandard
          AutoCheck = True
          Checked = True
          GroupIndex = 1
          RadioItem = True
        end
        object MenuDetailed: TMenuItem
          Action = ActViewDetailed
          AutoCheck = True
          GroupIndex = 1
          RadioItem = True
        end
      end
      object N2: TMenuItem
        Caption = '-'
      end
      object MenuShowReleaseNotes: TMenuItem
        Action = ActShowReleaseNotes
        AutoCheck = True
      end
      object MenuShowProgressDetails: TMenuItem
        Action = ActShowProgressDetails
        AutoCheck = True
      end
    end
    object MenuTools: TMenuItem
      Caption = '&Tools'
      object MenuAutoCheck: TMenuItem
        Action = ActAutoCheck
        AutoCheck = True
      end
      object N3: TMenuItem
        Caption = '-'
      end
      object MenuTestConnection: TMenuItem
        Action = ActTestConnection
      end
      object MenuResetUpdater: TMenuItem
        Action = ActResetUpdater
      end
    end
    object MenuHelp: TMenuItem
      Caption = '&Help'
      object MenuManual: TMenuItem
        Action = ActShowManual
      end
      object MenuAbout: TMenuItem
        Action = ActAbout
      end
    end
  end
  object ActionList: TActionList
    Images = ImageList
    Left = 88
    Top = 120
    object ActExit: TAction
      Category = 'File'
      Caption = 'E&xit'
      Hint = 'Exit application'
      ShortCut = 32883
      OnExecute = ActExitExecute
    end
    object ActCheckNow: TAction
      Category = 'File'
      Caption = '&Check for Updates'
      Hint = 'Check for updates now'
      ImageIndex = 0
      ShortCut = 116
      OnExecute = ActCheckNowExecute
    end
    object ActSettings: TAction
      Category = 'Edit'
      Caption = '&Settings...'
      Hint = 'Configure updater settings'
      ImageIndex = 1
      ShortCut = 32851
      OnExecute = ActSettingsExecute
    end
    object ActViewCompact: TAction
      Category = 'View'
      Caption = '&Compact'
      Hint = 'Compact view'
      ImageIndex = 2
      OnExecute = ActViewCompactExecute
    end
    object ActViewStandard: TAction
      Category = 'View'
      Caption = '&Standard'
      Hint = 'Standard view'
      ImageIndex = 3
      OnExecute = ActViewStandardExecute
    end
    object ActViewDetailed: TAction
      Category = 'View'
      Caption = '&Detailed'
      Hint = 'Detailed view'
      ImageIndex = 4
      OnExecute = ActViewDetailedExecute
    end
    object ActShowReleaseNotes: TAction
      Category = 'View'
      Caption = 'Show &Release Notes'
      Hint = 'Show/hide release notes panel'
      OnExecute = ActShowReleaseNotesExecute
    end
    object ActShowProgressDetails: TAction
      Category = 'View'
      Caption = 'Show &Progress Details'
      Hint = 'Show/hide progress details'
      OnExecute = ActShowProgressDetailsExecute
    end
    object ActAutoCheck: TAction
      Category = 'Tools'
      Caption = '&Auto Check'
      Hint = 'Enable automatic update checking'
      OnExecute = ActAutoCheckExecute
    end
    object ActResetUpdater: TAction
      Category = 'Tools'
      Caption = '&Reset Updater'
      Hint = 'Reset updater to initial state'
      OnExecute = ActResetUpdaterExecute
    end
    object ActTestConnection: TAction
      Category = 'Tools'
      Caption = '&Test Connection'
      Hint = 'Test connection to update servers'
      OnExecute = ActTestConnectionExecute
    end
    object ActAbout: TAction
      Category = 'Help'
      Caption = '&About...'
      Hint = 'Show about dialog'
      OnExecute = ActAboutExecute
    end
    object ActShowManual: TAction
      Category = 'Help'
      Caption = 'User &Manual'
      Hint = 'Open user manual'
      OnExecute = ActShowManualExecute
    end
  end
  object ImageList: TImageList
    Left = 144
    Top = 120
    ColorDepth = cd16x16
    Height = 16
    Width = 16
  end
  object ApplicationEvents: TApplicationEvents
    OnMinimize = ApplicationEventsMinimize
    Left = 200
    Top = 120
  end
  object TaskBar: TTaskbar
    Left = 256
    Top = 120
  end
end
