unit LanNet;

{ Networking core for LAN Share - cross-platform (Windows, Linux, macOS, BSD)
  Uses FPC's portable "sockets" unit; only local-IP lookup and socket
  timeouts need small per-OS code.

  Full specification for other clients (e.g. an Android app): PROTOCOL.md

  - UDP broadcast discovery (port DISCOVERY_PORT):
      'LSH2|id|tcpPort|name|os|caps|icon'
          os   = windows/linux/macos/android/...
          caps = comma list: bin,http,push
          icon = '<kind>.<color>' chosen by the user, e.g. 'laptop.2'
      A machine answers a newly seen peer at once (unicast), announces to
      peers it knows and probes its /24 subnets, so machines also find each
      other on networks that drop broadcasts.
  - The TCP port speaks two protocols, told apart by the first 4 bytes:
      'LSHR'            binary protocol below (PC <-> PC)
      'GET ','POST',... HTTP/1.1 JSON API + web page for phones (lanhttp.inc)
  - Binary protocol version 2. Every connection starts with
      'LSHR' + version(byte)=2 + command(byte) + senderName(str)

    CMD_PUSH  sender pushes files to the receiver (receiver may refuse)
      -> totalFiles(int32) + totalBytes(int64)
      <- 1 byte (1 = accept, 0 = reject)
      -> ENTRIES
      <- 1 byte (1 = all received OK)

    CMD_LIST  browse a shared folder of the other machine
      -> path(str)            ''  = list of shares, 'Share/sub' = inside a share
      <- status(byte) 1 = ok, 0 = error + message(str)
      <- count(int32) + count * (name(str) isDir(byte) size(int64) modified(int64 unix))

    CMD_GET   download shared files/folders from the other machine
      -> count(int32) + count * path(str)
      <- status(byte) 1 = ok, 0 = error + message(str)
      <- totalFiles(int32) + totalBytes(int64) + ENTRIES
      -> 1 byte (1 = all received OK)

    ENTRIES = repeated kind(byte):
                1 = dir : relPath(str)
                2 = file: relPath(str) + size(int64) + data
                0 = end
    str = uint16 length + UTF-8 bytes; paths always use '/' as separator.

  Shares are read-only: CMD_LIST/CMD_GET only reach files below a folder (or
  the single file) that the owner shared; '..' and empty path parts are refused. }

