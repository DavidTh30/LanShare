{ ======================================================================
  HTTP / JSON API of LAN Share  (included by lannet.pas)

  Lets phones (a future Android app, or any browser) use LAN Share with
  plain HTTP on the same TCP port as the binary protocol. One request per
  connection ("Connection: close"). Full description: PROTOCOL.md

    GET  /                    web page for browsers
    GET  /theme.css[?name=]   colours of the PC's current theme, or of a named one
    GET  /api/themes          themes a browser can pick (name, label, preview colours)
    GET  /view?path=          same page in viewer mode: Markdown pages with
                              PNG/JPG/GIF/PDF/MP4 (for notice / advert screens)
    GET  /api/info            who is this machine
    GET  /api/list?path=      one folder of the shares ('' = list of shares)
    GET  /api/tree?path=      every file/folder below path (for folder download)
    GET  /api/file?path=      file content, supports Range (resume) and HEAD
    POST /api/push/begin?files=&bytes=     ask to send files -> token
    PUT  /api/push/file?token=&path=       upload one file (body = content)
    POST /api/push/end?token=              finish the upload

  Security: same as the binary protocol (read-only shares, no '..').
  Requests whose Host header is a domain name are refused, so a web page on
  the internet cannot reach the API through DNS rebinding. No CORS headers
  are sent, so other web sites cannot read the answers.
  ====================================================================== }

{$I webui.inc}

type
  EHttp = class(ENetError)
  public
    Code: Integer;
    constructor CreateCode(ACode: Integer; const Msg: string);
  end;

constructor EHttp.CreateCode(ACode: Integer; const Msg: string);
begin
  inherited Create(Msg);
  Code := ACode;
end;

function JsonStr(const S: string): string;
var
  I: Integer;
  C: Char;
  U: UTF8String;
begin
  U := S;
  Result := '"';
  for I := 1 to Length(U) do
  begin
    C := U[I];
    case C of
      '"':  Result := Result + '\"';
      '\':  Result := Result + '\\';
      #8:   Result := Result + '\b';
      #9:   Result := Result + '\t';
      #10:  Result := Result + '\n';
      #12:  Result := Result + '\f';
      #13:  Result := Result + '\r';
      #0..#7, #11, #14..#31: Result := Result + '\u' + IntToHex(Ord(C), 4);
    else
      Result := Result + C;
    end;
  end;
  Result := Result + '"';
end;

function JsonBool(B: Boolean): string;
begin
  if B then Result := 'true' else Result := 'false';
end;

function UrlDecode(const S: string; PlusIsSpace: Boolean): string;
var
  I, H: Integer;
  R: RawByteString;
begin
  R := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '%') and (I + 2 <= Length(S)) and TryStrToInt('$' + Copy(S, I + 1, 2), H) then
    begin
      R := R + AnsiChar(H);
      Inc(I, 3);
    end
    else
    begin
      if PlusIsSpace and (S[I] = '+') then R := R + ' ' else R := R + S[I];
      Inc(I);
    end;
  end;
  SetCodePage(R, CP_UTF8, False);
  Result := R;
end;

function UrlEncode(const S: string): string;
var
  U: UTF8String;
  I: Integer;
begin
  U := S;
  Result := '';
  for I := 1 to Length(U) do
    if U[I] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~'] then
      Result := Result + U[I]
    else
      Result := Result + '%' + IntToHex(Ord(U[I]), 2);
end;

function StatusText(Code: Integer): string;
begin
  case Code of
    100: Result := 'Continue';
    200: Result := 'OK';
    204: Result := 'No Content';
    206: Result := 'Partial Content';
    400: Result := 'Bad Request';
    403: Result := 'Forbidden';
    404: Result := 'Not Found';
    405: Result := 'Method Not Allowed';
    410: Result := 'Gone';
    411: Result := 'Length Required';
    416: Result := 'Range Not Satisfiable';
    500: Result := 'Internal Server Error';
  else
    Result := 'Status';
  end;
end;

function MimeOf(const FileName: string): string;
var
  E: string;
