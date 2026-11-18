unit UIWidgets;

{ Custom controls painted entirely with BGRABitmap:
    THeaderBar     gradient title bar
    TFlatButton    rounded icon/text button
    TSidebar       list of computers + receive settings
    TPathBar       breadcrumb  (เครื่อง > แชร์ > โฟลเดอร์)
    TFileView      Explorer-style details list with icons, multi-select, scrolling
    TTransfersView list of transfers with progress bars }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, Forms,
  BGRABitmap, BGRABitmapTypes, UITheme, LanNet, I18n;

type
  { which theme colour a control is filled with; kept as a role so that a
    theme change repaints everything in the new colours }
  TBackRole = (brCustom, brBg, brSide, brPanel, brCard, brHead);

  { Base: double-buffered control drawn with a TBGRABitmap }
  TBGRAControl = class(TCustomControl)
  private
    FBackRole: TBackRole;
    FBackCustom: TBGRAPixel;
    function GetBackColor: TBGRAPixel;
    procedure SetBackColor(const C: TBGRAPixel);
  protected
    procedure Paint; override;
    procedure Render(B: TBGRABitmap); virtual;
  public
    procedure EraseBackground(DC: HDC); override;
    constructor Create(AOwner: TComponent); override;
    { assigning a theme colour (clBg, clPanel...) remembers its role }
    property BackColor: TBGRAPixel read GetBackColor write SetBackColor;
  end;

  { ---------- header ---------- }
  THeaderBar = class(TBGRAControl)
  protected
    procedure Render(B: TBGRABitmap); override;
  public
    SubTitle: string;
    Status: string;
    StatusOK: Boolean;
    RightReserve: Integer;   // width used by child buttons on the right
    MyIcon: string;          // this machine's device icon, shown as a badge on the logo
  end;

  { ---------- button ---------- }
  TButtonStyle = (bsGhost, bsNormal, bsAccent, bsDanger);

  TFlatButton = class(TBGRAControl)
  private
    FIcon: TIconKind;
    FStyle: TButtonStyle;
    FHot, FDown: Boolean;
    procedure SetIcon(AValue: TIconKind);
    procedure SetStyle(AValue: TButtonStyle);
  protected
    procedure Render(B: TBGRABitmap); override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure TextChanged; override;
    procedure SetEnabled(Value: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure FitWidth;
    property Icon: TIconKind read FIcon write SetIcon;
    property Style: TButtonStyle read FStyle write SetStyle;
  end;

  { ---------- sidebar ---------- }
  TSideItem = record
    ID: string;
    Title: string;
    Subtitle: string;
    IP: string;
    Port: Integer;
    IsMe: Boolean;
    Manual: Boolean;
    OS: string;          // windows / linux / macos / android / ios ...
    Icon: string;        // '<kind>.<color>' chosen by its owner
    Caps: string;        // bin,http,push
    CanBrowse: Boolean;  // speaks the binary protocol ('bin')
    Online: Boolean;
    LastSeen: QWord;
    { identity (empty for old versions and for devices that never announced) }
    Host: string;        // computer name
    User: string;        // login name
    Machine: string;     // machine code: the same after renames and restarts
    Version: string;
    Names: string;       // every display name seen, newest last, one per line
    FirstSeenAt: TDateTime;
    LastSeenAt: TDateTime;
  end;

  { Index = -1: right click on the empty part of the list }
  TSideContextEvent = procedure(Sender: TObject; Index: Integer; const ScreenPt: TPoint) of object;
  TContextPtEvent = procedure(Sender: TObject; const ScreenPt: TPoint) of object;

  TSidebar = class(TBGRAControl)
  private
    FHot: Integer;
    FScroll: Integer;
    FRectDir, FRectOpen, FRectToggle, FRectRefresh: TRect;
    FHotZone: Integer;
    function RowH: Integer;
    function ListTop: Integer;
    function ListBottom: Integer;
    function ItemAt(Y: Integer): Integer;
  protected
    procedure Render(B: TBGRABitmap); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    Items: array of TSideItem;
    Selected: Integer;
    DownloadDir: string;
    AutoAccept: Boolean;
    OnSelect: TNotifyEvent;
    OnPickDir: TNotifyEvent;
    OnOpenDir: TNotifyEvent;
    OnToggleAuto: TNotifyEvent;
    OnContext: TSideContextEvent;   // right click on a row (or empty space: -1)
    OnRefresh: TNotifyEvent;        // refresh button next to the heading
    Refreshing: Boolean;            // a refresh is running: button drawn active
    BottomReserve: Integer;   // space used by child buttons at the bottom
    constructor Create(AOwner: TComponent); override;
    function IndexOfID(const AID: string): Integer;
  end;

  { ---------- breadcrumb ---------- }
  TPathBar = class(TBGRAControl)
  private
    FRects: array of TRect;
    FHot: Integer;
  protected
    procedure Render(B: TBGRABitmap); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    Segments: array of string;
    Clicked: Integer;
    OnSegment: TNotifyEvent;
    constructor Create(AOwner: TComponent); override;
  end;

  { ---------- file list ---------- }
  TViewItem = record
    Name: string;
    IsDir: Boolean;
    Size: Int64;
    Modified: TDateTime;
    Info: string;        // 3rd column text (location or date)
    LocalPath: string;
    Shared: Boolean;     // draw share badge
    Writable: Boolean;   // others may change it (Read + Write share)
  end;
  TViewItems = array of TViewItem;
  TIntArray = array of Integer;

  { Details: one row per item with columns; List: compact rows in several
    columns; Icons: large tiles }
  TViewMode = (vmDetails, vmList, vmIcons);

  TFileView = class(TBGRAControl)
  private
    FViewMode: TViewMode;
    FItems: TViewItems;
    FSel: array of Boolean;
    FFocus, FAnchor, FHot: Integer;
    FScroll: Integer;
    FDragThumb: Boolean;
    FDragY0, FDragScroll0: Integer;
    FPressed: Boolean;           // left button down on a row: may become a drag-out
    FPressPt: TPoint;
    FDeferSelect: Integer;       // row to select alone on mouse-up (when no drag happened)
    function RowH: Integer;       // height of one row of cells
    function CellW: Integer;
    function Cols: Integer;
    function HeadH: Integer;
    function ContentH: Integer;
    function MaxScroll: Integer;
    function ItemRect(I: Integer): TRect;
    function ItemAt(X, Y: Integer): Integer;
    procedure SetViewMode(V: TViewMode);
    function ThumbRect: TRect;
    procedure SetScroll(V: Integer);
    procedure EnsureVisible(I: Integer);
    procedure SelectOnly(I: Integer);
    procedure SelChanged;
  protected
    procedure Render(B: TBGRABitmap); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure Resize; override;
  public
    Col3Title: string;
    EmptyTitle, EmptyText: string;
    IsLoading: Boolean;
    ErrorText: string;
    OnOpen: TNotifyEvent;       // double-click / Enter on FocusIndex
    OnSelChange: TNotifyEvent;
    OnBack: TNotifyEvent;       // Backspace
    OnDragOut: TNotifyEvent;    // selected rows dragged out of the list
    OnCopy: TNotifyEvent;       // Ctrl+C on selected rows
    OnRefresh: TNotifyEvent;    // F5
    OnContext: TContextPtEvent; // right click / menu key (selection already updated)
    OnRename: TNotifyEvent;     // F2
    OnDelete: TNotifyEvent;     // Delete key
    constructor Create(AOwner: TComponent); override;
    procedure SetItems(const A: TViewItems);
    procedure Clear;
    function Count: Integer;
    function Item(I: Integer): TViewItem;
    function SelCount: Integer;
    function SelectedIdx: TIntArray;
    procedure SelectAll;
    property FocusIndex: Integer read FFocus;
    property ViewMode: TViewMode read FViewMode write SetViewMode;
  end;

  { ---------- transfers ---------- }
  TCardMember = record
    Serial: PtrUInt;
    Done, Total: Int64;
    State: TTransferState;
  end;

  TTransferCard = record
    Key: string;                     // Group of the transfers, or 'S'+serial
    Members: array of TCardMember;   // HTTP batches have one member per file
    GroupFiles: Integer;
    GroupBytes: Int64;
    Ended: Boolean;                  // batch closed by the client
    LastUpdate: QWord;
    Kind: TTransferKind;
    State: TTransferState;
    Title, Peer, Msg, CurFile: string;
    Done, Total: Int64;
    Speed: Double;
    SpeedDone: Int64;
    SpeedTick: QWord;
  end;

  TTransfersView = class(TBGRAControl)
  private
    FCards: array of TTransferCard;
    FScroll: Integer;
    FHotCancel: Integer;
    FHotClear: Boolean;
    FCancelRects: array of TRect;
    FClearRect: TRect;
    function RowH: Integer;
    function HeadH: Integer;
  protected
    procedure Render(B: TBGRABitmap); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    CancelSerials: array of PtrUInt;   // active members of the card to cancel
    OnCancel: TNotifyEvent;
    constructor Create(AOwner: TComponent); override;
    procedure UpdateFrom(const T: TTransferInfo);
    procedure Tick;   // call every few seconds: closes batches that went quiet
    function ActiveCount: Integer;
    procedure ClearFinished;
  end;

function IsActiveState(S: TTransferState): Boolean;

implementation

uses
  Math, LCLIntf;

function IsActiveState(S: TTransferState): Boolean;
begin
  Result := S in [tsConnecting, tsWaiting, tsRunning];
end;

function PtIn(const R: TRect; X, Y: Integer): Boolean;
begin
  Result := (X >= R.Left) and (X < R.Right) and (Y >= R.Top) and (Y < R.Bottom);
end;

{ ================= TBGRAControl ================= }

constructor TBGRAControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BackColor := clPanel;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := False;
end;

function SamePx(const A, B: TBGRAPixel): Boolean;
begin
  Result := (A.red = B.red) and (A.green = B.green) and (A.blue = B.blue) and (A.alpha = B.alpha);
end;

function TBGRAControl.GetBackColor: TBGRAPixel;
begin
  case FBackRole of
    brBg:    Result := clBg;
    brSide:  Result := clSide;
    brPanel: Result := clPanel;
    brCard:  Result := clCard;
    brHead:  Result := clHead2;
  else
    Result := FBackCustom;
  end;
end;

procedure TBGRAControl.SetBackColor(const C: TBGRAPixel);
begin
  if SamePx(C, clBg) then FBackRole := brBg
  else if SamePx(C, clSide) then FBackRole := brSide
  else if SamePx(C, clPanel) then FBackRole := brPanel
  else if SamePx(C, clCard) then FBackRole := brCard
  else if SamePx(C, clHead2) then FBackRole := brHead
  else
  begin
    FBackRole := brCustom;
    FBackCustom := C;
  end;
  Invalidate;
end;

procedure TBGRAControl.EraseBackground(DC: HDC);
begin
  // everything is painted in Paint: avoid flicker
end;

procedure TBGRAControl.Render(B: TBGRABitmap);
begin
end;

procedure TBGRAControl.Paint;
var
  B: TBGRABitmap;
begin
  if (ClientWidth <= 0) or (ClientHeight <= 0) then Exit;
  B := TBGRABitmap.Create(ClientWidth, ClientHeight, BackColor);
  try
    Render(B);
    B.Draw(Canvas, 0, 0, True);
  finally
    B.Free;
  end;
end;

{ ================= THeaderBar ================= }

procedure THeaderBar.Render(B: TBGRABitmap);
var
  S, X, W, Badge, BX, BY: Integer;
  R: TRect;
begin
  B.GradientFill(0, 0, B.Width, B.Height, clHead1, clHead2, gtLinear,
    PointF(0, 0), PointF(B.Width, B.Height), dmSet);
  // subtle bottom line
  B.FillRect(0, B.Height - 1, B.Width, B.Height, WithAlpha(clAccent, 90), dmDrawWithTransparency);
  // logo
  S := ScI(40);
  X := ScI(16);
  DrawAppLogo(B, X, (B.Height - S) / 2, S);
  // this machine's own icon as a badge on the logo's corner, so several
  // LAN Share windows are easy to tell apart (the program icon stays)
  if MyIcon <> '' then
  begin
    Badge := Round(S * 0.62);
    BX := X + S - Badge + ScI(6);
    BY := Round((B.Height + S) / 2) - Badge + ScI(6);
    // ring in the header colour separates the badge from the logo
    B.FillRoundRectAntialias(BX - Sc(2.5), BY - Sc(2.5), BX + Badge + Sc(2.5), BY + Badge + Sc(2.5),
      Badge * 0.36, Badge * 0.36, Mix(clHead1, clHead2, 0.15));
    DrawDeviceAvatar(B, MyIcon, '', BX, BY, Badge, True, False);
  end;
  // title
  SetFont(B, 14, True);
  B.TextOut(X + S + ScI(16), ScI(9), 'LAN Share', clText);
  // status pill (right) gets at most 45% of the width; subtitle uses the rest
  R := Rect(B.Width - RightReserve, 0, B.Width - RightReserve, 0);
  if Status <> '' then
  begin
    SetFont(B, 9);
    W := Min(TextW(B, Status), Round(B.Width * 0.45) - ScI(36)) + ScI(36);
    R := Rect(B.Width - RightReserve - W - ScI(16), (B.Height - ScI(30)) div 2,
      B.Width - RightReserve - ScI(16), (B.Height + ScI(30)) div 2);
  end;
  SetFont(B, 9);
  B.TextOut(X + S + ScI(16), ScI(36),
    Ellipsize(B, SubTitle, R.Left - (X + S + ScI(16)) - ScI(16)), clTextDim);
  if Status <> '' then
  begin
    SetFont(B, 9);
    B.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, R.Height / 2, R.Height / 2,
      WithAlpha(clText, 20));
    if StatusOK then
      B.FillEllipseAntialias(R.Left + ScI(15), R.Top + R.Height / 2, Sc(4), Sc(4), clOk)
    else
      B.FillEllipseAntialias(R.Left + ScI(15), R.Top + R.Height / 2, Sc(4), Sc(4), clWarn);
    TextIn(B, Rect(R.Left + ScI(26), R.Top, R.Right - ScI(10), R.Bottom), Status, clText);
  end;
