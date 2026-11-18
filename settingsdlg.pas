unit SettingsDlg;

{ "ตั้งค่าเครื่องนี้": the name and icon other machines see.
  Drawn with BGRABitmap like the rest of the UI. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, StdCtrls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes, UITheme, UIWidgets, LanNet;

type
  { grid of device icons + row of colours + preview }
  TIconPicker = class(TBGRAControl)
  private
    FKindRects: array[0..7] of TRect;
    FColorRects: array[0..DEVICE_COLOR_COUNT - 1] of TRect;
    FHotKind, FHotColor: Integer;
  protected
    procedure Render(B: TBGRABitmap); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    SelKind, SelColor: Integer;
    PreviewName: string;
    constructor Create(AOwner: TComponent); override;
  end;

  { row of theme cards, each a small preview of its palette }
  TThemePicker = class(TBGRAControl)
  private
    FRects: array[TThemeKind] of TRect;
    FHot: Integer;
  protected
    procedure Render(B: TBGRABitmap); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    Selected: TThemeKind;
    constructor Create(AOwner: TComponent); override;
  end;

  TSettingsDialog = class(TForm)
  private
    FPanel: TBGRAControl;
    FEdit: TEdit;
    FPicker: TIconPicker;
    FThemes: TThemePicker;
    FHostName: string;
    procedure EditChange(Sender: TObject);
    procedure AnonClick(Sender: TObject);
    procedure HostClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  public
    constructor CreateDlg(AOwner: TComponent; const AName, AIcon, AHostName: string;
      ATheme: TThemeKind);
    function NameValue: string;
    function IconValue: string;
    function ThemeValue: TThemeKind;
  end;

{ shows the dialog; returns True and the new values when saved }
function EditIdentity(AOwner: TComponent; var AName, AIcon: string;
  var ATheme: TThemeKind; const AHostName: string): Boolean;

implementation

uses
  Math;

function PtIn(const R: TRect; X, Y: Integer): Boolean;
begin
  Result := (X >= R.Left) and (X < R.Right) and (Y >= R.Top) and (Y < R.Bottom);
end;

{ ---------- TIconPicker ---------- }

constructor TIconPicker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BackColor := clPanel;
  FHotKind := -1;
  FHotColor := -1;
end;

procedure TIconPicker.Render(B: TBGRABitmap);
var
  I, Cell, S, X, Y, Cols: Integer;
  R: TRect;
  Icon: string;
begin
  Icon := MakeDeviceIcon(SelKind, SelColor);
  Cols := 4;
  Cell := (B.Width - ScI(8)) div Cols;
  S := ScI(44);
  SetFont(B, 8.5);
  for I := 0 to High(DEVICE_KINDS) do
  begin
    X := (I mod Cols) * Cell + ScI(4);
    Y := (I div Cols) * ScI(84);
    R := Rect(X + ScI(3), Y, X + Cell - ScI(3), Y + ScI(80));
    FKindRects[I] := R;
    if I = SelKind then
    begin
      B.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, Sc(10), Sc(10), clSel);
      B.RoundRectAntialias(R.Left + 0.5, R.Top + 0.5, R.Right - 0.5, R.Bottom - 0.5, Sc(10), Sc(10), clSelBorder, 1.5);
    end
    else if I = FHotKind then
      B.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, Sc(10), Sc(10), clHover);
    DrawDeviceAvatar(B, MakeDeviceIcon(I, SelColor), '', R.Left + (R.Width - S) / 2, R.Top + ScI(8), S, True, False);
    TextIn(B, Rect(R.Left + ScI(2), R.Top + ScI(56), R.Right - ScI(2), R.Bottom - ScI(4)),
      DEVICE_KIND_LABELS[I], IfThen(I = SelKind, clText, clTextDim), taCenter);
  end;

  // colours
  Y := 2 * ScI(84) + ScI(10);
  SetFont(B, 8.5, True);
  B.TextOut(ScI(8), Y, 'สี', clTextDim);
  for I := 0 to DEVICE_COLOR_COUNT - 1 do
  begin
    X := ScI(40) + I * ScI(36);
    FColorRects[I] := Rect(X, Y - ScI(4), X + ScI(30), Y + ScI(26));
    if I = SelColor then
      B.EllipseAntialias(X + ScI(15), Y + ScI(11), Sc(14), Sc(14), BGRAWhite, Sc(2), BGRAPixelTransparent)
    else if I = FHotColor then
      B.EllipseAntialias(X + ScI(15), Y + ScI(11), Sc(14), Sc(14), clTextDim, Sc(1.5), BGRAPixelTransparent);
    B.FillEllipseAntialias(X + ScI(15), Y + ScI(11), Sc(10), Sc(10), DeviceColor(I));
  end;

  // preview: what other machines will see in their sidebar
  Y := Y + ScI(40);
  R := Rect(ScI(4), Y, B.Width - ScI(4), Y + ScI(64));
  B.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, Sc(12), Sc(12), clSide);
  B.RoundRectAntialias(R.Left + 0.5, R.Top + 0.5, R.Right - 0.5, R.Bottom - 0.5, Sc(12), Sc(12), clBorder, 1);
  DrawDeviceAvatar(B, Icon, '', R.Left + ScI(14), R.Top + ScI(14), ScI(36), True, True);
  SetFont(B, 10, True);
  if PreviewName <> '' then
    TextIn(B, Rect(R.Left + ScI(62), R.Top + ScI(10), R.Right - ScI(10), R.Top + ScI(34)), PreviewName, clText)
  else
    TextIn(B, Rect(R.Left + ScI(62), R.Top + ScI(10), R.Right - ScI(10), R.Top + ScI(34)), '192.168.x.x', clText);
  SetFont(B, 8.5);
  TextIn(B, Rect(R.Left + ScI(62), R.Top + ScI(33), R.Right - ScI(10), R.Bottom - ScI(8)),
    'ตัวอย่าง: เครื่องอื่นจะเห็นแบบนี้', clTextDim);
