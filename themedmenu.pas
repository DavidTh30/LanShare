unit ThemedMenu;

{ Right-click menu drawn in the app theme (the system popup menu ignores it).
  Closes when an item is picked, on Esc, or when the user clicks elsewhere.
  Keys: Up/Down to move, Enter to pick. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes, UITheme, UIWidgets;

type
  TMenuEntry = record
    Caption: string;
    Shortcut: string;      // shown on the right, e.g. 'F5'
    Icon: TIconKind;
    Enabled: Boolean;
    Separator: Boolean;
    Checked: Boolean;      // a check mark on the right (current choice / switch on)
    OnClick: TNotifyEvent;
  end;
  TMenuEntries = array of TMenuEntry;

function MenuItem(const ACaption: string; AIcon: TIconKind; AClick: TNotifyEvent;
  AEnabled: Boolean = True; const AShortcut: string = ''): TMenuEntry;
function MenuSep: TMenuEntry;
{ an entry with a check mark when AChecked }
function MenuCheck(const ACaption: string; AIcon: TIconKind; AClick: TNotifyEvent;
  AChecked: Boolean; AEnabled: Boolean = True): TMenuEntry;
procedure AddEntry(var A: TMenuEntries; const E: TMenuEntry);
{ shows the menu with its top-left corner at ScreenPt (kept on screen) }
procedure ShowThemedMenu(AOwner: TComponent; const ScreenPt: TPoint; const Entries: TMenuEntries);

implementation

uses
  Math;

const
  ITEM_H = 34;
  SEP_H = 11;
  PAD = 6;

type
  TMenuBody = class(TBGRAControl)
  private
    FHot: Integer;
    function ItemTop(I: Integer): Integer;
    function ItemAt(Y: Integer): Integer;
  protected
    procedure Render(B: TBGRABitmap); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    Entries: TMenuEntries;
    procedure Pick(I: Integer);
  end;

  TMenuForm = class(TForm)
  private
    FBody: TMenuBody;
    procedure DeactivateEvt(Sender: TObject);
    procedure CloseEvt(Sender: TObject; var CloseAction: TCloseAction);
    procedure KeyDownEvt(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor CreateMenu(AOwner: TComponent; const AEntries: TMenuEntries);
  end;

  { runs the picked command after the menu is gone (the command may open a
    dialog; the menu form must not be on the call stack when it is freed) }
  TMenuInvoker = class
  public
    Handler: TNotifyEvent;
    procedure Run(Data: PtrInt);
  end;

function MenuItem(const ACaption: string; AIcon: TIconKind; AClick: TNotifyEvent;
  AEnabled: Boolean; const AShortcut: string): TMenuEntry;
begin
  Result := Default(TMenuEntry);
  Result.Caption := ACaption;
  Result.Icon := AIcon;
  Result.OnClick := AClick;
  Result.Enabled := AEnabled and Assigned(AClick);
  Result.Shortcut := AShortcut;
end;

function MenuSep: TMenuEntry;
begin
  Result := Default(TMenuEntry);
  Result.Separator := True;
end;

function MenuCheck(const ACaption: string; AIcon: TIconKind; AClick: TNotifyEvent;
  AChecked: Boolean; AEnabled: Boolean): TMenuEntry;
begin
  Result := MenuItem(ACaption, AIcon, AClick, AEnabled);
  Result.Checked := AChecked;
end;

procedure AddEntry(var A: TMenuEntries; const E: TMenuEntry);
begin
  // no separator first, last or twice in a row
  if E.Separator and ((Length(A) = 0) or A[High(A)].Separator) then Exit;
  SetLength(A, Length(A) + 1);
  A[High(A)] := E;
end;

procedure TMenuInvoker.Run(Data: PtrInt);
begin
  try
    if Assigned(Handler) then Handler(nil);
  finally
    Free;
  end;
end;

{ ---------- body ---------- }

function TMenuBody.ItemTop(I: Integer): Integer;
var
  K: Integer;
begin
  Result := ScI(PAD);
  for K := 0 to I - 1 do
    if Entries[K].Separator then Inc(Result, ScI(SEP_H)) else Inc(Result, ScI(ITEM_H));
end;

function TMenuBody.ItemAt(Y: Integer): Integer;
var
  I, T, H: Integer;
begin
  Result := -1;
  T := ScI(PAD);
  for I := 0 to High(Entries) do
  begin
    if Entries[I].Separator then H := ScI(SEP_H) else H := ScI(ITEM_H);
    if (Y >= T) and (Y < T + H) then
    begin
      if (not Entries[I].Separator) and Entries[I].Enabled then Result := I;
      Exit;
    end;
    Inc(T, H);
  end;
end;

procedure TMenuBody.Render(B: TBGRABitmap);
var
  I, T: Integer;
  C: TBGRAPixel;
begin
  for I := 0 to High(Entries) do
  begin
    T := ItemTop(I);
    if Entries[I].Separator then
    begin
      B.DrawHorizLine(ScI(10), T + ScI(SEP_H) div 2, B.Width - ScI(10), clBorder);
      Continue;
    end;
    if I = FHot then
      B.FillRoundRectAntialias(ScI(5), T + 1, B.Width - ScI(5), T + ScI(ITEM_H) - 1, Sc(7), Sc(7), clHover);
    if Entries[I].Enabled then C := clText else C := WithAlpha(clTextDim, 130);
    if Entries[I].Icon <> ikNone then
      DrawIcon(B, Entries[I].Icon, ScI(14), T + (ScI(ITEM_H) - ScI(18)) / 2, ScI(18), C);
    SetFont(B, 9.5);
    TextIn(B, Rect(ScI(42), T, B.Width - ScI(14), T + ScI(ITEM_H)), Entries[I].Caption, C);
    if Entries[I].Checked then
      DrawIcon(B, ikCheck, B.Width - ScI(32), T + (ScI(ITEM_H) - ScI(18)) / 2, ScI(18), clAccent)
    else if Entries[I].Shortcut <> '' then
    begin
      SetFont(B, 8.5);
      TextIn(B, Rect(ScI(42), T, B.Width - ScI(14), T + ScI(ITEM_H)), Entries[I].Shortcut,
        WithAlpha(clTextDim, 200), taRightJustify);
    end;
  end;
end;

procedure TMenuBody.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  H: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  H := ItemAt(Y);
  if H <> FHot then
  begin
    FHot := H;
    Invalidate;
  end;
end;

procedure TMenuBody.MouseLeave;
begin
  inherited MouseLeave;
  if FHot >= 0 then
  begin
    FHot := -1;
    Invalidate;
  end;
end;

procedure TMenuBody.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  Pick(ItemAt(Y));
end;

procedure TMenuBody.Pick(I: Integer);
var
  Inv: TMenuInvoker;
begin
  if (I < 0) or (I > High(Entries)) or Entries[I].Separator or not Entries[I].Enabled then Exit;
  Inv := TMenuInvoker.Create;
  Inv.Handler := Entries[I].OnClick;
  Application.QueueAsyncCall(@Inv.Run, 0);
  TForm(Owner).Close;
end;

{ ---------- form ---------- }

constructor TMenuForm.CreateMenu(AOwner: TComponent; const AEntries: TMenuEntries);
var
  I, W, H: Integer;
  Tmp: TBGRABitmap;
begin
  inherited CreateNew(AOwner);
  BorderStyle := bsNone;
  Caption := 'LAN Share menu';   // not shown; names the window for tools
  Position := poDesigned;
  ShowInTaskBar := stNever;
  Color := BGRAToColor(clBorder);   // 1 px frame
  BorderWidth := 1;
  KeyPreview := True;
  OnKeyDown := @KeyDownEvt;
  OnDeactivate := @DeactivateEvt;
  OnClose := @CloseEvt;

  FBody := TMenuBody.Create(Self);
  FBody.Parent := Self;
  FBody.Align := alClient;
  FBody.BackColor := clPanel;
  FBody.Entries := AEntries;
  FBody.FHot := -1;

  // size to the longest caption + shortcut
  Tmp := TBGRABitmap.Create(1, 1);
  try
    W := ScI(200);
    H := ScI(PAD) * 2;
    for I := 0 to High(AEntries) do
      if AEntries[I].Separator then
        Inc(H, ScI(SEP_H))
      else
      begin
        Inc(H, ScI(ITEM_H));
        SetFont(Tmp, 9.5);
        W := Max(W, ScI(42) + TextW(Tmp, AEntries[I].Caption) + ScI(30) +
          IfThen(AEntries[I].Checked, ScI(30), 0) +
          IfThen(AEntries[I].Shortcut <> '', TextW(Tmp, AEntries[I].Shortcut) + ScI(10), 0));
      end;
  finally
    Tmp.Free;
  end;
  ClientWidth := W + 2;
  ClientHeight := H + 2;
end;

procedure TMenuForm.DeactivateEvt(Sender: TObject);
begin
  Close;   // a click anywhere else closes it
end;

procedure TMenuForm.CloseEvt(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
end;

procedure TMenuForm.KeyDownEvt(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  I, N: Integer;
begin
  N := Length(FBody.Entries);
  case Key of
    VK_ESCAPE: Close;
    VK_RETURN: FBody.Pick(FBody.FHot);
    VK_DOWN, VK_UP:
      if N > 0 then
      begin
        I := FBody.FHot;
        repeat
          if Key = VK_DOWN then I := (I + 1 + N) mod N else I := (I - 1 + N) mod N;
        until (not FBody.Entries[I].Separator and FBody.Entries[I].Enabled) or (I = FBody.FHot);
        FBody.FHot := I;
        FBody.Invalidate;
      end;
  end;
  Key := 0;
end;

procedure ShowThemedMenu(AOwner: TComponent; const ScreenPt: TPoint; const Entries: TMenuEntries);
var
  M: TMenuForm;
  WA: TRect;
  X, Y: Integer;
  E: TMenuEntries;
begin
  E := Copy(Entries);
  while (Length(E) > 0) and E[High(E)].Separator do SetLength(E, Length(E) - 1);
  if Length(E) = 0 then Exit;
  M := TMenuForm.CreateMenu(AOwner, E);
  WA := Screen.MonitorFromPoint(ScreenPt).WorkareaRect;
  X := ScreenPt.X;
  Y := ScreenPt.Y;
  if X + M.Width > WA.Right then X := Max(WA.Left, ScreenPt.X - M.Width);
  if Y + M.Height > WA.Bottom then Y := Max(WA.Top, ScreenPt.Y - M.Height);
  M.Left := X;
  M.Top := Y;
  M.Show;
end;

end.