end;

{ ================= TFlatButton ================= }

constructor TFlatButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Height := ScI(34);
  Width := ScI(34);
  FStyle := bsNormal;
  BorderSpacing.Around := ScI(4);
end;

procedure TFlatButton.SetIcon(AValue: TIconKind);
begin
  if FIcon = AValue then Exit;
  FIcon := AValue;
  Invalidate;
end;

procedure TFlatButton.SetStyle(AValue: TButtonStyle);
begin
  if FStyle = AValue then Exit;
  FStyle := AValue;
  Invalidate;
end;

procedure TFlatButton.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

procedure TFlatButton.SetEnabled(Value: Boolean);
begin
  inherited SetEnabled(Value);
  Invalidate;
end;

procedure TFlatButton.MouseEnter;
begin
  inherited MouseEnter;
  FHot := True;
  Invalidate;
end;

procedure TFlatButton.MouseLeave;
begin
  inherited MouseLeave;
  FHot := False;
  FDown := False;
  Invalidate;
end;

procedure TFlatButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDown := True;
    Invalidate;
  end;
end;

procedure TFlatButton.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDown := False;
  Invalidate;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TFlatButton.FitWidth;
var
  B: TBGRABitmap;
  W: Integer;
begin
  B := TBGRABitmap.Create(1, 1);
  try
    SetFont(B, 9.5, FStyle = bsAccent);
    if Caption = '' then
      W := ScI(34)
    else
    begin
      W := TextW(B, Caption) + ScI(24);
      if FIcon <> ikNone then Inc(W, ScI(24));
    end;
  finally
    B.Free;
  end;
  Width := W;
end;

procedure TFlatButton.Render(B: TBGRABitmap);
var
  Fill, Fg: TBGRAPixel;
  IS_, X: Single;
  R: Single;