end;

procedure TIconPicker.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  I, HK, HC: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  HK := -1;
  HC := -1;
  for I := 0 to High(FKindRects) do
    if PtIn(FKindRects[I], X, Y) then HK := I;
  for I := 0 to High(FColorRects) do
    if PtIn(FColorRects[I], X, Y) then HC := I;
  if (HK <> FHotKind) or (HC <> FHotColor) then
  begin
    FHotKind := HK;
    FHotColor := HC;
    if (HK >= 0) or (HC >= 0) then Cursor := crHandPoint else Cursor := crDefault;
    Invalidate;
  end;
end;

procedure TIconPicker.MouseLeave;
begin
  inherited MouseLeave;
  FHotKind := -1;
  FHotColor := -1;
  Invalidate;
end;

procedure TIconPicker.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  for I := 0 to High(FKindRects) do
    if PtIn(FKindRects[I], X, Y) then SelKind := I;
  for I := 0 to High(FColorRects) do
    if PtIn(FColorRects[I], X, Y) then SelColor := I;
  Invalidate;
end;

{ ---------- TThemePicker ---------- }

const
  THEME_COLS = 6;

function THEME_ROW_H: Integer;
begin
  Result := ScI(70);
end;

constructor TThemePicker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BackColor := clPanel;
  FHot := -1;
end;

procedure TThemePicker.Render(B: TBGRABitmap);
var
  T: TThemeKind;
  W, X, Y: Integer;
  R, P: TRect;
  Keep: TThemeKind;
  Bg, Side, Acc, Acc2, Txt, Dim, Sel, Brd, Hov, CText, CDim: TBGRAPixel;