{$mode objfpc}{$H+}
{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  Classes, SysUtils, sockets;

const
  DEFAULT_TCP_PORT = 50505;
  DISCOVERY_PORT   = 50506;
  APP_VERSION      = '1.0.0';   // program version (also in LanShare.lpi VersionInfo)
  PROTO_VERSION    = 2;
  CMD_PUSH = 1;
  CMD_LIST = 2;
  CMD_GET  = 3;
  KIND_END  = 0;
  KIND_DIR  = 1;
  KIND_FILE = 2;
  BUF_SIZE  = 256 * 1024;
  INVALID_SOCK = -1;

type
  TSock = LongInt;   // handle type of the portable sockets unit
  ENetError = class(Exception);

  TSendItem = record
    Kind: Byte;
    LocalPath: string;
    RelPath: string;
    Size: Int64;
  end;
  TSendItems = array of TSendItem;

  TRemoteEntry = record
    Name: string;
    IsDir: Boolean;
    Size: Int64;
    Modified: TDateTime;
    LocalPath: string;   // only filled for our own shares
  end;
  TRemoteEntries = array of TRemoteEntry;

  TTransferKind = (tkSend, tkReceive, tkDownload, tkServe);
  TTransferState = (tsConnecting, tsWaiting, tsRunning, tsDone, tsFailed, tsRejected);

  { Snapshot of one transfer, handed to the UI (in the main thread) }
  TTransferInfo = record
    Serial: PtrUInt;        // unique per thread
    Thread: TObject;        // the TNetThread; valid only while State is active
    Group: string;          // transfers with the same Group form one card (HTTP batches)
    GroupFiles: Integer;    // expected size of the whole group, 0 = unknown
    GroupBytes: Int64;
    GroupEnded: Boolean;    // the client said the batch is complete
    Kind: TTransferKind;
    State: TTransferState;
    PeerName, PeerIP, Title, CurFile, Msg: string;
    Done, Total: Int64;
  end;

  { An upload session opened by an HTTP client (POST /api/push/begin) }
  TPushSession = class
  public
    Token, PeerName, PeerIP, DestRoot: string;
    Files: Integer;
    Bytes: Int64;
    Received: Integer;
    TopMap: TStringList;
    LastUsed: QWord;
    Ended: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

  THttpReq = record
    Method, Target, Path: string;
    Params: TStringList;     // decoded query: name=value
    Headers: TStringList;    // lower-case name=value
    ContentLength: Int64;
  end;

  { Thread-safe list of local paths this machine shares }
  TShareList = class
  private
    FLock: TRTLCriticalSection;
    FPaths: TStringList;
    function NameOf(Index: Integer): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const P: string);
    procedure Remove(const P: string);
    function Count: Integer;
    function Paths: TStringArray;
    function RootEntries: TRemoteEntries;
    { Maps a virtual path ('Share/sub/file') to a local path. }
    function Resolve(const VPath: string; out Local: string): Boolean;
  end;

  { CSS for a theme name ('' = unknown); set by the UI, so this unit does not
    depend on the theme code }
  TThemeCssFunc = function(const Name: string): string;

  TNetThread = class;
  TTransferEvent = procedure(const Info: TTransferInfo) of object;
  TLogEvent = procedure(Sender: TObject; const Msg: string) of object;
  TAskEvent = function(Sender: TObject; const FromName, FromIP: string;
    FileCount: Integer; TotalBytes: Int64): Boolean of object;
  TPeerEvent = procedure(Sender: TObject; const ID, PeerName, IP: string; Port: Integer;
    const OS, Caps, Icon: string) of object;

  { Base for all threads that talk TCP; reports progress to the UI }
  TNetThread = class(TThread)
  private
    FTopMap: TStringList;
    FLastTick: QWord;
    procedure DoTransfer;
    procedure DoLog;
  protected
    FSock: TSock;
    FKind: TTransferKind;
    FState: TTransferState;
    FPeerName, FPeerIP: string;
    FTitle, FCurFile, FMsg, FLogMsg: string;
    FDone, FTotal: Int64;
    FFileCount: Integer;
    FDestRoot: string;
    FOnTransfer: TTransferEvent;
    FOnLog: TLogEvent;
    FSerial: PtrUInt;
    FGroup: string;
    FGroupFiles: Integer;
    FGroupBytes: Int64;
    FGroupEnded: Boolean;
    procedure Log(const S: string);
    procedure Report(Force: Boolean = False);
    procedure SetState(AState: TTransferState; const AMsg: string = '');
    procedure ConnectTo(const Host: string; Port: Integer);
    procedure SendHeader(Cmd: Byte; const MyName: string);
    procedure SendItems(const Items: TSendItems);
    function RecvItems: Integer;
    function SafeTarget(const RelPath: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Cancel;
    function Info: TTransferInfo;
    { unique per thread; unlike the object address it is never reused }
    property Serial: PtrUInt read FSerial;
    property Kind: TTransferKind read FKind;
    property State: TTransferState read FState;
    property PeerName: string read FPeerName;
    property PeerIP: string read FPeerIP;
    property Title: string read FTitle;
    property CurFile: string read FCurFile;
    property Msg: string read FMsg;
    property Done: Int64 read FDone;
    property Total: Int64 read FTotal;
    property FileCount: Integer read FFileCount;
    property OnTransfer: TTransferEvent read FOnTransfer write FOnTransfer;
    property OnLog: TLogEvent read FOnLog write FOnLog;
  end;

  { Pushes local files/folders to another machine }
  TSendThread = class(TNetThread)
  private
    FPort: Integer;
    FMyName: string;
    FItems: TSendItems;
  protected
    procedure Execute; override;
  public
    constructor Create(const AHost, APeerName: string; APort: Integer;
      const AMyName: string; const AItems: TSendItems);
  end;

  { Downloads shared files/folders from another machine }
  TDownloadThread = class(TNetThread)
  private
    FPort: Integer;
    FMyName: string;
    FPaths: TStringArray;
  protected
    procedure Execute; override;
  public
    constructor Create(const AHost, APeerName: string; APort: Integer;
      const AMyName: string; const APaths: TStringArray; const ADestDir: string);
  end;

  TBrowseThread = class;
  TBrowseEvent = procedure(B: TBrowseThread) of object;

  { Lists one folder of another machine's shares }
  TBrowseThread = class(TThread)
  private
    FHost, FMyName, FPath: string;
    FPort: Integer;
    FTag: Integer;
    FEntries: TRemoteEntries;
    FError: string;
    FOnDone: TBrowseEvent;
    procedure DoDone;
  protected
    procedure Execute; override;
  public
    constructor Create(const AHost: string; APort: Integer; const AMyName, APath: string; ATag: Integer);
    property Path: string read FPath;
    property Tag: Integer read FTag;
    property Entries: TRemoteEntries read FEntries;
    property Error: string read FError;
    property OnDone: TBrowseEvent read FOnDone write FOnDone;
  end;

  TListenThread = class;

  { Handles one incoming connection (push, list or get) }
  TServeThread = class(TNetThread)
  private
    FOwner: TListenThread;
    FAccepted: Boolean;
    FHttpSent, FHttpHead: Boolean;
    procedure DoAsk;
    procedure HandlePush;
    procedure HandleList;
    procedure HandleGet;
    { HTTP API (lanhttp.inc) }
    procedure HandleHttp(const First: string);
    procedure HttpReadHead(const First: string; var R: THttpReq);
    procedure HttpSend(Code: Integer; const ContentType, Body: string; const Extra: string = '');
    procedure HttpError(Code: Integer; const AMsg: string);
    procedure HttpInfo;
    procedure HttpList(const R: THttpReq);
    procedure HttpTree(const R: THttpReq);
    procedure HttpFile(const R: THttpReq);
    procedure HttpPushBegin(const R: THttpReq);
    procedure HttpPushFile(const R: THttpReq);
    procedure HttpPushEnd(const R: THttpReq);
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TListenThread; ASock: TSock; const APeerIP: string);
  end;

  { Accepts incoming TCP connections }
  TListenThread = class(TThread)
  private
    FPort: Integer;
    FSock: TSock;
    FOnLog: TLogEvent;
    FOnAsk: TAskEvent;
    FOnTransfer: TTransferEvent;
    FDownloadDir: string;
    FAutoAccept: Boolean;
    FShares: TShareList;
    FLock: TRTLCriticalSection;
    FSessions: TList;
    FMyName, FMyID, FMyIcon, FThemeCss, FThemesJson: string;
    FThemeCssFunc: TThemeCssFunc;
    function GetDownloadDir: string;
    function GetIdent(AIndex: Integer): string;
    procedure SetIdent(AIndex: Integer; const AValue: string);
    procedure SetDownloadDir(const AValue: string);
  protected
    procedure Execute; override;
  public
    constructor Create(APort: Integer; AShares: TShareList);
    destructor Destroy; override;
    procedure StopListening;
    { HTTP upload sessions (thread-safe) }
    function NewSession(const APeerName, APeerIP: string; AFiles: Integer; ABytes: Int64): TPushSession;
    function FindSession(const AToken: string): TPushSession;
    procedure Lock;
    procedure Unlock;
    property Shares: TShareList read FShares;
    { identity shown to others (read by serving threads, so behind the lock) }
    property MyName: string index 0 read GetIdent write SetIdent;
    property MyID: string index 1 read GetIdent write SetIdent;
    property MyIcon: string index 2 read GetIdent write SetIdent;
    { colours of the app theme as CSS, served as /theme.css to browsers }
    property ThemeCss: string index 3 read GetIdent write SetIdent;
    { list of themes (JSON) and CSS per theme name, for the web theme picker }
    property ThemesJson: string index 4 read GetIdent write SetIdent;
    property ThemeCssFunc: TThemeCssFunc read FThemeCssFunc write FThemeCssFunc;
    property Port: Integer read FPort;
    property DownloadDir: string read GetDownloadDir write SetDownloadDir;
    property AutoAccept: Boolean read FAutoAccept write FAutoAccept;
    property OnLog: TLogEvent read FOnLog write FOnLog;
    property OnAsk: TAskEvent read FOnAsk write FOnAsk;
    property OnTransfer: TTransferEvent read FOnTransfer write FOnTransfer;
  end;

  { Broadcasts our presence and listens for other peers }
  TDiscoveryThread = class(TThread)
  private
    FLock: TRTLCriticalSection;
    FSock: TSock;
    FID, FName, FIcon: string;
    FTcpPort: Integer;
    FTargets: TStringList;   // known peer addresses: announced to by unicast
    FSeen: TStringList;      // peer IDs we already answered
    FPeerID, FPeerName, FPeerIP, FPeerOS, FPeerCaps, FPeerIcon: string;
    FPeerPort: Integer;
    FOnPeer: TPeerEvent;
    procedure DoPeer;
    function Packet: string;
    procedure SendPacket(const Host, Msg: string);
    procedure Broadcast;
    procedure ScanSubnets;
  protected
    procedure Execute; override;
  public
    constructor Create(const AID, AName, AIcon: string; ATcpPort: Integer);
    destructor Destroy; override;
    procedure StopDiscovery;
    procedure AnnounceNow;
    { change the name/icon others see (thread-safe) }
    procedure SetIdentity(const AName, AIcon: string);
    { remember an address to announce to directly (thread-safe) }
    procedure AddTarget(const IP: string);
    property OnPeer: TPeerEvent read FOnPeer write FOnPeer;
  end;

function GetLocalIPs: TStringArray;
function GetPrimaryIP: string;
function GetBroadcastAddrs: TStringArray;
function GetMyHostName: string;
function GetOSName: string;
function FormatBytes(B: Int64): string;
function SafeTargetIn(const Root, RelPath: string; TopMap: TStringList): string;
function UrlEncode(const S: string): string;
function JoinVPath(const A, B: string): string;
function ParentVPath(const P: string): string;
function ListLocalDir(const Dir: string): TRemoteEntries;
procedure BuildSendItems(Paths: TStrings; out Items: TSendItems;
  out FileCount: Integer; out TotalBytes: Int64);

implementation

uses
  {$IFDEF UNIX} BaseUnix, Unix, UnixType, ctypes, {$ENDIF}
  DateUtils, Math, resolve;

{$IFDEF WINDOWS}
{ The Windows "sockets" unit does not re-export these Winsock constants.
  They are declared here instead of using winsock2, whose types clash with
  the portable ones (in_addr, psockaddr, TSocket). }
const
  SOL_SOCKET          = $FFFF;
  SO_REUSEADDR        = $0004;
  SO_BROADCAST        = $0020;
  SO_SNDTIMEO         = $1005;
  SO_RCVTIMEO         = $1006;
  SO_EXCLUSIVEADDRUSE = LongInt(not SO_REUSEADDR);

type
  PWinHostEnt = ^TWinHostEnt;
  TWinHostEnt = record
    h_name: PChar;
    h_aliases: ^PChar;
    h_addrtype: Smallint;
    h_length: Smallint;
    h_addr_list: ^PChar;
  end;

function win_gethostname(name: PChar; len: LongInt): LongInt; stdcall; external 'ws2_32.dll' name 'gethostname';
function win_gethostbyname(name: PChar): PWinHostEnt; stdcall; external 'ws2_32.dll' name 'gethostbyname';
{$ENDIF}

{$IFDEF UNIX}
{ getifaddrs() from the C library: same struct layout on Linux, macOS and BSD }
{$PACKRECORDS C}
type
  PIfAddrs = ^TIfAddrs;
  TIfAddrs = record
    ifa_next: PIfAddrs;
    ifa_name: PChar;
    ifa_flags: cuint;
    ifa_addr: psockaddr;
    ifa_netmask: psockaddr;
    ifa_broadaddr: psockaddr;
    ifa_data: Pointer;
  end;
{$PACKRECORDS DEFAULT}

function getifaddrs(var ifap: PIfAddrs): cint; cdecl; external 'c' name 'getifaddrs';
procedure freeifaddrs(ifa: PIfAddrs); cdecl; external 'c' name 'freeifaddrs';
{$ENDIF}

{ ---------- helpers ---------- }

function FormatBytes(B: Int64): string;
begin
  if B < 1024 then Result := Format('%d B', [B])
  else if B < 1024 * 1024 then Result := Format('%.1f KB', [B / 1024])
  else if B < Int64(1024) * 1024 * 1024 then Result := Format('%.1f MB', [B / (1024 * 1024)])
  else Result := Format('%.2f GB', [B / (1024 * 1024 * 1024)]);
end;

function JoinVPath(const A, B: string): string;
begin
  if A = '' then Result := B else Result := A + '/' + B;
end;

function ParentVPath(const P: string): string;
var
  I: Integer;
begin
  I := LastDelimiter('/', P);
  if I = 0 then Result := '' else Result := Copy(P, 1, I - 1);
end;

procedure AddStr(var Arr: TStringArray; const S: string);
var
  I: Integer;
begin
  for I := 0 to High(Arr) do
    if Arr[I] = S then Exit;
  SetLength(Arr, Length(Arr) + 1);
  Arr[High(Arr)] := S;
end;

{ Fills the IPv4 addresses of this machine and the matching broadcast addresses }
procedure CollectNets(out IPs, Bcasts: TStringArray);
{$IFDEF UNIX}
var
  List, P: PIfAddrs;
  Ip, Mask: LongWord;
  S: string;
begin
  IPs := nil;
  Bcasts := nil;
  if getifaddrs(List) <> 0 then Exit;
  try
    P := List;
    while P <> nil do
    begin
      if (P^.ifa_addr <> nil) and (P^.ifa_addr^.sa_family = AF_INET) then
      begin
        S := NetAddrToStr(psockaddr_in(P^.ifa_addr)^.sin_addr);
        if Copy(S, 1, 4) <> '127.' then
        begin
          AddStr(IPs, S);
          Ip := NToBE(psockaddr_in(P^.ifa_addr)^.sin_addr.s_addr);   // host order
          if P^.ifa_netmask <> nil then
            Mask := NToBE(psockaddr_in(P^.ifa_netmask)^.sin_addr.s_addr)
          else
            Mask := $FFFFFF00;
          Ip := BEtoN(Ip or not Mask);
          AddStr(Bcasts, NetAddrToStr(in_addr(Ip)));
        end;
      end;
      P := P^.ifa_next;
    end;
  finally
    freeifaddrs(List);
  end;
end;
{$ELSE}
var
  HostName: array[0..255] of AnsiChar;
  He: PWinHostEnt;
  P: ^PChar;
  A: in_addr;
  S: string;
begin
  IPs := nil;
  Bcasts := nil;
  if win_gethostname(@HostName[0], SizeOf(HostName)) <> 0 then Exit;
  He := win_gethostbyname(@HostName[0]);
  if He = nil then Exit;
  P := He^.h_addr_list;
  while (P <> nil) and (P^ <> nil) do
  begin
    Move(P^^, A, 4);
    S := NetAddrToStr(A);
    if Copy(S, 1, 4) <> '127.' then
    begin
      AddStr(IPs, S);
      // netmask is not available here: assume the common /24
      AddStr(Bcasts, Copy(S, 1, LastDelimiter('.', S)) + '255');
    end;
    Inc(P);
  end;
end;
{$ENDIF}

function GetLocalIPs: TStringArray;
var
  B: TStringArray;
begin
  CollectNets(Result, B);
end;

{ The local address used for the default route. A UDP "connect" sends no
  packet; it only makes the OS pick the outgoing interface. Skips virtual
  adapters (VirtualBox, Hyper-V...) that GetLocalIPs may list first. }
function GetPrimaryIP: string;
var
  S: TSock;
  Addr, Local: TInetSockAddr;
  Len: TSockLen;
begin
  Result := '';
  S := fpsocket(AF_INET, SOCK_DGRAM, 0);
  if S = INVALID_SOCK then Exit;
  try
    FillChar(Addr, SizeOf(Addr), 0);
    Addr.sin_family := AF_INET;
    Addr.sin_port := htons(53);
    Addr.sin_addr := StrToNetAddr('8.8.8.8');
    if fpconnect(S, psockaddr(@Addr), SizeOf(Addr)) <> 0 then Exit;
    Len := SizeOf(Local);
    FillChar(Local, SizeOf(Local), 0);
    if fpgetsockname(S, psockaddr(@Local), @Len) <> 0 then Exit;
    Result := NetAddrToStr(Local.sin_addr);
    if (Result = '0.0.0.0') or (Copy(Result, 1, 4) = '127.') then Result := '';
  finally
    CloseSocket(S);
  end;
end;

function GetBroadcastAddrs: TStringArray;
var
  I: TStringArray;
begin
  CollectNets(I, Result);
end;

function GetMyHostName: string;
begin
  {$IFDEF UNIX}
  Result := Unix.GetHostName;
  if Pos('.', Result) > 0 then Result := Copy(Result, 1, Pos('.', Result) - 1);
  {$ELSE}
  Result := GetEnvironmentVariable('COMPUTERNAME');
  {$ENDIF}
  if Result = '' then Result := 'PC';
end;

function GetOSName: string;
begin
  {$IF defined(ANDROID)}
  Result := 'android';
  {$ELSEIF defined(WINDOWS)}
  Result := 'windows';
  {$ELSEIF defined(DARWIN)}
  Result := 'macos';
  {$ELSEIF defined(LINUX)}
  Result := 'linux';
  {$ELSEIF defined(BSD)}
  Result := 'bsd';
  {$ELSE}
  Result := 'unknown';
  {$ENDIF}
end;

procedure SetTimeout(S: TSock; Ms: LongWord);
{$IFDEF UNIX}
var
  TV: timeval;
begin
  TV.tv_sec := Ms div 1000;
  TV.tv_usec := (Ms mod 1000) * 1000;
  fpsetsockopt(S, SOL_SOCKET, SO_RCVTIMEO, @TV, SizeOf(TV));
  fpsetsockopt(S, SOL_SOCKET, SO_SNDTIMEO, @TV, SizeOf(TV));
end;
{$ELSE}
begin
  fpsetsockopt(S, SOL_SOCKET, SO_RCVTIMEO, @Ms, SizeOf(Ms));
  fpsetsockopt(S, SOL_SOCKET, SO_SNDTIMEO, @Ms, SizeOf(Ms));
end;
{$ENDIF}

procedure SetOpt(S: TSock; Opt: LongInt);
var
  One: LongInt;
begin
  One := 1;
  fpsetsockopt(S, SOL_SOCKET, Opt, @One, SizeOf(One));
end;

function SendFlags: LongInt; inline;
begin
  {$IF DECLARED(MSG_NOSIGNAL)}
  Result := MSG_NOSIGNAL;   // Linux/BSD: no SIGPIPE when the peer disconnects
  {$ELSE}
  Result := 0;
  {$ENDIF}
end;

procedure SockSendAll(S: TSock; const Buf; Len: Integer);
var
  P: PByte;
  N: Integer;
begin
  P := @Buf;
  while Len > 0 do
  begin
    N := fpsend(S, P, Len, SendFlags);
    if N <= 0 then
      raise ENetError.CreateFmt('การเชื่อมต่อขาดระหว่างส่ง (error %d)', [socketerror]);
    Inc(P, N);
    Dec(Len, N);
  end;
end;

procedure SockRecvAll(S: TSock; var Buf; Len: Integer);
var
  P: PByte;
  N: Integer;
begin
  P := @Buf;
  while Len > 0 do
  begin
    N := fprecv(S, P, Len, 0);
    if N = 0 then
      raise ENetError.Create('อีกฝั่งปิดการเชื่อมต่อ');
    if N < 0 then
      raise ENetError.CreateFmt('การเชื่อมต่อขาดระหว่างรับ (error %d)', [socketerror]);
    Inc(P, N);
    Dec(Len, N);
  end;
end;

procedure SendByte(S: TSock; B: Byte);
begin
  SockSendAll(S, B, 1);
end;

function RecvByte(S: TSock): Byte;
begin
  SockRecvAll(S, Result, 1);
end;

procedure SendInt32(S: TSock; V: LongInt);
begin
  V := NtoLE(V);
  SockSendAll(S, V, 4);
end;

function RecvInt32(S: TSock): LongInt;
begin
  SockRecvAll(S, Result, 4);
  Result := LEtoN(Result);
end;

procedure SendInt64(S: TSock; V: Int64);
begin
  V := NtoLE(V);
  SockSendAll(S, V, 8);
end;

function RecvInt64(S: TSock): Int64;
begin
  SockRecvAll(S, Result, 8);
  Result := LEtoN(Result);
end;

procedure SendStr(S: TSock; const Str: string);
var
  L: Word;
  U: UTF8String;
begin
  U := Str;   // wire format is always UTF-8
  if Length(U) > 65535 then raise ENetError.Create('Path too long');
  L := NtoLE(Word(Length(U)));
  SockSendAll(S, L, 2);
  if U <> '' then SockSendAll(S, U[1], Length(U));
end;

function RecvStr(S: TSock): string;
var
  L: Word;
  U: UTF8String;
begin
  SockRecvAll(S, L, 2);
  L := LEtoN(L);
  SetLength(U, L);
  if L > 0 then SockRecvAll(S, U[1], L);
  Result := U;
end;

function MakeAddr(const Host: string; Port: Integer): TInetSockAddr;
var
  A: in_addr;
  R: THostResolver;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.sin_family := AF_INET;
  Result.sin_port := htons(Port);
  if TryStrToHostAddr(Host, A) then
    Result.sin_addr := StrToNetAddr(Host)
  else
  begin
    R := THostResolver.Create(nil);
    try
      if not R.NameLookup(Host) then
        raise ENetError.CreateFmt('หาเครื่อง "%s" ไม่เจอ', [Host]);
      Result.sin_addr := R.NetHostAddress;
    finally
      R.Free;
    end;
  end;
end;

procedure AddItem(var Items: TSendItems; AKind: Byte; const ALocal, ARel: string; ASize: Int64);
begin
  SetLength(Items, Length(Items) + 1);
  with Items[High(Items)] do
  begin
    Kind := AKind;
    LocalPath := ALocal;
    RelPath := ARel;
    Size := ASize;
  end;
end;

procedure ScanDir(const Dir, Rel: string; var Items: TSendItems;
  var FileCount: Integer; var TotalBytes: Int64);
var
  SR: TSearchRec;
begin
  AddItem(Items, KIND_DIR, Dir, Rel, 0);
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + AllFilesMask, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      if (SR.Attr and faDirectory) <> 0 then
      begin
        // do not follow symlinked folders (could loop forever)
        if (SR.Attr and faSymLink) = 0 then
          ScanDir(IncludeTrailingPathDelimiter(Dir) + SR.Name, Rel + '/' + SR.Name,
            Items, FileCount, TotalBytes);
      end
      else
      begin
        AddItem(Items, KIND_FILE, IncludeTrailingPathDelimiter(Dir) + SR.Name,
          Rel + '/' + SR.Name, SR.Size);
        Inc(FileCount);
        Inc(TotalBytes, SR.Size);
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

procedure AddPathItems(const P: string; var Items: TSendItems;
  var FileCount: Integer; var TotalBytes: Int64);
var
  SR: TSearchRec;
  Q: string;
begin
  Q := ExcludeTrailingPathDelimiter(P);
  if DirectoryExists(Q) then
    ScanDir(Q, ExtractFileName(Q), Items, FileCount, TotalBytes)
  else if FindFirst(Q, faAnyFile, SR) = 0 then
  begin
    AddItem(Items, KIND_FILE, Q, ExtractFileName(Q), SR.Size);
    Inc(FileCount);
    Inc(TotalBytes, SR.Size);
    FindClose(SR);
  end;
end;

procedure BuildSendItems(Paths: TStrings; out Items: TSendItems;
  out FileCount: Integer; out TotalBytes: Int64);
var
  I: Integer;
begin
  Items := nil;
  FileCount := 0;
  TotalBytes := 0;
  for I := 0 to Paths.Count - 1 do
    AddPathItems(Paths[I], Items, FileCount, TotalBytes);
end;

function IsHiddenEntry(const SR: TSearchRec): Boolean;
begin
  Result := (SR.Name <> '') and (SR.Name[1] = '.');
  {$IFDEF WINDOWS}
  Result := Result or ((SR.Attr and (faHidden or faSysFile)) <> 0);
  {$ENDIF}
end;

function ListLocalDir(const Dir: string): TRemoteEntries;
var
  SR: TSearchRec;
  N: Integer;
begin
  Result := nil;
  N := 0;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + AllFilesMask, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') or IsHiddenEntry(SR) then Continue;
      if N >= Length(Result) then SetLength(Result, N * 2 + 16);
      Result[N].Name := SR.Name;
      Result[N].IsDir := (SR.Attr and faDirectory) <> 0;
      if Result[N].IsDir then Result[N].Size := 0 else Result[N].Size := SR.Size;
      Result[N].Modified := SR.TimeStamp;
      Result[N].LocalPath := IncludeTrailingPathDelimiter(Dir) + SR.Name;
      Inc(N);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  SetLength(Result, N);
end;

function UniqueName(const Dir, Name: string): string;
var
  N: Integer;
  Base, Ext: string;
begin
  Result := Name;
  if not FileExists(Dir + Result) and not DirectoryExists(Dir + Result) then Exit;
  Ext := ExtractFileExt(Name);
  Base := Copy(Name, 1, Length(Name) - Length(Ext));
  N := 1;
  repeat
    Result := Format('%s (%d)%s', [Base, N, Ext]);
    Inc(N);
  until not FileExists(Dir + Result) and not DirectoryExists(Dir + Result);
end;

{ Makes one file/folder name valid on this OS. Names coming from Linux/macOS
  may contain characters Windows does not allow (e.g. "a:b?.txt"). }
function LocalName(const Part: string): string;
{$IFDEF WINDOWS}
var
  I: Integer;
begin
  Result := Part;
  for I := 1 to Length(Result) do
    if (Result[I] < ' ') or (Pos(Result[I], '<>:"|?*') > 0) then
      Result[I] := '_';
  // Windows silently drops trailing dots and spaces
  while (Result <> '') and (Result[Length(Result)] in ['.', ' ']) do
    Delete(Result, Length(Result), 1);
  if Result = '' then Result := '_';
end;
{$ELSE}
begin
  Result := Part;
end;
{$ENDIF}

{ Splits a network path and refuses anything that could leave its root }
function SplitSafe(const RelPath: string): TStringArray;
var
  I: Integer;
begin
  Result := StringReplace(RelPath, '\', '/', [rfReplaceAll]).Split(['/']);
  if Length(Result) = 0 then raise ENetError.Create('Empty path');
  for I := 0 to High(Result) do
    if (Result[I] = '') or (Result[I] = '.') or (Result[I] = '..') then
      raise ENetError.CreateFmt('Unsafe path rejected: %s', [RelPath]);
end;

{ Converts a relative path from the network into a safe local path inside
  Root. Rejects '..'; characters illegal on this OS become '_'.
  The top level name is renamed once per transfer (TopMap) if it already exists. }
function SafeTargetIn(const Root, RelPath: string; TopMap: TStringList): string;
var
  Parts: TStringArray;
  I: Integer;
  Top, R: string;
begin
  Parts := SplitSafe(RelPath);
  for I := 0 to High(Parts) do
    Parts[I] := LocalName(Parts[I]);
  R := IncludeTrailingPathDelimiter(Root);
  Top := TopMap.Values[Parts[0]];
  if Top = '' then
  begin
    Top := UniqueName(R, Parts[0]);
    TopMap.Values[Parts[0]] := Top;
  end;
  Result := R + Top;
  for I := 1 to High(Parts) do
    Result := Result + PathDelim + Parts[I];
end;

{ ---------- TPushSession ---------- }

constructor TPushSession.Create;
begin
  TopMap := TStringList.Create;
  LastUsed := GetTickCount64;
end;

destructor TPushSession.Destroy;
begin
  TopMap.Free;
  inherited Destroy;
end;

{ ---------- TShareList ---------- }

constructor TShareList.Create;
begin
  InitCriticalSection(FLock);
  FPaths := TStringList.Create;
end;

destructor TShareList.Destroy;
begin
  FPaths.Free;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

{ Display name of a share: folder/file name, made unique with " (2)" ... }
function TShareList.NameOf(Index: Integer): string;
var
  I, N: Integer;

  function BaseName(const P: string): string;
  begin
    Result := ExtractFileName(ExcludeTrailingPathDelimiter(P));
    if Result = '' then   // drive root such as C:\
      Result := 'Drive ' + StringReplace(StringReplace(P, ':', '', []), PathDelim, '', [rfReplaceAll]);
    Result := LocalName(Result);
  end;

begin
  Result := BaseName(FPaths[Index]);
  N := 1;
  for I := 0 to Index - 1 do
    if SameText(BaseName(FPaths[I]), BaseName(FPaths[Index])) then Inc(N);
  if N > 1 then Result := Format('%s (%d)', [Result, N]);
end;

procedure TShareList.Add(const P: string);
begin
  EnterCriticalSection(FLock);
  try
    if FPaths.IndexOf(P) < 0 then FPaths.Add(P);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TShareList.Remove(const P: string);
var
  I: Integer;
begin
  EnterCriticalSection(FLock);
  try
    I := FPaths.IndexOf(P);
    if I >= 0 then FPaths.Delete(I);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TShareList.Count: Integer;
begin
  EnterCriticalSection(FLock);
  try
    Result := FPaths.Count;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TShareList.Paths: TStringArray;
var
  I: Integer;
begin
  EnterCriticalSection(FLock);
  try
    SetLength(Result, FPaths.Count);
    for I := 0 to FPaths.Count - 1 do
      Result[I] := FPaths[I];
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TShareList.RootEntries: TRemoteEntries;
var
  I: Integer;
  SR: TSearchRec;
  P: string;
begin
  EnterCriticalSection(FLock);
  try
    SetLength(Result, FPaths.Count);
    for I := 0 to FPaths.Count - 1 do
    begin
      P := FPaths[I];
      Result[I].Name := NameOf(I);
      Result[I].LocalPath := P;
      Result[I].IsDir := DirectoryExists(P);
      Result[I].Size := 0;
      Result[I].Modified := 0;
      if FindFirst(ExcludeTrailingPathDelimiter(P), faAnyFile, SR) = 0 then
      begin
        if not Result[I].IsDir then Result[I].Size := SR.Size;
        Result[I].Modified := SR.TimeStamp;
        FindClose(SR);
      end;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TShareList.Resolve(const VPath: string; out Local: string): Boolean;
var
  Parts: TStringArray;
  I, J: Integer;
begin
  Result := False;
  Local := '';
  Parts := SplitSafe(VPath);
  EnterCriticalSection(FLock);
  try
    for I := 0 to FPaths.Count - 1 do
      if NameOf(I) = Parts[0] then
      begin
        Local := ExcludeTrailingPathDelimiter(FPaths[I]);
        if (Length(Parts) > 1) and not DirectoryExists(Local) then Exit;  // a shared file has no children
        for J := 1 to High(Parts) do
          Local := Local + PathDelim + Parts[J];
        Result := FileExists(Local) or DirectoryExists(Local);
        Exit;
      end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

{ ---------- TNetThread ---------- }

var
  GSerial: LongInt = 0;

constructor TNetThread.Create;
begin
  inherited Create(True);
  FSerial := PtrUInt(InterLockedIncrement(GSerial));
  FreeOnTerminate := True;
  FSock := INVALID_SOCK;
  FTopMap := TStringList.Create;
  FState := tsConnecting;
end;

destructor TNetThread.Destroy;
begin
  FTopMap.Free;
  inherited Destroy;
end;

procedure TNetThread.Cancel;
begin
  Terminate;
  if FSock <> INVALID_SOCK then
    fpshutdown(FSock, SHUT_RDWR);
end;

function TNetThread.Info: TTransferInfo;
begin
  Result := Default(TTransferInfo);
  Result.Serial := FSerial;
  Result.Thread := Self;
  Result.Group := FGroup;
  Result.GroupFiles := FGroupFiles;
  Result.GroupBytes := FGroupBytes;
  Result.GroupEnded := FGroupEnded;
  Result.Kind := FKind;
  Result.State := FState;
  Result.PeerName := FPeerName;
  Result.PeerIP := FPeerIP;
  Result.Title := FTitle;
  Result.CurFile := FCurFile;
  Result.Msg := FMsg;
  Result.Done := FDone;
  Result.Total := FTotal;
end;

procedure TNetThread.DoTransfer;
begin
  if Assigned(FOnTransfer) then FOnTransfer(Info);
end;

procedure TNetThread.DoLog;
begin
  if Assigned(FOnLog) then FOnLog(Self, FLogMsg);
end;

procedure TNetThread.Log(const S: string);
begin
  FLogMsg := S;
  Synchronize(@DoLog);
end;

procedure TNetThread.Report(Force: Boolean);
begin
  if Force or (GetTickCount64 - FLastTick > 120) then
  begin
    FLastTick := GetTickCount64;
    Synchronize(@DoTransfer);
  end;
end;

procedure TNetThread.SetState(AState: TTransferState; const AMsg: string);
begin
  FState := AState;
  if AMsg <> '' then FMsg := AMsg;
  Report(True);
end;

procedure TNetThread.ConnectTo(const Host: string; Port: Integer);
var
  Addr: TInetSockAddr;
begin
  Addr := MakeAddr(Host, Port);
  FSock := fpsocket(AF_INET, SOCK_STREAM, 0);
  if FSock = INVALID_SOCK then raise ENetError.Create('Cannot create socket');
  {$IF DECLARED(SO_NOSIGPIPE)}
  SetOpt(FSock, SO_NOSIGPIPE);   // macOS
  {$ENDIF}
  if fpconnect(FSock, psockaddr(@Addr), SizeOf(Addr)) <> 0 then
    raise ENetError.CreateFmt('เชื่อมต่อ %s:%d ไม่ได้ (error %d)', [Host, Port, socketerror]);
end;

procedure TNetThread.SendHeader(Cmd: Byte; const MyName: string);
begin
  SockSendAll(FSock, PChar('LSHR')^, 4);
  SendByte(FSock, PROTO_VERSION);
  SendByte(FSock, Cmd);
  SendStr(FSock, MyName);
end;

procedure TNetThread.SendItems(const Items: TSendItems);
var
  I, N: Integer;
  FS: TFileStream;
  Buf: array of Byte;
begin
  SetLength(Buf, BUF_SIZE);
  for I := 0 to High(Items) do
  begin
    if Terminated then raise ENetError.Create('ยกเลิกแล้ว');
    case Items[I].Kind of
      KIND_DIR:
        begin
          SendByte(FSock, KIND_DIR);
          SendStr(FSock, Items[I].RelPath);
        end;
      KIND_FILE:
        begin
          FCurFile := Items[I].RelPath;
          FS := TFileStream.Create(Items[I].LocalPath, fmOpenRead or fmShareDenyNone);
          try
            SendByte(FSock, KIND_FILE);
            SendStr(FSock, Items[I].RelPath);
            SendInt64(FSock, FS.Size);   // real size, may differ from the scan
            repeat
              N := FS.Read(Buf[0], BUF_SIZE);
              if N > 0 then
              begin
                SockSendAll(FSock, Buf[0], N);
                Inc(FDone, N);
                Report;
              end;
              if Terminated then raise ENetError.Create('ยกเลิกแล้ว');
            until N <= 0;
          finally
            FS.Free;
          end;
        end;
    end;
  end;
  SendByte(FSock, KIND_END);
end;

function TNetThread.RecvItems: Integer;
var
  K: Byte;
  Rel, Target: string;
  Size, Left: Int64;
  FS: TFileStream;
  Buf: array of Byte;
  N: Integer;
begin
  Result := 0;
  ForceDirectories(FDestRoot);
  SetLength(Buf, BUF_SIZE);
  repeat
    if Terminated then raise ENetError.Create('ยกเลิกแล้ว');
    K := RecvByte(FSock);
    case K of
      KIND_END: Break;
      KIND_DIR:
        begin
          Rel := RecvStr(FSock);
          ForceDirectories(SafeTarget(Rel));
        end;
      KIND_FILE:
        begin
          Rel := RecvStr(FSock);
          Size := RecvInt64(FSock);
          FCurFile := Rel;
          Target := SafeTarget(Rel);
          ForceDirectories(ExtractFileDir(Target));
          FS := TFileStream.Create(Target, fmCreate);
          try
            Left := Size;
            while Left > 0 do
            begin
              if Left > BUF_SIZE then N := BUF_SIZE else N := Left;
              N := fprecv(FSock, @Buf[0], N, 0);
              if N <= 0 then raise ENetError.Create('การเชื่อมต่อขาด');
              FS.WriteBuffer(Buf[0], N);
              Dec(Left, N);
              Inc(FDone, N);
              Report;
            end;
          finally
            FS.Free;
          end;
          Inc(Result);
        end;
    else
      raise ENetError.CreateFmt('ข้อมูลผิดรูปแบบ (kind %d)', [K]);
    end;
  until False;
end;

{ Converts a relative path from the network into a safe local path inside
  FDestRoot. Rejects '..'; characters illegal on this OS become '_'.
  The top level name is renamed once per transfer if it already exists. }
function TNetThread.SafeTarget(const RelPath: string): string;
begin
  Result := SafeTargetIn(FDestRoot, RelPath, FTopMap);
end;

{ ---------- TSendThread ---------- }

constructor TSendThread.Create(const AHost, APeerName: string; APort: Integer;
  const AMyName: string; const AItems: TSendItems);
var
  I: Integer;
begin
  inherited Create;
  FKind := tkSend;
  FPeerIP := AHost;
  FPeerName := APeerName;
  FPort := APort;
  FMyName := AMyName;
  FItems := Copy(AItems);
  for I := 0 to High(FItems) do
    if FItems[I].Kind = KIND_FILE then
    begin
      Inc(FTotal, FItems[I].Size);
      Inc(FFileCount);
    end;
  if FFileCount = 1 then
    for I := 0 to High(FItems) do
      if FItems[I].Kind = KIND_FILE then FTitle := ExtractFileName(FItems[I].LocalPath);
  if FTitle = '' then FTitle := Format('%d ไฟล์', [FFileCount]);
end;

procedure TSendThread.Execute;
begin
  try
    SetState(tsConnecting, 'กำลังเชื่อมต่อ...');
    ConnectTo(FPeerIP, FPort);
    SendHeader(CMD_PUSH, FMyName);
    SendInt32(FSock, FFileCount);
    SendInt64(FSock, FTotal);
    SetState(tsWaiting, 'รอปลายทางกดยอมรับ...');
    if RecvByte(FSock) <> 1 then
    begin
      SetState(tsRejected, 'ปลายทางปฏิเสธ');
      Log(Format('%s ปฏิเสธการรับ %s', [FPeerName, FTitle]));
    end
    else
    begin
      SetTimeout(FSock, 60000);
      SetState(tsRunning, '');
      SendItems(FItems);
      if RecvByte(FSock) = 1 then
      begin
        SetState(tsDone, 'ส่งสำเร็จ');
        Log(Format('ส่ง %s (%s) ไปยัง %s สำเร็จ', [FTitle, FormatBytes(FTotal), FPeerName]));
      end;
    end;
  except
    on E: Exception do
    begin
      FState := tsFailed;
      FMsg := E.Message;
      Log('ส่งไม่สำเร็จ: ' + E.Message);
    end;
  end;
  if FSock <> INVALID_SOCK then CloseSocket(FSock);
  FSock := INVALID_SOCK;
  Report(True);
end;

{ ---------- TDownloadThread ---------- }

constructor TDownloadThread.Create(const AHost, APeerName: string; APort: Integer;
  const AMyName: string; const APaths: TStringArray; const ADestDir: string);
var
  P: string;
begin
  inherited Create;
  FKind := tkDownload;
  FPeerIP := AHost;
  FPeerName := APeerName;
  FPort := APort;
  FMyName := AMyName;
  FPaths := Copy(APaths);
  FDestRoot := ADestDir;
  if Length(FPaths) = 1 then
  begin
    P := FPaths[0];
    FTitle := Copy(P, LastDelimiter('/', P) + 1, MaxInt);
  end
  else
    FTitle := Format('%d รายการ', [Length(FPaths)]);
end;

procedure TDownloadThread.Execute;
var
  I, Files: Integer;
begin
  try
    SetState(tsConnecting, 'กำลังเชื่อมต่อ...');
    ConnectTo(FPeerIP, FPort);
    SetTimeout(FSock, 60000);
    SendHeader(CMD_GET, FMyName);
    SendInt32(FSock, Length(FPaths));
    for I := 0 to High(FPaths) do
      SendStr(FSock, FPaths[I]);
    if RecvByte(FSock) <> 1 then
      raise ENetError.Create(RecvStr(FSock));
    FFileCount := RecvInt32(FSock);
    FTotal := RecvInt64(FSock);
    SetState(tsRunning, '');
    Files := RecvItems;
    SendByte(FSock, 1);
    SetState(tsDone, 'ดาวน์โหลดสำเร็จ');
    Log(Format('ดาวน์โหลด %s (%d ไฟล์, %s) จาก %s สำเร็จ',
      [FTitle, Files, FormatBytes(FDone), FPeerName]));
  except
    on E: Exception do
    begin
      FState := tsFailed;
      FMsg := E.Message;
      Log('ดาวน์โหลดไม่สำเร็จ: ' + E.Message);
    end;
  end;
  if FSock <> INVALID_SOCK then CloseSocket(FSock);
  FSock := INVALID_SOCK;
  Report(True);
end;

{ ---------- TBrowseThread ---------- }

constructor TBrowseThread.Create(const AHost: string; APort: Integer;
  const AMyName, APath: string; ATag: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FHost := AHost;
  FPort := APort;
  FMyName := AMyName;
  FPath := APath;
  FTag := ATag;
end;

procedure TBrowseThread.DoDone;
begin
  if Assigned(FOnDone) then FOnDone(Self);
end;

procedure TBrowseThread.Execute;
var
  S: TSock;
  Addr: TInetSockAddr;
  I, N: Integer;
begin
  S := INVALID_SOCK;
  try
    Addr := MakeAddr(FHost, FPort);
    S := fpsocket(AF_INET, SOCK_STREAM, 0);
    if S = INVALID_SOCK then raise ENetError.Create('Cannot create socket');
    {$IF DECLARED(SO_NOSIGPIPE)}
    SetOpt(S, SO_NOSIGPIPE);
    {$ENDIF}
    if fpconnect(S, psockaddr(@Addr), SizeOf(Addr)) <> 0 then
      raise ENetError.CreateFmt('เชื่อมต่อ %s ไม่ได้ (error %d)', [FHost, socketerror]);
    SetTimeout(S, 15000);
    SockSendAll(S, PChar('LSHR')^, 4);
    SendByte(S, PROTO_VERSION);
    SendByte(S, CMD_LIST);
    SendStr(S, FMyName);
    SendStr(S, FPath);
    if RecvByte(S) <> 1 then
      raise ENetError.Create(RecvStr(S));
    N := RecvInt32(S);
    if (N < 0) or (N > 1000000) then raise ENetError.Create('ข้อมูลผิดรูปแบบ');
    SetLength(FEntries, N);
    for I := 0 to N - 1 do
    begin
      FEntries[I].Name := RecvStr(S);
      FEntries[I].IsDir := RecvByte(S) = 1;
      FEntries[I].Size := RecvInt64(S);
      FEntries[I].Modified := UnixToDateTime(RecvInt64(S), False);
    end;
  except
    on E: Exception do
      FError := E.Message;
  end;
  if S <> INVALID_SOCK then CloseSocket(S);
  Synchronize(@DoDone);
end;

{ ---------- TServeThread ---------- }

constructor TServeThread.Create(AOwner: TListenThread; ASock: TSock; const APeerIP: string);
begin
  inherited Create;
  FOwner := AOwner;
  FSock := ASock;
  FPeerIP := APeerIP;
  FOnTransfer := AOwner.OnTransfer;
  FOnLog := AOwner.OnLog;
end;

procedure TServeThread.DoAsk;
begin
  if FOwner.AutoAccept then
    FAccepted := True
  else if Assigned(FOwner.OnAsk) then
    FAccepted := FOwner.OnAsk(Self, FPeerName, FPeerIP, FFileCount, FTotal)
  else
    FAccepted := False;
end;

procedure TServeThread.HandlePush;
var
  Files: Integer;
begin
  FKind := tkReceive;
  FFileCount := RecvInt32(FSock);
  FTotal := RecvInt64(FSock);
  FTitle := Format('%d ไฟล์', [FFileCount]);
  Synchronize(@DoAsk);
  if not FAccepted then
  begin
    SendByte(FSock, 0);
    Log(Format('ปฏิเสธไฟล์จาก %s (%s)', [FPeerName, FPeerIP]));
    Exit;
  end;
  SendByte(FSock, 1);
  FDestRoot := FOwner.DownloadDir;
  SetTimeout(FSock, 60000);
  SetState(tsRunning, '');
  try
    Files := RecvItems;
    SendByte(FSock, 1);
    SetState(tsDone, 'รับสำเร็จ');
    Log(Format('รับ %d ไฟล์ (%s) จาก %s สำเร็จ', [Files, FormatBytes(FDone), FPeerName]));
  except
    on E: Exception do
    begin
      SetState(tsFailed, E.Message);
      raise;
    end;
  end;
end;

procedure TServeThread.HandleList;
var
  Path, Local: string;
  E: TRemoteEntries;
  I: Integer;
begin
  Path := RecvStr(FSock);
  if Path = '' then
    E := FOwner.Shares.RootEntries
  else if FOwner.Shares.Resolve(Path, Local) and DirectoryExists(Local) then
    E := ListLocalDir(Local)
  else
  begin
    SendByte(FSock, 0);
    SendStr(FSock, 'ไม่พบโฟลเดอร์นี้ หรือเลิกแชร์แล้ว');
    Exit;
  end;
  SendByte(FSock, 1);
  SendInt32(FSock, Length(E));
  for I := 0 to High(E) do
  begin
    SendStr(FSock, E[I].Name);
    SendByte(FSock, Ord(E[I].IsDir));
    SendInt64(FSock, E[I].Size);
    if E[I].Modified > 0 then
      SendInt64(FSock, DateTimeToUnix(E[I].Modified, False))
    else
      SendInt64(FSock, 0);
  end;
end;

procedure TServeThread.HandleGet;
var
  I, N: Integer;
  Paths: TStringArray;
  Local: string;
  Items: TSendItems;
begin
  FKind := tkServe;
  N := RecvInt32(FSock);
  if (N <= 0) or (N > 10000) then raise ENetError.Create('ข้อมูลผิดรูปแบบ');
  SetLength(Paths, N);
  for I := 0 to N - 1 do
    Paths[I] := RecvStr(FSock);
  Items := nil;
  for I := 0 to N - 1 do
  begin
    if not FOwner.Shares.Resolve(Paths[I], Local) then
    begin
      SendByte(FSock, 0);
      SendStr(FSock, 'ไม่พบ "' + Paths[I] + '" หรือเลิกแชร์แล้ว');
      Exit;
    end;
    AddPathItems(Local, Items, FFileCount, FTotal);
  end;
  if N = 1 then FTitle := Copy(Paths[0], LastDelimiter('/', Paths[0]) + 1, MaxInt)
  else FTitle := Format('%d รายการ', [N]);
  SendByte(FSock, 1);
  SendInt32(FSock, FFileCount);
  SendInt64(FSock, FTotal);
  SetTimeout(FSock, 60000);
  SetState(tsRunning, '');
  try
    SendItems(Items);
    if RecvByte(FSock) = 1 then
    begin
      SetState(tsDone, 'ส่งสำเร็จ');
      Log(Format('%s ดาวน์โหลด %s (%s) จากเครื่องนี้', [FPeerName, FTitle, FormatBytes(FTotal)]));
    end;
  except
    on E: Exception do
    begin
      SetState(tsFailed, E.Message);
      raise;
    end;
  end;
end;

procedure TServeThread.Execute;
var
  Magic: array[0..3] of AnsiChar;
  Ver, Cmd: Byte;
begin
  try
    try
      {$IF DECLARED(SO_NOSIGPIPE)}
      SetOpt(FSock, SO_NOSIGPIPE);
      {$ENDIF}
      SetTimeout(FSock, 30000);
      SockRecvAll(FSock, Magic, 4);
      if Magic <> 'LSHR' then
      begin
        if (Magic = 'GET ') or (Magic = 'HEAD') or (Magic = 'POST') or (Magic = 'PUT ')
          or (Magic = 'OPTI') then
          HandleHttp(Magic)
        else
          raise ENetError.Create('Unknown protocol');
        Exit;
      end;
      Ver := RecvByte(FSock);
      if Ver <> PROTO_VERSION then
        raise ENetError.CreateFmt('เครื่อง %s ใช้โปรแกรมคนละเวอร์ชัน (v%d)', [FPeerIP, Ver]);
      Cmd := RecvByte(FSock);
      FPeerName := RecvStr(FSock);
      if FPeerName = '' then FPeerName := FPeerIP;   // sender set no name
      case Cmd of
        CMD_PUSH: HandlePush;
        CMD_LIST: HandleList;
        CMD_GET:  HandleGet;
      else
        raise ENetError.CreateFmt('Unknown command %d', [Cmd]);
      end;
    except
      on E: Exception do
        Log('การเชื่อมต่อจาก ' + FPeerIP + ' ผิดพลาด: ' + E.Message);
    end;
  finally
    CloseSocket(FSock);
    FSock := INVALID_SOCK;
  end;
end;

{ ---------- TListenThread ---------- }

constructor TListenThread.Create(APort: Integer; AShares: TShareList);
var
  Addr: TInetSockAddr;
begin
  inherited Create(True);
  InitCriticalSection(FLock);
  FSessions := TList.Create;
  FPort := APort;
  FShares := AShares;
  FSock := fpsocket(AF_INET, SOCK_STREAM, 0);
  if FSock = INVALID_SOCK then raise ENetError.Create('Cannot create socket');
  {$IFDEF WINDOWS}
  SetOpt(FSock, SO_EXCLUSIVEADDRUSE);   // never share the port with another process
  {$ELSE}
  SetOpt(FSock, SO_REUSEADDR);          // allow quick restart (TIME_WAIT)
  {$ENDIF}
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(APort);
  Addr.sin_addr.s_addr := 0;   // INADDR_ANY
  if fpbind(FSock, psockaddr(@Addr), SizeOf(Addr)) <> 0 then
  begin
    CloseSocket(FSock);
    raise ENetError.CreateFmt('พอร์ต %d ถูกใช้งานอยู่ (เปิดโปรแกรมซ้ำหรือไม่?)', [APort]);
  end;
  if fplisten(FSock, 16) <> 0 then
  begin
    CloseSocket(FSock);
    raise ENetError.Create('listen() failed');
  end;
end;

destructor TListenThread.Destroy;
var
  I: Integer;
begin
  for I := 0 to FSessions.Count - 1 do TPushSession(FSessions[I]).Free;
  FSessions.Free;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

function TListenThread.GetIdent(AIndex: Integer): string;
begin
  EnterCriticalSection(FLock);
  try
    case AIndex of
      0: Result := FMyName;
      1: Result := FMyID;
      2: Result := FMyIcon;
      3: Result := FThemeCss;
    else
      Result := FThemesJson;
    end;
    UniqueString(Result);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TListenThread.SetIdent(AIndex: Integer; const AValue: string);
begin
  EnterCriticalSection(FLock);
  try
    case AIndex of
      0: FMyName := AValue;
      1: FMyID := AValue;
      2: FMyIcon := AValue;
      3: FThemeCss := AValue;
    else
      FThemesJson := AValue;
    end;
    UniqueString(FMyName);
    UniqueString(FMyIcon);
    UniqueString(FThemeCss);
    UniqueString(FThemesJson);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TListenThread.Lock;
begin
  EnterCriticalSection(FLock);
end;

procedure TListenThread.Unlock;
begin
  LeaveCriticalSection(FLock);
end;

function TListenThread.NewSession(const APeerName, APeerIP: string; AFiles: Integer;
  ABytes: Int64): TPushSession;
var
  I: Integer;
  S: TPushSession;
begin
  Result := TPushSession.Create;
  Result.Token := '';
  for I := 1 to 4 do
    Result.Token := Result.Token + IntToHex(Random($10000), 4);
  Result.PeerName := APeerName;
  Result.PeerIP := APeerIP;
  Result.Files := AFiles;
  Result.Bytes := ABytes;
  Result.DestRoot := DownloadDir;
  EnterCriticalSection(FLock);
  try
    // forget sessions idle for more than 30 minutes
    for I := FSessions.Count - 1 downto 0 do
    begin
      S := TPushSession(FSessions[I]);
      if GetTickCount64 - S.LastUsed > 30 * 60 * 1000 then
      begin
        S.Free;
        FSessions.Delete(I);
      end;
    end;
    FSessions.Add(Result);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TListenThread.FindSession(const AToken: string): TPushSession;
var
  I: Integer;
begin
  Result := nil;
  if AToken = '' then Exit;
  EnterCriticalSection(FLock);
  try
    for I := 0 to FSessions.Count - 1 do
      if TPushSession(FSessions[I]).Token = AToken then
      begin
        Result := TPushSession(FSessions[I]);
        Result.LastUsed := GetTickCount64;
        Break;
      end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TListenThread.GetDownloadDir: string;
begin
  EnterCriticalSection(FLock);
  try
    Result := FDownloadDir;
    UniqueString(Result);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TListenThread.SetDownloadDir(const AValue: string);
begin
  EnterCriticalSection(FLock);
  try
    FDownloadDir := AValue;
    UniqueString(FDownloadDir);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TListenThread.StopListening;
var
  S: TSock;
  Addr: TInetSockAddr;
begin
  Terminate;
  // Wake the blocking accept() in a way that works on every OS:
  // shutdown() is enough on Linux, a dummy connection works everywhere.
  fpshutdown(FSock, SHUT_RDWR);
  S := fpsocket(AF_INET, SOCK_STREAM, 0);
  if S <> INVALID_SOCK then
  begin
    FillChar(Addr, SizeOf(Addr), 0);
    Addr.sin_family := AF_INET;
    Addr.sin_port := htons(FPort);
    Addr.sin_addr := StrToNetAddr('127.0.0.1');
    fpconnect(S, psockaddr(@Addr), SizeOf(Addr));
    CloseSocket(S);
  end;
end;

procedure TListenThread.Execute;
var
  Client: TSock;
  Addr: TInetSockAddr;
  Len: TSockLen;
begin
  while not Terminated do
  begin
    Len := SizeOf(Addr);
    Client := fpaccept(FSock, psockaddr(@Addr), @Len);
    if Terminated then
    begin
      if Client <> INVALID_SOCK then CloseSocket(Client);
      Break;
    end;
    if Client = INVALID_SOCK then
    begin
      Sleep(100);
      Continue;
    end;
    TServeThread.Create(Self, Client, NetAddrToStr(Addr.sin_addr)).Start;
  end;
  CloseSocket(FSock);
end;

{ ---------- TDiscoveryThread ---------- }

constructor TDiscoveryThread.Create(const AID, AName, AIcon: string; ATcpPort: Integer);
var
  Addr: TInetSockAddr;
begin
  inherited Create(True);
  InitCriticalSection(FLock);
  FTargets := TStringList.Create;
  FSeen := TStringList.Create;
  FID := AID;
  FName := AName;
  FIcon := AIcon;
  FTcpPort := ATcpPort;
  FSock := fpsocket(AF_INET, SOCK_DGRAM, 0);
  if FSock = INVALID_SOCK then raise ENetError.Create('Cannot create UDP socket');
  // several programs on one machine may share the discovery port
  SetOpt(FSock, SO_REUSEADDR);
  {$IF DECLARED(SO_REUSEPORT)}
  SetOpt(FSock, SO_REUSEPORT);   // macOS/BSD need this for shared UDP ports
  {$ENDIF}
  SetOpt(FSock, SO_BROADCAST);
  SetTimeout(FSock, 500);
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(DISCOVERY_PORT);
  Addr.sin_addr.s_addr := 0;   // INADDR_ANY
  fpbind(FSock, psockaddr(@Addr), SizeOf(Addr));
end;

destructor TDiscoveryThread.Destroy;
begin
  FTargets.Free;
  FSeen.Free;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure TDiscoveryThread.StopDiscovery;
begin
  Terminate;
end;

procedure TDiscoveryThread.AnnounceNow;
begin
  Broadcast;
end;

procedure TDiscoveryThread.SetIdentity(const AName, AIcon: string);
begin
  EnterCriticalSection(FLock);
  try
    FName := AName;
    FIcon := AIcon;
    UniqueString(FName);
    UniqueString(FIcon);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TDiscoveryThread.AddTarget(const IP: string);
begin
  if (IP = '') or (Copy(IP, 1, 4) = '127.') then Exit;
  EnterCriticalSection(FLock);
  try
    if FTargets.IndexOf(IP) < 0 then
    begin
      FTargets.Add(IP);
      while FTargets.Count > 64 do FTargets.Delete(0);
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TDiscoveryThread.DoPeer;
begin
  if Assigned(FOnPeer) then
    FOnPeer(Self, FPeerID, FPeerName, FPeerIP, FPeerPort, FPeerOS, FPeerCaps, FPeerIcon);
end;

function TDiscoveryThread.Packet: string;
begin
  EnterCriticalSection(FLock);
  try
    Result := Format('LSH2|%s|%d|%s|%s|bin,http,push|%s',
      [FID, FTcpPort, StringReplace(FName, '|', '-', [rfReplaceAll]), GetOSName,
       StringReplace(FIcon, '|', '-', [rfReplaceAll])]);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TDiscoveryThread.SendPacket(const Host, Msg: string);
var
  Addr: TInetSockAddr;
begin
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(DISCOVERY_PORT);
  Addr.sin_addr := StrToNetAddr(Host);
  fpsendto(FSock, Pointer(Msg), Length(Msg), 0, psockaddr(@Addr), SizeOf(Addr));
end;

procedure TDiscoveryThread.Broadcast;
var
  Msg: string;
  L: TStringArray;
  I: Integer;
begin
  Msg := Packet;
  SendPacket('255.255.255.255', Msg);
  // directed broadcast on each local network (needed on multi-NIC machines
  // and on macOS, where 255.255.255.255 only leaves the primary interface)
  L := GetBroadcastAddrs;
  for I := 0 to High(L) do
    SendPacket(L[I], Msg);
  // known peers directly: works where routers/Wi-Fi drop broadcasts
  EnterCriticalSection(FLock);
  try
    L := FTargets.ToStringArray;
  finally
    LeaveCriticalSection(FLock);
  end;
  for I := 0 to High(L) do
    SendPacket(L[I], Msg);
end;

{ Announce to every address of our /24 networks. Peers that hear it answer
  directly, so both sides appear even when broadcasts are blocked. }
procedure TDiscoveryThread.ScanSubnets;
var
  IPs: TStringArray;
  I, H: Integer;
  Base, Msg: string;
begin
  Msg := Packet;
  IPs := GetLocalIPs;
  for I := 0 to High(IPs) do
  begin
    Base := Copy(IPs[I], 1, LastDelimiter('.', IPs[I]));
    for H := 1 to 254 do
      if Base + IntToStr(H) <> IPs[I] then
        SendPacket(Base + IntToStr(H), Msg);
  end;
end;

procedure TDiscoveryThread.Execute;
var
  Buf: array[0..1023] of AnsiChar;
  From: TInetSockAddr;
  FromLen: TSockLen;
  N: LongInt;
  S: string;
  Parts: TStringArray;
  LastSend, LastScan: QWord;
begin
  LastSend := 0;
  LastScan := 0;
  while not Terminated do
  begin
    if GetTickCount64 - LastSend >= 3000 then
    begin
      LastSend := GetTickCount64;
      Broadcast;
    end;
    if (LastScan = 0) or (GetTickCount64 - LastScan >= 60000) then
    begin
      LastScan := GetTickCount64;
      ScanSubnets;
    end;
    FromLen := SizeOf(From);
    N := fprecvfrom(FSock, @Buf[0], SizeOf(Buf), 0, psockaddr(@From), @FromLen);
    if N > 0 then
    begin
      SetString(S, PAnsiChar(@Buf[0]), N);
      Parts := S.Split(['|']);
      if (Length(Parts) >= 4) and (Parts[0] = 'LSH2') and (Parts[1] <> FID) then
      begin
        FPeerID := Parts[1];
        FPeerPort := StrToIntDef(Parts[2], DEFAULT_TCP_PORT);
        FPeerName := Parts[3];
        if Length(Parts) >= 5 then FPeerOS := Parts[4] else FPeerOS := '';
        if Length(Parts) >= 6 then FPeerCaps := Parts[5] else FPeerCaps := 'bin';
        if Length(Parts) >= 7 then FPeerIcon := Parts[6] else FPeerIcon := '';
        FPeerIP := NetAddrToStr(From.sin_addr);
        // first time we hear this peer: answer at once so it sees us too
        if FSeen.IndexOf(FPeerID) < 0 then
        begin
          FSeen.Add(FPeerID);
          if FSeen.Count > 1000 then FSeen.Delete(0);
          SendPacket(FPeerIP, Packet);
          AddTarget(FPeerIP);
        end;
        Synchronize(@DoPeer);
      end;
    end
    else if N < 0 then
      Sleep(10);   // timeout or error: loop again and check Terminated
  end;
  CloseSocket(FSock);
end;

{$I lanhttp.inc}

{$IFDEF UNIX}
initialization
  // writing to a closed connection must raise an error, not kill the program
  fpSignal(SIGPIPE, SignalHandler(SIG_IGN));
{$ENDIF}

end.