begin
  R := Sc(8);
  Fg := clText;
  case FStyle of
    bsGhost:  if FHot then Fill := clHover else Fill := BGRAPixelTransparent;
    bsNormal: if FHot then Fill := Mix(clCard, clText, 0.07) else Fill := clCard;
    bsAccent: Fill := clAccent;
    bsDanger: if FHot then Fill := Mix(clErr, BGRABlack, 0.1) else Fill := WithAlpha(clErr, 60);
  end;
  if FDown then Fill := Mix(Fill, BGRABlack, 0.15);
  if not Enabled then
  begin
    Fg := WithAlpha(clTextDim, 110);
    if FStyle in [bsAccent, bsDanger] then Fill := clCard;
  end;
  if FStyle = bsAccent then
  begin
    if Enabled then
    begin
      if FHot then
        FillGradientRoundRect(B, 0.5, 0.5, B.Width - 0.5, B.Height - 0.5, R,
          Mix(clAccent, BGRAWhite, 0.12), Mix(clAccent2, BGRAWhite, 0.12))
      else
        FillGradientRoundRect(B, 0.5, 0.5, B.Width - 0.5, B.Height - 0.5, R, clAccent, clAccent2);
      if FDown then
        B.FillRoundRectAntialias(0.5, 0.5, B.Width - 0.5, B.Height - 0.5, R, R, BGRA(0, 0, 0, 40));
      Fg := BGRAWhite;
    end
    else
      B.FillRoundRectAntialias(0.5, 0.5, B.Width - 0.5, B.Height - 0.5, R, R, Fill);
  end
  else if Fill.alpha > 0 then
    B.FillRoundRectAntialias(0.5, 0.5, B.Width - 0.5, B.Height - 0.5, R, R, Fill);

  IS_ := Sc(18);
  if Caption = '' then
  begin
    if FIcon <> ikNone then
      DrawIcon(B, FIcon, (B.Width - IS_) / 2, (B.Height - IS_) / 2, IS_, Fg);
    Exit;
  end;
  X := ScI(12);
  if FIcon <> ikNone then
  begin
    DrawIcon(B, FIcon, X, (B.Height - IS_) / 2, IS_, Fg);
    X := X + IS_ + ScI(6);
  end;
  SetFont(B, 9.5, FStyle = bsAccent);
  TextIn(B, Rect(Round(X), 0, B.Width - ScI(8), B.Height), Caption, Fg);
end;

{ ================= TSidebar ================= }

constructor TSidebar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BackColor := clSide;
  FHot := -1;
  FHotZone := 0;
  Selected := 0;
end;

function TSidebar.RowH: Integer;
begin
  Result := ScI(56);
end;

function TSidebar.ListTop: Integer;
begin
  Result := ScI(46);
end;

function TSidebar.ListBottom: Integer;
begin
  Result := ClientHeight - BottomReserve - ScI(132);
end;

function TSidebar.ItemAt(Y: Integer): Integer;
begin
  Result := -1;
  if (Y < ListTop) or (Y >= ListBottom) then Exit;
  Result := (Y - ListTop + FScroll) div RowH;
  if Result >= Length(Items) then Result := -1;
end;

function TSidebar.IndexOfID(const AID: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Items) do
    if Items[I].ID = AID then Exit(I);
  Result := -1;
end;

procedure TSidebar.Render(B: TBGRABitmap);
var
  I, Y, IconS, CardTop: Integer;
  R: TRect;
  Peers: Integer;
  Sub: string;
  SubC: TBGRAPixel;
begin
  // right border
  B.FillRect(B.Width - 1, 0, B.Width, B.Height, clBorder, dmSet);
  Peers := 0;
  for I := 0 to High(Items) do
    if (not Items[I].IsMe) and Items[I].Online then Inc(Peers);
  SetFont(B, 8.5, True);
  B.TextOut(ScI(18), ScI(18), L('Computers', 'เครื่องในเครือข่าย'), clTextDim);
  // refresh button
  FRectRefresh := Rect(B.Width - ScI(44), ScI(10), B.Width - ScI(14), ScI(40));
  if FHotZone = 4 then
    B.FillRoundRectAntialias(FRectRefresh.Left, FRectRefresh.Top, FRectRefresh.Right, FRectRefresh.Bottom,
      Sc(7), Sc(7), clHover);
  if Refreshing then
    DrawIcon(B, ikRefresh, FRectRefresh.Left + ScI(6), FRectRefresh.Top + ScI(6), ScI(18), clAccent)
  else
    DrawIcon(B, ikRefresh, FRectRefresh.Left + ScI(6), FRectRefresh.Top + ScI(6), ScI(18), clTextDim);
  SetFont(B, 8.5, True);
  if Peers > 0 then
    TextIn(B, Rect(0, ScI(14), FRectRefresh.Left - ScI(4), ScI(34)), IntToStr(Peers) + L(' online', ' ออนไลน์'), clOk, taRightJustify);

  B.ClipRect := Rect(0, ListTop, B.Width, ListBottom);
  IconS := ScI(36);
  for I := 0 to High(Items) do
  begin
    Y := ListTop + I * RowH - FScroll;
    if Y + RowH < ListTop then Continue;
    if Y > ListBottom then Break;
    R := Rect(ScI(8), Y + ScI(2), B.Width - ScI(9), Y + RowH - ScI(2));
    if I = Selected then
    begin
      B.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, Sc(10), Sc(10), clSel);
      B.FillRoundRectAntialias(R.Left, R.Top + ScI(12), R.Left + ScI(3), R.Bottom - ScI(12),
        Sc(2), Sc(2), clSelBorder);
    end
    else if I = FHot then
      B.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, Sc(10), Sc(10), clHover);
    DrawDeviceAvatar(B, Items[I].Icon, Items[I].OS, R.Left + ScI(10), R.Top + (R.Height - IconS) / 2,
      IconS, Items[I].Online, not Items[I].IsMe);
    if (Items[I].Title = '') and (Items[I].Subtitle = '') then
      Continue;   // nothing to say (e.g. this machine without a name): icon only
    SetFont(B, 10, True);
    TextIn(B, Rect(R.Left + ScI(56), R.Top + ScI(6), R.Right - ScI(8), R.Top + ScI(28)),
      Items[I].Title, clText);
    if Items[I].IsMe then
    begin
      Sub := Items[I].Subtitle;
      SubC := clTextDim;
    end
    else if not Items[I].Online then
    begin
      Sub := Items[I].IP + L(' • offline', ' • ออฟไลน์');
      SubC := WithAlpha(clTextDim, 150);
    end
    else
    begin
      if Items[I].Title = Items[I].IP then
        Sub := ''                         // unnamed: the title already is the address
      else
        Sub := Items[I].IP;
      if (Items[I].Port <> DEFAULT_TCP_PORT) and (Sub <> '') then Sub := Sub + ':' + IntToStr(Items[I].Port);
      if OSLabel(Items[I].OS) <> '' then
      begin
        if Sub <> '' then Sub := OSLabel(Items[I].OS) + '  •  ' + Sub
        else Sub := OSLabel(Items[I].OS);
      end;
      SubC := clTextDim;
    end;
    SetFont(B, 8.5);
    TextIn(B, Rect(R.Left + ScI(56), R.Top + ScI(27), R.Right - ScI(8), R.Bottom - ScI(5)), Sub, SubC);
  end;
  B.NoClip;

  if Length(Items) <= 1 then
  begin
    SetFont(B, 8.5);
    R := Rect(ScI(20), ListTop + RowH + ScI(10), B.Width - ScI(20), ListTop + RowH + ScI(56));
    TextIn(B, Rect(R.Left, R.Top, R.Right, R.Top + ScI(20)), L('Looking for other computers...', 'กำลังค้นหาเครื่องอื่น...'), clTextDim, taCenter);
    TextIn(B, Rect(R.Left, R.Top + ScI(20), R.Right, R.Top + ScI(40)), L('Open LAN Share on another computer on this network', 'เปิด LAN Share บนเครื่องอื่นในวงเดียวกัน'), WithAlpha(clTextDim, 160), taCenter);
  end;

  // receive settings card
  CardTop := B.Height - BottomReserve - ScI(124);
  R := Rect(ScI(12), CardTop, B.Width - ScI(13), CardTop + ScI(116));
  B.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, Sc(12), Sc(12), clPanel);
  B.RoundRectAntialias(R.Left + 0.5, R.Top + 0.5, R.Right - 0.5, R.Bottom - 0.5, Sc(12), Sc(12), clBorder, 1);
  SetFont(B, 8.5, True);
  B.TextOut(R.Left + ScI(12), R.Top + ScI(10), L('Receive folder', 'โฟลเดอร์รับไฟล์'), clTextDim);

  FRectDir := Rect(R.Left + ScI(8), R.Top + ScI(32), R.Right - ScI(44), R.Top + ScI(64));
  FRectOpen := Rect(R.Right - ScI(40), R.Top + ScI(32), R.Right - ScI(8), R.Top + ScI(64));
  if FHotZone = 1 then
    B.FillRoundRectAntialias(FRectDir.Left, FRectDir.Top, FRectDir.Right, FRectDir.Bottom, Sc(7), Sc(7), clHover)
  else
    B.FillRoundRectAntialias(FRectDir.Left, FRectDir.Top, FRectDir.Right, FRectDir.Bottom, Sc(7), Sc(7), clCard);
  DrawFolderIcon(B, FRectDir.Left + ScI(6), FRectDir.Top + ScI(6), ScI(20));
  SetFont(B, 8.5);
  TextIn(B, Rect(FRectDir.Left + ScI(32), FRectDir.Top, FRectDir.Right - ScI(6), FRectDir.Bottom),
    ExtractFileName(ExcludeTrailingPathDelimiter(DownloadDir)), clText);
  if FHotZone = 2 then
    B.FillRoundRectAntialias(FRectOpen.Left, FRectOpen.Top, FRectOpen.Right, FRectOpen.Bottom, Sc(7), Sc(7), clHover)
  else
    B.FillRoundRectAntialias(FRectOpen.Left, FRectOpen.Top, FRectOpen.Right, FRectOpen.Bottom, Sc(7), Sc(7), clCard);
  DrawIcon(B, ikFolderOpen, FRectOpen.Left + ScI(7), FRectOpen.Top + ScI(7), ScI(18), clText);

  // toggle switch
  FRectToggle := Rect(R.Left + ScI(8), R.Top + ScI(74), R.Right - ScI(8), R.Top + ScI(106));
  if FHotZone = 3 then
    B.FillRoundRectAntialias(FRectToggle.Left, FRectToggle.Top, FRectToggle.Right, FRectToggle.Bottom, Sc(7), Sc(7), clHover);
  Y := FRectToggle.Top + FRectToggle.Height div 2;
  if AutoAccept then
  begin
    FillGradientRoundRect(B, FRectToggle.Left + ScI(6), Y - ScI(9), FRectToggle.Left + ScI(42), Y + ScI(9),
      Sc(9), clAccent, clAccent2);
    B.FillEllipseAntialias(FRectToggle.Left + ScI(33), Y, Sc(7), Sc(7), BGRAWhite);
  end
  else
  begin
    B.FillRoundRectAntialias(FRectToggle.Left + ScI(6), Y - ScI(9), FRectToggle.Left + ScI(42), Y + ScI(9),
      Sc(9), Sc(9), Mix(clCard, clTextDim, 0.45));
    B.FillEllipseAntialias(FRectToggle.Left + ScI(15), Y, Sc(7), Sc(7), clPanel);
  end;
  SetFont(B, 9);
  TextIn(B, Rect(FRectToggle.Left + ScI(52), FRectToggle.Top, FRectToggle.Right, FRectToggle.Bottom),
    L('Accept files automatically', 'รับไฟล์อัตโนมัติ (ไม่ถาม)'), clText);