begin
  E := LowerCase(ExtractFileExt(FileName));
  if (E = '.jpg') or (E = '.jpeg') then Result := 'image/jpeg'
  else if E = '.png' then Result := 'image/png'
  else if E = '.gif' then Result := 'image/gif'
  else if E = '.webp' then Result := 'image/webp'
  else if E = '.mp4' then Result := 'video/mp4'
  else if E = '.webm' then Result := 'video/webm'
  else if E = '.mp3' then Result := 'audio/mpeg'
  else if E = '.m4a' then Result := 'audio/mp4'
  else if E = '.pdf' then Result := 'application/pdf'
  else if (E = '.txt') or (E = '.log') or (E = '.md') or (E = '.csv') then Result := 'text/plain; charset=utf-8'
  else if E = '.apk' then Result := 'application/vnd.android.package-archive'
  else Result := 'application/octet-stream';
end;

{ Refuse Host names that look like internet domains (DNS rebinding) }
function HostAllowed(const Host: string): Boolean;
var
  H: string;
  A: in_addr;
begin
  H := LowerCase(Trim(Host));
  if (H <> '') and (H[1] = '[') then Exit(True);          // IPv6 literal
  if Pos(':', H) > 0 then H := Copy(H, 1, Pos(':', H) - 1);
  Result := (H = '') or (H = 'localhost') or TryStrToHostAddr(H, A)
    or (Pos('.', H) = 0) or H.EndsWith('.local') or H.EndsWith('.lan');
end;