begin
  Keep := CurrentTheme;
  CText := clText;
  CDim := clTextDim;
  Sel := clSelBorder;
  Brd := clBorder;
  Hov := clHover;
  W := (B.Width - ScI(8)) div THEME_COLS;
  for T := Low(TThemeKind) to High(TThemeKind) do
  begin
    X := (Ord(T) mod THEME_COLS) * W + ScI(4);
    Y := (Ord(T) div THEME_COLS) * THEME_ROW_H;
    R := Rect(X + ScI(2), Y, X + W - ScI(2), Y + THEME_ROW_H - ScI(4));
    FRects[T] := R;
    if Ord(T) = FHot then
      B.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, Sc(10), Sc(10), Hov);
    // read the palette of T without disturbing the current one
    SetTheme(T);
    Bg := clBg; Side := clSide; Acc := clAccent; Acc2 := clAccent2;
    Txt := clText; Dim := clTextDim;
    SetTheme(Keep);
    // mini window: sidebar + content + accent button
    P := Rect(R.Left + ScI(5), R.Top + ScI(5), R.Right - ScI(5), R.Top + ScI(42));
    B.FillRoundRectAntialias(P.Left, P.Top, P.Right, P.Bottom, Sc(7), Sc(7), Bg);
    B.FillRoundRectAntialias(P.Left, P.Top, P.Left + P.Width div 3, P.Bottom, Sc(7), Sc(7), Side,
      [rrTopRightSquare, rrBottomRightSquare]);
    B.FillRoundRectAntialias(P.Left + P.Width div 3 + ScI(5), P.Top + ScI(7), P.Right - ScI(6), P.Top + ScI(13),
      Sc(3), Sc(3), Dim);
    B.FillRoundRectAntialias(P.Left + P.Width div 3 + ScI(5), P.Top + ScI(17), P.Right - ScI(16), P.Top + ScI(23),
      Sc(3), Sc(3), Txt);
    FillGradientRoundRect(B, P.Right - ScI(22), P.Bottom - ScI(12), P.Right - ScI(4), P.Bottom - ScI(4),
      Sc(3), Acc, Acc2);
    if T = thAuto then
    begin
      // half light / half dark
      B.FillPolyAntialias([PointF(P.Right, P.Top), PointF(P.Right, P.Bottom), PointF(P.Left + P.Width * 0.45, P.Bottom)],
        BGRA(246, 247, 250, 210));
    end;
    B.RoundRectAntialias(P.Left + 0.5, P.Top + 0.5, P.Right - 0.5, P.Bottom - 0.5, Sc(7), Sc(7), Brd, 1);
    if T = Selected then
      B.RoundRectAntialias(P.Left - ScI(2), P.Top - ScI(2), P.Right + ScI(2), P.Bottom + ScI(2), Sc(9), Sc(9), Sel, Sc(2));
    SetFont(B, 8.5, T = Selected);
    if T = Selected then
      TextIn(B, Rect(R.Left, P.Bottom + ScI(4), R.Right, R.Bottom), THEME_LABELS[T], CText, taCenter)
    else
      TextIn(B, Rect(R.Left, P.Bottom + ScI(4), R.Right, R.Bottom), THEME_LABELS[T], CDim, taCenter);
  end;
end;

procedure TThemePicker.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  T: TThemeKind;
  H: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  H := -1;
  for T := Low(TThemeKind) to High(TThemeKind) do
    if PtIn(FRects[T], X, Y) then H := Ord(T);
  if H <> FHot then
  begin
    FHot := H;
    if H >= 0 then Cursor := crHandPoint else Cursor := crDefault;
    Invalidate;
  end;
end;

procedure TThemePicker.MouseLeave;
begin
  inherited MouseLeave;
  FHot := -1;
  Invalidate;
end;

procedure TThemePicker.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  T: TThemeKind;
begin
  inherited MouseDown(Button, Shift, X, Y);
  for T := Low(TThemeKind) to High(TThemeKind) do
    if PtIn(FRects[T], X, Y) then Selected := T;
  Invalidate;
end;

{ ---------- TSettingsDialog ---------- }

type
  TCaptionBar = class(TBGRAControl)
  protected
    procedure Render(B: TBGRABitmap); override;
  public
    CapText: string;
  end;