end;

procedure TSidebar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  H, Z: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  H := ItemAt(Y);
  if PtIn(FRectDir, X, Y) then Z := 1
  else if PtIn(FRectOpen, X, Y) then Z := 2
  else if PtIn(FRectToggle, X, Y) then Z := 3
  else if PtIn(FRectRefresh, X, Y) then Z := 4
  else Z := 0;
  if (H <> FHot) or (Z <> FHotZone) then
  begin
    FHot := H;
    FHotZone := Z;
    if (H >= 0) or (Z > 0) then Cursor := crHandPoint else Cursor := crDefault;
    Invalidate;
  end;
end;

procedure TSidebar.MouseLeave;
begin
  inherited MouseLeave;
  FHot := -1;
  FHotZone := 0;
  Invalidate;
end;

procedure TSidebar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbRight then
  begin
    // on a row, or on the empty part of the list
    if (Y >= ListTop) and (Y < ListBottom) and Assigned(OnContext) then
      OnContext(Self, ItemAt(Y), ClientToScreen(Point(X, Y)));
    Exit;
  end;
  if Button <> mbLeft then Exit;
  if PtIn(FRectRefresh, X, Y) then
  begin
    if Assigned(OnRefresh) then OnRefresh(Self);
    Exit;
  end;
  if PtIn(FRectDir, X, Y) then
  begin
    if Assigned(OnPickDir) then OnPickDir(Self);
    Exit;
  end;
  if PtIn(FRectOpen, X, Y) then
  begin
    if Assigned(OnOpenDir) then OnOpenDir(Self);
    Exit;
  end;
  if PtIn(FRectToggle, X, Y) then
  begin
    AutoAccept := not AutoAccept;
    Invalidate;
    if Assigned(OnToggleAuto) then OnToggleAuto(Self);
    Exit;
  end;
  I := ItemAt(Y);
  if (I >= 0) then
  begin
    Selected := I;
    Invalidate;
    if Assigned(OnSelect) then OnSelect(Self);
  end;
end;

function TSidebar.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  MaxS: Integer;
begin
  MaxS := Max(0, Length(Items) * RowH - (ListBottom - ListTop));
  FScroll := EnsureRange(FScroll - WheelDelta div 2, 0, MaxS);
  Invalidate;
  Result := True;
end;

{ ================= TPathBar ================= }

constructor TPathBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHot := -1;
  Clicked := -1;
end;

procedure TPathBar.Render(B: TBGRABitmap);
var
  I, X, W, H, Y0: Integer;
  T: string;
  Avail: Integer;
begin
  H := ScI(32);
  Y0 := (B.Height - H) div 2;
  B.FillRoundRectAntialias(0.5, Y0 + 0.5, B.Width - 0.5, Y0 + H - 0.5, Sc(8), Sc(8), clCard);
  SetLength(FRects, Length(Segments));
  X := ScI(8);
  SetFont(B, 9.5);
  for I := 0 to High(Segments) do
  begin
    if I > 0 then
    begin
      DrawIcon(B, ikChevron, X - ScI(2), Y0 + (H - ScI(14)) div 2, ScI(14), clTextDim);
      Inc(X, ScI(14));
    end;
    if I = High(Segments) then SetFont(B, 9.5, True) else SetFont(B, 9.5);
    Avail := B.Width - X - ScI(8);
    if Avail < ScI(30) then Break;
    T := Ellipsize(B, Segments[I], Min(Avail - ScI(16), ScI(260)));
    W := TextW(B, T) + ScI(16);
    if I = 0 then Inc(W, ScI(22));
    FRects[I] := Rect(X, Y0 + ScI(3), X + W, Y0 + H - ScI(3));
    if (I = FHot) and (I < High(Segments)) then
      B.FillRoundRectAntialias(FRects[I].Left, FRects[I].Top, FRects[I].Right, FRects[I].Bottom,
        Sc(6), Sc(6), clHover);
    if I = 0 then
    begin
      DrawIcon(B, ikComputer, X + ScI(6), Y0 + (H - ScI(18)) div 2, ScI(18), clAccent);
      TextIn(B, Rect(X + ScI(30), Y0, X + W, Y0 + H), T, clText);
    end
    else if I = High(Segments) then
      TextIn(B, Rect(X + ScI(8), Y0, X + W, Y0 + H), T, clText)
    else
      TextIn(B, Rect(X + ScI(8), Y0, X + W, Y0 + H), T, clTextDim);
    Inc(X, W + ScI(2));
  end;
end;

procedure TPathBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  I, H: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  H := -1;
  for I := 0 to High(FRects) do
    if PtIn(FRects[I], X, Y) then H := I;
  if H <> FHot then
  begin
    FHot := H;
    if (H >= 0) and (H < High(Segments)) then Cursor := crHandPoint else Cursor := crDefault;
    Invalidate;
  end;
end;

procedure TPathBar.MouseLeave;
begin
  inherited MouseLeave;
  FHot := -1;
  Invalidate;
end;

procedure TPathBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  for I := 0 to High(FRects) do
    if PtIn(FRects[I], X, Y) and (I < High(Segments)) then
    begin
      Clicked := I;
      if Assigned(OnSegment) then OnSegment(Self);
      Exit;
    end;
end;

{ ================= TFileView ================= }

constructor TFileView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BackColor := clBg;
  TabStop := True;
  FFocus := -1;
  FAnchor := -1;
  FHot := -1;
  FDeferSelect := -1;
  Col3Title := L('Modified', 'แก้ไขล่าสุด');
end;

function TFileView.RowH: Integer;
begin
  case FViewMode of
    vmList:  Result := ScI(34);
    vmIcons: Result := ScI(124);
  else
    Result := ScI(40);
  end;
end;

function TFileView.CellW: Integer;
begin
  case FViewMode of
    vmList:  Result := ScI(250);
    vmIcons: Result := ScI(118);
  else
    Result := Max(1, ClientWidth - ScI(22));
  end;
