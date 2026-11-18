program makeicon;

{ Draws the LAN Share logo (UITheme.DrawAppLogo) with BGRABitmap and writes
    ../../LanShare.ico        multi-size Windows icon (PNG entries 16..256)
    ../../favicon.b64         32 px PNG as base64 for the web page
    ../../screenshots/icon-256.png
  Build:  lazbuild tools/makeicon/makeicon.lpi   then run it from any folder. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Classes, SysUtils, base64, BGRABitmap, BGRABitmapTypes, UITheme;

const
  Sizes: array[0..8] of Integer = (16, 20, 24, 32, 40, 48, 64, 128, 256);

function DrawLogo(S: Integer): TBGRABitmap;
var
  M: Single;
begin
  Result := TBGRABitmap.Create(S, S, BGRAPixelTransparent);
  // small icons use the full square; big ones keep a little margin
  if S <= 24 then M := 0 else M := S * 0.04;
  DrawAppLogo(Result, M, M, S - 2 * M);
end;

function LogoPng(S: Integer): TMemoryStream;
var
  B: TBGRABitmap;
begin
  B := DrawLogo(S);
  try
    Result := TMemoryStream.Create;
    B.SaveToStreamAsPng(Result);
    Result.Position := 0;
  finally
    B.Free;
  end;
end;

procedure WriteWord(F: TStream; V: Word); forward;
procedure WriteDWord(F: TStream; V: LongWord); forward;

{ 32-bit DIB icon image (BITMAPINFOHEADER + BGRA rows bottom-up + AND mask).
  Used for sizes below 256: LCL (and old Windows) cannot read PNG entries there. }
function LogoDib(S: Integer): TMemoryStream;
var
  B: TBGRABitmap;
  X, Y, MaskRow: Integer;
  P: PBGRAPixel;
  Px: array[0..3] of Byte;
begin
  B := DrawLogo(S);
  try
    Result := TMemoryStream.Create;
    WriteDWord(Result, 40);          // biSize
    WriteDWord(Result, S);           // biWidth
    WriteDWord(Result, S * 2);       // biHeight: image + mask
    WriteWord(Result, 1);            // biPlanes
    WriteWord(Result, 32);           // biBitCount
    WriteDWord(Result, 0);           // BI_RGB
    WriteDWord(Result, S * S * 4);
    WriteDWord(Result, 0);
    WriteDWord(Result, 0);
    WriteDWord(Result, 0);
    WriteDWord(Result, 0);
    for Y := S - 1 downto 0 do
    begin
      P := B.ScanLine[Y];
      for X := 0 to S - 1 do
      begin
        Px[0] := P^.blue;
        Px[1] := P^.green;
        Px[2] := P^.red;
        Px[3] := P^.alpha;
        Result.WriteBuffer(Px, 4);
        Inc(P);
      end;
    end;
    // AND mask: all 0 (the alpha channel decides transparency), rows padded to 32 bits
    MaskRow := ((S + 31) div 32) * 4;
    for Y := 0 to S - 1 do
      for X := 1 to MaskRow do
        Result.WriteByte(0);
    Result.Position := 0;
  finally
    B.Free;
  end;
end;

procedure WriteWord(F: TStream; V: Word);
begin
  V := NtoLE(V);
  F.WriteBuffer(V, 2);
end;

procedure WriteDWord(F: TStream; V: LongWord);
begin
  V := NtoLE(V);
  F.WriteBuffer(V, 4);
end;

var
  Root: string;
  Pngs: array of TMemoryStream;
  F: TFileStream;
  I: Integer;
  Offset: LongWord;
  S: string;
  T: TStringList;
  Fav: TMemoryStream;
begin
  Root := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + '..' + PathDelim);
  if ParamCount > 0 then Root := IncludeTrailingPathDelimiter(ParamStr(1));
  UIScale := 1;

  SetLength(Pngs, Length(Sizes));
  for I := 0 to High(Sizes) do
    if Sizes[I] >= 256 then
      Pngs[I] := LogoPng(Sizes[I])
    else
      Pngs[I] := LogoDib(Sizes[I]);
  try
    // ICO = header + directory + images (DIB below 256 px, PNG at 256 px)
    F := TFileStream.Create(Root + 'LanShare.ico', fmCreate);
    try
      WriteWord(F, 0);
      WriteWord(F, 1);
      WriteWord(F, Length(Sizes));
      Offset := 6 + 16 * Length(Sizes);
      for I := 0 to High(Sizes) do
      begin
        F.WriteByte(Byte(Sizes[I] mod 256));   // 256 is written as 0
        F.WriteByte(Byte(Sizes[I] mod 256));
        F.WriteByte(0);
        F.WriteByte(0);
        WriteWord(F, 1);
        WriteWord(F, 32);
        WriteDWord(F, Pngs[I].Size);
        WriteDWord(F, Offset);
        Inc(Offset, Pngs[I].Size);
      end;
      for I := 0 to High(Sizes) do
        F.CopyFrom(Pngs[I], 0);
    finally
      F.Free;
    end;

    // favicon for the web page (32 px PNG)
    Fav := LogoPng(32);
    try
      SetLength(S, Fav.Size);
      Fav.ReadBuffer(S[1], Length(S));
    finally
      Fav.Free;
    end;
    T := TStringList.Create;
    try
      T.Text := EncodeStringBase64(S);
      T.SaveToFile(Root + 'favicon.b64');
    finally
      T.Free;
    end;

    ForceDirectories(Root + 'screenshots');
    Pngs[High(Pngs)].SaveToFile(Root + 'screenshots' + PathDelim + 'icon-256.png');
    WriteLn('wrote ', Root, 'LanShare.ico, favicon.b64, screenshots/icon-256.png');
  finally
    for I := 0 to High(Pngs) do Pngs[I].Free;
  end;
end.