function CleanVPath(const P: string): string;
begin
  Result := StringReplace(P, '\', '/', [rfReplaceAll]);
  while (Result <> '') and (Result[1] = '/') do Delete(Result, 1, 1);
  while (Result <> '') and (Result[Length(Result)] = '/') do Delete(Result, Length(Result), 1);
end;

function LastSeg(const VPath: string): string;
begin
  Result := Copy(VPath, LastDelimiter('/', VPath) + 1, MaxInt);
end;

{ RelPath from AddPathItems starts with the local folder name; replace that by
  the share-visible name so the result can be used with /api/file }
function ReplaceTop(const RelPath, NewTop: string): string;
var
  P: Integer;
begin
  P := Pos('/', RelPath);
  if P = 0 then Result := NewTop else Result := NewTop + Copy(RelPath, P, MaxInt);
end;

function UnixTimeOf(D: TDateTime): Int64;
begin
  if D > 1 then Result := DateTimeToUnix(D, False) else Result := 0;
end;

{ ---------- request / response ---------- }

procedure TServeThread.HttpReadHead(const First: string; var R: THttpReq);
var
  Head: RawByteString;
  Lines, Parts, Q: TStringArray;
  I, P: Integer;
  Name: string;
begin
  Head := First;
  while Pos(#13#10#13#10, Head) = 0 do
  begin
    if Length(Head) > 16384 then raise EHttp.CreateCode(400, 'header too large');
    Head := Head + AnsiChar(RecvByte(FSock));
  end;
  SetCodePage(Head, CP_UTF8, False);
  Lines := string(Copy(Head, 1, Pos(#13#10#13#10, Head) - 1)).Split([#13#10]);
  Parts := Lines[0].Split([' ']);
  if Length(Parts) < 2 then raise EHttp.CreateCode(400, 'bad request line');
  R.Method := UpperCase(Parts[0]);
  R.Target := Parts[1];
  P := Pos('?', R.Target);
  if P > 0 then
  begin
    R.Path := UrlDecode(Copy(R.Target, 1, P - 1), False);
    Q := Copy(R.Target, P + 1, MaxInt).Split(['&']);
    for I := 0 to High(Q) do
    begin
      P := Pos('=', Q[I]);
      if P > 0 then
        R.Params.Values[UrlDecode(Copy(Q[I], 1, P - 1), True)] := UrlDecode(Copy(Q[I], P + 1, MaxInt), True)
      else if Q[I] <> '' then
        R.Params.Values[UrlDecode(Q[I], True)] := '1';
    end;
  end
  else
    R.Path := UrlDecode(R.Target, False);
  for I := 1 to High(Lines) do
  begin
    P := Pos(':', Lines[I]);
    if P = 0 then Continue;
    Name := LowerCase(Trim(Copy(Lines[I], 1, P - 1)));
    R.Headers.Values[Name] := Trim(Copy(Lines[I], P + 1, MaxInt));
  end;
  R.ContentLength := StrToInt64Def(R.Headers.Values['content-length'], -1);
end;

procedure TServeThread.HttpSend(Code: Integer; const ContentType, Body: string; const Extra: string);
var
  H: string;
  U: UTF8String;
begin
  U := Body;
  H := Format('HTTP/1.1 %d %s'#13#10, [Code, StatusText(Code)]) +
    'Server: LanShare/' + APP_VERSION + #13#10 +
    'Content-Type: ' + ContentType + #13#10 +
    'Content-Length: ' + IntToStr(Length(U)) + #13#10 +
    'Cache-Control: no-store'#13#10 +
    'X-Content-Type-Options: nosniff'#13#10 +
    'Connection: close'#13#10 + Extra + #13#10;
  SockSendAll(FSock, H[1], Length(H));
  FHttpSent := True;   // headers are out: errors can no longer be reported by HTTP
  if (U <> '') and not FHttpHead then SockSendAll(FSock, U[1], Length(U));
end;

procedure TServeThread.HttpError(Code: Integer; const AMsg: string);
begin
  HttpSend(Code, 'application/json; charset=utf-8', '{"error":' + JsonStr(AMsg) + '}');
end;

procedure TServeThread.HandleHttp(const First: string);
var
  R: THttpReq;
  Css: string;
begin
  R := Default(THttpReq);
  R.Params := TStringList.Create;
  R.Headers := TStringList.Create;
  try
    try
      SetTimeout(FSock, 60000);
      HttpReadHead(First, R);
      FPeerName := UrlDecode(R.Headers.Values['x-lanshare-name'], False);
      if FPeerName = '' then FPeerName := R.Params.Values['client'];
      if FPeerName = '' then FPeerName := 'เบราว์เซอร์ ' + FPeerIP;
      FHttpHead := R.Method = 'HEAD';
      if not HostAllowed(R.Headers.Values['host']) then
        raise EHttp.CreateCode(403, 'Host not allowed');
      if R.Method = 'OPTIONS' then
        HttpSend(204, 'text/plain', '', 'Allow: GET, HEAD, POST, PUT'#13#10)
      else if ((R.Path = '/') or (R.Path = '/index.html') or (R.Path = '/view'))
        and ((R.Method = 'GET') or (R.Method = 'HEAD')) then
        HttpSend(200, 'text/html; charset=utf-8', WebUIHtml)
      else if R.Path = '/theme.css' then
      begin
        Css := '';
        if (R.Params.Values['name'] <> '') and Assigned(FOwner.ThemeCssFunc) then
          Css := FOwner.ThemeCssFunc(R.Params.Values['name']);
        if Css = '' then Css := FOwner.ThemeCss;
        HttpSend(200, 'text/css; charset=utf-8', Css);
      end
      else if R.Path = '/api/themes' then
        HttpSend(200, 'application/json; charset=utf-8', FOwner.ThemesJson)
      else if R.Path = '/api/info' then
        HttpInfo
      else if R.Path = '/api/list' then
        HttpList(R)
      else if R.Path = '/api/tree' then
        HttpTree(R)
      else if R.Path = '/api/file' then
        HttpFile(R)
      else if R.Path = '/api/push/begin' then
      begin
        if R.Method <> 'POST' then raise EHttp.CreateCode(405, 'use POST');
        HttpPushBegin(R);
      end
      else if R.Path = '/api/push/file' then
      begin
        if (R.Method <> 'PUT') and (R.Method <> 'POST') then raise EHttp.CreateCode(405, 'use PUT');
        HttpPushFile(R);
      end
      else if R.Path = '/api/push/end' then
      begin
        if R.Method <> 'POST' then raise EHttp.CreateCode(405, 'use POST');
        HttpPushEnd(R);
      end
      else
        raise EHttp.CreateCode(404, 'not found: ' + R.Path);
    except
      on E: Exception do
        if not FHttpSent then   // only if no response has started yet
        try
          if E is EHttp then HttpError(EHttp(E).Code, E.Message)
          else HttpError(400, E.Message);
        except
          // client already gone
        end;
    end;
  finally
    R.Params.Free;
    R.Headers.Free;
  end;
end;

{ ---------- endpoints ---------- }

procedure TServeThread.HttpInfo;
begin
  HttpSend(200, 'application/json; charset=utf-8',
    '{"app":"LanShare","version":"' + APP_VERSION + '","protocol":' + IntToStr(PROTO_VERSION) + ',"api":1' +
    ',"id":' + JsonStr(FOwner.MyID) +
    ',"name":' + JsonStr(FOwner.MyName) +
    ',"icon":' + JsonStr(FOwner.MyIcon) +
    ',"theme":"/theme.css"' +
    ',"os":' + JsonStr(GetOSName) +
    ',"port":' + IntToStr(FOwner.Port) +
    ',"caps":["bin","http","push"]' +
    ',"shares":' + IntToStr(FOwner.Shares.Count) +
    ',"autoAccept":' + JsonBool(FOwner.AutoAccept) + '}');
end;

procedure TServeThread.HttpList(const R: THttpReq);
var
  Path, Local, J: string;
  E: TRemoteEntries;
  I: Integer;
begin
  Path := CleanVPath(R.Params.Values['path']);
  if Path = '' then
    E := FOwner.Shares.RootEntries
  else if FOwner.Shares.Resolve(Path, Local) and DirectoryExists(Local) then
    E := ListLocalDir(Local)
  else
    raise EHttp.CreateCode(404, 'folder not found or no longer shared');
  J := '{"path":' + JsonStr(Path) + ',"items":[';
  for I := 0 to High(E) do
  begin
    if I > 0 then J := J + ',';
    J := J + '{"name":' + JsonStr(E[I].Name) + ',"dir":' + JsonBool(E[I].IsDir) +
      ',"size":' + IntToStr(E[I].Size) + ',"mtime":' + IntToStr(UnixTimeOf(E[I].Modified)) + '}';
  end;
  HttpSend(200, 'application/json; charset=utf-8', J + ']}');
end;

procedure TServeThread.HttpTree(const R: THttpReq);
var
  Path, Local: string;
  Roots: TRemoteEntries;
  Items: TSendItems;
  FC, K: Integer;
  TB: Int64;
  J: TStringList;
  VParent, Rel: string;

  procedure AddRoot(const VPath, ALocal: string);
  var
    Start, X: Integer;
  begin
    Start := Length(Items);
    AddPathItems(ALocal, Items, FC, TB);
    if Length(Items) > 200000 then raise EHttp.CreateCode(400, 'too many files');
    for X := Start to High(Items) do
    begin
      Rel := ReplaceTop(Items[X].RelPath, LastSeg(VPath));
      VParent := ParentVPath(VPath);
      if J.Count > 0 then J.Add(',');
      if Items[X].Kind = KIND_DIR then
        J.Add('{"path":' + JsonStr(JoinVPath(VParent, Rel)) + ',"rel":' + JsonStr(Rel) + ',"dir":true}')
      else
        J.Add('{"path":' + JsonStr(JoinVPath(VParent, Rel)) + ',"rel":' + JsonStr(Rel) +
          ',"dir":false,"size":' + IntToStr(Items[X].Size) + '}');
    end;
  end;

begin
  Path := CleanVPath(R.Params.Values['path']);
  Items := nil;
  FC := 0;
  TB := 0;
  J := TStringList.Create;
  try
    J.LineBreak := '';
    if Path = '' then
    begin
      Roots := FOwner.Shares.RootEntries;
      for K := 0 to High(Roots) do
        AddRoot(Roots[K].Name, Roots[K].LocalPath);
    end
    else if FOwner.Shares.Resolve(Path, Local) then
      AddRoot(Path, Local)
    else
      raise EHttp.CreateCode(404, 'not found or no longer shared');
    HttpSend(200, 'application/json; charset=utf-8',
      '{"path":' + JsonStr(Path) + ',"files":' + IntToStr(FC) + ',"bytes":' + IntToStr(TB) +
      ',"items":[' + J.Text + ']}');
  finally
    J.Free;
  end;
end;

procedure TServeThread.HttpFile(const R: THttpReq);
var
  Path, Local, Rng, A, B, Extra, Disp: string;
  FS: TFileStream;
  Size, StartPos, EndPos, Len, Left: Int64;
  Partial, HeadOnly, Silent: Boolean;
  Buf: array of Byte;
  N, P: Integer;
  H: string;
begin
  Path := CleanVPath(R.Params.Values['path']);
  if (Path = '') or not FOwner.Shares.Resolve(Path, Local) or not FileExists(Local) then
    raise EHttp.CreateCode(404, 'file not found or no longer shared');
  HeadOnly := R.Method = 'HEAD';
  FS := TFileStream.Create(Local, fmOpenRead or fmShareDenyNone);
  try
    Size := FS.Size;
    StartPos := 0;
    EndPos := Size - 1;
    Partial := False;
    Rng := LowerCase(R.Headers.Values['range']);
    if (Copy(Rng, 1, 6) = 'bytes=') and (Pos(',', Rng) = 0) then
    begin
      Rng := Copy(Rng, 7, MaxInt);
      P := Pos('-', Rng);
      if P > 0 then
      begin
        A := Trim(Copy(Rng, 1, P - 1));
        B := Trim(Copy(Rng, P + 1, MaxInt));
        if A = '' then
        begin                                     // last N bytes
          StartPos := Max(0, Size - StrToInt64Def(B, 0));
        end
        else
        begin
          StartPos := StrToInt64Def(A, 0);
          if B <> '' then EndPos := Min(Size - 1, StrToInt64Def(B, Size - 1));
        end;
        Partial := True;
        if (StartPos >= Size) or (StartPos > EndPos) then
        begin
          HttpSend(416, 'application/json; charset=utf-8', '{"error":"range"}',
            'Content-Range: bytes */' + IntToStr(Size) + #13#10);
          Exit;
        end;
      end;
    end;
    Len := EndPos - StartPos + 1;
    if Size = 0 then Len := 0;

    if R.Params.Values['dl'] = '1' then Disp := 'attachment' else Disp := 'inline';
    Extra := 'Accept-Ranges: bytes'#13#10 +
      'Content-Disposition: ' + Disp + '; filename*=UTF-8''''' + UrlEncode(LastSeg(Path)) + #13#10;
    if Partial then
      Extra := Extra + Format('Content-Range: bytes %d-%d/%d'#13#10, [StartPos, EndPos, Size]);
    if Partial then N := 206 else N := 200;
    H := Format('HTTP/1.1 %d %s'#13#10, [N, StatusText(N)]) +
      'Server: LanShare/' + APP_VERSION + #13#10 +
      'Content-Type: ' + MimeOf(Local) + #13#10 +
      'Content-Length: ' + IntToStr(Len) + #13#10 +
      'Connection: close'#13#10 + Extra + #13#10;
    SockSendAll(FSock, H[1], Length(H));
    FHttpSent := True;
    if HeadOnly or (Len = 0) then Exit;

    // progress card only for real downloads (dl=1 or a batch); pictures, video
    // and .md pages shown inline by the web page / kiosk screens stay silent
    Silent := (R.Params.Values['dl'] <> '1') and (R.Params.Values['batch'] = '');
    // several files of one folder download share a "batch" card
    FKind := tkServe;
    FTitle := LastSeg(Path);
    FTotal := Len;
    if R.Params.Values['batch'] <> '' then
    begin
      FGroup := 'http:' + FPeerIP + ':' + R.Params.Values['batch'];
      FGroupFiles := StrToIntDef(R.Params.Values['batchFiles'], 0);
      FGroupBytes := StrToInt64Def(R.Params.Values['batchBytes'], 0);
    end;
    if not Silent then SetState(tsRunning, '');
    try
      FS.Position := StartPos;
      SetLength(Buf, BUF_SIZE);
      Left := Len;
      while Left > 0 do
      begin
        if Terminated then raise ENetError.Create('ยกเลิกแล้ว');
        if Left > BUF_SIZE then N := BUF_SIZE else N := Left;
        N := FS.Read(Buf[0], N);
        if N <= 0 then raise ENetError.Create('อ่านไฟล์ไม่ได้');
        SockSendAll(FSock, Buf[0], N);
        Dec(Left, N);
        Inc(FDone, N);
        if not Silent then Report;
      end;
      if not Silent then SetState(tsDone, 'ส่งสำเร็จ');
    except
      on E: Exception do
      begin
        if not Silent then SetState(tsFailed, E.Message);
        raise;
      end;
    end;
  finally
    FS.Free;
  end;
end;

procedure TServeThread.HttpPushBegin(const R: THttpReq);
var
  S: TPushSession;
begin
  FFileCount := StrToIntDef(R.Params.Values['files'], 0);
  FTotal := StrToInt64Def(R.Params.Values['bytes'], 0);
  if (FFileCount <= 0) or (FTotal < 0) then
    raise EHttp.CreateCode(400, 'files and bytes are required');
  Synchronize(@DoAsk);   // may show a question on screen; the request waits
  if not FAccepted then
  begin
    Log(Format('ปฏิเสธไฟล์จาก %s (%s)', [FPeerName, FPeerIP]));
    raise EHttp.CreateCode(403, 'rejected');
  end;
  S := FOwner.NewSession(FPeerName, FPeerIP, FFileCount, FTotal);
  FTotal := 0;
  HttpSend(200, 'application/json; charset=utf-8', '{"token":' + JsonStr(S.Token) + '}');
end;

procedure TServeThread.HttpPushFile(const R: THttpReq);
var
  S: TPushSession;
  Rel, Target: string;
  FS: TFileStream;
  Left: Int64;
  Buf: array of Byte;
  N: Integer;
  H: string;
begin
  S := FOwner.FindSession(R.Params.Values['token']);
  if S = nil then raise EHttp.CreateCode(404, 'unknown or expired token');
  if S.Ended then raise EHttp.CreateCode(410, 'session already ended');
  Rel := CleanVPath(R.Params.Values['path']);
  if Rel = '' then raise EHttp.CreateCode(400, 'path is required');
  FOwner.Lock;
  try
    Target := SafeTargetIn(S.DestRoot, Rel, S.TopMap);
  finally
    FOwner.Unlock;
  end;
  if R.Params.Values['dir'] = '1' then
  begin
    ForceDirectories(Target);
    HttpSend(200, 'application/json; charset=utf-8', '{"ok":true}');
    Exit;
  end;
  if R.ContentLength < 0 then raise EHttp.CreateCode(411, 'Content-Length is required');
  if LowerCase(R.Headers.Values['expect']) = '100-continue' then
  begin
    H := 'HTTP/1.1 100 Continue'#13#10#13#10;
    SockSendAll(FSock, H[1], Length(H));
  end;

  FKind := tkReceive;
  FPeerName := S.PeerName;
  FTitle := LastSeg(Rel);
  FTotal := R.ContentLength;
  FGroup := 'push:' + S.Token;
  FGroupFiles := S.Files;
  FGroupBytes := S.Bytes;
  ForceDirectories(ExtractFileDir(Target));
  SetState(tsRunning, '');
  try
    FS := TFileStream.Create(Target, fmCreate);
    try
      SetLength(Buf, BUF_SIZE);
      Left := R.ContentLength;
      while Left > 0 do
      begin
        if Terminated then raise ENetError.Create('ยกเลิกแล้ว');
        if Left > BUF_SIZE then N := BUF_SIZE else N := Left;
        N := fprecv(FSock, @Buf[0], N, 0);
        if N <= 0 then raise ENetError.Create('การเชื่อมต่อขาด');
        FS.WriteBuffer(Buf[0], N);
        Dec(Left, N);
        Inc(FDone, N);
        S.LastUsed := GetTickCount64;
        Report;
      end;
    finally
      FS.Free;
    end;
    FOwner.Lock;
    try
      Inc(S.Received);
    finally
      FOwner.Unlock;
    end;
    SetState(tsDone, 'รับสำเร็จ');
  except
    on E: Exception do
    begin
      SetState(tsFailed, E.Message);
      raise;
    end;
  end;
  HttpSend(200, 'application/json; charset=utf-8', '{"ok":true}');
end;

procedure TServeThread.HttpPushEnd(const R: THttpReq);
var
  S: TPushSession;
begin
  S := FOwner.FindSession(R.Params.Values['token']);
  if S = nil then raise EHttp.CreateCode(404, 'unknown or expired token');
  S.Ended := True;
  Log(Format('รับ %d ไฟล์จาก %s สำเร็จ', [S.Received, S.PeerName]));
  // tell the UI that this batch is complete (closes its card)
  FKind := tkReceive;
  FPeerName := S.PeerName;
  FGroup := 'push:' + S.Token;
  FGroupFiles := S.Files;
  FGroupBytes := S.Bytes;
  FGroupEnded := True;
  FState := tsDone;
  Report(True);
  HttpSend(200, 'application/json; charset=utf-8',
    '{"ok":true,"received":' + IntToStr(S.Received) + '}');
end;