end;

function TFileView.Cols: Integer;
begin
  if FViewMode = vmDetails then Result := 1
  else Result := Max(1, (ClientWidth - ScI(24)) div CellW);
end;

function TFileView.HeadH: Integer;
begin
  // the column header exists only in Details
  if FViewMode = vmDetails then Result := ScI(34) else Result := ScI(10);
end;

function TFileView.ContentH: Integer;
begin
  Result := ((Length(FItems) + Cols - 1) div Cols) * RowH;
  if FViewMode <> vmDetails then Inc(Result, ScI(10));
end;

function TFileView.MaxScroll: Integer;
begin
  Result := Max(0, ContentH - (ClientHeight - HeadH));
end;

procedure TFileView.SetScroll(V: Integer);
begin
  V := EnsureRange(V, 0, MaxScroll);
  if V <> FScroll then
  begin
    FScroll := V;
    Invalidate;
  end;
end;

procedure TFileView.SetViewMode(V: TViewMode);
begin
  if V = FViewMode then Exit;
  FViewMode := V;
  FScroll := 0;
  FHot := -1;
  if FFocus >= 0 then EnsureVisible(FFocus);
  Invalidate;
end;

procedure TFileView.Resize;
begin
  inherited Resize;
  FScroll := EnsureRange(FScroll, 0, MaxScroll);
end;

{ the cell of item I in client coordinates (scrolled) }
function TFileView.ItemRect(I: Integer): TRect;
var
  C, Row, X0, Y0: Integer;
begin
  C := I mod Cols;
  Row := I div Cols;
  X0 := ScI(8) + C * CellW;
  Y0 := HeadH + Row * RowH - FScroll;
  if FViewMode = vmDetails then
    Result := Rect(ScI(8), Y0, ClientWidth - ScI(14), Y0 + RowH)
  else
    Result := Rect(X0, Y0, X0 + CellW, Y0 + RowH);
end;

function TFileView.ItemAt(X, Y: Integer): Integer;
var
  Row, C: Integer;
begin
  Result := -1;
  if Y < HeadH then Exit;
  Row := (Y - HeadH + FScroll) div RowH;
  if FViewMode = vmDetails then
    Result := Row
  else
  begin
    if X < ScI(8) then Exit;
    C := (X - ScI(8)) div CellW;
    if C >= Cols then Exit;
    Result := Row * Cols + C;
  end;
  if Result >= Length(FItems) then Result := -1;
end;

function TFileView.ThumbRect: TRect;
var
  ViewH, TH, TY: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  ViewH := ClientHeight - HeadH;
  if (ContentH <= ViewH) or (ViewH <= 0) then Exit;
  TH := Max(ScI(30), Round(ViewH * ViewH / ContentH));
  TY := HeadH + Round((ViewH - TH) * FScroll / MaxScroll);
  Result := Rect(ClientWidth - ScI(10), TY, ClientWidth - ScI(3), TY + TH);
end;

procedure TFileView.EnsureVisible(I: Integer);
var
  RowTop: Integer;
begin
  if I < 0 then Exit;
  RowTop := (I div Cols) * RowH;
  if RowTop < FScroll then SetScroll(RowTop)
  else if RowTop + RowH > FScroll + ClientHeight - HeadH then
    SetScroll(RowTop + RowH - (ClientHeight - HeadH));
end;

procedure TFileView.SelChanged;
begin
  Invalidate;
  if Assigned(OnSelChange) then OnSelChange(Self);
end;

procedure TFileView.SelectOnly(I: Integer);
var
  J: Integer;
begin
  for J := 0 to High(FSel) do FSel[J] := J = I;
  FFocus := I;
  FAnchor := I;
end;

function CompareItems(const A, B: TViewItem): Integer;
begin
  if A.IsDir <> B.IsDir then
  begin
    if A.IsDir then Result := -1 else Result := 1;
  end
  else
    Result := AnsiCompareText(A.Name, B.Name);
end;

procedure TFileView.SetItems(const A: TViewItems);
var
  I, J: Integer;
  T: TViewItem;
begin
  FItems := Copy(A);
  // insertion sort: folders first, then by name
  for I := 1 to High(FItems) do
  begin
    T := FItems[I];
    J := I - 1;
    while (J >= 0) and (CompareItems(FItems[J], T) > 0) do
    begin
      FItems[J + 1] := FItems[J];
      Dec(J);
    end;
    FItems[J + 1] := T;
  end;
  SetLength(FSel, Length(FItems));
  for I := 0 to High(FSel) do FSel[I] := False;
  FFocus := -1;
  FAnchor := -1;
  FHot := -1;
  FScroll := 0;
  IsLoading := False;
  ErrorText := '';
  SelChanged;
end;

procedure TFileView.Clear;
begin
  SetItems(nil);
end;

function TFileView.Count: Integer;
begin
  Result := Length(FItems);
end;

function TFileView.Item(I: Integer): TViewItem;
begin
  Result := FItems[I];
end;

function TFileView.SelCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FSel) do
    if FSel[I] then Inc(Result);
end;

function TFileView.SelectedIdx: TIntArray;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(FSel) do
    if FSel[I] then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := I;
    end;
end;

procedure TFileView.SelectAll;
var
  I: Integer;
begin
  for I := 0 to High(FSel) do FSel[I] := True;
  SelChanged;
end;

procedure TFileView.Render(B: TBGRABitmap);
var
  I, Y, IconS, NameR, SizeX, InfoX, RightPad: Integer;
  R, TR: TRect;
  S: string;
  A: Single;
  Showing3: Boolean;
