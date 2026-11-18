unit UITheme;

{ Colours, fonts and vector icons for LAN Share. Everything is drawn with
  BGRABitmap at any size, so the UI stays sharp on high-DPI screens. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, I18n, BGRABitmap, BGRABitmapTypes, BGRAGraphics, BGRAGradientScanner;

type
  TIconKind = (ikNone, ikBack, ikUp, ikRefresh, ikDownload, ikUpload, ikPlus,
    ikShare, ikTrash, ikFolderOpen, ikNetwork, ikClose, ikCheck, ikChevron,
    ikComputer, ikFolderPlus, ikFilePlus, ikGear, ikEye,
    ikViewDetails, ikViewList, ikViewIcons, ikEdit);

const
  { device icons a user can pick; sent to others as '<kind>.<color>' }
  DEVICE_KINDS: array[0..7] of string =
    ('desktop', 'laptop', 'phone', 'tablet', 'server', 'tv', 'store', 'megaphone');
  DEVICE_KIND_LABELS: array[TLang, 0..7] of string = (
    ('Computer', 'Laptop', 'Phone', 'Tablet', 'Server', 'TV screen', 'Shop', 'Notice'),
    ('คอมพิวเตอร์', 'โน้ตบุ๊ก', 'มือถือ', 'แท็บเล็ต', 'เซิร์ฟเวอร์', 'จอทีวี', 'ร้านค้า', 'ประกาศ'));
  DEVICE_COLOR_COUNT = 8;

type
  TThemeKind = (thDark, thLight, thOcean, thRose, thForest, thSunset, thCoffee, thNeon, thLavender, thMono, thAuto);

const
  THEME_NAMES: array[TThemeKind] of string = ('dark', 'light', 'ocean', 'rose', 'forest', 'sunset', 'coffee', 'neon', 'lavender', 'mono', 'auto');
  THEME_LABELS: array[TLang, TThemeKind] of string = (
    ('Dark', 'Light', 'Ocean', 'Pink', 'Forest', 'Sunset', 'Coffee', 'Neon', 'Lavender', 'Mono', 'System'),
    ('มืด', 'สว่าง', 'มหาสมุทร', 'ชมพู', 'ป่าไม้', 'ยามเย็น', 'กาแฟ', 'นีออน', 'ลาเวนเดอร์', 'ขาวดำ', 'ตามระบบ'));

var
  UIScale: Single = 1.0;
  CurrentTheme: TThemeKind = thDark;   // as chosen (may be thAuto)

  { dark theme }
  clBg        : TBGRAPixel;   // file list background
  clSide      : TBGRAPixel;   // sidebar
  clPanel     : TBGRAPixel;   // toolbar / transfers
  clCard      : TBGRAPixel;   // cards, inputs
  clHover     : TBGRAPixel;
  clSel       : TBGRAPixel;
  clSelBorder : TBGRAPixel;
  clBorder    : TBGRAPixel;
  clAccent    : TBGRAPixel;
  clAccent2   : TBGRAPixel;
  clText      : TBGRAPixel;
  clTextDim   : TBGRAPixel;
  clOk        : TBGRAPixel;
  clErr       : TBGRAPixel;
  clWarn      : TBGRAPixel;
  clHead1     : TBGRAPixel;   // header gradient
  clHead2     : TBGRAPixel;
  clIconPage  : TBGRAPixel;   // file icon paper

{ switch every colour above to a theme (thAuto follows the OS light/dark setting) }
procedure SetTheme(T: TThemeKind);
{ labels in the current language }
function ThemeLabel(T: TThemeKind): string;
function DeviceKindLabel(I: Integer): string;
function ThemeFromName(const S: string): TThemeKind;
{ the palette that thAuto resolves to right now }
function ResolveTheme(T: TThemeKind): TThemeKind;
{ current colours as CSS custom properties, served to browsers as /theme.css }
function ThemeCss: string;
{ True when the current palette is a light one }
function IsLightTheme: Boolean;
{ CSS of a named theme without touching the current colours (thread-safe);
  '' for unknown names and 'auto' }
function ThemeCssByName(const Name: string): string;
{ JSON list of the themes for the web page's theme picker }
function ThemesJson: string;

function Sc(V: Single): Single; inline;
function ScI(V: Single): Integer; inline;
procedure SetFont(B: TBGRABitmap; SizePt: Single; Bold: Boolean = False);
function Ellipsize(B: TBGRABitmap; const S: string; MaxW: Integer): string;
{ Draws S vertically centred in R, starting at R.Left, cut to R's width }
procedure TextIn(B: TBGRABitmap; const R: TRect; const S: string; C: TBGRAPixel;
  Align: TAlignment = taLeftJustify);
function TextW(B: TBGRABitmap; const S: string): Integer;

procedure DrawIcon(B: TBGRABitmap; Kind: TIconKind; X, Y, S: Single; C: TBGRAPixel);
procedure DrawFolderIcon(B: TBGRABitmap; X, Y, S: Single; Shared: Boolean = False);
procedure DrawFileIcon(B: TBGRABitmap; const FileName: string; X, Y, S: Single);
function OSLabel(const OS: string): string;
procedure FillGradientRoundRect(B: TBGRABitmap; X1, Y1, X2, Y2, R: Single;
  C1, C2: TBGRAPixel; Horizontal: Boolean = True);
{ app logo: gradient rounded square with the network glyph }
procedure DrawAppLogo(B: TBGRABitmap; X, Y, S: Single);
{ device avatar for '<kind>.<color>' (empty/unknown -> by OS) }
procedure DrawDeviceAvatar(B: TBGRABitmap; const Icon, OS: string; X, Y, S: Single;
  Online: Boolean; ShowDot: Boolean = True);
procedure ParseDeviceIcon(const Icon, OS: string; out Kind, Color: Integer);
function MakeDeviceIcon(Kind, Color: Integer): string;
function DeviceColor(Index: Integer): TBGRAPixel;
function FileColor(const FileName: string): TBGRAPixel;
function WithAlpha(C: TBGRAPixel; A: Byte): TBGRAPixel;
function Mix(A, B: TBGRAPixel; T: Single): TBGRAPixel;

implementation

uses
  {$IFDEF WINDOWS} Windows, Registry, {$ENDIF}
  Math, LazUTF8;

function ThemeFromName(const S: string): TThemeKind;
var
  T: TThemeKind;
begin
  for T := Low(TThemeKind) to High(TThemeKind) do
    if THEME_NAMES[T] = LowerCase(S) then Exit(T);
  Result := thDark;
end;

function ResolveTheme(T: TThemeKind): TThemeKind;
{$IFDEF WINDOWS}
var
  R: TRegistry;
{$ENDIF}
begin
  Result := T;
  if T <> thAuto then Exit;
  Result := thDark;
  {$IFDEF WINDOWS}
  R := TRegistry.Create(KEY_READ);
  try
    R.RootKey := HKEY_CURRENT_USER;
    if R.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') then
      if R.ValueExists('AppsUseLightTheme') and (R.ReadInteger('AppsUseLightTheme') = 1) then
        Result := thLight;
  finally
    R.Free;
  end;
  {$ENDIF}
end;

type
  { colours as $RRGGBB: TBGRAPixel's field order differs between platforms }
  TPalette = record
    Light: Boolean;
    Bg, Side, Panel, Card, Hover, Sel, SelBorder, Border,
    Accent, Accent2, Text, Dim, Head1, Head2: LongWord;
  end;

const
  { one row per theme (thAuto has no row: it picks dark or light) }
  PALETTES: array[TThemeKind] of TPalette = (
    (Light: False; Bg: $171920; Side: $1D2029; Panel: $1F222C; Card: $282C38; Hover: $2C313F; Sel: $2A4880; SelBorder: $4A80E6;
     Border: $323746; Accent: $4891FF; Accent2: $8A5CF6; Text: $E8ECF4; Dim: $929AAC; Head1: $1E2A4E; Head2: $341E5C),
    (Light: True; Bg: $F6F7FA; Side: $ECEFF5; Panel: $FFFFFF; Card: $E6EAF1; Hover: $DEE4EE; Sel: $D4E2FC; SelBorder: $3B82F6;
     Border: $D6DCE6; Accent: $2563EB; Accent2: $7C3AED; Text: $181C26; Dim: $626A7A; Head1: $E2ECFF; Head2: $EFE6FF),
    (Light: False; Bg: $0D171F; Side: $111E28; Panel: $13222D; Card: $1B2E3C; Hover: $1F3545; Sel: $0E526A; SelBorder: $22C5E0;
     Border: $233A4A; Accent: $0EA5E9; Accent2: $14B8A6; Text: $E2F0F6; Dim: $88A3B4; Head1: $082F49; Head2: $0B484E),
    (Light: True; Bg: $FDF6F8; Side: $FAEDF2; Panel: $FFFFFF; Card: $F6E4EB; Hover: $F3DDE6; Sel: $FCD4E4; SelBorder: $EC4899;
     Border: $EED4DE; Accent: $EC4899; Accent2: $F97316; Text: $2A1821; Dim: $826370; Head1: $FFE2EC; Head2: $FFECD6),
    (Light: False; Bg: $0F1713; Side: $131E18; Panel: $15221B; Card: $1D2E25; Hover: $22352B; Sel: $1B5239; SelBorder: $34D399;
     Border: $25392E; Accent: $16A34A; Accent2: $14B8A6; Text: $E6F2EA; Dim: $8CA696; Head1: $0D3222; Head2: $193E27),
    (Light: False; Bg: $1C141A; Side: $231820; Panel: $271B24; Card: $342430; Hover: $3C2937; Sel: $6E3040; SelBorder: $FB923C;
     Border: $422E3C; Accent: $F97316; Accent2: $EC4899; Text: $FAECF0; Dim: $B496A5; Head1: $581C34; Head2: $783416),
    (Light: True; Bg: $FAF6F0; Side: $F3ECE2; Panel: $FFFCF7; Card: $ECE2D4; Hover: $E6DACA; Sel: $E8D6BE; SelBorder: $92400E;
     Border: $E1D4C4; Accent: $92400E; Accent2: $C26818; Text: $2C1E14; Dim: $7A6454; Head1: $F5E6D2; Head2: $ECDAC4),
    (Light: False; Bg: $0A0814; Side: $0F0C1E; Panel: $120E24; Card: $1C1634; Hover: $241C42; Sel: $461464; SelBorder: $00F0FF;
     Border: $302454; Accent: $FF00AA; Accent2: $00C8FF; Text: $F0ECFF; Dim: $968CBE; Head1: $280646; Head2: $062850),
    (Light: True; Bg: $F8F6FD; Side: $F0ECFB; Panel: $FFFFFF; Card: $E8E2F8; Hover: $E0D8F6; Sel: $DDD2FC; SelBorder: $7C3AED;
     Border: $DED6F2; Accent: $7C3AED; Accent2: $DB2777; Text: $1E1830; Dim: $696082; Head1: $EDE4FF; Head2: $E4ECFF),
    (Light: False; Bg: $000000; Side: $0C0C0C; Panel: $121212; Card: $202020; Hover: $2C2C2C; Sel: $464646; SelBorder: $FFFFFF;
     Border: $404040; Accent: $606060; Accent2: $3C3C3C; Text: $FFFFFF; Dim: $AFAFAF; Head1: $161616; Head2: $2E2E2E),
    (Light: False; Bg: 0; Side: 0; Panel: 0; Card: 0; Hover: 0; Sel: 0; SelBorder: 0; Border: 0; Accent: 0; Accent2: 0; Text: 0; Dim: 0; Head1: 0; Head2: 0)   // thAuto: unused
  );

function Px(V: LongWord): TBGRAPixel;
begin
  Result := BGRA((V shr 16) and $FF, (V shr 8) and $FF, V and $FF);
end;

procedure SetTheme(T: TThemeKind);
var
  P: TPalette;
begin
  CurrentTheme := T;
  P := PALETTES[ResolveTheme(T)];
  clBg        := Px(P.Bg);
  clSide      := Px(P.Side);
  clPanel     := Px(P.Panel);
  clCard      := Px(P.Card);
  clHover     := Px(P.Hover);
  clSel       := Px(P.Sel);
  clSelBorder := Px(P.SelBorder);
  clBorder    := Px(P.Border);
  clAccent    := Px(P.Accent);
  clAccent2   := Px(P.Accent2);
  clText      := Px(P.Text);
  clTextDim   := Px(P.Dim);
  clHead1     := Px(P.Head1);
  clHead2     := Px(P.Head2);
  if P.Light then
  begin
    clOk := BGRA(22, 163, 74);
    clErr := BGRA(220, 38, 38);
    clWarn := BGRA(217, 119, 6);
    clIconPage := BGRA(255, 255, 255);
  end
  else
  begin
    clOk := BGRA(52, 211, 130);
    clErr := BGRA(244, 92, 102);
    clWarn := BGRA(250, 190, 70);
    clIconPage := BGRA(236, 240, 246);
  end;
end;

function ThemeLabel(T: TThemeKind): string;
begin
  Result := THEME_LABELS[Lang, T];
end;

function DeviceKindLabel(I: Integer): string;
begin
  if (I >= 0) and (I <= 7) then
    Result := DEVICE_KIND_LABELS[Lang, I]
  else
    Result := '';
end;

function CssColor(const C: TBGRAPixel): string;
begin
  Result := Format('#%.2x%.2x%.2x', [C.red, C.green, C.blue]);
end;

{ CSS custom properties of theme T, built from the palette table only }
function ThemeCssOf(T: TThemeKind): string;
var
  P: TPalette;
  Ok, Err, Page: TBGRAPixel;
begin
  P := PALETTES[ResolveTheme(T)];
  if P.Light then
  begin
    Ok := BGRA(22, 163, 74);
    Err := BGRA(220, 38, 38);
    Page := BGRA(255, 255, 255);
  end
  else
  begin
    Ok := BGRA(52, 211, 130);
    Err := BGRA(244, 92, 102);
    Page := BGRA(236, 240, 246);
  end;
  Result := ':root{' +
    '--bg:' + CssColor(Px(P.Bg)) + ';--panel:' + CssColor(Px(P.Panel)) + ';--side:' + CssColor(Px(P.Side)) +
    ';--card:' + CssColor(Px(P.Card)) + ';--hover:' + CssColor(Px(P.Hover)) + ';--sel:' + CssColor(Px(P.Sel)) +
    ';--text:' + CssColor(Px(P.Text)) + ';--dim:' + CssColor(Px(P.Dim)) +
    ';--accent:' + CssColor(Px(P.Accent)) + ';--accent2:' + CssColor(Px(P.Accent2)) +
    ';--ok:' + CssColor(Ok) + ';--err:' + CssColor(Err) + ';--line:' + CssColor(Px(P.Border)) +
    ';--head1:' + CssColor(Px(P.Head1)) + ';--head2:' + CssColor(Px(P.Head2)) +
    ';--page:' + CssColor(Page) + ';color-scheme:';
  if P.Light then Result := Result + 'light' else Result := Result + 'dark';
  Result := Result + '}';
end;

function ThemeCss: string;
begin
  Result := ThemeCssOf(CurrentTheme);
end;

function IsLightTheme: Boolean;
begin
  Result := PALETTES[ResolveTheme(CurrentTheme)].Light;
end;

function ThemeCssByName(const Name: string): string;
var
  T: TThemeKind;
begin
  Result := '';
  for T := Low(TThemeKind) to High(TThemeKind) do
    if (T <> thAuto) and (THEME_NAMES[T] = LowerCase(Name)) then
      Exit(ThemeCssOf(T));
end;

function ThemesJson: string;
var
  T: TThemeKind;
  P: TPalette;
begin
  Result := '[';
  for T := Low(TThemeKind) to High(TThemeKind) do
  begin
    if T = thAuto then Continue;
    P := PALETTES[T];
    if Result <> '[' then Result := Result + ',';
    Result := Result + '{"name":"' + THEME_NAMES[T] + '","label":"' + ThemeLabel(T) + '"' +
      ',"light":' + BoolToStr(P.Light, 'true', 'false') +
      ',"bg":"' + CssColor(Px(P.Bg)) + '","side":"' + CssColor(Px(P.Side)) + '"' +
      ',"text":"' + CssColor(Px(P.Text)) + '","dim":"' + CssColor(Px(P.Dim)) + '"' +
      ',"accent":"' + CssColor(Px(P.Accent)) + '","accent2":"' + CssColor(Px(P.Accent2)) + '"}';
  end;
  Result := Result + ']';
end;

function Sc(V: Single): Single;
begin
  Result := V * UIScale;
end;

function ScI(V: Single): Integer;
begin
  Result := Round(V * UIScale);
end;

function WithAlpha(C: TBGRAPixel; A: Byte): TBGRAPixel;
begin
  Result := C;
  Result.alpha := A;
end;

function Mix(A, B: TBGRAPixel; T: Single): TBGRAPixel;
begin
  Result.red := Round(A.red + (B.red - A.red) * T);
  Result.green := Round(A.green + (B.green - A.green) * T);
  Result.blue := Round(A.blue + (B.blue - A.blue) * T);
  Result.alpha := Round(A.alpha + (B.alpha - A.alpha) * T);
end;

function ThemeFont: string;
begin
  {$IFDEF WINDOWS}
  Result := 'Segoe UI';
  {$ELSE}
  {$IFDEF DARWIN}
  Result := 'Helvetica Neue';
  {$ELSE}
  Result := 'Sans';
  {$ENDIF}
  {$ENDIF}
end;

procedure SetFont(B: TBGRABitmap; SizePt: Single; Bold: Boolean);
begin
  B.FontName := ThemeFont;
  B.FontHeight := Round(SizePt * 96 / 72 * UIScale * 1.25);   // em box incl. line gap
  if Bold then B.FontStyle := [fsBold] else B.FontStyle := [];
  B.FontQuality := fqSystemClearType;
end;

function TextW(B: TBGRABitmap; const S: string): Integer;
begin
  Result := B.TextSize(S).cx;
end;

function Ellipsize(B: TBGRABitmap; const S: string; MaxW: Integer): string;
var
  L: Integer;
begin
  Result := S;
  if (MaxW <= 0) or (TextW(B, S) <= MaxW) then Exit;
  L := UTF8Length(S);
  while L > 0 do
  begin
    Dec(L);
    Result := UTF8Copy(S, 1, L) + '…';
    if TextW(B, Result) <= MaxW then Exit;
  end;
  Result := '';
end;

procedure TextIn(B: TBGRABitmap; const R: TRect; const S: string; C: TBGRAPixel;
  Align: TAlignment);
var
  T: string;
  H, W, X: Integer;
begin
  T := Ellipsize(B, S, R.Width);
  H := B.TextSize('Ag').cy;
  W := TextW(B, T);
  case Align of
    taRightJustify: X := R.Right - W;
    taCenter: X := R.Left + (R.Width - W) div 2;
  else
    X := R.Left;
  end;
  B.TextOut(X, R.Top + (R.Height - H) div 2, T, C);
end;

procedure FillGradientRoundRect(B: TBGRABitmap; X1, Y1, X2, Y2, R: Single;
  C1, C2: TBGRAPixel; Horizontal: Boolean);
var
  G: TBGRAGradientScanner;
begin
  if Horizontal then
    G := TBGRAGradientScanner.Create(C1, C2, gtLinear, PointF(X1, Y1), PointF(X2, Y1))
  else
    G := TBGRAGradientScanner.Create(C1, C2, gtLinear, PointF(X1, Y1), PointF(X1, Y2));
  try
    B.FillRoundRectAntialias(X1, Y1, X2, Y2, R, R, G);
  finally
    G.Free;
  end;
end;

{ ---------- line icons (drawn in a unit square) ---------- }

procedure DrawIcon(B: TBGRABitmap; Kind: TIconKind; X, Y, S: Single; C: TBGRAPixel);
var
  W: Single;
  Pts: array of TPointF;
  I: Integer;
  A: Single;

  function P(FX, FY: Single): TPointF;
  begin
    Result := PointF(X + FX * S, Y + FY * S);
  end;

  procedure Line(const APts: array of TPointF);
  begin
    B.DrawPolyLineAntialias(APts, C, W);
  end;

  procedure Dot(FX, FY, FR: Single);
  begin
    B.FillEllipseAntialias(X + FX * S, Y + FY * S, FR * S, FR * S, C);
  end;

begin
  W := Max(1.4, S * 0.085);
  B.LineCap := pecRound;
  B.JoinStyle := pjsRound;
  case Kind of
    ikBack:    Line([P(0.6, 0.22), P(0.32, 0.5), P(0.6, 0.78)]);
    ikChevron: Line([P(0.4, 0.26), P(0.62, 0.5), P(0.4, 0.74)]);
    ikUp:
      begin
        Line([P(0.5, 0.8), P(0.5, 0.22)]);
        Line([P(0.26, 0.45), P(0.5, 0.21), P(0.74, 0.45)]);
      end;
    ikRefresh:
      begin
        SetLength(Pts, 25);
        for I := 0 to 24 do
        begin
          A := DegToRad(-50 + I * (280 / 24));
          Pts[I] := P(0.5 + 0.29 * Cos(A), 0.5 + 0.29 * Sin(A));
        end;
        Line(Pts);
        // arrow head at the start of the arc
        A := DegToRad(-50);
        Line([P(0.5 + 0.29 * Cos(A) - 0.02, 0.5 + 0.29 * Sin(A) - 0.2),
              P(0.5 + 0.29 * Cos(A), 0.5 + 0.29 * Sin(A)),
              P(0.5 + 0.29 * Cos(A) - 0.2, 0.5 + 0.29 * Sin(A) + 0.01)]);
      end;
    ikDownload:
      begin
        Line([P(0.5, 0.14), P(0.5, 0.62)]);
        Line([P(0.3, 0.43), P(0.5, 0.63), P(0.7, 0.43)]);
        Line([P(0.17, 0.66), P(0.17, 0.84), P(0.83, 0.84), P(0.83, 0.66)]);
      end;
    ikUpload:
      begin
        Line([P(0.5, 0.62), P(0.5, 0.15)]);
        Line([P(0.3, 0.35), P(0.5, 0.15), P(0.7, 0.35)]);
        Line([P(0.17, 0.66), P(0.17, 0.84), P(0.83, 0.84), P(0.83, 0.66)]);
      end;
    ikPlus:
      begin
        Line([P(0.5, 0.2), P(0.5, 0.8)]);
        Line([P(0.2, 0.5), P(0.8, 0.5)]);
      end;
    ikClose:
      begin
        Line([P(0.28, 0.28), P(0.72, 0.72)]);
        Line([P(0.72, 0.28), P(0.28, 0.72)]);
      end;
    ikCheck: Line([P(0.2, 0.52), P(0.41, 0.73), P(0.8, 0.29)]);
    ikTrash:
      begin
        Line([P(0.16, 0.27), P(0.84, 0.27)]);
        Line([P(0.39, 0.27), P(0.41, 0.15), P(0.59, 0.15), P(0.61, 0.27)]);
        Line([P(0.25, 0.27), P(0.3, 0.86), P(0.7, 0.86), P(0.75, 0.27)]);
        Line([P(0.43, 0.42), P(0.44, 0.72)]);
        Line([P(0.57, 0.42), P(0.56, 0.72)]);
      end;
    ikShare:
      begin
        Line([P(0.7, 0.25), P(0.3, 0.5), P(0.7, 0.75)]);
        Dot(0.72, 0.24, 0.12);
        Dot(0.28, 0.5, 0.12);
        Dot(0.72, 0.76, 0.12);
      end;
    ikFolderOpen:
      begin
        Line([P(0.14, 0.78), P(0.14, 0.2), P(0.4, 0.2), P(0.48, 0.3), P(0.82, 0.3), P(0.82, 0.44)]);
        Line([P(0.14, 0.78), P(0.27, 0.46), P(0.93, 0.46), P(0.8, 0.78), P(0.14, 0.78)]);
      end;
    ikFolderPlus, ikFilePlus:
      begin
        if Kind = ikFolderPlus then
          Line([P(0.12, 0.8), P(0.12, 0.2), P(0.38, 0.2), P(0.46, 0.3), P(0.88, 0.3), P(0.88, 0.5)])
        else
          Line([P(0.6, 0.12), P(0.2, 0.12), P(0.2, 0.88), P(0.52, 0.88)]);
        if Kind = ikFolderPlus then
          Line([P(0.12, 0.8), P(0.5, 0.8)])
        else
          Line([P(0.6, 0.12), P(0.8, 0.32), P(0.8, 0.5)]);
        Line([P(0.75, 0.6), P(0.75, 0.94)]);
        Line([P(0.58, 0.77), P(0.92, 0.77)]);
      end;
    ikViewDetails:
      // rows with a small icon and two columns
      for I := 0 to 2 do
      begin
        Dot(0.2, 0.27 + I * 0.23, 0.055);
        Line([P(0.34, 0.27 + I * 0.23), P(0.6, 0.27 + I * 0.23)]);
        Line([P(0.7, 0.27 + I * 0.23), P(0.84, 0.27 + I * 0.23)]);
      end;
    ikViewList:
      // two columns of short rows
      for I := 0 to 2 do
      begin
        Dot(0.17, 0.27 + I * 0.23, 0.05);
        Line([P(0.27, 0.27 + I * 0.23), P(0.43, 0.27 + I * 0.23)]);
        Dot(0.57, 0.27 + I * 0.23, 0.05);
        Line([P(0.67, 0.27 + I * 0.23), P(0.83, 0.27 + I * 0.23)]);
      end;
    ikViewIcons:
      // 2 x 2 tiles
      for I := 0 to 3 do
        B.RoundRectAntialias(X + (0.16 + (I mod 2) * 0.38) * S, Y + (0.16 + (I div 2) * 0.38) * S,
          X + (0.46 + (I mod 2) * 0.38) * S, Y + (0.46 + (I div 2) * 0.38) * S, 0.06 * S, 0.06 * S, C, W);
    ikEdit:
      begin
        // pencil
        Line([P(0.2, 0.8), P(0.25, 0.62), P(0.66, 0.21), P(0.79, 0.34), P(0.38, 0.75), P(0.2, 0.8)]);
        Line([P(0.57, 0.3), P(0.7, 0.43)]);
      end;
    ikComputer:
      begin
        B.RoundRectAntialias(X + 0.12 * S, Y + 0.18 * S, X + 0.88 * S, Y + 0.66 * S,
          0.07 * S, 0.07 * S, C, W);
        Line([P(0.5, 0.66), P(0.5, 0.8)]);
        Line([P(0.32, 0.82), P(0.68, 0.82)]);
      end;
    ikGear:
      begin
        SetLength(Pts, 49);
        for I := 0 to 48 do
        begin
          A := DegToRad(I * 7.5);
          if (I mod 6) < 3 then
            Pts[I] := P(0.5 + 0.38 * Cos(A), 0.5 + 0.38 * Sin(A))
          else
            Pts[I] := P(0.5 + 0.28 * Cos(A), 0.5 + 0.28 * Sin(A));
        end;
        Line(Pts);
        B.EllipseAntialias(X + 0.5 * S, Y + 0.5 * S, 0.11 * S, 0.11 * S, C, W, BGRAPixelTransparent);
      end;
    ikEye:
      begin
        SetLength(Pts, 25);
        for I := 0 to 24 do
        begin
          A := DegToRad(180 + I * 7.5);
          Pts[I] := P(0.5 + 0.4 * Cos(A), 0.5 + 0.26 * Sin(A));
        end;
        Line(Pts);
        for I := 0 to 24 do
        begin
          A := DegToRad(I * 7.5);
          Pts[I] := P(0.5 + 0.4 * Cos(A), 0.5 + 0.26 * Sin(A));
        end;
        Line(Pts);
        B.EllipseAntialias(X + 0.5 * S, Y + 0.5 * S, 0.12 * S, 0.12 * S, C, W, BGRAPixelTransparent);
      end;
    ikNetwork:
      begin
        Line([P(0.5, 0.5), P(0.2, 0.2)]);
        Line([P(0.5, 0.5), P(0.8, 0.2)]);
        Line([P(0.5, 0.5), P(0.2, 0.8)]);
        Line([P(0.5, 0.5), P(0.8, 0.8)]);
        Dot(0.5, 0.5, 0.15);
        Dot(0.2, 0.2, 0.1);
        Dot(0.8, 0.2, 0.1);
        Dot(0.2, 0.8, 0.1);
        Dot(0.8, 0.8, 0.1);
      end;
  end;
end;

{ ---------- coloured icons ---------- }

procedure DrawFolderIcon(B: TBGRABitmap; X, Y, S: Single; Shared: Boolean);
var
  R: Single;
begin
  R := S * 0.07;
  // back plate with tab
  B.FillRoundRectAntialias(X + 0.06 * S, Y + 0.16 * S, X + 0.46 * S, Y + 0.4 * S, R, R,
    BGRA(214, 145, 36));
  B.FillRoundRectAntialias(X + 0.06 * S, Y + 0.24 * S, X + 0.94 * S, Y + 0.6 * S, R, R,
    BGRA(214, 145, 36));
  // front
  FillGradientRoundRect(B, X + 0.06 * S, Y + 0.32 * S, X + 0.94 * S, Y + 0.86 * S, R,
    BGRA(255, 213, 102), BGRA(246, 172, 46), False);
  B.DrawLineAntialias(X + 0.1 * S, Y + 0.355 * S, X + 0.9 * S, Y + 0.355 * S,
    BGRA(255, 236, 170, 200), Max(1, S * 0.025));
  if Shared then
  begin
    B.FillEllipseAntialias(X + 0.78 * S, Y + 0.76 * S, 0.2 * S, 0.2 * S, clAccent);
    B.EllipseAntialias(X + 0.78 * S, Y + 0.76 * S, 0.2 * S, 0.2 * S, clBg, Max(1, S * 0.04), BGRAPixelTransparent);
    DrawIcon(B, ikShare, X + 0.63 * S, Y + 0.61 * S, 0.3 * S, BGRAWhite);
  end;
end;

function ExtOf(const FileName: string): string;
begin
  Result := LowerCase(Copy(ExtractFileExt(FileName), 2, 10));
end;

function InList(const E, List: string): Boolean;
begin
  Result := (E <> '') and (Pos(' ' + E + ' ', ' ' + List + ' ') > 0);
end;

function FileColor(const FileName: string): TBGRAPixel;
var
  E: string;
begin
  E := ExtOf(FileName);
  if InList(E, 'jpg jpeg png gif bmp webp svg ico heic tif tiff raw psd') then Result := BGRA(46, 204, 113)
  else if InList(E, 'mp4 mkv avi mov wmv webm flv m4v mpg mpeg') then Result := BGRA(155, 89, 182)
  else if InList(E, 'mp3 wav flac aac ogg m4a wma opus') then Result := BGRA(232, 67, 147)
  else if InList(E, 'zip rar 7z tar gz bz2 xz iso tgz') then Result := BGRA(243, 156, 18)
  else if E = 'pdf' then Result := BGRA(231, 76, 60)
  else if InList(E, 'md markdown') then Result := BGRA(0, 180, 216)
  else if InList(E, 'doc docx odt rtf txt log') then Result := BGRA(52, 152, 219)
  else if InList(E, 'xls xlsx csv ods') then Result := BGRA(39, 174, 96)
  else if InList(E, 'ppt pptx odp key') then Result := BGRA(230, 126, 34)
  else if InList(E, 'pas pp lpr lpi lfm inc c cpp h hpp cs js ts py java html htm css json xml yml yaml sh bat ps1 go rs php sql') then
    Result := BGRA(26, 188, 156)
  else if InList(E, 'exe msi dll appimage deb rpm apk dmg pkg so') then Result := BGRA(120, 135, 160)
  else Result := BGRA(130, 140, 155);
end;

procedure DrawFileIcon(B: TBGRABitmap; const FileName: string; X, Y, S: Single);
var
  C: TBGRAPixel;
  E: string;
  FH: Integer;
begin
  C := FileColor(FileName);
  // page
  B.FillPolyAntialias([PointF(X + 0.2 * S, Y + 0.06 * S), PointF(X + 0.62 * S, Y + 0.06 * S),
    PointF(X + 0.84 * S, Y + 0.28 * S), PointF(X + 0.84 * S, Y + 0.94 * S),
    PointF(X + 0.2 * S, Y + 0.94 * S)], clIconPage);
  // folded corner
  B.FillPolyAntialias([PointF(X + 0.62 * S, Y + 0.06 * S), PointF(X + 0.84 * S, Y + 0.28 * S),
    PointF(X + 0.62 * S, Y + 0.28 * S)], BGRA(190, 198, 212));
  // coloured label
  B.FillRoundRectAntialias(X + 0.1 * S, Y + 0.54 * S, X + 0.74 * S, Y + 0.82 * S,
    S * 0.05, S * 0.05, C);
  E := UpperCase(ExtOf(FileName));
  if (E <> '') and (S >= 22) then
  begin
    if Length(E) > 4 then E := Copy(E, 1, 4);
    FH := Round(S * 0.22);
    B.FontName := 'Arial';
    B.FontStyle := [fsBold];
    B.FontQuality := fqFineAntialiasing;
    B.FontHeight := FH;
    B.TextOut(X + 0.42 * S, Y + 0.68 * S - FH / 2, E, BGRAWhite, taCenter);
  end
  else
    B.FillRoundRectAntialias(X + 0.28 * S, Y + 0.33 * S, X + 0.7 * S, Y + 0.4 * S,
      S * 0.03, S * 0.03, BGRA(200, 206, 216));
end;

function OSLabel(const OS: string): string;
begin
  if OS = 'windows' then Result := 'Windows'
  else if OS = 'linux' then Result := 'Linux'
  else if OS = 'macos' then Result := 'macOS'
  else if OS = 'android' then Result := 'Android'
  else if OS = 'ios' then Result := 'iOS'
  else if OS = 'bsd' then Result := 'BSD'
  else Result := '';
end;

procedure DrawAppLogo(B: TBGRABitmap; X, Y, S: Single);
begin
  FillGradientRoundRect(B, X, Y, X + S, Y + S, S * 0.26, clAccent, clAccent2, False);
  // soft sheen fading from the top
  FillGradientRoundRect(B, X, Y, X + S, Y + S, S * 0.26, BGRA(255, 255, 255, 46),
    BGRA(255, 255, 255, 0), False);
  DrawIcon(B, ikNetwork, X + S * 0.17, Y + S * 0.17, S * 0.66, BGRAWhite);
end;

function DeviceColor(Index: Integer): TBGRAPixel;
begin
  case Index of
    1: Result := BGRA(138, 92, 246);    // purple
    2: Result := BGRA(20, 184, 166);    // teal
    3: Result := BGRA(52, 199, 89);     // green
    4: Result := BGRA(255, 149, 0);     // orange
    5: Result := BGRA(236, 72, 153);    // pink
    6: Result := BGRA(239, 68, 68);     // red
    7: Result := BGRA(100, 116, 139);   // slate
  else
    Result := BGRA(59, 130, 246);       // blue
  end;
end;

function MakeDeviceIcon(Kind, Color: Integer): string;
begin
  Result := DEVICE_KINDS[EnsureRange(Kind, 0, High(DEVICE_KINDS))] + '.' +
    IntToStr(EnsureRange(Color, 0, DEVICE_COLOR_COUNT - 1));
end;

procedure ParseDeviceIcon(const Icon, OS: string; out Kind, Color: Integer);
var
  P, I: Integer;
  K: string;
begin
  if (OS = 'android') or (OS = 'ios') then Kind := 2 else Kind := 0;
  Color := 0;
  P := Pos('.', Icon);
  if P = 0 then Exit;
  K := Copy(Icon, 1, P - 1);
  for I := 0 to High(DEVICE_KINDS) do
    if DEVICE_KINDS[I] = K then Kind := I;
  Color := EnsureRange(StrToIntDef(Copy(Icon, P + 1, 3), 0), 0, DEVICE_COLOR_COUNT - 1);
end;

{ white glyph for a device kind, drawn in the unit square at X,Y size S }
procedure DrawDeviceGlyph(B: TBGRABitmap; Kind: Integer; X, Y, S: Single; C: TBGRAPixel);
var
  W: Single;

  function P(FX, FY: Single): TPointF;
  begin
    Result := PointF(X + FX * S, Y + FY * S);
  end;

  procedure Line(const APts: array of TPointF);
  begin
    B.DrawPolyLineAntialias(APts, C, W);
  end;

  procedure Box(X1, Y1, X2, Y2, R: Single);
  begin
    B.RoundRectAntialias(X + X1 * S, Y + Y1 * S, X + X2 * S, Y + Y2 * S, R * S, R * S, C, W);
  end;

  procedure Dot(FX, FY, FR: Single);
  begin
    B.FillEllipseAntialias(X + FX * S, Y + FY * S, FR * S, FR * S, C);
  end;

begin
  W := Max(1.3, S * 0.075);
  B.LineCap := pecRound;
  B.JoinStyle := pjsRound;
  case Kind of
    1: begin  // laptop
         Box(0.2, 0.22, 0.8, 0.64, 0.05);
         Line([P(0.08, 0.76), P(0.92, 0.76)]);
       end;
    2: begin  // phone
         Box(0.32, 0.12, 0.68, 0.88, 0.08);
         Dot(0.5, 0.76, 0.035);
       end;
    3: begin  // tablet
         Box(0.2, 0.14, 0.8, 0.86, 0.07);
         Dot(0.5, 0.76, 0.035);
       end;
    4: begin  // server
         Box(0.2, 0.14, 0.8, 0.42, 0.05);
         Box(0.2, 0.58, 0.8, 0.86, 0.05);
         Dot(0.32, 0.28, 0.035);
         Dot(0.32, 0.72, 0.035);
         Line([P(0.48, 0.28), P(0.68, 0.28)]);
         Line([P(0.48, 0.72), P(0.68, 0.72)]);
       end;
    5: begin  // tv
         Box(0.1, 0.2, 0.9, 0.7, 0.05);
         Line([P(0.36, 0.84), P(0.64, 0.84)]);
         Line([P(0.5, 0.7), P(0.5, 0.84)]);
       end;
    6: begin  // store
         Line([P(0.14, 0.4), P(0.2, 0.18), P(0.8, 0.18), P(0.86, 0.4)]);
         Line([P(0.14, 0.4), P(0.86, 0.4)]);
         Line([P(0.22, 0.4), P(0.22, 0.84), P(0.78, 0.84), P(0.78, 0.4)]);
         Line([P(0.42, 0.84), P(0.42, 0.6), P(0.58, 0.6), P(0.58, 0.84)]);
       end;
    7: begin  // megaphone
         Line([P(0.18, 0.4), P(0.18, 0.6), P(0.34, 0.6), P(0.74, 0.8), P(0.74, 0.2), P(0.34, 0.4), P(0.18, 0.4)]);
         Line([P(0.3, 0.6), P(0.36, 0.82)]);
         Line([P(0.84, 0.42), P(0.84, 0.58)]);
       end;
  else
    begin    // desktop
      Box(0.12, 0.16, 0.88, 0.64, 0.06);
      Line([P(0.5, 0.64), P(0.5, 0.8)]);
      Line([P(0.3, 0.82), P(0.7, 0.82)]);
    end;
  end;
end;

procedure DrawDeviceAvatar(B: TBGRABitmap; const Icon, OS: string; X, Y, S: Single;
  Online: Boolean; ShowDot: Boolean);
var
  Kind, Color: Integer;
  C1, C2: TBGRAPixel;
begin
  ParseDeviceIcon(Icon, OS, Kind, Color);
  C1 := DeviceColor(Color);
  if not Online then C1 := Mix(C1, BGRA(70, 76, 90), 0.75);
  C2 := Mix(C1, BGRABlack, 0.35);
  FillGradientRoundRect(B, X, Y, X + S, Y + S, S * 0.28, Mix(C1, BGRAWhite, 0.12), C2, False);
  DrawDeviceGlyph(B, Kind, X + S * 0.18, Y + S * 0.18, S * 0.64, BGRAWhite);
  if ShowDot then
  begin
    B.FillEllipseAntialias(X + S * 0.92, Y + S * 0.92, S * 0.15, S * 0.15, clSide);
    if Online then
      B.FillEllipseAntialias(X + S * 0.92, Y + S * 0.92, S * 0.1, S * 0.1, clOk)
    else
      B.FillEllipseAntialias(X + S * 0.92, Y + S * 0.92, S * 0.1, S * 0.1, BGRA(120, 126, 140));
  end;
end;

initialization
  SetTheme(thDark);
end.
