unit DragOut;

{ Drag files and folders from LAN Share into Explorer, the desktop or any
  program that accepts dropped files (Windows OLE drag and drop).

  - Own shares:   a normal file drag (CF_HDROP) with the real paths.
  - Other PCs:    "virtual files" (FileGroupDescriptorW + FileContents), the
                  way Outlook attachments or zip folders are dragged out.
                  Explorer gets the names and sizes at once and asks for each
                  file's content only when it is dropped; the content is then
                  fetched from the other PC over its HTTP API.

  On other systems the functions return False (not supported). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TRemoteFile = record
    RelPath: string;   // where it lands, relative to the drop folder ('/' separated)
    VPath: string;     // path in the other PC's shares (for /api/file)
    IsDir: Boolean;
    Size: Int64;
    MTime: Int64;      // unix time, 0 = unknown
  end;
  TRemoteFiles = array of TRemoteFile;

function DragOutSupported: Boolean;
{ starts a drag of local files/folders; returns when the drag ended }
function DragLocalFiles(const Paths: array of string): Boolean;
{ expands folders with /api/tree of Host and adds files as they are }
function RemoteDragList(const Host: string; Port: Integer; const Items: TRemoteFiles;
  out Files: TRemoteFiles; out Error: string): Boolean;
{ starts a drag of files on another PC; their content is downloaded on drop }
function DragRemoteFiles(const Host: string; Port: Integer; const ClientName: string;
  const Files: TRemoteFiles): Boolean;
{ removes temporary download folders left by earlier drags }
procedure CleanupDragTemp;
{ the same data on the clipboard (Ctrl+C), for "Paste" in Explorer }
function CopyLocalFiles(const Paths: array of string): Boolean;
function CopyRemoteFiles(const Host: string; Port: Integer; const ClientName: string;
  const Files: TRemoteFiles): Boolean;
{ at exit: take our files off the clipboard (they cannot be pasted any more) }
procedure ReleaseClipboardFiles;

implementation

uses
  {$IFDEF WINDOWS} Windows, ActiveX, ShlObj, {$ENDIF}
  fphttpclient, fpjson, jsonparser, DateUtils;

function TempRoot: string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'LanShareDrag' + PathDelim;
end;

procedure CleanupDragTemp;
var
  SR: TSearchRec;

  procedure RemoveTree(const Dir: string);
  var
    S: TSearchRec;
  begin
    if FindFirst(IncludeTrailingPathDelimiter(Dir) + AllFilesMask, faAnyFile, S) = 0 then
    try
      repeat
        if (S.Name = '.') or (S.Name = '..') then Continue;
        if (S.Attr and faDirectory) <> 0 then
          RemoveTree(IncludeTrailingPathDelimiter(Dir) + S.Name)
        else
          SysUtils.DeleteFile(IncludeTrailingPathDelimiter(Dir) + S.Name);
      until FindNext(S) <> 0;
    finally
      SysUtils.FindClose(S);
    end;
    RemoveDir(Dir);
  end;

begin
  if not DirectoryExists(TempRoot) then Exit;
  // files still in use (Explorer copying right now) simply stay until next time
  if FindFirst(TempRoot + AllFilesMask, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        if (SR.Attr and faDirectory) <> 0 then RemoveTree(TempRoot + SR.Name)
        else SysUtils.DeleteFile(TempRoot + SR.Name);
      end;
    until FindNext(SR) <> 0;
  finally
    SysUtils.FindClose(SR);
  end;
end;

function UrlEnc(const S: string): string;
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

function RemoteDragList(const Host: string; Port: Integer; const Items: TRemoteFiles;
  out Files: TRemoteFiles; out Error: string): Boolean;
var
  C: TFPHTTPClient;
  J: TJSONData;
  A: TJSONArray;
  O: TJSONObject;
  I, K, N: Integer;
  Top: string;
begin
  Files := nil;
  Error := '';
  Result := False;
  C := TFPHTTPClient.Create(nil);
  try
    C.IOTimeout := 15000;
    for I := 0 to High(Items) do
    begin
      if not Items[I].IsDir then
      begin
        SetLength(Files, Length(Files) + 1);
        Files[High(Files)] := Items[I];
        Continue;
      end;
      // a folder: list everything below it
      try
        J := GetJSON(C.Get(Format('http://%s:%d/api/tree?path=%s', [Host, Port, UrlEnc(Items[I].VPath)])));
      except
        on E: Exception do
        begin
          Error := E.Message;
          Exit;
        end;
      end;
      try
        A := TJSONObject(J).Arrays['items'];
        Top := Items[I].RelPath;    // name of the dragged folder
        N := Length(Files);
        SetLength(Files, N + A.Count);
        for K := 0 to A.Count - 1 do
        begin
          O := A.Objects[K];
          Files[N + K].VPath := O.Get('path', '');
          // 'rel' starts with the folder's own name: put it under Top
          Files[N + K].RelPath := Top + Copy(O.Get('rel', ''), Pos('/', O.Get('rel', '') + '/'), MaxInt);
          Files[N + K].IsDir := O.Get('dir', False);
          Files[N + K].Size := O.Get('size', Int64(0));
          Files[N + K].MTime := 0;
        end;
      finally
        J.Free;
      end;
    end;
    Result := True;
  finally
    C.Free;
  end;
end;

{$IFDEF WINDOWS}

const
  FD_ATTRIBUTES = $00000004;
  FD_WRITESTIME = $00000020;
  FD_FILESIZE   = $00000040;
  FD_PROGRESSUI = $00004000;
  DATADIR_GET   = 1;

function SHCreateStdEnumFmtEtc(cfmt: UINT; afmt: PFormatEtc; out ppenum: IEnumFORMATETC): HRESULT;
  stdcall; external 'shell32.dll' name 'SHCreateStdEnumFmtEtc';
procedure ReleaseStgMedium(var medium: TStgMedium); stdcall; external 'ole32.dll' name 'ReleaseStgMedium';

var
  CF_FILEDESCRIPTORW, CF_FILECONTENTS, CF_PREFERREDDROPEFFECT: Word;

type
  { temporary download that deletes itself once Explorer is done with it }
  TTempFileStream = class(TFileStream)
  private
    FPath: string;
  public
    constructor Create(const APath: string);
    destructor Destroy; override;
  end;

  TDropSource = class(TInterfacedObject, IDropSource)
    function QueryContinueDrag(fEscapePressed: BOOL; grfKeyState: DWORD): HResult; stdcall;
    function GiveFeedback(dwEffect: DWORD): HResult; stdcall;
  end;

  TFileDataObject = class(TInterfacedObject, IDataObject)
  private
    FFormats: array of TFormatEtc;
    FLocal: TStringArray;          // local mode: real paths
    FRemote: TRemoteFiles;         // remote mode: files on another PC
    FHost, FClient, FBatch, FTemp: string;
    FPort: Integer;
    FTotal: Int64;
    FFileCount: Integer;
    procedure AddFormat(ACf: Word; ATymed: DWORD; AIndex: LongInt = -1);
    function HGlobalOf(const Data; Size: PtrUInt): HGLOBAL;
    function DropFilesBlock: HGLOBAL;
    function DescriptorBlock: HGLOBAL;
    function ContentsStream(Index: Integer; out Stm: IStream): HRESULT;
  public
    constructor CreateLocal(const Paths: array of string);
    constructor CreateRemote(const AHost: string; APort: Integer; const AClient: string;
      const Files: TRemoteFiles);
    function GetData(const formatetcIn: FORMATETC; out medium: STGMEDIUM): HRESULT; stdcall;
    function GetDataHere(const pformatetc: FormatETC; out medium: STGMEDIUM): HRESULT; stdcall;
    function QueryGetData(const pformatetc: FORMATETC): HRESULT; stdcall;
    function GetCanonicalFormatEtc(const pformatetcIn: FORMATETC; out pformatetcOut: FORMATETC): HResult; stdcall;
    function SetData(const pformatetc: FORMATETC; var medium: STGMEDIUM; FRelease: BOOL): HRESULT; stdcall;
    function EnumFormatEtc(dwDirection: DWord; out enumformatetcpara: IENUMFORMATETC): HRESULT; stdcall;
    function DAdvise(const formatetc: FORMATETC; advf: DWORD; const AdvSink: IAdviseSink; out dwConnection: DWORD): HRESULT; stdcall;
    function DUnadvise(dwconnection: DWord): HRESULT; stdcall;
    function EnumDAdvise(out enumAdvise: IEnumStatData): HResult; stdcall;
  end;

{ ---------- TTempFileStream ---------- }

constructor TTempFileStream.Create(const APath: string);
begin
  inherited Create(APath, fmOpenRead or fmShareDenyWrite);
  FPath := APath;
end;

destructor TTempFileStream.Destroy;
begin
  inherited Destroy;
  SysUtils.DeleteFile(FPath);
end;

{ ---------- TDropSource ---------- }

function TDropSource.QueryContinueDrag(fEscapePressed: BOOL; grfKeyState: DWORD): HResult; stdcall;
begin
  if fEscapePressed or ((grfKeyState and MK_RBUTTON) <> 0) then
    Result := DRAGDROP_S_CANCEL
  else if (grfKeyState and MK_LBUTTON) = 0 then
    Result := DRAGDROP_S_DROP
  else
    Result := S_OK;
end;

function TDropSource.GiveFeedback(dwEffect: DWORD): HResult; stdcall;
begin
  Result := DRAGDROP_S_USEDEFAULTCURSORS;
end;

{ ---------- TFileDataObject ---------- }

procedure TFileDataObject.AddFormat(ACf: Word; ATymed: DWORD; AIndex: LongInt);
var
  F: TFormatEtc;
begin
  // no "with" here: the record field "tymed" would hide a parameter of the same name
  F.CfFormat := ACf;
  F.Ptd := nil;
  F.dwAspect := DVASPECT_CONTENT;
  F.lindex := AIndex;
  F.tymed := ATymed;
  SetLength(FFormats, Length(FFormats) + 1);
  FFormats[High(FFormats)] := F;
end;

constructor TFileDataObject.CreateLocal(const Paths: array of string);
var
  I: Integer;
begin
  inherited Create;
  SetLength(FLocal, Length(Paths));
  for I := 0 to High(Paths) do FLocal[I] := Paths[I];
  AddFormat(CF_HDROP, TYMED_HGLOBAL);
  AddFormat(CF_PREFERREDDROPEFFECT, TYMED_HGLOBAL);
end;

constructor TFileDataObject.CreateRemote(const AHost: string; APort: Integer;
  const AClient: string; const Files: TRemoteFiles);
var
  I: Integer;
begin
  inherited Create;
  FHost := AHost;
  FPort := APort;
  FClient := AClient;
  FRemote := Copy(Files);
  FBatch := 'drag' + IntToHex(Random($FFFFFF), 6);
  FTemp := TempRoot + FBatch + PathDelim;
  for I := 0 to High(FRemote) do
    if not FRemote[I].IsDir then
    begin
      Inc(FTotal, FRemote[I].Size);
      Inc(FFileCount);
    end;
  AddFormat(CF_FILEDESCRIPTORW, TYMED_HGLOBAL);
  AddFormat(CF_FILECONTENTS, TYMED_ISTREAM);
  AddFormat(CF_PREFERREDDROPEFFECT, TYMED_HGLOBAL);
end;

function TFileDataObject.HGlobalOf(const Data; Size: PtrUInt): HGLOBAL;
var
  P: Pointer;
begin
  Result := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, Size);
  if Result = 0 then Exit;
  P := GlobalLock(Result);
  Move(Data, P^, Size);
  GlobalUnlock(Result);
end;

{ DROPFILES header followed by double-NUL-terminated wide paths }
function TFileDataObject.DropFilesBlock: HGLOBAL;
var
  Buf: TBytes;
  W: UnicodeString;
  I, Pos_: Integer;
  DF: TDropFiles;
begin
  W := '';
  for I := 0 to High(FLocal) do
    W := W + UnicodeString(ExcludeTrailingPathDelimiter(FLocal[I])) + #0;
  W := W + #0;
  SetLength(Buf, SizeOf(DF) + Length(W) * 2);
  FillChar(DF, SizeOf(DF), 0);
  DF.pFiles := SizeOf(DF);
  DF.fWide := True;
  Move(DF, Buf[0], SizeOf(DF));
  Pos_ := SizeOf(DF);
  Move(W[1], Buf[Pos_], Length(W) * 2);
  Result := HGlobalOf(Buf[0], Length(Buf));
end;

function UnixToFileTime(U: Int64): TFileTime;
var
  V: Int64;
begin
  V := (U + 11644473600) * 10000000;
  Result.dwLowDateTime := DWORD(V and $FFFFFFFF);
  Result.dwHighDateTime := DWORD(V shr 32);
end;

function TFileDataObject.DescriptorBlock: HGLOBAL;
var
  Buf: TBytes;
  FD: TFileDescriptorW;
  I, Head: Integer;
  N: UINT;
  Name: UnicodeString;
begin
  N := Length(FRemote);
  // FILEGROUPDESCRIPTORW: cItems followed by the descriptors (aligned like the C struct)
  Head := PtrUInt(@PFileGroupDescriptorW(nil)^.fgd[0]);
  SetLength(Buf, Head + Integer(N) * SizeOf(TFileDescriptorW));
  FillChar(Buf[0], Length(Buf), 0);
  Move(N, Buf[0], SizeOf(N));
  for I := 0 to High(FRemote) do
  begin
    FillChar(FD, SizeOf(FD), 0);
    FD.dwFlags := FD_ATTRIBUTES or FD_PROGRESSUI;
    if FRemote[I].IsDir then
      FD.dwFileAttributes := FILE_ATTRIBUTE_DIRECTORY
    else
    begin
      FD.dwFileAttributes := FILE_ATTRIBUTE_NORMAL;
      FD.dwFlags := FD.dwFlags or FD_FILESIZE;
      FD.nFileSizeHigh := DWORD(FRemote[I].Size shr 32);
      FD.nFileSizeLow := DWORD(FRemote[I].Size and $FFFFFFFF);
      if FRemote[I].MTime > 0 then
      begin
        FD.dwFlags := FD.dwFlags or FD_WRITESTIME;
        FD.ftLastWriteTime := UnixToFileTime(FRemote[I].MTime);
      end;
    end;
    Name := UnicodeString(StringReplace(FRemote[I].RelPath, '/', '\', [rfReplaceAll]));
    if Length(Name) > MAX_PATH - 1 then SetLength(Name, MAX_PATH - 1);
    if Name <> '' then Move(Name[1], FD.cFileName[0], Length(Name) * 2);
    Move(FD, Buf[Head + I * SizeOf(TFileDescriptorW)], SizeOf(FD));
  end;
  Result := HGlobalOf(Buf[0], Length(Buf));
end;

{ Downloads one file of the other PC when Explorer asks for it }
function TFileDataObject.ContentsStream(Index: Integer; out Stm: IStream): HRESULT;
var
  C: TFPHTTPClient;
  Path: string;
  F: TFileStream;
begin
  Stm := nil;
  if (Index < 0) or (Index > High(FRemote)) or FRemote[Index].IsDir then Exit(DV_E_LINDEX);
  ForceDirectories(FTemp);
  Path := FTemp + IntToStr(Index) + '.part';
  try
    F := TFileStream.Create(Path, fmCreate);
    try
      C := TFPHTTPClient.Create(nil);
      try
        C.IOTimeout := 60000;
        if FClient <> '' then C.AddHeader('X-LanShare-Name', UrlEnc(FClient));
        // one "batch" card on the other PC for the whole drag
        C.Get(Format('http://%s:%d/api/file?path=%s&dl=1&batch=%s&batchFiles=%d&batchBytes=%d',
          [FHost, FPort, UrlEnc(FRemote[Index].VPath), FBatch, FFileCount, FTotal]), F);
      finally
        C.Free;
      end;
    finally
      F.Free;
    end;
    Stm := TStreamAdapter.Create(TTempFileStream.Create(Path), soOwned);
    Result := S_OK;
  except
    SysUtils.DeleteFile(Path);
    Result := E_FAIL;
  end;
end;

function TFileDataObject.GetData(const formatetcIn: FORMATETC; out medium: STGMEDIUM): HRESULT; stdcall;
var
  Effect: DWORD;
  Stm: IStream;
begin
  FillChar(medium, SizeOf(medium), 0);
  Result := DV_E_FORMATETC;
  if (formatetcIn.CfFormat = CF_HDROP) and (Length(FLocal) > 0)
     and ((formatetcIn.tymed and TYMED_HGLOBAL) <> 0) then
  begin
    medium.Tymed := TYMED_HGLOBAL;
    medium.HGLOBAL := DropFilesBlock;
    Result := S_OK;
  end
  else if (formatetcIn.CfFormat = CF_FILEDESCRIPTORW) and (Length(FRemote) > 0)
     and ((formatetcIn.tymed and TYMED_HGLOBAL) <> 0) then
  begin
    medium.Tymed := TYMED_HGLOBAL;
    medium.HGLOBAL := DescriptorBlock;
    Result := S_OK;
  end
  else if (formatetcIn.CfFormat = CF_FILECONTENTS) and (Length(FRemote) > 0)
     and ((formatetcIn.tymed and TYMED_ISTREAM) <> 0) then
  begin
    Result := ContentsStream(formatetcIn.lindex, Stm);
    if Result = S_OK then
    begin
      medium.Tymed := TYMED_ISTREAM;
      medium.pstm := Pointer(Stm);
      Stm._AddRef;          // the reference now belongs to the receiver
    end;
  end
  else if (formatetcIn.CfFormat = CF_PREFERREDDROPEFFECT)
     and ((formatetcIn.tymed and TYMED_HGLOBAL) <> 0) then
  begin
    Effect := DROPEFFECT_COPY;
    medium.Tymed := TYMED_HGLOBAL;
    medium.HGLOBAL := HGlobalOf(Effect, SizeOf(Effect));
    Result := S_OK;
  end;
end;

function TFileDataObject.GetDataHere(const pformatetc: FormatETC; out medium: STGMEDIUM): HRESULT; stdcall;
begin
  Result := E_NOTIMPL;
end;

function TFileDataObject.QueryGetData(const pformatetc: FORMATETC): HRESULT; stdcall;
var
  I: Integer;
begin
  for I := 0 to High(FFormats) do
    if (FFormats[I].CfFormat = pformatetc.CfFormat) and ((FFormats[I].tymed and pformatetc.tymed) <> 0) then
      Exit(S_OK);
  Result := DV_E_FORMATETC;
end;

function TFileDataObject.GetCanonicalFormatEtc(const pformatetcIn: FORMATETC; out pformatetcOut: FORMATETC): HResult; stdcall;
begin
  pformatetcOut := pformatetcIn;
  pformatetcOut.Ptd := nil;
  Result := DATA_S_SAMEFORMATETC;
end;

function TFileDataObject.SetData(const pformatetc: FORMATETC; var medium: STGMEDIUM; FRelease: BOOL): HRESULT; stdcall;
begin
  // Explorer reports things like "Performed DropEffect" here; nothing to keep
  if FRelease then ReleaseStgMedium(medium);
  Result := S_OK;
end;

function TFileDataObject.EnumFormatEtc(dwDirection: DWord; out enumformatetcpara: IENUMFORMATETC): HRESULT; stdcall;
begin
  enumformatetcpara := nil;
  if dwDirection = DATADIR_GET then
    Result := SHCreateStdEnumFmtEtc(Length(FFormats), @FFormats[0], enumformatetcpara)
  else
    Result := E_NOTIMPL;
end;

function TFileDataObject.DAdvise(const formatetc: FORMATETC; advf: DWORD; const AdvSink: IAdviseSink; out dwConnection: DWORD): HRESULT; stdcall;
begin
  dwConnection := 0;
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function TFileDataObject.DUnadvise(dwconnection: DWord): HRESULT; stdcall;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function TFileDataObject.EnumDAdvise(out enumAdvise: IEnumStatData): HResult; stdcall;
begin
  enumAdvise := nil;
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

{ ---------- public ---------- }

function RunDrag(DataObj: IDataObject): Boolean;
var
  Effect: DWORD;
  Src: IDropSource;
begin
  Src := TDropSource.Create;
  Effect := 0;
  Result := DoDragDrop(DataObj, Src, DROPEFFECT_COPY, @Effect) = DRAGDROP_S_DROP;
end;

function DragOutSupported: Boolean;
begin
  Result := True;
end;

function DragLocalFiles(const Paths: array of string): Boolean;
begin
  Result := (Length(Paths) > 0) and RunDrag(TFileDataObject.CreateLocal(Paths));
end;

function DragRemoteFiles(const Host: string; Port: Integer; const ClientName: string;
  const Files: TRemoteFiles): Boolean;
begin
  Result := (Length(Files) > 0) and RunDrag(TFileDataObject.CreateRemote(Host, Port, ClientName, Files));
end;

var
  ClipObj: IDataObject;   // kept alive while it is on the clipboard

function PutOnClipboard(Obj: IDataObject): Boolean;
begin
  ClipObj := Obj;
  Result := OleSetClipboard(Obj) = S_OK;
end;

function CopyLocalFiles(const Paths: array of string): Boolean;
begin
  Result := (Length(Paths) > 0) and PutOnClipboard(TFileDataObject.CreateLocal(Paths));
end;

function CopyRemoteFiles(const Host: string; Port: Integer; const ClientName: string;
  const Files: TRemoteFiles): Boolean;
begin
  Result := (Length(Files) > 0) and PutOnClipboard(TFileDataObject.CreateRemote(Host, Port, ClientName, Files));
end;

procedure ReleaseClipboardFiles;
begin
  if (ClipObj <> nil) and (OleIsCurrentClipboard(ClipObj) = S_OK) then
    OleSetClipboard(nil);
  ClipObj := nil;
end;

initialization
  OleInitialize(nil);
  CF_FILEDESCRIPTORW := RegisterClipboardFormatW('FileGroupDescriptorW');
  CF_FILECONTENTS := RegisterClipboardFormatW('FileContents');
  CF_PREFERREDDROPEFFECT := RegisterClipboardFormatW('Preferred DropEffect');

finalization
  OleUninitialize;

{$ELSE}

function CopyLocalFiles(const Paths: array of string): Boolean;
begin
  Result := False;
end;

function CopyRemoteFiles(const Host: string; Port: Integer; const ClientName: string;
  const Files: TRemoteFiles): Boolean;
begin
  Result := False;
end;

procedure ReleaseClipboardFiles;
begin
end;

function DragOutSupported: Boolean;
begin
  Result := False;
end;

function DragLocalFiles(const Paths: array of string): Boolean;
begin
  Result := False;
end;

function DragRemoteFiles(const Host: string; Port: Integer; const ClientName: string;
  const Files: TRemoteFiles): Boolean;
begin
  Result := False;
end;

{$ENDIF}

end.