begin
  RightPad := ScI(16);
  Showing3 := B.Width > ScI(520);
  if Showing3 then InfoX := B.Width - RightPad - ScI(170) else InfoX := B.Width - RightPad;
  SizeX := InfoX - ScI(100);
  NameR := SizeX - ScI(12);

  // column header (Details only)
  if FViewMode = vmDetails then
  begin
    B.FillRect(0, 0, B.Width, HeadH, clBg, dmSet);
    SetFont(B, 8.5, True);
    TextIn(B, Rect(ScI(56), 0, NameR, HeadH), L('Name', 'ชื่อ'), clTextDim);
    TextIn(B, Rect(SizeX, 0, InfoX - ScI(16), HeadH), L('Size', 'ขนาด'), clTextDim, taRightJustify);
    if Showing3 then
      TextIn(B, Rect(InfoX, 0, B.Width - RightPad, HeadH), Col3Title, clTextDim);
    B.FillRect(ScI(12), HeadH - 1, B.Width - ScI(12), HeadH, clBorder, dmSet);
  end;

  if IsLoading then
  begin
    // three animated-looking dots (static) + text
    for I := 0 to 2 do
      B.FillEllipseAntialias(B.Width / 2 - Sc(16) + I * Sc(16), B.Height / 2 - Sc(10), Sc(4), Sc(4),
        WithAlpha(clAccent, 120 + I * 60));
    SetFont(B, 10);
    TextIn(B, Rect(0, B.Height div 2, B.Width, B.Height div 2 + ScI(30)), L('Loading...', 'กำลังโหลด...'), clTextDim, taCenter);
    Exit;
  end;
  if ErrorText <> '' then
  begin
    B.FillEllipseAntialias(B.Width / 2, B.Height / 2 - Sc(30), Sc(24), Sc(24), WithAlpha(clErr, 50));
    DrawIcon(B, ikClose, B.Width / 2 - Sc(12), B.Height / 2 - Sc(42), Sc(24), clErr);
    SetFont(B, 11, True);
    TextIn(B, Rect(0, B.Height div 2 + ScI(4), B.Width, B.Height div 2 + ScI(30)), L('Cannot open', 'เปิดไม่ได้'), clText, taCenter);
    SetFont(B, 9);
    TextIn(B, Rect(ScI(20), B.Height div 2 + ScI(30), B.Width - ScI(20), B.Height div 2 + ScI(54)), ErrorText, clTextDim, taCenter);
    Exit;
  end;
  if Length(FItems) = 0 then
  begin
    A := Sc(72);
    B.FillEllipseAntialias(B.Width / 2, B.Height / 2 - Sc(34), A * 0.75, A * 0.75, clPanel);
    DrawFolderIcon(B, B.Width / 2 - A / 2, B.Height / 2 - Sc(34) - A / 2, A);
    SetFont(B, 11, True);
    TextIn(B, Rect(0, B.Height div 2 + ScI(26), B.Width, B.Height div 2 + ScI(52)), EmptyTitle, clText, taCenter);
    SetFont(B, 9);
    TextIn(B, Rect(ScI(20), B.Height div 2 + ScI(52), B.Width - ScI(20), B.Height div 2 + ScI(76)), EmptyText, clTextDim, taCenter);
    Exit;
  end;

  B.ClipRect := Rect(0, HeadH, B.Width, B.Height);
  IconS := ScI(26);
  for I := 0 to High(FItems) do
  begin
    R := ItemRect(I);
    Y := R.Top;
    if R.Bottom < HeadH then Continue;
    if R.Top > B.Height then Break;
    if FViewMode = vmDetails then
      R := Rect(R.Left, R.Top + ScI(1), R.Right, R.Bottom - ScI(1))
    else
      R := Rect(R.Left + ScI(2), R.Top + ScI(2), R.Right - ScI(4), R.Bottom - ScI(2));
    if FSel[I] then
    begin
      B.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, Sc(8), Sc(8), clSel);
      if (I = FFocus) and Focused then
        B.RoundRectAntialias(R.Left + 0.5, R.Top + 0.5, R.Right - 0.5, R.Bottom - 0.5, Sc(8), Sc(8), clSelBorder, 1);
    end
    else if I = FHot then
      B.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, Sc(8), Sc(8), clHover);

    if FViewMode = vmList then
    begin
      A := ScI(22);
      if FItems[I].IsDir then
        DrawFolderIcon(B, R.Left + ScI(8), R.Top + (R.Height - A) / 2, A, FItems[I].Shared)
      else
        DrawFileIcon(B, FItems[I].Name, R.Left + ScI(8), R.Top + (R.Height - A) / 2, A);
      SetFont(B, 9.5);
      TextIn(B, Rect(R.Left + ScI(38), R.Top, R.Right - ScI(6), R.Bottom), FItems[I].Name, clText);
      Continue;
    end;
    if FViewMode = vmIcons then
    begin
      A := ScI(56);
      if FItems[I].IsDir then
        DrawFolderIcon(B, (R.Left + R.Right - A) / 2, R.Top + ScI(8), A, FItems[I].Shared)
      else
        DrawFileIcon(B, FItems[I].Name, (R.Left + R.Right - A) / 2, R.Top + ScI(8), A);
      if FItems[I].Writable and FItems[I].IsDir then
      begin
        // pencil badge: others may change this folder
        B.FillEllipseAntialias((R.Left + R.Right + A) / 2 - Sc(4), R.Top + ScI(14), Sc(9), Sc(9), clAccent);
        DrawIcon(B, ikEdit, (R.Left + R.Right + A) / 2 - Sc(11), R.Top + ScI(7), Sc(14), BGRAWhite);
      end;
      SetFont(B, 9);
      TextIn(B, Rect(R.Left + ScI(6), R.Top + ScI(68), R.Right - ScI(6), R.Top + ScI(90)),
        FItems[I].Name, clText, taCenter);
      SetFont(B, 8);
      if FItems[I].IsDir then S := L('Folder', 'โฟลเดอร์') else S := FormatBytes(FItems[I].Size);
      TextIn(B, Rect(R.Left + ScI(6), R.Top + ScI(90), R.Right - ScI(6), R.Top + ScI(108)), S, clTextDim, taCenter);
      Continue;
    end;

    if FItems[I].IsDir then
      DrawFolderIcon(B, ScI(18), Y + (RowH - IconS) / 2, IconS, FItems[I].Shared)
    else
      DrawFileIcon(B, FItems[I].Name, ScI(18), Y + (RowH - IconS) / 2, IconS);

    SetFont(B, 10);
    TR := Rect(ScI(56), Y, NameR, Y + RowH);
    TextIn(B, TR, FItems[I].Name, clText);
    SetFont(B, 9);
    if FItems[I].IsDir then S := L('Folder', 'โฟลเดอร์') else S := FormatBytes(FItems[I].Size);
    TextIn(B, Rect(SizeX, Y, InfoX - ScI(16), Y + RowH), S, clTextDim, taRightJustify);
    if Showing3 then
      TextIn(B, Rect(InfoX, Y, B.Width - RightPad, Y + RowH), FItems[I].Info, clTextDim);
  end;
  B.NoClip;

  // scrollbar
  R := ThumbRect;
  if R.Bottom > R.Top then
    B.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, Sc(3.5), Sc(3.5),
      WithAlpha(clTextDim, IfThen(FDragThumb, 160, 90)));
end;

procedure TFileView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  H: Integer;
  R: TRect;
  ViewH: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  // moved far enough with the button down on a selected row: drag out
  if FPressed and (ssLeft in Shift) and
     ((Abs(X - FPressPt.X) > ScI(6)) or (Abs(Y - FPressPt.Y) > ScI(6))) then
  begin
    FPressed := False;
    FDeferSelect := -1;
    if Assigned(OnDragOut) and (SelCount > 0) then
    begin
      MouseCapture := False;
      OnDragOut(Self);        // runs the whole drag; returns when it is dropped or cancelled
      FHot := -1;
      Invalidate;
    end;
    Exit;
  end;
  if FDragThumb then
  begin
    R := ThumbRect;
    ViewH := ClientHeight - HeadH - R.Height;
    if ViewH > 0 then
      SetScroll(FDragScroll0 + Round((Y - FDragY0) * MaxScroll / ViewH));
    Exit;
  end;
  H := ItemAt(X, Y);
  if H <> FHot then
  begin
    FHot := H;
    Invalidate;
  end;
end;

procedure TFileView.MouseLeave;
begin
  inherited MouseLeave;
  if FHot <> -1 then
  begin
    FHot := -1;
    Invalidate;
  end;
end;

procedure TFileView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I, J: Integer;
  R: TRect;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then SetFocus;
  R := ThumbRect;
  if (R.Bottom > R.Top) and (X >= R.Left - ScI(4)) then
  begin
    FDragThumb := True;
    FDragY0 := Y;
    FDragScroll0 := FScroll;
    Invalidate;
    Exit;
  end;
  I := ItemAt(X, Y);
  if I < 0 then
  begin
    if not (ssCtrl in Shift) then
    begin
      SelectOnly(-1);
      SelChanged;
    end;
    Exit;
  end;
  if (Button = mbRight) and FSel[I] then Exit;   // keep multi-selection for context use
  if (Button = mbLeft) and (ssDouble in Shift) then
  begin
    // double-click: open the row under the mouse
    SelectOnly(I);
    SelChanged;
    if Assigned(OnOpen) then OnOpen(Self);
    Exit;
  end;
  if Button = mbLeft then
  begin
    FPressed := True;
    FPressPt := Point(X, Y);
  end;
  if (Button = mbLeft) and FSel[I] and (Shift * [ssShift, ssCtrl] = []) then
  begin
    // like Explorer: keep the selection so all of it can be dragged;
    // a plain click (no drag) selects only this row on mouse-up
    FDeferSelect := I;
    FFocus := I;
    Invalidate;
    Exit;
  end;
  if (ssShift in Shift) and (FAnchor >= 0) then
  begin
    for J := 0 to High(FSel) do
      FSel[J] := (J >= Min(FAnchor, I)) and (J <= Max(FAnchor, I));
    FFocus := I;
  end
  else if ssCtrl in Shift then
  begin
    FSel[I] := not FSel[I];
    FFocus := I;
    FAnchor := I;
  end
  else
    SelectOnly(I);
  SelChanged;
end;

procedure TFileView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbRight) and Assigned(OnContext) then
  begin
    OnContext(Self, ClientToScreen(Point(X, Y)));
    Exit;
  end;
  FPressed := False;
  if FDeferSelect >= 0 then
  begin
    if FDeferSelect <= High(FSel) then
    begin
      SelectOnly(FDeferSelect);
      SelChanged;
    end;
    FDeferSelect := -1;
  end;
  if FDragThumb then
  begin
    FDragThumb := False;
    Invalidate;
  end;
end;

procedure TFileView.KeyDown(var Key: Word; Shift: TShiftState);
var
  N, C, Page: Integer;
