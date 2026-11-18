unit IdentDlg;

{ Right-click popup on a sidebar row: everything known about that computer
  (display name, computer name, user, machine code, address, version...). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType, Clipbrd,
  BGRABitmap, BGRABitmapTypes, UITheme, UIWidgets, I18n;

{ WebUrl: address of its web page ('' = none); shown next to ScreenPt }
procedure ShowIdentity(AOwner: TComponent; const Item: TSideItem; const WebUrl: string;
  const ScreenPt: TPoint);

implementation

uses
  Math;

type
  TIdentRow = record
    Key, Value: string;
    Empty: Boolean;    // nothing known: drawn dim
  end;

  TIdentBody = class(TBGRAControl)
  protected
    procedure Render(B: TBGRABitmap); override;
  public
    Item: TSideItem;
    Rows: array of TIdentRow;
  end;

  TIdentPopup = class(TForm)
  private
    FBody: TIdentBody;
    procedure CopyClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure DeactivateEvt(Sender: TObject);
    procedure CloseEvt(Sender: TObject; var CloseAction: TCloseAction);
    procedure KeyDownEvt(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor CreatePopup(AOwner: TComponent; const AItem: TSideItem; const WebUrl: string);
    function AsText: string;
  end;

const
  POP_W = 460;      // width at 96 dpi
  HEAD_H = 84;
  ROW_H = 25;
  FOOT_H = 54;
  KEY_W = 150;

function HasName(const It: TSideItem): Boolean;
begin
  Result := (It.Title <> '') and (It.Title <> It.IP);
end;

function DateText(D: TDateTime): string;
begin
  if D = 0 then Result := '' else Result := FormatDateTime('d mmm yyyy  hh:nn:ss', D);
end;

{ ---------- body ---------- }

procedure TIdentBody.Render(B: TBGRABitmap);
var
  I, Y, KeyX, ValX: Integer;
  Status: string;
  StC: TBGRAPixel;
begin
  // header: avatar, name, status
  DrawDeviceAvatar(B, Item.Icon, Item.OS, ScI(18), ScI(16), ScI(50), Item.Online or Item.IsMe);
  SetFont(B, 13, True);
  if HasName(Item) then
    TextIn(B, Rect(ScI(82), ScI(14), B.Width - ScI(16), ScI(42)), Item.Title, clText)
  else
    TextIn(B, Rect(ScI(82), ScI(14), B.Width - ScI(16), ScI(42)), L('No name', 'ไม่ได้ตั้งชื่อ'), clTextDim);
  if Item.IsMe then
  begin
    Status := L('This PC', 'เครื่องนี้');
    StC := clAccent;
  end
  else if Item.Online then
  begin
    Status := L('Online', 'ออนไลน์');
    StC := clOk;
  end
  else
  begin
    Status := L('Offline', 'ออฟไลน์');
    StC := clTextDim;
  end;
  SetFont(B, 9.5, True);
  TextIn(B, Rect(ScI(82), ScI(44), B.Width - ScI(16), ScI(66)), Status, StC);
  B.DrawHorizLine(ScI(16), ScI(HEAD_H) - 1, B.Width - ScI(16), clBorder);

  // key / value rows
  KeyX := ScI(18);
  ValX := ScI(KEY_W);
  Y := ScI(HEAD_H) + ScI(6);
  for I := 0 to High(Rows) do
  begin
    if Rows[I].Key = '' then
    begin
      // section gap
      B.DrawHorizLine(ScI(16), Y + ScI(ROW_H) div 2, B.Width - ScI(16), clBorder);
      Inc(Y, ScI(ROW_H));
      Continue;
    end;
    SetFont(B, 9);
    TextIn(B, Rect(KeyX, Y, ValX - ScI(8), Y + ScI(ROW_H)), Rows[I].Key, clTextDim);
    if Rows[I].Empty then
    begin
      SetFont(B, 9.5);
      TextIn(B, Rect(ValX, Y, B.Width - ScI(16), Y + ScI(ROW_H)), Rows[I].Value, clTextDim);
    end
    else
    begin
      SetFont(B, 9.5, True);
      TextIn(B, Rect(ValX, Y, B.Width - ScI(16), Y + ScI(ROW_H)), Rows[I].Value, clText);
    end;
    Inc(Y, ScI(ROW_H));
  end;
end;

{ ---------- popup ---------- }

constructor TIdentPopup.CreatePopup(AOwner: TComponent; const AItem: TSideItem; const WebUrl: string);
var
  Foot: TBGRAControl;
  BtnCopy, BtnClose: TFlatButton;
  NoInfo: string;

  procedure Add(const K, V: string; const IfEmpty: string = '');
  var
    N: Integer;
  begin
    N := Length(FBody.Rows);
    SetLength(FBody.Rows, N + 1);
    FBody.Rows[N].Key := K;
    if V <> '' then
      FBody.Rows[N].Value := V
    else
    begin
      if IfEmpty <> '' then FBody.Rows[N].Value := IfEmpty else FBody.Rows[N].Value := '—';
      FBody.Rows[N].Empty := True;
    end;
  end;

  procedure Gap;
  begin
    Add('', '');
  end;

  function Btn(const ACap: string; AStyle: TButtonStyle; AClick: TNotifyEvent): TFlatButton;
  begin
    Result := TFlatButton.Create(Self);
    Result.Parent := Foot;
    Result.Caption := ACap;
    Result.Style := AStyle;
    Result.BackColor := clPanel;
    Result.Align := alRight;
    Result.BorderSpacing.Left := ScI(8);
    Result.OnClick := AClick;
    Result.FitWidth;
  end;

begin
  inherited CreateNew(AOwner);
  BorderStyle := bsNone;
  Caption := 'LAN Share identity';   // not shown (no border); names the window for tools
  Position := poDesigned;
  ShowInTaskBar := stNever;
  // a 1 px frame in the theme's border colour (no window border of its own)
  Color := BGRAToColor(clBorder);
  BorderWidth := 1;
  KeyPreview := True;
  OnKeyDown := @KeyDownEvt;
  OnDeactivate := @DeactivateEvt;
  OnClose := @CloseEvt;

  FBody := TIdentBody.Create(Self);
  FBody.Parent := Self;
  FBody.Align := alClient;
  FBody.BackColor := clPanel;
  FBody.Item := AItem;

  // a peer from before 1.1 (or not heard from yet) sends no identity
  if AItem.IsMe then NoInfo := '' else NoInfo := L('not sent (hidden by its owner, or an older LAN Share)', 'ไม่ได้ส่งมา (เจ้าของปิดไว้ หรือ LAN Share รุ่นเก่า)');
  if HasName(AItem) then Add(L('Display name', 'ชื่อที่แสดง'), AItem.Title)
  else Add(L('Display name', 'ชื่อที่แสดง'), '', L('not set (others see the icon and IP)', 'ไม่ได้ตั้ง (เครื่องอื่นเห็นไอคอนและ IP)'));
  Add(L('Computer name', 'ชื่อคอมพิวเตอร์'), AItem.Host, NoInfo);
  Add(L('User', 'ผู้ใช้'), AItem.User, NoInfo);
  Add(L('Machine code', 'รหัสเครื่อง'), AItem.Machine, NoInfo);
  if Pos(#10, Trim(AItem.Names)) > 0 then
    Add(L('Names used', 'ชื่อที่เคยใช้'), StringReplace(Trim(AItem.Names), #10, '  →  ', [rfReplaceAll]));
  Gap;
  Add(L('IP address', 'IP'), AItem.IP);
  if AItem.Port > 0 then Add(L('Port', 'พอร์ต'), IntToStr(AItem.Port)) else Add(L('Port', 'พอร์ต'), '');
  Add(L('Web page', 'หน้าเว็บ'), WebUrl);
  Add(L('System', 'ระบบ'), OSLabel(AItem.OS));
  Add(L('Version', 'เวอร์ชัน'), AItem.Version, NoInfo);
  Add(L('Features', 'ความสามารถ'), StringReplace(AItem.Caps, ',', ', ', [rfReplaceAll]));
  if not AItem.IsMe then
  begin
    Gap;
    if AItem.Manual then
      Add(L('Found by', 'พบโดย'), L('added by IP', 'เพิ่มด้วย IP'))
    else
      Add(L('Found by', 'พบโดย'), L('found automatically on the network', 'พบอัตโนมัติในเครือข่าย'));
    if Copy(AItem.ID, 1, 7) = 'manual:' then Add(L('Session', 'รหัสรอบการทำงาน'), '')
    else Add(L('Session', 'รหัสรอบการทำงาน'), AItem.ID);
    Add(L('First seen', 'เห็นครั้งแรก'), DateText(AItem.FirstSeenAt));
    Add(L('Last seen', 'เห็นล่าสุด'), DateText(AItem.LastSeenAt));
  end
  else
    Add(L('Session', 'รหัสรอบการทำงาน'), AItem.ID);

  Foot := TBGRAControl.Create(Self);
  Foot.Parent := Self;
  Foot.Align := alBottom;
  Foot.Height := ScI(FOOT_H);
  Foot.BackColor := clPanel;
  Foot.ChildSizing.TopBottomSpacing := ScI(10);
  Foot.ChildSizing.LeftRightSpacing := ScI(14);
  BtnClose := Btn(L('Close', 'ปิด'), bsAccent, @CloseClick);
  BtnCopy := Btn(L('Copy', 'คัดลอก'), bsNormal, @CopyClick);
  BtnClose.Left := 900;
  BtnCopy.Left := 800;

  ClientWidth := ScI(POP_W) + 2;
  ClientHeight := 2 + ScI(HEAD_H) + ScI(6) + Length(FBody.Rows) * ScI(ROW_H) + ScI(6) + ScI(FOOT_H);
end;

function TIdentPopup.AsText: string;
var
  I: Integer;
begin
  if HasName(FBody.Item) then Result := FBody.Item.Title else Result := FBody.Item.IP;
  Result := Result + LineEnding;
  for I := 0 to High(FBody.Rows) do
    if FBody.Rows[I].Key <> '' then
      Result := Result + FBody.Rows[I].Key + ': ' + FBody.Rows[I].Value + LineEnding;
end;

procedure TIdentPopup.CopyClick(Sender: TObject);
begin
  Clipboard.AsText := AsText;
  Close;
end;

procedure TIdentPopup.CloseClick(Sender: TObject);
begin
  Close;
end;

procedure TIdentPopup.DeactivateEvt(Sender: TObject);
begin
  // a click anywhere else closes it, like a menu
  Close;
end;

procedure TIdentPopup.CloseEvt(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
end;

procedure TIdentPopup.KeyDownEvt(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then Close
  else if (Key = VK_C) and (ssCtrl in Shift) then CopyClick(nil);
end;

procedure ShowIdentity(AOwner: TComponent; const Item: TSideItem; const WebUrl: string;
  const ScreenPt: TPoint);
var
  P: TIdentPopup;
  WA: TRect;
  X, Y: Integer;
begin
  // not modal: it frees itself when closed (or with its owner)
  P := TIdentPopup.CreatePopup(AOwner, Item, WebUrl);
  // next to the mouse, kept inside the screen it is on
  WA := Screen.MonitorFromPoint(ScreenPt).WorkareaRect;
  X := ScreenPt.X + ScI(6);
  Y := ScreenPt.Y;
  if X + P.Width > WA.Right then X := Max(WA.Left, ScreenPt.X - P.Width - ScI(6));
  if Y + P.Height > WA.Bottom then Y := Max(WA.Top, WA.Bottom - P.Height);
  P.Left := X;
  P.Top := Y;
  P.Show;
end;

end.
