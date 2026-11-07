object EnhancedDemoForm: TEnhancedDemoForm
  Left = 0
  Top = 0
  Caption = 'VittixAutoUpdater Demo'
  ClientHeight = 720
  ClientWidth = 960
  Color = clBtnFace
  Constraints.MinHeight = 560
  Constraints.MinWidth = 900
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnResize = FormResize
  PixelsPerInch = 96
  TextHeight = 13
  object TopPanel: TPanel
    Left = 0
    Top = 0
    Width = 960
    Height = 88
    Align = alTop
    BevelOuter = bvNone
    ParentBackground = False
    TabOrder = 0
    object HeaderTextPanel: TPanel
      Left = 0
      Top = 0
      Width = 520
      Height = 88
      Align = alClient
      BevelOuter = bvNone
      ParentBackground = False
      Padding.Left = 16
      Padding.Top = 8
      Padding.Right = 8
      Padding.Bottom = 6
      TabOrder = 0
      object LblTitle: TLabel
        Left = 16
        Top = 8
        Width = 300
        Height = 24
        Align = alTop
        AutoSize = False
        Caption = 'VittixAutoUpdater Demo'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -16
        Font.Name = 'Tahoma'
        Font.Style = [fsBold]
        Layout = tlCenter
        ParentFont = False
      end
      object LblStatus: TLabel
        Left = 16
        Top = 32
        Width = 420
        Height = 24
        Align = alTop
        Alignment = taLeftJustify
        AutoSize = False
        Caption = 'Ready'
        Layout = tlCenter
        WordWrap = True
      end
      object LblVersion: TLabel
        Left = 16
        Top = 56
        Width = 180
        Height = 18
        Align = alTop
        AutoSize = False
        Caption = 'Version: 0.0.0.0'
        Layout = tlCenter
      end
    end
    object HeaderActionsPanel: TFlowPanel
      Left = 520
      Top = 0
      Width = 424
      Height = 88
      Align = alRight
      AutoWrap = False
      BevelOuter = bvNone
      FlowStyle = fsLeftRightTopBottom
      Padding.Left = 8
      Padding.Top = 8
      Padding.Right = 8
      Padding.Bottom = 8
      ParentBackground = False
      ShowCaption = False
      TabOrder = 0
      object BtnToggleLog: TButton
        Left = 0
        Top = 0
        Width = 100
        Height = 30
        Caption = 'Hide Log'
        Margins.Left = 4
        Margins.Top = 8
        Margins.Right = 4
        TabOrder = 0
        OnClick = BtnToggleLogClick
      end
      object BtnCheck: TButton
        Left = 0
        Top = 0
        Width = 100
        Height = 30
        Caption = 'Check Now'
        Margins.Left = 4
        Margins.Top = 8
        Margins.Right = 4
        TabOrder = 1
        OnClick = BtnCheckClick
      end
      object BtnSettings: TButton
        Left = 0
        Top = 0
        Width = 96
        Height = 30
        Caption = 'Settings'
        Margins.Left = 4
        Margins.Top = 8
        Margins.Right = 4
        TabOrder = 2
        OnClick = BtnSettingsClick
      end
      object BtnReset: TButton
        Left = 0
        Top = 0
        Width = 80
        Height = 30
        Caption = 'Reset'
        Margins.Left = 4
        Margins.Top = 8
        Margins.Right = 4
        TabOrder = 3
        OnClick = BtnResetClick
      end
    end
  end
  object LogPanel: TPanel
    Left = 0
    Top = 520
    Width = 960
    Height = 181
    Align = alBottom
    Caption = ''
    ShowCaption = False
    TabOrder = 1
    object MemoLog: TMemo
      Left = 9
      Top = 7
      Width = 942
      Height = 167
      Align = alClient
      AlignWithMargins = True
      ReadOnly = True
      ScrollBars = ssVertical
      TabOrder = 0
      WordWrap = True
      Margins.Left = 8
      Margins.Top = 6
      Margins.Right = 8
      Margins.Bottom = 6
    end
  end
  object UpdaterUI: TVittixAutoUpdaterUI
    Left = 0
    Top = 88
    Width = 960
    Height = 432
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
    Align = alBottom
    Panels = <>
    SimplePanel = True
  end
end
