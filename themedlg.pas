unit ThemeDlg;

{ Dialogs drawn in the current theme (instead of the system MessageDlg /
  InputQuery, which always look like plain Windows). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, StdCtrls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes, UITheme, UIWidgets, I18n;

type
  TDlgKind = (dkQuestion, dkInfo, dkWarning, dkError);

{ Two buttons. Returns True for YesText (the highlighted one; also Enter),
  False for NoText (also Esc and the window's close box).
  An empty NoText shows a single button. }
function ThemedAsk(AOwner: TComponent; Kind: TDlgKind; const Title, Msg,
  YesText, NoText: string): Boolean;

{ One-line text input. Returns False when cancelled. }
function ThemedInput(AOwner: TComponent; const Title, Prompt: string;
  var Value: string; const Hint: string = ''): Boolean;

{ Windows 10/11: dark or light title bar to match the theme (Windows 11 also
  takes the theme's exact colours). Does nothing on other systems. }
procedure ApplyWindowTheme(F: TCustomForm);

implementation

uses
  {$IFDEF WINDOWS} Windows, {$ENDIF}
  Math, LazUTF8;

{$IFDEF WINDOWS}
function DwmSetWindowAttribute(hwnd: HWND; dwAttribute: DWORD; pvAttribute: Pointer;
  cbAttribute: DWORD): HRESULT; stdcall; external 'dwmapi.dll';

procedure ApplyWindowTheme(F: TCustomForm);
const
  DWMWA_USE_IMMERSIVE_DARK_MODE_OLD = 19;   // Windows 10 before 20H1
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
  DWMWA_CAPTION_COLOR = 35;                 // Windows 11
  DWMWA_TEXT_COLOR = 36;
var
  Dark: LongBool;
  C: COLORREF;
begin
  if not F.HandleAllocated then Exit;
  Dark := not IsLightTheme;
  if DwmSetWindowAttribute(F.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, @Dark, SizeOf(Dark)) <> S_OK then
    DwmSetWindowAttribute(F.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE_OLD, @Dark, SizeOf(Dark));
  C := RGB(clPanel.red, clPanel.green, clPanel.blue);
  DwmSetWindowAttribute(F.Handle, DWMWA_CAPTION_COLOR, @C, SizeOf(C));
  C := RGB(clText.red, clText.green, clText.blue);
  DwmSetWindowAttribute(F.Handle, DWMWA_TEXT_COLOR, @C, SizeOf(C));
  // Windows 10 repaints the frame only when asked
  SetWindowPos(F.Handle, 0, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
    SWP_NOACTIVATE or SWP_FRAMECHANGED);
end;
{$ELSE}
procedure ApplyWindowTheme(F: TCustomForm);
begin
end;
{$ENDIF}

type
  { icon + title + wrapped message, all drawn with BGRABitmap }
  TDlgBody = class(TBGRAControl)
  protected
    procedure Render(B: TBGRABitmap); override;
  public
    Kind: TDlgKind;
    Title: string;
    Lines: TStringList;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

  TThemedDialog = class(TForm)
  private
    procedure YesClick(Sender: TObject);
    procedure NoClick(Sender: TObject);
    procedure KeyDownEvt(Sender: TObject; var Key: Word; Shift: TShiftState);
  protected
    procedure CreateWnd; override;
  public
    Body: TDlgBody;
    Edit: TEdit;
    constructor CreateDlg(AOwner: TComponent; Kind: TDlgKind; const ATitle, AMsg,
      YesText, NoText: string; WithEdit: Boolean);
  end;

const
  DLG_W = 440;          // dialog width (96 dpi)
  TEXT_X = 76;          // message starts right of the icon

{ ---------- wrapping (Thai has no spaces between words) ---------- }

procedure WrapText(B: TBGRABitmap; const S: string; MaxW: Integer; Out_: TStrings);
var
  Paras: TStringArray;
  P, Line, Word_, Try_: string;
  Words: TStringArray;
  I, N: Integer;

  procedure FlushLongWord(var W: string);
  var
    L: Integer;
  begin
    // a "word" wider than the line: break between characters
    while TextW(B, W) > MaxW do
    begin
      L := UTF8Length(W);
      while (L > 1) and (TextW(B, UTF8Copy(W, 1, L)) > MaxW) do Dec(L);
      Out_.Add(UTF8Copy(W, 1, L));
      W := UTF8Copy(W, L + 1, MaxInt);
    end;
  end;

begin
  Paras := StringReplace(S, #13#10, #10, [rfReplaceAll]).Split([#10]);
  for P in Paras do
  begin
    if P = '' then
    begin
      Out_.Add('');
      Continue;
    end;
    Words := P.Split([' ']);
    Line := '';
    N := Length(Words);
    for I := 0 to N - 1 do
    begin
      Word_ := Words[I];
      if Line = '' then Try_ := Word_ else Try_ := Line + ' ' + Word_;
      if TextW(B, Try_) <= MaxW then
        Line := Try_
      else
      begin
        if Line <> '' then Out_.Add(Line);
        FlushLongWord(Word_);
        Line := Word_;
      end;
    end;
    if Line <> '' then Out_.Add(Line);
  end;
end;

{ ---------- TDlgBody ---------- }

constructor TDlgBody.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BackColor := clPanel;
  Lines := TStringList.Create;
end;

destructor TDlgBody.Destroy;
begin
  Lines.Free;
  inherited Destroy;
end;

procedure TDlgBody.Render(B: TBGRABitmap);
var
  C: TBGRAPixel;
  Glyph: string;
  CX, CY, R: Single;
  I, Y, LH: Integer;
begin
  case Kind of
    dkError:   begin C := clErr;  Glyph := '!'; end;
    dkWarning: begin C := clWarn; Glyph := '!'; end;
    dkInfo:    begin C := clAccent; Glyph := 'i'; end;
  else
    begin C := clAccent; Glyph := '?'; end;
  end;
  // icon: soft halo + filled circle + glyph
  R := Sc(20);
  CX := ScI(24) + R;
  CY := ScI(22) + R;
  B.FillEllipseAntialias(CX, CY, R + Sc(6), R + Sc(6), WithAlpha(C, 40));
  if Kind = dkQuestion then
    FillGradientRoundRect(B, CX - R, CY - R, CX + R, CY + R, R, clAccent, clAccent2, False)
  else
    B.FillEllipseAntialias(CX, CY, R, R, C);
  B.FontName := 'Arial';
  B.FontStyle := [fsBold];
  B.FontQuality := fqFineAntialiasing;
  B.FontHeight := Round(R * 1.35);
  B.TextOut(CX, CY - B.FontHeight / 2, Glyph, BGRAWhite, taCenter);

  SetFont(B, 12, True);
  B.TextOut(ScI(TEXT_X), ScI(18), Title, clText);
  SetFont(B, 10);
  LH := B.TextSize('Ag').cy + ScI(3);
  Y := ScI(52);
  for I := 0 to Lines.Count - 1 do
  begin
    B.TextOut(ScI(TEXT_X), Y, Lines[I], clTextDim);
    Inc(Y, LH);
  end;
end;

{ ---------- TThemedDialog ---------- }

constructor TThemedDialog.CreateDlg(AOwner: TComponent; Kind: TDlgKind; const ATitle,
  AMsg, YesText, NoText: string; WithEdit: Boolean);
var
  Bottom: TBGRAControl;
  Probe: TBGRABitmap;
  LH, BodyH: Integer;

  function MkBtn(const ACap: string; AStyle: TButtonStyle; ALeft: Integer;
    AClick: TNotifyEvent): TFlatButton;
  begin
    Result := TFlatButton.Create(Self);
    Result.Parent := Bottom;
    Result.Caption := ACap;
    Result.Style := AStyle;
    Result.BackColor := clPanel;
    Result.Align := alRight;
    Result.Left := ALeft;
    Result.OnClick := AClick;
    Result.FitWidth;
    if Result.Width < ScI(96) then Result.Width := ScI(96);
  end;

begin
  inherited CreateNew(AOwner);
  Caption := ATitle;
  BorderStyle := bsDialog;
  if (AOwner is TForm) and TForm(AOwner).Visible then
    Position := poOwnerFormCenter
  else
    Position := poScreenCenter;
  Color := BGRAToColor(clPanel);
  KeyPreview := True;
  OnKeyDown := @KeyDownEvt;

  Body := TDlgBody.Create(Self);
  Body.Parent := Self;
  Body.Kind := Kind;
  Body.Title := ATitle;
  // measure the wrapped message to size the window
  Probe := TBGRABitmap.Create(1, 1);
  try
    SetFont(Probe, 10);
    WrapText(Probe, AMsg, ScI(DLG_W - TEXT_X - 24), Body.Lines);
    LH := Probe.TextSize('Ag').cy + ScI(3);
  finally
    Probe.Free;
  end;
  BodyH := Max(ScI(80), ScI(60) + Body.Lines.Count * LH);
  ClientWidth := ScI(DLG_W);

  Bottom := TBGRAControl.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := ScI(60);
  Bottom.BackColor := clPanel;
  Bottom.ChildSizing.LeftRightSpacing := ScI(14);
  Bottom.ChildSizing.TopBottomSpacing := ScI(12);

  MkBtn(YesText, bsAccent, 2000, @YesClick);
  if NoText <> '' then MkBtn(NoText, bsNormal, 1000, @NoClick);

  if WithEdit then
  begin
    Edit := TEdit.Create(Self);
    Edit.Parent := Self;
    Edit.Align := alBottom;
    Edit.Top := 0;
    Edit.BorderSpacing.Left := ScI(TEXT_X);
    Edit.BorderSpacing.Right := ScI(24);
    Edit.BorderSpacing.Bottom := ScI(6);
    Edit.Font.Size := 11;
    Edit.Color := BGRAToColor(clCard);
    Edit.Font.Color := BGRAToColor(clText);
    ClientHeight := BodyH + ScI(36) + Bottom.Height;
  end
  else
    ClientHeight := BodyH + Bottom.Height;

  Body.Align := alClient;
  ActiveControl := nil;
end;

procedure TThemedDialog.CreateWnd;
begin
  inherited CreateWnd;
  ApplyWindowTheme(Self);
end;

procedure TThemedDialog.YesClick(Sender: TObject);
begin
  ModalResult := mrYes;
end;

procedure TThemedDialog.NoClick(Sender: TObject);
begin
  ModalResult := mrNo;
end;

procedure TThemedDialog.KeyDownEvt(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN: begin ModalResult := mrYes; Key := 0; end;
    VK_ESCAPE: begin ModalResult := mrNo; Key := 0; end;
  end;
end;

{ ---------- public ---------- }

function ThemedAsk(AOwner: TComponent; Kind: TDlgKind; const Title, Msg,
  YesText, NoText: string): Boolean;
var
  D: TThemedDialog;
begin
  D := TThemedDialog.CreateDlg(AOwner, Kind, Title, Msg, YesText, NoText, False);
  try
    Result := D.ShowModal = mrYes;
  finally
    D.Free;
  end;
end;

function ThemedInput(AOwner: TComponent; const Title, Prompt: string;
  var Value: string; const Hint: string): Boolean;
var
  D: TThemedDialog;
begin
  D := TThemedDialog.CreateDlg(AOwner, dkQuestion, Title, Prompt, L('OK', 'ตกลง'), L('Cancel', 'ยกเลิก'), True);
  try
    D.Edit.Text := Value;
    D.Edit.TextHint := Hint;
    D.ActiveControl := D.Edit;
    Result := D.ShowModal = mrYes;
    if Result then Value := D.Edit.Text;
  finally
    D.Free;
  end;
end;

end.