procedure TCaptionBar.Render(B: TBGRABitmap);
begin
  SetFont(B, 9, True);
  B.TextOut(0, B.Height - ScI(22), CapText, clTextDim);
end;

type
  { bottom row: version on the left, buttons (children) on the right }
  TButtonRow = class(TBGRAControl)
  protected
    procedure Render(B: TBGRABitmap); override;
  end;

procedure TButtonRow.Render(B: TBGRABitmap);
begin
  SetFont(B, 8.5);
  TextIn(B, Rect(0, 0, B.Width div 2, B.Height), 'LAN Share ' + APP_VERSION, clTextDim);
end;

type
  TLabelPanel = class(TBGRAControl)
  protected
    procedure Render(B: TBGRABitmap); override;
  public
    Title, Sub: string;
  end;

procedure TLabelPanel.Render(B: TBGRABitmap);
begin
  SetFont(B, 13, True);
  B.TextOut(0, ScI(4), Title, clText);
  SetFont(B, 9);
  TextIn(B, Rect(0, ScI(34), B.Width, ScI(54)), Sub, clTextDim);
  SetFont(B, 9, True);
  B.TextOut(0, B.Height - ScI(22), 'ชื่อที่เครื่องอื่นเห็น', clTextDim);
end;

constructor TSettingsDialog.CreateDlg(AOwner: TComponent; const AName, AIcon, AHostName: string;
  ATheme: TThemeKind);
var
  Head: TLabelPanel;
  Row, Bottom: TBGRAControl;
  Gap, ThemeCap: TCaptionBar;
  B: TFlatButton;
  K, C: Integer;

  function Btn(AParent: TWinControl; const ACap: string; AStyle: TButtonStyle; AAlign: TAlign;
    AClick: TNotifyEvent): TFlatButton;
  begin
    Result := TFlatButton.Create(Self);
    Result.Parent := AParent;
    Result.Caption := ACap;
    Result.Style := AStyle;
    Result.BackColor := clPanel;
    Result.Align := AAlign;
    Result.OnClick := AClick;
    Result.FitWidth;
  end;

