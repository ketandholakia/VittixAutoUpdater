object EnhancedDemoForm: TEnhancedDemoForm
  Left = 0
  Top = 0
  Caption = 'VittixAutoUpdater Demo'
  ClientHeight = 720
  ClientWidth = 960
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
  object TopPanel: TPanel
    Left = 0
    Top = 0
    Width = 960
    Height = 72
    Align = alTop
    BevelOuter = bvNone
    ParentBackground = False
    TabOrder = 0
    object LblTitle: TLabel
      Left = 16
      Top = 12
      Width = 149
      Height = 19
      Caption = 'VittixAutoUpdater Demo'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Tahoma'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object LblVersion: TLabel
      Left = 16
      Top = 39
      Width = 78
      Height = 13
      Caption = 'Version: 0.0.0.0'
    end
    object LblStatus: TLabel
      Left = 200
      Top = 39
      Width = 32
      Height = 13
      Caption = 'Ready'
    end
    object BtnCheck: TButton
      Left = 632
      Top = 20
      Width = 97
      Height = 25
      Caption = 'Check Now'
      TabOrder = 0
      OnClick = BtnCheckClick
    end
    object BtnSettings: TButton
      Left = 736
      Top = 20
      Width = 89
      Height = 25
      Caption = 'Settings'
      TabOrder = 1
      OnClick = BtnSettingsClick
    end
    object BtnReset: TButton
      Left = 832
      Top = 20
      Width = 89
      Height = 25
      Caption = 'Reset'
      TabOrder = 2
      OnClick = BtnResetClick
    end
    object BtnToggleLog: TButton
      Left = 528
      Top = 20
      Width = 97
      Height = 25
      Caption = 'Hide Log'
      TabOrder = 3
      OnClick = BtnToggleLogClick
    end
  end
  object LogPanel: TPanel
    Left = 0
    Top = 520
    Width = 960
    Height = 181
    Align = alBottom
    Caption = 'LogPanel'
    ShowCaption = False
    TabOrder = 1
    object MemoLog: TMemo
      Left = 1
      Top = 1
      Width = 958
      Height = 179
      Align = alClient
      ReadOnly = True
      ScrollBars = ssVertical
      TabOrder = 0
    end
  end
  object UpdaterUI: TVittixAutoUpdaterUI
    Left = 0
    Top = 72
    Width = 960
    Height = 448
    Align = alClient
    Color = clBtnFace
    ParentColor = False
    TabOrder = 2
  end
  object StatusBar: TStatusBar
    Left = 0
    Top = 701
    Width = 960
    Height = 19
    Panels = <>
    SimplePanel = True
  end
end