begin
  inherited KeyDown(Key, Shift);
  N := Length(FItems);
  C := Cols;
  Page := Max(1, (ClientHeight - HeadH) div RowH) * C;
  // Left/Right move between cells only where items sit side by side
  if (Key in [VK_LEFT, VK_RIGHT]) and (FViewMode = vmDetails) then Exit;
  case Key of
    VK_DOWN, VK_UP, VK_LEFT, VK_RIGHT, VK_HOME, VK_END, VK_NEXT, VK_PRIOR:
      if N > 0 then
      begin
        case Key of
          VK_DOWN:  if FFocus < 0 then FFocus := 0 else if FFocus + C < N then FFocus := FFocus + C;
          VK_UP:    if FFocus < 0 then FFocus := 0 else if FFocus - C >= 0 then FFocus := FFocus - C;
          VK_RIGHT: FFocus := Min(N - 1, FFocus + 1);
          VK_LEFT:  FFocus := Max(0, FFocus - 1);
          VK_HOME:  FFocus := 0;
          VK_END:   FFocus := N - 1;
          VK_NEXT:  FFocus := Min(N - 1, FFocus + Page);
          VK_PRIOR: FFocus := Max(0, FFocus - Page);
        end;
        SelectOnly(FFocus);
        EnsureVisible(FFocus);
        SelChanged;
        Key := 0;
      end;
    VK_RETURN:
      begin
        if (FFocus >= 0) and Assigned(OnOpen) then OnOpen(Self);
        Key := 0;
      end;
    VK_BACK:
      begin
        if Assigned(OnBack) then OnBack(Self);
        Key := 0;
      end;
    VK_A:
      if ssCtrl in Shift then
      begin
        SelectAll;
        Key := 0;
      end;
    VK_C:
      if (ssCtrl in Shift) and (SelCount > 0) and Assigned(OnCopy) then
      begin
        OnCopy(Self);
        Key := 0;
      end;
    VK_F2:
      if (SelCount = 1) and Assigned(OnRename) then
      begin
        OnRename(Self);
        Key := 0;
      end;
    VK_DELETE:
      if (SelCount > 0) and Assigned(OnDelete) then
      begin
        OnDelete(Self);
        Key := 0;
      end;
    VK_F5:
      if Assigned(OnRefresh) then
      begin
        OnRefresh(Self);
        Key := 0;
      end;
    VK_APPS, VK_F10:
      // menu key or Shift+F10: the menu at the focused row
      if ((Key = VK_APPS) or (ssShift in Shift)) and Assigned(OnContext) then
      begin
        if FFocus >= 0 then
          OnContext(Self, ClientToScreen(Point(ItemRect(FFocus).Left + ScI(40), ItemRect(FFocus).Bottom)))
        else
          OnContext(Self, ClientToScreen(Point(ScI(60), HeadH + ScI(10))));
        Key := 0;
      end;
  end;
end;

function TFileView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  SetScroll(FScroll - (WheelDelta * Min(RowH, ScI(40)) * 3) div 120);
  Result := True;
end;

{ ================= TTransfersView ================= }

constructor TTransfersView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BackColor := clPanel;
  FHotCancel := -1;
end;

function TTransfersView.RowH: Integer;
begin
  Result := ScI(50);
end;

function TTransfersView.HeadH: Integer;
begin
  Result := ScI(34);
end;

function TTransfersView.ActiveCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FCards) do
    if IsActiveState(FCards[I].State) then Inc(Result);
end;

procedure TTransfersView.UpdateFrom(const T: TTransferInfo);
var
  I, J, M, DoneFiles: Integer;
  Key: string;
  Now_, Dt: QWord;
  AnyActive, AnyRunning, AnyFailed, AnyRejected: Boolean;
  SumDone, SumTotal: Int64;
begin
  if T.Group <> '' then Key := T.Group else Key := 'S' + IntToStr(T.Serial);
  I := -1;
  for J := 0 to High(FCards) do
    if FCards[J].Key = Key then
    begin
      I := J;
      Break;
    end;
  if I < 0 then
  begin
    // ignore threads that never got anywhere visible (e.g. list requests)
    if (T.Kind = tkServe) and (T.Total = 0) and (T.State <> tsRunning) then Exit;
    SetLength(FCards, Length(FCards) + 1);
    for J := High(FCards) downto 1 do FCards[J] := FCards[J - 1];
    I := 0;
    FCards[0] := Default(TTransferCard);
    FCards[0].Key := Key;
    FCards[0].SpeedTick := GetTickCount64;
  end;
  with FCards[I] do
  begin
    LastUpdate := GetTickCount64;
    if T.GroupEnded then
      Ended := True
    else
    begin
      M := -1;
      for J := 0 to High(Members) do
        if Members[J].Serial = T.Serial then M := J;
      if M < 0 then
      begin
        SetLength(Members, Length(Members) + 1);
        M := High(Members);
        Members[M].Serial := T.Serial;
      end;
      Members[M].Done := T.Done;
      Members[M].Total := T.Total;
      Members[M].State := T.State;
    end;

    // aggregate all members of the card
    SumDone := 0;
    SumTotal := 0;
    DoneFiles := 0;
    AnyActive := False;
    AnyRunning := False;
    AnyFailed := False;
    AnyRejected := False;
    for J := 0 to High(Members) do
    begin
      Inc(SumDone, Members[J].Done);
      Inc(SumTotal, Members[J].Total);
      if IsActiveState(Members[J].State) then AnyActive := True;
      if Members[J].State = tsRunning then AnyRunning := True;
      if Members[J].State = tsFailed then AnyFailed := True;
      if Members[J].State = tsRejected then AnyRejected := True;
      if Members[J].State = tsDone then Inc(DoneFiles);
    end;
    GroupFiles := T.GroupFiles;
    GroupBytes := T.GroupBytes;
    Kind := T.Kind;
    if AnyRunning then State := tsRunning
    else if AnyActive then State := T.State
    else if AnyFailed then State := tsFailed
    else if AnyRejected then State := tsRejected
    else State := tsDone;
    // a batch with known size that is not complete yet stays "running"
    if (State = tsDone) and (GroupFiles > 0) and (DoneFiles < GroupFiles) and not Ended then
      State := tsRunning;
    if (State = tsDone) and Ended and (GroupFiles > 0) and (DoneFiles < GroupFiles) then
      Msg := Format(L('Got %d of %d files', 'ได้รับ %d จาก %d ไฟล์'), [DoneFiles, GroupFiles]);

    if T.GroupEnded then
      // keep the title from the file reports
    else if T.Group = '' then
      Title := T.Title
    else if GroupFiles > 0 then
      Title := Format(L('%d / %d files', '%d / %d ไฟล์'), [DoneFiles, GroupFiles])
    else
      Title := Format(L('%d file(s)', '%d ไฟล์'), [Length(Members)]);
    if T.PeerName <> '' then Peer := T.PeerName else if T.PeerIP <> '' then Peer := T.PeerIP;
    if not T.GroupEnded then
    begin
      if (T.Msg <> '') or (T.Group = '') then Msg := T.Msg;
      CurFile := T.CurFile;
      if (T.Group <> '') and (T.Title <> '') then CurFile := T.Title;
    end;
    Done := SumDone;
    if GroupBytes > SumTotal then Total := GroupBytes else Total := SumTotal;

    Now_ := GetTickCount64;
    Dt := Now_ - SpeedTick;
    if Dt >= 700 then
    begin
      Speed := (Done - SpeedDone) * 1000 / Dt;
      SpeedDone := Done;
      SpeedTick := Now_;
    end;
  end;
  Invalidate;
end;

procedure TTransfersView.Tick;
var
  I, J: Integer;
  Busy, AnyChanged: Boolean;
begin
  AnyChanged := False;
  for I := 0 to High(FCards) do
    with FCards[I] do
      if (State = tsRunning) and (GetTickCount64 - LastUpdate > 20000) then
      begin
        Busy := False;
        for J := 0 to High(Members) do
          if IsActiveState(Members[J].State) then Busy := True;
        if not Busy then
        begin
          // a batch whose client stopped sending/asking: it will not finish
          State := tsFailed;
          Msg := L('The other side stopped', 'อีกฝั่งหยุดกลางคัน');
          AnyChanged := True;
        end;
      end;
  if AnyChanged then Invalidate;
end;

procedure TTransfersView.ClearFinished;
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to High(FCards) do
    if IsActiveState(FCards[I].State) then
    begin
      FCards[N] := FCards[I];
      Inc(N);
    end;
  SetLength(FCards, N);
  FScroll := 0;
  Invalidate;
end;

procedure TTransfersView.Render(B: TBGRABitmap);
var
  I, Y, BarL, BarR, BarY: Integer;
  R: TRect;
  C: TBGRAPixel;
  Pct: Double;
  Dir, Right_, Line2: string;
  Ico: TIconKind;