begin
  inherited CreateNew(AOwner);
  FHostName := AHostName;
  Caption := 'ตั้งค่าเครื่องนี้';
  BorderStyle := bsDialog;
  Position := poOwnerFormCenter;
  ClientWidth := ScI(460);
  ClientHeight := ScI(770);
  Color := BGRAToColor(clPanel);

  FPanel := TBGRAControl.Create(Self);
  FPanel.Parent := Self;
  FPanel.Align := alClient;
  FPanel.BackColor := clPanel;
  FPanel.ChildSizing.LeftRightSpacing := ScI(20);
  FPanel.ChildSizing.TopBottomSpacing := ScI(16);

  Head := TLabelPanel.Create(Self);
  Head.Parent := FPanel;
  Head.Align := alTop;
  Head.Height := ScI(86);
  Head.BackColor := clPanel;
  Head.Title := 'ตั้งค่าเครื่องนี้';
  Head.Sub := 'เว้นว่างไว้ = ไม่แสดงชื่อ (ค่าเริ่มต้น) เครื่องอื่นเห็นเพียงไอคอนและ IP';

  FEdit := TEdit.Create(Self);
  FEdit.Parent := FPanel;
  FEdit.Align := alTop;
  FEdit.Top := ScI(200);
  FEdit.MaxLength := 40;
  FEdit.Font.Size := 11;
  FEdit.Color := BGRAToColor(clCard);
  FEdit.Font.Color := BGRAToColor(clText);
  FEdit.BorderSpacing.Top := ScI(4);
  FEdit.Text := AName;
  FEdit.TextHint := 'ไม่แสดงชื่อ';
  FEdit.OnChange := @EditChange;

  Row := TBGRAControl.Create(Self);
  Row.Parent := FPanel;
  Row.Align := alTop;
  Row.Top := ScI(300);
  Row.Height := ScI(44);
  Row.BackColor := clPanel;
  Btn(Row, 'ไม่แสดงชื่อ', bsNormal, alLeft, @AnonClick).BorderSpacing.Left := 0;
  B := Btn(Row, 'ใช้ชื่อคอมพิวเตอร์', bsGhost, alLeft, @HostClick);
  B.Left := 500;
  B.Hint := 'จะแสดงชื่อ "' + FHostName + '" ให้ทุกเครื่องในวง LAN เห็น';
  B.ShowHint := True;

  Gap := TCaptionBar.Create(Self);
  Gap.Parent := FPanel;
  Gap.Align := alTop;
  Gap.Top := ScI(400);
  Gap.Height := ScI(34);
  Gap.BackColor := clPanel;
  Gap.CapText := 'ไอคอน';

  Bottom := TButtonRow.Create(Self);
  Bottom.Parent := FPanel;
  Bottom.Align := alBottom;
  Bottom.Height := ScI(46);
  Bottom.BackColor := clPanel;
  B := Btn(Bottom, 'บันทึก', bsAccent, alRight, @OkClick);
  B.Left := 900;
  Btn(Bottom, 'ยกเลิก', bsNormal, alRight, @CancelClick).Left := 800;

  // theme (above the buttons; alBottom controls stack upwards)
  FThemes := TThemePicker.Create(Self);
  FThemes.Parent := FPanel;
  FThemes.Align := alBottom;
  FThemes.Height := ScI(142);
  FThemes.BorderSpacing.Bottom := ScI(12);
  FThemes.Selected := ATheme;
  ThemeCap := TCaptionBar.Create(Self);
  ThemeCap.Parent := FPanel;
  ThemeCap.Align := alBottom;
  ThemeCap.Height := ScI(30);
  ThemeCap.BackColor := clPanel;
  ThemeCap.CapText := 'ธีม';
  // LCL orders alBottom controls by Top: larger Top = lower on screen
  ThemeCap.Top := 10000;
  FThemes.Top := 10100;
  Bottom.Top := 10200;

  FPicker := TIconPicker.Create(Self);
  FPicker.Parent := FPanel;
  FPicker.Align := alClient;
  ParseDeviceIcon(AIcon, '', K, C);
  FPicker.SelKind := K;
  FPicker.SelColor := C;
  FPicker.PreviewName := AName;

  ActiveControl := FEdit;
end;

procedure TSettingsDialog.EditChange(Sender: TObject);
begin
  FPicker.PreviewName := NameValue;
  FPicker.Invalidate;
end;

procedure TSettingsDialog.AnonClick(Sender: TObject);
begin
  FEdit.Text := '';
end;

procedure TSettingsDialog.HostClick(Sender: TObject);
begin
  FEdit.Text := FHostName;
end;

procedure TSettingsDialog.OkClick(Sender: TObject);
begin
  ModalResult := mrOK;
end;

procedure TSettingsDialog.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

function TSettingsDialog.NameValue: string;
begin
  Result := Trim(StringReplace(FEdit.Text, '|', '-', [rfReplaceAll]));
end;

function TSettingsDialog.ThemeValue: TThemeKind;
begin
  Result := FThemes.Selected;
end;

function TSettingsDialog.IconValue: string;
begin
  Result := MakeDeviceIcon(FPicker.SelKind, FPicker.SelColor);
end;

function EditIdentity(AOwner: TComponent; var AName, AIcon: string;
  var ATheme: TThemeKind; const AHostName: string): Boolean;
var
  D: TSettingsDialog;
begin
  D := TSettingsDialog.CreateDlg(AOwner, AName, AIcon, AHostName, ATheme);
  try
    Result := D.ShowModal = mrOK;
    if Result then
    begin
      AName := D.NameValue;
      AIcon := D.IconValue;
      ATheme := D.ThemeValue;
    end;
  finally
    D.Free;
  end;
end;

end.