begin
  B.FillRect(0, 0, B.Width, 1, clBorder, dmSet);
  SetFont(B, 9.5, True);
  B.TextOut(ScI(18), ScI(9), L('Transfers', 'การถ่ายโอน'), clText);
  if ActiveCount > 0 then
  begin
    SetFont(B, 8.5);
    SetFont(B, 9.5, True);
    I := ScI(18) + TextW(B, L('Transfers', 'การถ่ายโอน')) + ScI(12);
    SetFont(B, 8.5);
    B.TextOut(I, ScI(11), Format(L('%d running', 'กำลังทำงาน %d รายการ'), [ActiveCount]), clAccent);
  end;
  FClearRect := Rect(0, 0, 0, 0);
  if Length(FCards) > ActiveCount then
  begin
    SetFont(B, 8.5);
    FClearRect := Rect(B.Width - ScI(18) - TextW(B, L('Clear finished', 'ล้างรายการที่เสร็จแล้ว')) - ScI(16), ScI(5),
      B.Width - ScI(14), ScI(29));
    if FHotClear then
      B.FillRoundRectAntialias(FClearRect.Left, FClearRect.Top, FClearRect.Right, FClearRect.Bottom, Sc(6), Sc(6), clHover);
    TextIn(B, Rect(FClearRect.Left + ScI(8), FClearRect.Top, FClearRect.Right, FClearRect.Bottom),
      L('Clear finished', 'ล้างรายการที่เสร็จแล้ว'), clTextDim);
  end;

  SetLength(FCancelRects, Length(FCards));
  if Length(FCards) = 0 then
  begin
    SetFont(B, 9);
    TextIn(B, Rect(0, HeadH, B.Width, B.Height), L('No transfers yet — select files and click Download, or send files to another computer', 'ยังไม่มีการถ่ายโอน — เลือกไฟล์แล้วกดดาวน์โหลด หรือส่งไฟล์ไปยังเครื่องอื่น'),
      WithAlpha(clTextDim, 170), taCenter);
    Exit;
  end;

  B.ClipRect := Rect(0, HeadH, B.Width, B.Height);
  for I := 0 to High(FCards) do
  begin
    FCancelRects[I] := Rect(0, 0, 0, 0);
    Y := HeadH + I * RowH - FScroll;
    if Y + RowH < HeadH then Continue;
    if Y > B.Height then Break;
    R := Rect(ScI(12), Y + ScI(2), B.Width - ScI(12), Y + RowH - ScI(4));
    B.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, Sc(10), Sc(10), clCard);
    with FCards[I] do
    begin
      case Kind of
        tkSend:     begin Dir := L('To', 'ส่งไปยัง');     Ico := ikUpload; end;
        tkReceive:  begin Dir := L('From', 'รับจาก');       Ico := ikDownload; end;
        tkDownload: begin Dir := L('Downloading from', 'ดาวน์โหลดจาก'); Ico := ikDownload; end;
      else
        begin Dir := L('Sent to', 'ส่งให้'); Ico := ikUpload; end;
      end;
      case State of
        tsDone: C := clOk;
        tsFailed, tsRejected: C := clErr;
      else
        C := clAccent;
      end;
      B.FillEllipseAntialias(R.Left + ScI(22), R.Top + R.Height / 2, Sc(15), Sc(15), WithAlpha(C, 45));
      if State = tsDone then
        DrawIcon(B, ikCheck, R.Left + ScI(12), R.Top + R.Height / 2 - Sc(10), Sc(20), C)
      else if State in [tsFailed, tsRejected] then
        DrawIcon(B, ikClose, R.Left + ScI(12), R.Top + R.Height / 2 - Sc(10), Sc(20), C)
      else
        DrawIcon(B, Ico, R.Left + ScI(12), R.Top + R.Height / 2 - Sc(10), Sc(20), C);

      if Total > 0 then Pct := Done / Total else if State = tsDone then Pct := 1 else Pct := 0;
      case State of
        tsConnecting, tsWaiting: Right_ := Msg;
        tsRunning:  Right_ := Format('%d%%  •  %s/s', [Round(Pct * 100), FormatBytes(Round(Speed))]);
        tsDone:     Right_ := Format(L('%s  •  done', '%s  •  เสร็จแล้ว'), [FormatBytes(Total)]);
        tsRejected: Right_ := L('Declined', 'ถูกปฏิเสธ');
      else
        Right_ := L('Failed', 'ล้มเหลว');
      end;

      BarL := R.Left + ScI(48);
      BarR := R.Right - ScI(190);
      SetFont(B, 9.5, True);
      TextIn(B, Rect(BarL, R.Top + ScI(4), BarR, R.Top + ScI(22)), Title, clText);
      SetFont(B, 8.5);
      if (State = tsRunning) and (CurFile <> '') then Line2 := Dir + ' ' + Peer + '  •  ' + CurFile
      else if State = tsFailed then Line2 := Msg
      else Line2 := Dir + ' ' + Peer;
      BarY := R.Top + ScI(28);
      if State = tsRunning then
      begin
        TextIn(B, Rect(BarL, R.Top + ScI(20), BarR, R.Top + ScI(34)), Line2, clTextDim);
        BarY := R.Bottom - ScI(9);
        B.FillRoundRectAntialias(BarL, BarY, BarR, BarY + ScI(5), Sc(2.5), Sc(2.5), Mix(clCard, clText, 0.12));
        if Pct > 0 then
          FillGradientRoundRect(B, BarL, BarY, BarL + Max(ScI(5), Round((BarR - BarL) * Pct)), BarY + ScI(5),
            Sc(2.5), clAccent, clAccent2);
      end
      else
        TextIn(B, Rect(BarL, R.Top + ScI(22), BarR, R.Bottom - ScI(4)), Line2,
          IfThen(State = tsFailed, clErr, clTextDim));

      SetFont(B, 9);
      TextIn(B, Rect(BarR + ScI(10), R.Top, R.Right - ScI(44), R.Bottom), Right_,
        IfThen(State in [tsDone, tsFailed, tsRejected], C, clText), taRightJustify);

      if IsActiveState(State) then
      begin
        FCancelRects[I] := Rect(R.Right - ScI(38), R.Top + (R.Height - ScI(28)) div 2,
          R.Right - ScI(10), R.Top + (R.Height + ScI(28)) div 2);
        if I = FHotCancel then
          B.FillRoundRectAntialias(FCancelRects[I].Left, FCancelRects[I].Top, FCancelRects[I].Right,
            FCancelRects[I].Bottom, Sc(6), Sc(6), WithAlpha(clErr, 70));
        DrawIcon(B, ikClose, FCancelRects[I].Left + ScI(6), FCancelRects[I].Top + ScI(6), ScI(16), clTextDim);
      end;
    end;
  end;
  B.NoClip;
end;

procedure TTransfersView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  I, H: Integer;
  HC: Boolean;
begin
  inherited MouseMove(Shift, X, Y);
  H := -1;
  for I := 0 to High(FCancelRects) do
    if PtIn(FCancelRects[I], X, Y) then H := I;
  HC := PtIn(FClearRect, X, Y);
  if (H <> FHotCancel) or (HC <> FHotClear) then
  begin
    FHotCancel := H;
    FHotClear := HC;
    if (H >= 0) or HC then Cursor := crHandPoint else Cursor := crDefault;
    Invalidate;
  end;
end;

procedure TTransfersView.MouseLeave;
begin
  inherited MouseLeave;
  FHotCancel := -1;
  FHotClear := False;
  Invalidate;
end;

procedure TTransfersView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I, J: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if PtIn(FClearRect, X, Y) then
  begin
    ClearFinished;
    Exit;
  end;
  for I := 0 to High(FCancelRects) do
    if PtIn(FCancelRects[I], X, Y) and (I <= High(FCards)) and IsActiveState(FCards[I].State) then
    begin
      CancelSerials := nil;
      for J := 0 to High(FCards[I].Members) do
        if IsActiveState(FCards[I].Members[J].State) then
        begin
          SetLength(CancelSerials, Length(CancelSerials) + 1);
          CancelSerials[High(CancelSerials)] := FCards[I].Members[J].Serial;
        end;
      if Assigned(OnCancel) then OnCancel(Self);
      Exit;
    end;
end;

function TTransfersView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FScroll := EnsureRange(FScroll - WheelDelta div 2, 0,
    Max(0, Length(FCards) * RowH - (ClientHeight - HeadH)));
  Invalidate;
  Result := True;
end;

end.
