unit MainForm;

{ LAN Share main window.
  Left: every computer running LAN Share on the LAN ("This PC" first).
  Right: an Explorer-like view (Details / List / Icons) of the selected computer's shares.
    - This PC   : manage what this computer shares (add / remove, read only or Read + Write)
    - other PCs : browse, download, send files; in Read + Write folders also upload,
                  new folder, rename, delete and edit files
  Bottom: transfers with progress. The UI is drawn with BGRABitmap (see UIWidgets).
  Every text is written as L('English', 'ไทย') (unit I18n). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, IniFiles,
  LCLIntf, LCLType, DateUtils, BGRABitmapTypes, LanNet, UITheme, UIWidgets, SettingsDlg, DragOut,
  ThemeDlg, I18n, MachineID, IdentDlg, ThemedMenu, Clipbrd, FileOps;

type
  TNavEntry = record
    PeerID: string;
    Path: string;
  end;

  { a file of another computer opened here for editing: saved back when it changes }
  TEditSession = record
    PeerID, IP, PeerTitle, VPath, Dir, LocalFile: string;
    Port: Integer;
    Serial: PtrUInt;     // the download thread, until the copy is here
    Ready: Boolean;      // copy downloaded and opened
    Busy: Boolean;       // being saved back
    Stamp, Pending: LongInt;   // FileAge saved last / seen changed once
  end;

  { TFormMain }

  TFormMain = class(TForm)
  private
    Header: THeaderBar;
    BtnSettings: TFlatButton;
    Sidebar: TSidebar;
    BtnAddPeer: TFlatButton;
    Content: TBGRAControl;
    Toolbar: TBGRAControl;
    BtnBack, BtnUp, BtnRefresh: TFlatButton;
    PathBar: TPathBar;
    BtnShareFile, BtnShareFolder, BtnUnshare, BtnOpenLocal: TFlatButton;
    BtnSendFile, BtnSendFolder, BtnDownload, BtnPreview: TFlatButton;
    BtnUpload, BtnNewFolder, BtnView: TFlatButton;   // Read + Write folders; view mode
    TmrEdit: TTimer;
    FileView: TFileView;
    Transfers: TTransfersView;
    TmrPeers: TTimer;
    TmrStatus: TTimer;

    FTcpPort: Integer;
    FMyID, FMyIPs: string;
    FWebHost: string;          // address phones can open (the port is added when shown)
    FMyName: string;           // name others see; '' = not set (nothing is shown)
    FMyIcon: string;           // '<kind>.<color>' shown to others
    FTheme: TThemeKind;        // as chosen (thAuto follows the OS)
    FShownTheme: TThemeKind;   // palette currently on screen
    FHostName: string;         // real computer name: sent with the identity, shown only on right-click
    FMyUser: string;           // login name (identity)
    FMyMachine: string;        // machine code: the same after renames and restarts
    FSendHost: Boolean;        // send computer and user name with the identity
    FSaveWarned: Boolean;      // told the user once that settings cannot be saved
    FRefreshAt: QWord;         // a refresh of the computer list is running since
    FMenuPeer: string;         // ID of the sidebar row a menu was opened on
    FKnown: TStringList;       // addresses of peers seen before (auto-connect)
    FShares: TShareList;
    FListen: TListenThread;
    FDiscovery: TDiscoveryThread;
    FIniName: string;
    FDownloadDir: string;
    FAutoAccept: Boolean;
    FCurPeer: string;          // sidebar item ID being shown
    FCurPath: string;          // virtual path inside the peer's shares
    FHistory: array of TNavEntry;
    FBrowseSeq: Integer;
    FThreads: TList;           // running TNetThreads started or served here
    FClosing: Boolean;
    FDraggingOut: Boolean;     // our own drag: ignore it if it is dropped back on us
    FCurWritable: Boolean;     // the peer folder shown accepts changes
    FHintedPath: string;       // the Read + Write hint was shown for this folder
    FEdits: array of TEditSession;
    FViewMode: TViewMode;

    procedure BuildUI;
    procedure ApplyTexts;
    function MkBtn(AParent: TWinControl; const ACaption: string; AIcon: TIconKind;
      AStyle: TButtonStyle; AAlign: TAlign; AClick: TNotifyEvent): TFlatButton;
    procedure LoadSettings;
    procedure SaveSettings;
    function StartNetwork: Boolean;
    function OpenListener(APort: Integer): Boolean;
    procedure UpdateHeader;
    procedure UpdateMeItem;
    procedure UpdateToolbar;
    function CurItem: Integer;
    function PeerIndex(const ID: string): Integer;
    procedure Navigate(const PeerID, Path: string; AddHistory: Boolean = True);
    procedure ShowMyShares;
    procedure RequestListing;
    procedure SetStatus(const S: string; OK: Boolean = True);
    procedure AddShares(const Paths: array of string);
    procedure SendPaths(const Paths: array of string);
    procedure DownloadSelected;
    procedure TrackThread(T: TNetThread);
    procedure ApplyIdentity;
    procedure ApplyTheme;
    procedure OpenPreview;

    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormDropFilesEvt(Sender: TObject; const FileNames: array of string);
    procedure SidebarSelect(Sender: TObject);
    procedure SidebarPickDir(Sender: TObject);
    procedure SidebarOpenDir(Sender: TObject);
    procedure SidebarToggleAuto(Sender: TObject);
    procedure BtnAddPeerClick(Sender: TObject);
    procedure BtnBackClick(Sender: TObject);
    procedure BtnUpClick(Sender: TObject);
    procedure BtnRefreshClick(Sender: TObject);
    procedure PathBarSegment(Sender: TObject);
    procedure BtnShareFileClick(Sender: TObject);
    procedure BtnShareFolderClick(Sender: TObject);
    procedure BtnUnshareClick(Sender: TObject);
    procedure BtnOpenLocalClick(Sender: TObject);
    procedure BtnSendFileClick(Sender: TObject);
    procedure BtnSendFolderClick(Sender: TObject);
    procedure BtnDownloadClick(Sender: TObject);
    procedure BtnPreviewClick(Sender: TObject);
    procedure BtnSettingsClick(Sender: TObject);
    procedure FileViewOpen(Sender: TObject);
    procedure FileViewSelChange(Sender: TObject);
    procedure FileViewDragOut(Sender: TObject);
    procedure FileViewCopy(Sender: TObject);
    function PrepareOut(ToClipboard: Boolean): Boolean;
    procedure TransfersCancel(Sender: TObject);
    procedure TmrPeersTimer(Sender: TObject);
    procedure TmrStatusTimer(Sender: TObject);

    procedure NetLog(Sender: TObject; const Msg: string);
    procedure NetTransfer(const T: TTransferInfo);
    function NetAsk(Sender: TObject; const FromName, FromIP: string;
      FileCount: Integer; TotalBytes: Int64): Boolean;
    procedure NetPeer(Sender: TObject; const ID, PeerName, IP: string; Port: Integer;
      const OS, Caps, PeerIcon: string; const Ident: TPeerIdent);
    procedure SidebarContext(Sender: TObject; Index: Integer; const ScreenPt: TPoint);
    procedure SidebarRefresh(Sender: TObject);
    procedure FileViewContext(Sender: TObject; const ScreenPt: TPoint);
    procedure ShowPeerIdentity(Index: Integer; const ScreenPt: TPoint);
    procedure RefreshPeers;
    procedure ApplyMachine;
    procedure UseInstanceIni(APort: Integer);
    function MenuPeerIndex: Integer;
    procedure MnuPeerOpen(Sender: TObject);
    procedure MnuPeerIdentity(Sender: TObject);
    procedure MnuPeerCopyIP(Sender: TObject);
    procedure MnuPeerWeb(Sender: TObject);
    procedure MnuPeerRemove(Sender: TObject);
    function CurCanWrite: Boolean;
    procedure StartWriteOp(Op: Byte; const Paths: TStringArray; const NewName: string = '');
    procedure WriteDone(T: TWriteThread);
    procedure UploadPaths(const Paths: array of string);
    procedure BtnUploadClick(Sender: TObject);
    procedure MnuUploadFolder(Sender: TObject);
    procedure BtnNewFolderClick(Sender: TObject);
    procedure FileViewRename(Sender: TObject);
    procedure FileViewDelete(Sender: TObject);
    procedure MnuEdit(Sender: TObject);
    procedure EditArrived(I: Integer);
    procedure EditSaved(T: TWriteThread);
    procedure TmrEditTimer(Sender: TObject);
    procedure MnuToggleWrite(Sender: TObject);
    procedure SetViewMode(M: TViewMode);
    procedure BtnViewClick(Sender: TObject);
    procedure MnuViewDetails(Sender: TObject);
    procedure MnuViewList(Sender: TObject);
    procedure MnuViewIcons(Sender: TObject);
    procedure NetPeerGone(Sender: TObject; const ID: string);
    procedure BrowseDone(B: TBrowseThread);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  FormMain: TFormMain;

implementation

const
  ME_ID = '*me*';

{ "name (ip)", or just the ip when the sender set no name }
function Who(const AName, AIP: string): string;
begin
  if (AName = '') or (AName = AIP) then Result := AIP
  else Result := AName + ' (' + AIP + ')';
end;

function IsPreviewable(const FileName: string): Boolean;
var
  E: string;
begin
  E := LowerCase(ExtractFileExt(FileName));
  Result := (E = '.md') or (E = '.markdown') or (E = '.png') or (E = '.jpg') or (E = '.jpeg')
    or (E = '.gif') or (E = '.webp') or (E = '.pdf') or (E = '.mp4') or (E = '.webm');
end;

{ ---------- construction ---------- }

{ temp folder for files of other computers opened for editing }
function EditRoot: string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'LanShareEdit' + PathDelim;
end;

function LastSegOf(const VPath: string): string;
begin
  Result := Copy(VPath, LastDelimiter('/', VPath) + 1, MaxInt);
end;

{$IFDEF WINDOWS}
{ Settings live next to the exe (portable) - unless that folder cannot be
  written (Program Files, a read-only drive) or is a temporary copy (the exe
  was opened from inside a zip): then in %APPDATA%\LanShare, so shares and
  names are remembered. Settings found next to a read-only exe are copied
  there the first time. }
function ChooseIniName: string;
var
  Portable, Dir, Probe, Base: string;
  Writable: Boolean;
  Src, Dst: TFileStream;
begin
  Portable := ChangeFileExt(Application.ExeName, '.ini');
  Dir := ExtractFilePath(Portable);
  // a temp folder is emptied: never keep settings there
  Writable := Pos(LowerCase(IncludeTrailingPathDelimiter(GetTempDir(False))), LowerCase(Dir)) <> 1;
  if Writable then
    try
      if FileExists(Portable) then
        TFileStream.Create(Portable, fmOpenReadWrite or fmShareDenyNone).Free
      else
      begin
        Probe := Dir + 'LanShare.write-test';
        TFileStream.Create(Probe, fmCreate).Free;
        SysUtils.DeleteFile(Probe);
      end;
    except
      Writable := False;
    end;
  if Writable then Exit(Portable);
  Base := GetEnvironmentVariable('APPDATA');
  if Base = '' then Base := GetUserDir;
  Result := IncludeTrailingPathDelimiter(Base) + 'LanShare' + PathDelim;
  ForceDirectories(Result);
  Result := Result + 'LanShare.ini';
  if FileExists(Portable) and not FileExists(Result) then
    try
      Src := TFileStream.Create(Portable, fmOpenRead or fmShareDenyNone);
      try
        Dst := TFileStream.Create(Result, fmCreate);
        try
          Dst.CopyFrom(Src, 0);
        finally
          Dst.Free;
        end;
      finally
        Src.Free;
      end;
    except
      // start with defaults
    end;
end;
{$ENDIF}

constructor TFormMain.Create(TheOwner: TComponent);
var
  I: Integer;
  IPs: TStringArray;
begin
  inherited CreateNew(TheOwner);   // the UI is built in code, no .lfm
  UIScale := Screen.PixelsPerInch / 96;
  FTcpPort := DEFAULT_TCP_PORT;
  for I := 1 to ParamCount do
    if Pos('--port=', ParamStr(I)) = 1 then
      FTcpPort := StrToIntDef(Copy(ParamStr(I), 8, 10), DEFAULT_TCP_PORT);

  FHostName := GetMyHostName;
  FMyUser := GetUserLogin;
  Randomize;
  FMyID := IntToHex(Random($7FFFFFFF), 8) + IntToHex(GetTickCount64 and $FFFF, 4);
  IPs := GetLocalIPs;
  FMyIPs := '';
  for I := 0 to High(IPs) do
  begin
    if FMyIPs <> '' then FMyIPs := FMyIPs + ', ';
    FMyIPs := FMyIPs + IPs[I];
  end;
  if FMyIPs = '' then FMyIPs := L('no IP found', 'ไม่พบ IP');
  // address phones can open in a browser: the default-route address first,
  // else the usual home/office ranges
  FWebHost := GetPrimaryIP;
  if FWebHost = '' then
    for I := 0 to High(IPs) do
      if Copy(IPs[I], 1, 8) = '192.168.' then begin FWebHost := IPs[I]; Break; end;
  if FWebHost = '' then
    for I := 0 to High(IPs) do
      if Copy(IPs[I], 1, 3) = '10.' then begin FWebHost := IPs[I]; Break; end;
  if (FWebHost = '') and (Length(IPs) > 0) then FWebHost := IPs[0];

  {$IFDEF WINDOWS}
  FIniName := ChooseIniName;
  {$ELSE}
  // GetAppConfigDir names the folder after Application.Title ("LAN Share"),
  // so take its parent (~/.config, honours XDG_CONFIG_HOME) and fix the name.
  FIniName := ExtractFilePath(ExcludeTrailingPathDelimiter(GetAppConfigDir(False)))
    + 'LanShare' + PathDelim;
  ForceDirectories(FIniName);
  FIniName := FIniName + 'LanShare.ini';
  {$ENDIF}

  CleanupDragTemp;   // leftovers of earlier drags to Explorer
  DeleteTree(EditRoot);   // and of files opened for editing last time
  FShares := TShareList.Create;
  FThreads := TList.Create;
  FKnown := TStringList.Create;
  BuildUI;
  LoadSettings;
  SetViewMode(FViewMode);
  ApplyTexts;
  ApplyTheme;
  if not StartNetwork then
  begin
    // the user chose "Close": end before the window is shown
    FClosing := True;
    Application.ShowMainForm := False;
    Application.Terminate;
    Exit;
  end;
  UpdateMeItem;
  Navigate(ME_ID, '', False);
end;

destructor TFormMain.Destroy;
begin
  FThreads.Free;
  FKnown.Free;
  // FShares is still referenced by serving threads that may outlive the form;
  // it is released when the process exits.
  inherited Destroy;
end;

function TFormMain.MkBtn(AParent: TWinControl; const ACaption: string; AIcon: TIconKind;
  AStyle: TButtonStyle; AAlign: TAlign; AClick: TNotifyEvent): TFlatButton;
begin
  Result := TFlatButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Icon := AIcon;
  Result.Style := AStyle;
  Result.BackColor := TBGRAControl(AParent).BackColor;
  Result.Align := AAlign;
  Result.OnClick := AClick;
  Result.FitWidth;
end;

procedure TFormMain.BuildUI;
begin
  Caption := 'LAN Share';
  Width := ScI(1120);
  Height := ScI(720);
  Constraints.MinWidth := ScI(760);
  Constraints.MinHeight := ScI(480);
  Position := poScreenCenter;
  Color := BGRAToColor(clBg);
  AllowDropFiles := True;
  OnDropFiles := @FormDropFilesEvt;
  OnCloseQuery := @FormCloseQuery;
  KeyPreview := False;

  Header := THeaderBar.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.Height := ScI(64);
  Header.BackColor := clHead2;
  Header.ChildSizing.TopBottomSpacing := ScI(13);
  BtnSettings := MkBtn(Header, '', ikGear, bsNormal, alRight, @BtnSettingsClick);
  BtnSettings.BorderSpacing.Right := ScI(14);
  BtnSettings.ShowHint := True;

  { sidebar }
  Sidebar := TSidebar.Create(Self);
  Sidebar.Parent := Self;
  Sidebar.Align := alLeft;
  Sidebar.Width := ScI(268);
  Sidebar.BottomReserve := ScI(54);
  Sidebar.OnSelect := @SidebarSelect;
  Sidebar.OnPickDir := @SidebarPickDir;
  Sidebar.OnOpenDir := @SidebarOpenDir;
  Sidebar.OnToggleAuto := @SidebarToggleAuto;
  Sidebar.OnContext := @SidebarContext;
  Sidebar.OnRefresh := @SidebarRefresh;
  SetLength(Sidebar.Items, 1);
  Sidebar.Items[0].ID := ME_ID;
  Sidebar.Items[0].IsMe := True;
  Sidebar.Items[0].Online := True;

  BtnAddPeer := MkBtn(Sidebar, '', ikPlus, bsNormal, alBottom, @BtnAddPeerClick);
  BtnAddPeer.BorderSpacing.Around := ScI(12);
  BtnAddPeer.BorderSpacing.Top := 0;
  BtnAddPeer.Height := ScI(34);

  { content area }
  Content := TBGRAControl.Create(Self);
  Content.Parent := Self;
  Content.Align := alClient;
  Content.BackColor := clBg;

  Toolbar := TBGRAControl.Create(Self);
  Toolbar.Parent := Content;
  Toolbar.Align := alTop;
  Toolbar.Height := ScI(56);
  Toolbar.BackColor := clBg;
  Toolbar.ChildSizing.TopBottomSpacing := ScI(8);
  Toolbar.ChildSizing.LeftRightSpacing := ScI(10);

  BtnBack := MkBtn(Toolbar, '', ikBack, bsGhost, alLeft, @BtnBackClick);
  BtnUp := MkBtn(Toolbar, '', ikUp, bsGhost, alLeft, @BtnUpClick);
  BtnRefresh := MkBtn(Toolbar, '', ikRefresh, bsGhost, alLeft, @BtnRefreshClick);
  BtnBack.ShowHint := True;
  BtnUp.ShowHint := True;
  BtnRefresh.ShowHint := True;

  // right-aligned actions (created right-to-left)
  BtnDownload := MkBtn(Toolbar, '', ikDownload, bsAccent, alRight, @BtnDownloadClick);
  BtnSendFolder := MkBtn(Toolbar, '', ikFolderPlus, bsNormal, alRight, @BtnSendFolderClick);
  BtnSendFile := MkBtn(Toolbar, '', ikUpload, bsNormal, alRight, @BtnSendFileClick);
  BtnUnshare := MkBtn(Toolbar, '', ikTrash, bsDanger, alRight, @BtnUnshareClick);
  BtnShareFolder := MkBtn(Toolbar, '', ikFolderPlus, bsAccent, alRight, @BtnShareFolderClick);
  BtnShareFile := MkBtn(Toolbar, '', ikFilePlus, bsNormal, alRight, @BtnShareFileClick);
  BtnOpenLocal := MkBtn(Toolbar, '', ikFolderOpen, bsNormal, alRight, @BtnOpenLocalClick);
  BtnPreview := MkBtn(Toolbar, '', ikEye, bsNormal, alRight, @BtnPreviewClick);
  // in a Read + Write folder of another computer these take the place of Send
  BtnUpload := MkBtn(Toolbar, '', ikUpload, bsNormal, alRight, @BtnUploadClick);
  BtnNewFolder := MkBtn(Toolbar, '', ikFolderPlus, bsNormal, alRight, @BtnNewFolderClick);
  BtnUpload.Visible := False;
  BtnNewFolder.Visible := False;
  BtnView := MkBtn(Toolbar, '', ikViewDetails, bsGhost, alLeft, @BtnViewClick);
  BtnView.ShowHint := True;
  BtnPreview.ShowHint := True;
  // LCL orders controls with the same Align by their Left: make it explicit
  BtnBack.Left := 0;
  BtnUp.Left := 100;
  BtnRefresh.Left := 200;
  BtnView.Left := 300;
  BtnUpload.Left := 3000;
  BtnNewFolder.Left := 3100;
  BtnPreview.Left := 2800;
  BtnOpenLocal.Left := 2900;
  BtnUnshare.Left := 3000;      BtnSendFile.Left := 3000;
  BtnShareFile.Left := 3100;    BtnSendFolder.Left := 3100;
  BtnShareFolder.Left := 3200;  BtnDownload.Left := 3200;

  PathBar := TPathBar.Create(Self);
  PathBar.Parent := Toolbar;
  PathBar.Align := alClient;
  PathBar.BackColor := clBg;
  PathBar.BorderSpacing.Left := ScI(6);
  PathBar.BorderSpacing.Right := ScI(8);
  PathBar.OnSegment := @PathBarSegment;

  Transfers := TTransfersView.Create(Self);
  Transfers.Parent := Content;
  Transfers.Align := alBottom;
  Transfers.Height := ScI(192);
  Transfers.OnCancel := @TransfersCancel;

  FileView := TFileView.Create(Self);
  FileView.Parent := Content;
  FileView.Align := alClient;
  FileView.OnOpen := @FileViewOpen;
  FileView.OnSelChange := @FileViewSelChange;
  FileView.OnBack := @BtnBackClick;
  FileView.OnDragOut := @FileViewDragOut;
  FileView.OnCopy := @FileViewCopy;
  FileView.OnRefresh := @BtnRefreshClick;
  FileView.OnContext := @FileViewContext;
  FileView.OnRename := @FileViewRename;
  FileView.OnDelete := @FileViewDelete;

  TmrEdit := TTimer.Create(Self);
  TmrEdit.Interval := 1500;
  TmrEdit.OnTimer := @TmrEditTimer;

  TmrPeers := TTimer.Create(Self);
  TmrPeers.Interval := 3000;
  TmrPeers.OnTimer := @TmrPeersTimer;

  TmrStatus := TTimer.Create(Self);
  TmrStatus.Enabled := False;
  TmrStatus.Interval := 6000;
  TmrStatus.OnTimer := @TmrStatusTimer;
end;

{ every text that is set once (not drawn each time): run again when the
  language changes }
procedure TFormMain.ApplyTexts;

  procedure Cap(B: TFlatButton; const S: string);
  begin
    B.Caption := S;
    B.FitWidth;
  end;

begin
  if FTcpPort <> DEFAULT_TCP_PORT then
    Caption := Format(L('LAN Share (port %d)', 'LAN Share (พอร์ต %d)'), [FTcpPort])   // tells the windows apart
  else
    Caption := 'LAN Share';
  Cap(BtnSettings, L('Settings', 'ตั้งค่า'));
  BtnSettings.Hint := L('Name, icon, theme and language', 'ชื่อ ไอคอน ธีม และภาษา');
  Header.RightReserve := BtnSettings.Width + ScI(22);
  Sidebar.Items[0].Title := L('This PC', 'เครื่องนี้');
  Cap(BtnAddPeer, L('Connect by IP', 'เชื่อมต่อด้วย IP'));
  BtnBack.Hint := L('Back (Backspace)', 'ย้อนกลับ (Backspace)');
  BtnUp.Hint := L('Up one level', 'ขึ้นหนึ่งระดับ');
  BtnRefresh.Hint := L('Refresh', 'รีเฟรช');
  Cap(BtnDownload, L('Download', 'ดาวน์โหลด'));
  Cap(BtnSendFolder, L('Send folder', 'ส่งโฟลเดอร์'));
  Cap(BtnSendFile, L('Send files', 'ส่งไฟล์'));
  Cap(BtnUnshare, L('Unshare', 'เลิกแชร์'));
  Cap(BtnShareFolder, L('Share folder', 'แชร์โฟลเดอร์'));
  Cap(BtnShareFile, L('Share files', 'แชร์ไฟล์'));
  Cap(BtnOpenLocal, L('Open locally', 'เปิดในเครื่อง'));
  Cap(BtnPreview, L('Preview', 'ดูตัวอย่าง'));
  Cap(BtnUpload, L('Upload', 'อัปโหลด'));
  Cap(BtnNewFolder, L('New folder', 'โฟลเดอร์ใหม่'));
  BtnUpload.Hint := L('Add files to this folder of the other computer', 'เพิ่มไฟล์ลงในโฟลเดอร์นี้ของเครื่องนั้น');
  BtnUpload.ShowHint := True;
  BtnView.Hint := L('View: Details, List or Icons', 'มุมมอง: รายละเอียด รายการ หรือไอคอน');
  BtnPreview.Hint := L('View in the browser: Markdown pages (.md), pictures, PDF, video', 'เปิดดูในเบราว์เซอร์: หน้า Markdown (.md) รูป PDF วิดีโอ');
end;

{ ---------- settings ---------- }

procedure TFormMain.LoadSettings;
var
  Ini: TIniFile;
  N, I, P: Integer;
  S, IP: string;
  Port: Integer;
begin
  Ini := TIniFile.Create(FIniName);
  try
    FDownloadDir := Ini.ReadString('Main', 'DownloadDir',
      IncludeTrailingPathDelimiter(GetUserDir) + 'Downloads' + PathDelim + 'LanShare');
    FAutoAccept := Ini.ReadBool('Main', 'AutoAccept', False);
    // privacy: no name is sent unless the user sets one (never the computer name)
    FMyName := Ini.ReadString('Main', 'DisplayName', '');
    FMyIcon := Ini.ReadString('Main', 'Icon', 'desktop.0');
    FTheme := ThemeFromName(Ini.ReadString('Main', 'Theme', 'dark'));
    Lang := LangFromCode(Ini.ReadString('Main', 'Language', 'en'));
    FSendHost := Ini.ReadBool('Main', 'SendComputerName', True);
    // machine code: from the OS machine id, else from a random key saved once
    S := GetRawMachineID;
    if S = '' then
    begin
      S := Ini.ReadString('Main', 'MachineKey', '');
      if S = '' then
      begin
        S := TGUID.NewGuid.ToString(True);
        Ini.WriteString('Main', 'MachineKey', S);
      end;
    end;
    FMyMachine := MakeMachineCode(S);
    N := Ini.ReadInteger('Known', 'Count', 0);
    for I := 0 to N - 1 do
    begin
      S := Ini.ReadString('Known', 'Item' + IntToStr(I), '');
      if (S <> '') and (FKnown.IndexOf(S) < 0) then FKnown.Add(S);
    end;
    N := Ini.ReadInteger('Shares', 'Count', 0);
    for I := 0 to N - 1 do
    begin
      S := Ini.ReadString('Shares', 'Item' + IntToStr(I), '');
      // keep shares that are not there right now (network or USB drive not
      // connected yet): they come back by themselves, and dropping them here
      // would erase them from the settings at the next save
      if S <> '' then
      begin
        FShares.Add(S);
        if Ini.ReadBool('Shares', 'Write' + IntToStr(I), False) then FShares.SetWritable(S, True);
      end;
    end;
    case Ini.ReadString('Main', 'View', 'details') of
      'list':  FViewMode := vmList;
      'icons': FViewMode := vmIcons;
    else
      FViewMode := vmDetails;
    end;
    N := Ini.ReadInteger('Peers', 'Count', 0);
    for I := 0 to N - 1 do
    begin
      S := Ini.ReadString('Peers', 'Item' + IntToStr(I), '');
      if S = '' then Continue;
      P := Pos(':', S);
      if P > 0 then
      begin
        IP := Copy(S, 1, P - 1);
        Port := StrToIntDef(Copy(S, P + 1, 10), DEFAULT_TCP_PORT);
      end
      else
      begin
        IP := S;
        Port := DEFAULT_TCP_PORT;
      end;
      NetPeer(nil, 'manual:' + IP + ':' + IntToStr(Port), IP, IP, Port, '', '', '', Default(TPeerIdent));
    end;
  finally
    Ini.Free;
  end;
  Sidebar.DownloadDir := FDownloadDir;
  Sidebar.AutoAccept := FAutoAccept;
end;

procedure TFormMain.SaveSettings;
var
  Ini: TIniFile;
  P: TStringArray;
  I, N: Integer;
begin
  try
    Ini := TIniFile.Create(FIniName);
    try
      Ini.WriteString('Main', 'DownloadDir', FDownloadDir);
      Ini.WriteBool('Main', 'AutoAccept', FAutoAccept);
      Ini.DeleteKey('Main', 'Name');            // old versions stored the computer name
      Ini.DeleteKey('Main', 'AnonTag');
      if FMyName = '' then
        Ini.DeleteKey('Main', 'DisplayName')
      else
        Ini.WriteString('Main', 'DisplayName', FMyName);
      Ini.WriteString('Main', 'Icon', FMyIcon);
      Ini.WriteString('Main', 'Theme', THEME_NAMES[FTheme]);
      Ini.WriteString('Main', 'Language', LANG_CODES[Lang]);
      Ini.WriteBool('Main', 'SendComputerName', FSendHost);
      Ini.EraseSection('Known');
      Ini.WriteInteger('Known', 'Count', FKnown.Count);
      for I := 0 to FKnown.Count - 1 do
        Ini.WriteString('Known', 'Item' + IntToStr(I), FKnown[I]);
      Ini.EraseSection('Shares');
      P := FShares.Paths;
      Ini.WriteInteger('Shares', 'Count', Length(P));
      for I := 0 to High(P) do
      begin
        Ini.WriteString('Shares', 'Item' + IntToStr(I), P[I]);
        if FShares.IsWritable(P[I]) then Ini.WriteBool('Shares', 'Write' + IntToStr(I), True);
      end;
      case FViewMode of
        vmList:  Ini.WriteString('Main', 'View', 'list');
        vmIcons: Ini.WriteString('Main', 'View', 'icons');
      else
        Ini.WriteString('Main', 'View', 'details');
      end;
      Ini.EraseSection('Peers');
      N := 0;
      for I := 0 to High(Sidebar.Items) do
        if Sidebar.Items[I].Manual then
        begin
          Ini.WriteString('Peers', 'Item' + IntToStr(N),
            Sidebar.Items[I].IP + ':' + IntToStr(Sidebar.Items[I].Port));
          Inc(N);
        end;
      Ini.WriteInteger('Peers', 'Count', N);
    finally
      Ini.Free;
    end;
  except
    // say it once: otherwise shares and names are silently forgotten
    if not FSaveWarned then
    begin
      FSaveWarned := True;
      SetStatus(Format(L('Cannot save settings to %s', 'บันทึกการตั้งค่าไม่ได้: %s'), [FIniName]), False);
    end;
  end;
end;

{ ---------- network start ---------- }

function TFormMain.OpenListener(APort: Integer): Boolean;
begin
  Result := False;
  try
    FListen := TListenThread.Create(APort, FShares);
  except
    FListen := nil;
    Exit;
  end;
  FTcpPort := APort;
  Result := True;
end;

{ Returns False when the user chose to close the program }
function TFormMain.StartNetwork: Boolean;
var
  I, P: Integer;
begin
  Result := True;
  P := 0;
  if not OpenListener(FTcpPort) then
  begin
    // usually LAN Share is already open on this computer
    if not ThemedAsk(Self, dkWarning, L('LAN Share already open?', 'LAN Share เปิดอยู่แล้ว?'),
      Format(L('Port %d is in use — LAN Share may already be running on this computer.', 'พอร์ต %d ถูกใช้งานอยู่ — อาจเปิด LAN Share ไว้แล้วบนเครื่องนี้') + #10#10 +
             L('Open again: start another window on the next free port', 'เปิดซ้ำ: เปิดอีกหน้าต่างโดยใช้พอร์ตถัดไปที่ว่าง') + #10 +
             L('Close: keep using the window that is already open', 'ปิดโปรแกรม: ใช้หน้าต่างที่เปิดอยู่แล้วต่อ'), [FTcpPort]),
      L('Open again', 'เปิดซ้ำ'), L('Close', 'ปิดโปรแกรม')) then
      Exit(False);
    P := FTcpPort;
    for I := 1 to 20 do
      if OpenListener(P + I) then Break;
    if FListen = nil then
      ThemedAsk(Self, dkError, L('Cannot accept connections', 'เปิดตัวรับการเชื่อมต่อไม่ได้'),
        Format(L('No free port between %d and %d — you can still browse other computers, but they cannot browse this one.', 'ไม่มีพอร์ตว่างระหว่าง %d–%d — ยังเปิดดูเครื่องอื่นได้ แต่เครื่องอื่นจะเปิดดูเครื่องนี้ไม่ได้'),
          [P, P + 20]), L('OK', 'ตกลง'), '');
  end;
  // opened again on another port: own settings file (see UseInstanceIni)
  if (FListen <> nil) and (FTcpPort <> P) and (P <> 0) then UseInstanceIni(FTcpPort);
  ApplyTexts;   // the window caption shows the port when it is not the default
  if FListen <> nil then
  begin
    FListen.DownloadDir := FDownloadDir;
    FListen.AutoAccept := FAutoAccept;
    FListen.OnLog := @NetLog;
    FListen.OnAsk := @NetAsk;
    FListen.OnTransfer := @NetTransfer;
    FListen.MyName := FMyName;
    FListen.MyID := FMyID;
    FListen.MyIcon := FMyIcon;
    FListen.ThemeCss := UITheme.ThemeCss;
    FListen.ThemesJson := UITheme.ThemesJson;
    FListen.Lang := LANG_CODES[Lang];
    FListen.ThemeCssFunc := @UITheme.ThemeCssByName;
    FListen.Start;
  end;
  try
    FDiscovery := TDiscoveryThread.Create(FMyID, FMyName, FMyIcon, FTcpPort);
    ApplyMachine;
    FDiscovery.OnPeer := @NetPeer;
    FDiscovery.OnPeerGone := @NetPeerGone;
    for I := 0 to FKnown.Count - 1 do
      FDiscovery.AddTarget(FKnown[I]);   // reconnect to machines seen last time
    FDiscovery.Start;
  except
    on E: Exception do
      FDiscovery := nil;
  end;
  UpdateHeader;
end;

{ ---------- helpers ---------- }

procedure TFormMain.UpdateHeader;
var
  Online, I: Integer;
begin
  if FWebHost <> '' then
    Header.SubTitle := Format(L('Phones can open http://%s:%d in a browser', 'มือถือเปิดในเบราว์เซอร์ได้ที่ http://%s:%d'), [FWebHost, FTcpPort])
  else
    Header.SubTitle := Format(L('%s  •  port %d', '%s  •  พอร์ต %d'), [FMyIPs, FTcpPort]);
  if FMyName <> '' then Header.SubTitle := FMyName + '  •  ' + Header.SubTitle;
  if not TmrStatus.Enabled then
  begin
    Online := 0;
    for I := 0 to High(Sidebar.Items) do
      if (not Sidebar.Items[I].IsMe) and Sidebar.Items[I].Online then Inc(Online);
    if FListen = nil then
    begin
      Header.Status := L('Cannot receive files (port in use)', 'รับไฟล์ไม่ได้ (พอร์ตถูกใช้)');
      Header.StatusOK := False;
    end
    else
    begin
      Header.Status := Format(L('Online  •  %d public shares  •  %d computers found', 'ออนไลน์  •  แชร์สาธารณะ %d รายการ  •  พบ %d เครื่อง'), [FShares.Count, Online]);
      Header.StatusOK := True;
    end;
  end;
  Header.Invalidate;
end;

procedure TFormMain.SetStatus(const S: string; OK: Boolean);
begin
  Header.Status := S;
  Header.StatusOK := OK;
  Header.Invalidate;
  TmrStatus.Enabled := False;
  TmrStatus.Enabled := True;
end;

procedure TFormMain.TmrStatusTimer(Sender: TObject);
begin
  TmrStatus.Enabled := False;
  UpdateHeader;
end;

procedure TFormMain.UpdateMeItem;
var
  I: Integer;
begin
  I := PeerIndex(ME_ID);
  if I >= 0 then
  begin
    Sidebar.Items[I].Icon := FMyIcon;
    Header.MyIcon := FMyIcon;
    if FMyName = '' then
    begin
      // no name set: no text at all, only the icon
      Sidebar.Items[I].Title := '';
      Sidebar.Items[I].Subtitle := '';
    end
    else
    begin
      Sidebar.Items[I].Title := FMyName;
      if FShares.Count = 0 then
        Sidebar.Items[I].Subtitle := ''
      else
        Sidebar.Items[I].Subtitle := Format(L('%d public shares', 'แชร์สาธารณะ %d รายการ'), [FShares.Count]);
    end;
  end;
  Sidebar.Invalidate;
  UpdateHeader;
end;

function TFormMain.PeerIndex(const ID: string): Integer;
begin
  Result := Sidebar.IndexOfID(ID);
end;

function TFormMain.CurItem: Integer;
begin
  Result := PeerIndex(FCurPeer);
end;

procedure TFormMain.UpdateToolbar;
var
  IsMe, HasSel, Online: Boolean;
  I: Integer;
  Order: array of TFlatButton;
begin
  IsMe := FCurPeer = ME_ID;
  HasSel := FileView.SelCount > 0;
  I := CurItem;
  // a device without a LAN Share server (e.g. a phone app that only sends) cannot receive
  Online := (I >= 0) and Sidebar.Items[I].Online and Sidebar.Items[I].CanBrowse;
  BtnShareFile.Visible := IsMe and (FCurPath = '');
  BtnShareFolder.Visible := IsMe;
  BtnUnshare.Visible := IsMe and (FCurPath = '');
  BtnUnshare.Enabled := HasSel;
  BtnOpenLocal.Visible := IsMe and (FCurPath <> '');
  BtnPreview.Visible := IsMe or ((I >= 0) and Sidebar.Items[I].CanBrowse);
  BtnPreview.Enabled := (FileView.ErrorText = '') and ((not IsMe) or (FShares.Count > 0));
  // a Read + Write folder: add files into it instead of sending to the receive folder
  BtnUpload.Visible := (not IsMe) and CurCanWrite;
  BtnNewFolder.Visible := (not IsMe) and CurCanWrite;
  BtnSendFile.Visible := (not IsMe) and not CurCanWrite;
  BtnSendFolder.Visible := (not IsMe) and not CurCanWrite;
  BtnDownload.Visible := not IsMe;
  BtnDownload.Enabled := HasSel and (FileView.ErrorText = '');
  BtnSendFile.Enabled := Online;
  BtnSendFolder.Enabled := Online;
  BtnBack.Enabled := Length(FHistory) > 0;
  BtnUp.Enabled := FCurPath <> '';
  BtnRefresh.Enabled := True;
  // LCL places alRight controls by Left (larger = further right); buttons
  // that were hidden keep an old Left, so set the order again every time
  Order := [BtnPreview, BtnOpenLocal, BtnUnshare, BtnSendFile, BtnUpload, BtnShareFile,
    BtnSendFolder, BtnNewFolder, BtnShareFolder, BtnDownload];
  Toolbar.DisableAlign;
  try
    for I := 0 to High(Order) do
      Order[I].Left := 5000 + I * 100;
  finally
    Toolbar.EnableAlign;
  end;
end;

{ ---------- navigation ---------- }

procedure TFormMain.Navigate(const PeerID, Path: string; AddHistory: Boolean);
var
  I, K: Integer;
  Parts: TStringArray;
begin
  if AddHistory and ((PeerID <> FCurPeer) or (Path <> FCurPath)) and (FCurPeer <> '') then
  begin
    SetLength(FHistory, Length(FHistory) + 1);
    FHistory[High(FHistory)].PeerID := FCurPeer;
    FHistory[High(FHistory)].Path := FCurPath;
    if Length(FHistory) > 100 then Delete(FHistory, 0, 1);
  end;
  FCurPeer := PeerID;
  FCurPath := Path;
  I := PeerIndex(PeerID);
  if I < 0 then
  begin
    FCurPeer := ME_ID;
    FCurPath := '';
    I := PeerIndex(ME_ID);
  end;
  if Sidebar.Selected <> I then
  begin
    Sidebar.Selected := I;
    Sidebar.Invalidate;
  end;

  // breadcrumb
  if FCurPath = '' then
    Parts := nil
  else
    Parts := FCurPath.Split(['/']);
  SetLength(PathBar.Segments, Length(Parts) + 1);
  if Sidebar.Items[I].IsMe then
    PathBar.Segments[0] := L('This PC — my shares', 'เครื่องนี้ — สิ่งที่ฉันแชร์')
  else
    PathBar.Segments[0] := Sidebar.Items[I].Title;
  for K := 0 to High(Parts) do
    PathBar.Segments[K + 1] := Parts[K];
  PathBar.Invalidate;

  if FCurPeer = ME_ID then
  begin
    FCurWritable := False;
    ShowMyShares;
  end
  else if not Sidebar.Items[I].CanBrowse then
  begin
    FileView.SetItems(nil);
    FileView.Col3Title := L('Modified', 'แก้ไขล่าสุด');
    FileView.EmptyTitle := Sidebar.Items[I].Title;
    FileView.EmptyText := L('This device cannot be browsed yet, but it can send files to this PC', 'อุปกรณ์นี้ยังเปิดให้ดูไฟล์ไม่ได้ แต่ส่งไฟล์มาที่เครื่องนี้ได้');
    FileView.Invalidate;
  end
  else
    RequestListing;
  UpdateToolbar;
end;

procedure TFormMain.ShowMyShares;
var
  E: TRemoteEntries;
  V: TViewItems;
  I: Integer;
  Local: string;
begin
  if FCurPath = '' then
  begin
    FileView.Col3Title := L('Location on this PC', 'ตำแหน่งในเครื่องนี้');
    FileView.EmptyTitle := L('Nothing shared yet', 'ยังไม่ได้แชร์ไฟล์หรือโฟลเดอร์');
    FileView.EmptyText := L('Everything shared here is visible to every computer on the LAN — click "Share folder" or drop files here', 'สิ่งที่แชร์ที่นี่ทุกเครื่องในวง LAN เห็นได้ — กด "แชร์โฟลเดอร์" หรือลากไฟล์มาวาง');
    E := FShares.RootEntries(True);
  end
  else
  begin
    // inside a shared folder: show what the other machines see there
    FileView.Col3Title := L('Modified', 'แก้ไขล่าสุด');
    FileView.EmptyTitle := L('This folder is empty', 'โฟลเดอร์นี้ว่างเปล่า');
    FileView.EmptyText := L('Files you put in this folder are visible to other computers at once', 'ไฟล์ที่ใส่ในโฟลเดอร์นี้ เครื่องอื่นจะเห็นทันที');
    try
      if FShares.Resolve(FCurPath, Local) and DirectoryExists(Local) then
        E := ListLocalDir(Local)
      else
      begin
        FileView.SetItems(nil);
        FileView.ErrorText := L('This folder was deleted, moved or unshared', 'โฟลเดอร์นี้ถูกลบ ย้าย หรือเลิกแชร์แล้ว');
        FileView.Invalidate;
        Exit;
      end;
    except
      E := nil;
    end;
  end;
  SetLength(V, Length(E));
  for I := 0 to High(E) do
  begin
    V[I].Name := E[I].Name;
    V[I].IsDir := E[I].IsDir;
    V[I].Size := E[I].Size;
    V[I].Modified := E[I].Modified;
    V[I].LocalPath := E[I].LocalPath;
    if FCurPath = '' then
    begin
      V[I].Writable := E[I].Writable;
      if E[I].Writable then
        V[I].Info := L('Read & write  •  ', 'อ่านและเขียน  •  ') + E[I].LocalPath
      else if DirectoryExists(E[I].LocalPath) or FileExists(E[I].LocalPath) then
        V[I].Info := E[I].LocalPath
      else
        V[I].Info := L('Not found now: ', 'ไม่พบตอนนี้: ') + E[I].LocalPath;
      V[I].Shared := True;
    end
    else if E[I].Modified > 1 then
      V[I].Info := FormatDateTime('d mmm yyyy  hh:nn', E[I].Modified);
  end;
  FileView.SetItems(V);
end;

procedure TFormMain.RequestListing;
var
  I: Integer;
  B: TBrowseThread;
begin
  I := CurItem;
  FileView.Col3Title := L('Modified', 'แก้ไขล่าสุด');
  FileView.EmptyTitle := L('No files', 'ไม่มีไฟล์');
  if FCurPath = '' then
    FileView.EmptyText := L('This computer has not shared anything yet', 'เครื่องนี้ยังไม่ได้แชร์อะไร')
  else
    FileView.EmptyText := L('This folder is empty', 'โฟลเดอร์นี้ว่างเปล่า');
  FileView.SetItems(nil);
  FileView.IsLoading := True;
  FileView.Invalidate;
  Inc(FBrowseSeq);
  FCurWritable := False;
  B := TBrowseThread.Create(Sidebar.Items[I].IP, Sidebar.Items[I].Port, FMyName, FCurPath, FBrowseSeq,
    Pos('write', Sidebar.Items[I].Caps) > 0);
  B.OnDone := @BrowseDone;
  B.Start;
end;

procedure TFormMain.BrowseDone(B: TBrowseThread);
var
  V: TViewItems;
  I: Integer;
begin
  if FClosing or (B.Tag <> FBrowseSeq) then Exit;   // a newer request replaced this one
  if B.Error <> '' then
  begin
    FileView.SetItems(nil);
    FileView.ErrorText := B.Error;
    FileView.Invalidate;
    UpdateToolbar;
    Exit;
  end;
  SetLength(V, Length(B.Entries));
  for I := 0 to High(V) do
  begin
    V[I].Name := B.Entries[I].Name;
    V[I].IsDir := B.Entries[I].IsDir;
    V[I].Size := B.Entries[I].Size;
    V[I].Modified := B.Entries[I].Modified;
    if B.Entries[I].Modified > 1 then
      V[I].Info := FormatDateTime('d mmm yyyy  hh:nn', B.Entries[I].Modified)
    else
      V[I].Info := '';
    V[I].Shared := B.Path = '';
    V[I].Writable := B.Entries[I].Writable;
    if (B.Path = '') and B.Entries[I].Writable then
      V[I].Info := L('Read & write', 'อ่านและเขียน') + '  •  ' + V[I].Info;
  end;
  FCurWritable := B.Writable;
  FileView.SetItems(V);
  // say it once when entering the folder (not again after each refresh)
  if FCurWritable and (FHintedPath <> FCurPeer + '|' + FCurPath) then
    SetStatus(L('You can add, rename, delete and edit files in this folder', 'โฟลเดอร์นี้เพิ่ม เปลี่ยนชื่อ ลบ และแก้ไขไฟล์ได้'));
  if FCurWritable then FHintedPath := FCurPeer + '|' + FCurPath else FHintedPath := '';
  UpdateToolbar;
end;

{ ---------- sharing / sending / downloading ---------- }

procedure TFormMain.TrackThread(T: TNetThread);
begin
  T.OnTransfer := @NetTransfer;
  T.OnLog := @NetLog;
  T.Start;
end;

procedure TFormMain.AddShares(const Paths: array of string);
var
  I: Integer;
begin
  for I := 0 to High(Paths) do
    if FileExists(Paths[I]) or DirectoryExists(Paths[I]) then
      FShares.Add(ExcludeTrailingPathDelimiter(Paths[I]));
  SaveSettings;
  UpdateMeItem;
  if FCurPeer = ME_ID then ShowMyShares;
  SetStatus(Format(L('Shared %d more item(s)', 'แชร์เพิ่ม %d รายการ'), [Length(Paths)]));
end;

procedure TFormMain.SendPaths(const Paths: array of string);
var
  L: TStringList;
  Items: TSendItems;
  FileCount, I: Integer;
  Total: Int64;
begin
  I := CurItem;
  if (I < 0) or Sidebar.Items[I].IsMe or (Length(Paths) = 0) then Exit;
  L := TStringList.Create;
  try
    for FileCount := 0 to High(Paths) do L.Add(Paths[FileCount]);
    Screen.Cursor := crHourGlass;
    try
      BuildSendItems(L, Items, FileCount, Total);
    finally
      Screen.Cursor := crDefault;
    end;
  finally
    L.Free;
  end;
  if Length(Items) = 0 then Exit;
  TrackThread(TSendThread.Create(Sidebar.Items[I].IP, Sidebar.Items[I].Title,
    Sidebar.Items[I].Port, FMyName, Items));
end;

procedure TFormMain.DownloadSelected;
var
  Idx: TIntArray;
  P: TStringArray;
  I, K: Integer;
begin
  K := CurItem;
  if (K < 0) or Sidebar.Items[K].IsMe then Exit;
  Idx := FileView.SelectedIdx;
  if Length(Idx) = 0 then Exit;
  SetLength(P, Length(Idx));
  for I := 0 to High(Idx) do
    P[I] := JoinVPath(FCurPath, FileView.Item(Idx[I]).Name);
  TrackThread(TDownloadThread.Create(Sidebar.Items[K].IP, Sidebar.Items[K].Title,
    Sidebar.Items[K].Port, FMyName, P, FDownloadDir));
end;

{ ---------- UI events ---------- }

procedure TFormMain.FormDropFilesEvt(Sender: TObject; const FileNames: array of string);
begin
  if FDraggingOut then Exit;   // our own drag dropped back on the window
  if FCurPeer = ME_ID then
    AddShares(FileNames)
  else if CurCanWrite then
    UploadPaths(FileNames)        // straight into the folder shown
  else
    SendPaths(FileNames);
end;

procedure TFormMain.SidebarSelect(Sender: TObject);
begin
  if Sidebar.Selected >= 0 then
    Navigate(Sidebar.Items[Sidebar.Selected].ID, '');
end;

procedure TFormMain.SidebarPickDir(Sender: TObject);
var
  Dlg: TSelectDirectoryDialog;
begin
  Dlg := TSelectDirectoryDialog.Create(Self);
  try
    Dlg.Title := L('Choose the folder for received files', 'เลือกโฟลเดอร์สำหรับเก็บไฟล์ที่ได้รับ');
    Dlg.InitialDir := FDownloadDir;
    if Dlg.Execute then
    begin
      FDownloadDir := Dlg.FileName;
      Sidebar.DownloadDir := FDownloadDir;
      if FListen <> nil then FListen.DownloadDir := FDownloadDir;
      Sidebar.Invalidate;
      SaveSettings;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TFormMain.SidebarOpenDir(Sender: TObject);
begin
  ForceDirectories(FDownloadDir);
  OpenDocument(FDownloadDir);
end;

procedure TFormMain.SidebarToggleAuto(Sender: TObject);
begin
  FAutoAccept := Sidebar.AutoAccept;
  if FListen <> nil then FListen.AutoAccept := FAutoAccept;
  SaveSettings;
end;

procedure TFormMain.BtnAddPeerClick(Sender: TObject);
var
  S, IP, ID: string;
  P, Port: Integer;
begin
  S := '';
  if not ThemedInput(Self, L('Connect by IP', 'เชื่อมต่อด้วย IP'),
    L('IP address or name of a computer running LAN Share (a port may be added)', 'ใส่ IP หรือชื่อเครื่องที่เปิด LAN Share อยู่ (ระบุพอร์ตได้)'), S, L('e.g. 192.168.1.20 or 192.168.1.20:50505', 'เช่น 192.168.1.20 หรือ 192.168.1.20:50505')) then Exit;
  S := Trim(S);
  if S = '' then Exit;
  Port := DEFAULT_TCP_PORT;
  IP := S;
  P := Pos(':', S);
  if P > 0 then
  begin
    IP := Copy(S, 1, P - 1);
    Port := StrToIntDef(Copy(S, P + 1, 10), DEFAULT_TCP_PORT);
  end;
  ID := 'manual:' + IP + ':' + IntToStr(Port);
  NetPeer(nil, ID, IP, IP, Port, '', '', '', Default(TPeerIdent));
  SaveSettings;
  Navigate(ID, '');
end;

procedure TFormMain.BtnBackClick(Sender: TObject);
var
  E: TNavEntry;
begin
  if Length(FHistory) = 0 then Exit;
  E := FHistory[High(FHistory)];
  SetLength(FHistory, Length(FHistory) - 1);
  Navigate(E.PeerID, E.Path, False);
end;

procedure TFormMain.BtnUpClick(Sender: TObject);
begin
  if FCurPath <> '' then
    Navigate(FCurPeer, ParentVPath(FCurPath));
end;

procedure TFormMain.BtnRefreshClick(Sender: TObject);
begin
  if FDiscovery <> nil then FDiscovery.AnnounceNow;
  Navigate(FCurPeer, FCurPath, False);
end;

procedure TFormMain.PathBarSegment(Sender: TObject);
var
  Parts: TStringArray;
  P: string;
  I: Integer;
begin
  Parts := FCurPath.Split(['/']);
  P := '';
  for I := 0 to PathBar.Clicked - 1 do
    P := JoinVPath(P, Parts[I]);
  Navigate(FCurPeer, P);
end;

procedure TFormMain.BtnShareFileClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  A: array of string;
  I: Integer;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := L('Choose files to share', 'เลือกไฟล์ที่จะแชร์');
    Dlg.Options := Dlg.Options + [ofAllowMultiSelect, ofFileMustExist];
    if Dlg.Execute then
    begin
      SetLength(A, Dlg.Files.Count);
      for I := 0 to Dlg.Files.Count - 1 do A[I] := Dlg.Files[I];
      AddShares(A);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TFormMain.BtnShareFolderClick(Sender: TObject);
var
  Dlg: TSelectDirectoryDialog;
begin
  Dlg := TSelectDirectoryDialog.Create(Self);
  try
    Dlg.Title := L('Choose a folder to share with other computers', 'เลือกโฟลเดอร์ที่จะแชร์ให้เครื่องอื่นเปิดดู');
    if Dlg.Execute then AddShares([Dlg.FileName]);
  finally
    Dlg.Free;
  end;
end;

procedure TFormMain.BtnUnshareClick(Sender: TObject);
var
  Idx: TIntArray;
  I: Integer;
begin
  Idx := FileView.SelectedIdx;
  if Length(Idx) = 0 then Exit;
  for I := 0 to High(Idx) do
    FShares.Remove(FileView.Item(Idx[I]).LocalPath);
  SaveSettings;
  UpdateMeItem;
  ShowMyShares;
  SetStatus(Format(L('Unshared %d item(s) (the files themselves are kept)', 'เลิกแชร์ %d รายการ (ไฟล์จริงยังอยู่)'), [Length(Idx)]));
end;

procedure TFormMain.BtnOpenLocalClick(Sender: TObject);
var
  Local: string;
  Idx: TIntArray;
begin
  Idx := FileView.SelectedIdx;
  if Length(Idx) = 1 then
    OpenDocument(FileView.Item(Idx[0]).LocalPath)
  else if FShares.Resolve(FCurPath, Local) then
    OpenDocument(Local);
end;

procedure TFormMain.BtnSendFileClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  A: array of string;
  I: Integer;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := L('Choose files to send', 'เลือกไฟล์ที่จะส่ง');
    Dlg.Options := Dlg.Options + [ofAllowMultiSelect, ofFileMustExist];
    if Dlg.Execute then
    begin
      SetLength(A, Dlg.Files.Count);
      for I := 0 to Dlg.Files.Count - 1 do A[I] := Dlg.Files[I];
      SendPaths(A);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TFormMain.BtnSendFolderClick(Sender: TObject);
var
  Dlg: TSelectDirectoryDialog;
begin
  Dlg := TSelectDirectoryDialog.Create(Self);
  try
    Dlg.Title := L('Choose a folder to send', 'เลือกโฟลเดอร์ที่จะส่ง');
    if Dlg.Execute then SendPaths([Dlg.FileName]);
  finally
    Dlg.Free;
  end;
end;

procedure TFormMain.BtnDownloadClick(Sender: TObject);
begin
  DownloadSelected;
end;

procedure TFormMain.FileViewOpen(Sender: TObject);
var
  It: TViewItem;
begin
  if FileView.FocusIndex < 0 then Exit;
  It := FileView.Item(FileView.FocusIndex);
  if FCurPeer = ME_ID then
  begin
    if It.IsDir then
      Navigate(ME_ID, JoinVPath(FCurPath, It.Name))   // look inside our own share
    else
      OpenDocument(It.LocalPath);                     // open the file locally
  end
  else if It.IsDir then
    Navigate(FCurPeer, JoinVPath(FCurPath, It.Name))
  else if IsPreviewable(It.Name) then
    OpenPreview                      // .md pages, pictures, PDF, video: show them
  else
    DownloadSelected;                // other files: download
end;

procedure TFormMain.FileViewDragOut(Sender: TObject);
begin
  PrepareOut(False);
end;

procedure TFormMain.FileViewCopy(Sender: TObject);
begin
  if PrepareOut(True) then
    SetStatus(L('Copied — paste (Ctrl+V) in Explorer or any folder', 'คัดลอกแล้ว — กด "วาง" (Ctrl+V) ใน Explorer หรือโฟลเดอร์ที่ต้องการ'));
end;

{ drag (or copy to the clipboard) the selected rows, for Explorer / another program }
function TFormMain.PrepareOut(ToClipboard: Boolean): Boolean;
var
  Idx: TIntArray;
  I, K: Integer;
  Paths: array of string;
  Items, Files: TRemoteFiles;
  It: TViewItem;
  Err: string;
  Ok: Boolean;
begin
  Result := False;
  if not DragOutSupported then
  begin
    SetStatus(L('Dragging or copying files to other programs works on Windows only', 'การลาก/คัดลอกไฟล์ไปยังโปรแกรมอื่นใช้ได้บน Windows'), False);
    Exit;
  end;
  Idx := FileView.SelectedIdx;
  if Length(Idx) = 0 then Exit;
  FDraggingOut := not ToClipboard;
  try
    if FCurPeer = ME_ID then
    begin
      SetLength(Paths, Length(Idx));
      for I := 0 to High(Idx) do
        Paths[I] := FileView.Item(Idx[I]).LocalPath;
      if ToClipboard then Result := CopyLocalFiles(Paths)
      else Result := DragLocalFiles(Paths);
      Exit;
    end;
    K := CurItem;
    if (K < 0) or not Sidebar.Items[K].CanBrowse then Exit;
    SetLength(Items, Length(Idx));
    for I := 0 to High(Idx) do
    begin
      It := FileView.Item(Idx[I]);
      Items[I].RelPath := It.Name;
      Items[I].VPath := JoinVPath(FCurPath, It.Name);
      Items[I].IsDir := It.IsDir;
      Items[I].Size := It.Size;
      if It.Modified > 1 then Items[I].MTime := DateTimeToUnix(It.Modified, False)
      else Items[I].MTime := 0;
    end;
    // folders: ask the other PC for everything inside them first
    Screen.Cursor := crHourGlass;
    try
      Ok := RemoteDragList(Sidebar.Items[K].IP, Sidebar.Items[K].Port, Items, Files, Err);
    finally
      Screen.Cursor := crDefault;
    end;
    if not Ok then
    begin
      SetStatus(L('Cannot drag out: ', 'ลากออกไม่ได้: ') + Err, False);
      Exit;
    end;
    if ToClipboard then
      Result := CopyRemoteFiles(Sidebar.Items[K].IP, Sidebar.Items[K].Port, FMyName, Files)
    else
    begin
      Result := DragRemoteFiles(Sidebar.Items[K].IP, Sidebar.Items[K].Port, FMyName, Files);
      if Result then
        SetStatus(Format(L('Copied %d item(s) from %s', 'คัดลอก %d รายการจาก %s แล้ว'), [Length(Items), Sidebar.Items[K].Title]));
    end;
  finally
    FDraggingOut := False;
  end;
end;

procedure TFormMain.FileViewSelChange(Sender: TObject);
begin
  UpdateToolbar;
end;

procedure TFormMain.TransfersCancel(Sender: TObject);
var
  I, J: Integer;
begin
  // active members of the card are still alive (see NetTransfer)
  for I := 0 to FThreads.Count - 1 do
    for J := 0 to High(Transfers.CancelSerials) do
      if TNetThread(FThreads[I]).Serial = Transfers.CancelSerials[J] then
        TNetThread(FThreads[I]).Cancel;
end;

procedure TFormMain.TmrPeersTimer(Sender: TObject);
var
  I, J: Integer;
  AnyChange: Boolean;
  Now_: QWord;
begin
  AnyChange := False;
  Now_ := GetTickCount64;
  Transfers.Tick;
  // "ตามระบบ": follow a light/dark switch of the OS
  if (FTheme = thAuto) and (ResolveTheme(thAuto) <> FShownTheme) then ApplyTheme;
  for I := High(Sidebar.Items) downto 0 do
    with Sidebar.Items[I] do
    begin
      if IsMe or (LastSeen = 0) then Continue;
      if Online and (Now_ - LastSeen > 12000) then
      begin
        Online := Manual;     // manual entries stay usable (no broadcasts may reach us)
        AnyChange := True;
      end;
      if (not Manual) and (Now_ - LastSeen > 90000) and (ID <> FCurPeer) then
      begin
        Delete(Sidebar.Items, I, 1);
        if Sidebar.Selected > I then Dec(Sidebar.Selected);
        AnyChange := True;
      end;
    end;
  // end of a refresh: computers that did not announce since are gone
  // (each one announces every 3 s; 7 s allows one lost packet)
  if (FRefreshAt > 0) and (Now_ - FRefreshAt >= 7000) then
  begin
    J := 0;
    for I := 0 to High(Sidebar.Items) do
      with Sidebar.Items[I] do
        if not IsMe then
        begin
          if Online and (not Manual) and (LastSeen < FRefreshAt) then Online := False;
          if Online then Inc(J);
        end;
    FRefreshAt := 0;
    Sidebar.Refreshing := False;
    SetStatus(Format(L('%d computer(s) online', 'ออนไลน์ %d เครื่อง'), [J]));
    AnyChange := True;
  end;
  if AnyChange then
  begin
    Sidebar.Invalidate;
    UpdateHeader;
    UpdateToolbar;
  end;
end;

{ ---------- identity / preview ---------- }

procedure TFormMain.ApplyIdentity;
begin
  if FListen <> nil then
  begin
    FListen.MyName := FMyName;
    FListen.MyIcon := FMyIcon;
  end;
  if FDiscovery <> nil then
  begin
    FDiscovery.SetIdentity(FMyName, FMyIcon);
    FDiscovery.AnnounceNow;   // others update their sidebar right away
  end;
  UpdateMeItem;
  UpdateHeader;
  if FCurPeer = ME_ID then Navigate(ME_ID, FCurPath, False);
end;

procedure InvalidateTree(C: TWinControl);
var
  I: Integer;
begin
  C.Invalidate;
  for I := 0 to C.ControlCount - 1 do
    if C.Controls[I] is TWinControl then
      InvalidateTree(TWinControl(C.Controls[I]))
    else
      C.Controls[I].Invalidate;
end;

{ the window handle may be (re)created after the constructor: theme its title bar each time }
procedure TFormMain.CreateWnd;
begin
  inherited CreateWnd;
  ApplyWindowTheme(Self);
end;

procedure TFormMain.ApplyTheme;
begin
  SetTheme(FTheme);
  FShownTheme := ResolveTheme(FTheme);
  Color := BGRAToColor(clBg);
  ApplyWindowTheme(Self);   // title bar in the theme (also done in CreateWnd)
  InvalidateTree(Self);
  if FListen <> nil then FListen.ThemeCss := UITheme.ThemeCss;   // phones follow the theme
end;

procedure TFormMain.BtnSettingsClick(Sender: TObject);
var
  N, Ic, OldName: string;
  Th: TThemeKind;
  Lg: TLang;
  SH: Boolean;
begin
  N := FMyName;
  OldName := FMyName;
  Ic := FMyIcon;
  Th := FTheme;
  Lg := Lang;
  SH := FSendHost;
  if EditIdentity(Self, N, Ic, Th, Lg, SH, FHostName) then
  begin
    FSendHost := SH;
    ApplyMachine;   // sent with the next announcement (ApplyIdentity below)
    if Lg <> Lang then
    begin
      Lang := Lg;
      ApplyTexts;
      if FListen <> nil then
      begin
        FListen.ThemesJson := UITheme.ThemesJson;   // theme names for phones
        FListen.Lang := LANG_CODES[Lang];
      end;
      if FCurPeer = ME_ID then Navigate(ME_ID, FCurPath, False) else UpdateToolbar;
      InvalidateTree(Self);
    end;
    FMyName := N;
    FMyIcon := Ic;
    if Th <> FTheme then
    begin
      FTheme := Th;
      ApplyTheme;
    end;
    SaveSettings;
    ApplyIdentity;
    if (FMyName <> OldName) and (FMyName <> '') then
      SetStatus(L('Other computers will see the name "', 'เครื่องอื่นจะเห็นชื่อ "') + FMyName + '"');
  end;
end;

{ Shows the selected file (or the current folder with its README/index.md)
  in the browser, served by the machine that shares it. }
procedure TFormMain.OpenPreview;
var
  K: Integer;
  Host, Path: string;
  Idx: TIntArray;
begin
  K := CurItem;
  if K < 0 then Exit;
  if Sidebar.Items[K].IsMe then
    Host := Format('http://127.0.0.1:%d', [FTcpPort])
  else
    Host := Format('http://%s:%d', [Sidebar.Items[K].IP, Sidebar.Items[K].Port]);
  Idx := FileView.SelectedIdx;
  if (Length(Idx) = 1) and not FileView.Item(Idx[0]).IsDir then
  begin
    Path := JoinVPath(FCurPath, FileView.Item(Idx[0]).Name);
    OpenURL(Host + '/view?path=' + UrlEncode(Path));
  end
  else
  begin
    Path := FCurPath;
    if (Length(Idx) = 1) then Path := JoinVPath(FCurPath, FileView.Item(Idx[0]).Name);
    OpenURL(Host + '/#' + UrlEncode(Path));
  end;
end;

procedure TFormMain.BtnPreviewClick(Sender: TObject);
begin
  OpenPreview;
end;

{ ---------- network callbacks (main thread, via Synchronize) ---------- }

procedure TFormMain.NetLog(Sender: TObject; const Msg: string);
begin
  if FClosing then Exit;
  SetStatus(Msg, (Pos('failed', Msg) = 0) and (Pos('ไม่สำเร็จ', Msg) = 0));
end;

procedure TFormMain.NetTransfer(const T: TTransferInfo);
var
  I: Integer;
begin
  if FClosing then Exit;
  if FThreads.IndexOf(T.Thread) < 0 then
  begin
    if IsActiveState(T.State) then FThreads.Add(T.Thread);
  end
  else if not IsActiveState(T.State) then
    FThreads.Remove(T.Thread);   // the thread frees itself right after this call
  Transfers.UpdateFrom(T);
  // a file opened for editing has arrived (or could not be fetched)
  for I := 0 to High(FEdits) do
    if (not FEdits[I].Ready) and (FEdits[I].Serial = T.Serial) then
    begin
      if T.State = tsDone then
        EditArrived(I)
      else if not IsActiveState(T.State) then
      begin
        SetStatus(L('Cannot open for editing: ', 'เปิดเพื่อแก้ไขไม่ได้: ') + T.Msg, False);
        Delete(FEdits, I, 1);
      end;
      Break;
    end;
  // new files arrived in a folder we are looking at
  if (T.State = tsDone) and (T.Kind = tkReceive) and (FCurPeer = ME_ID) and (FCurPath <> '') then
    ShowMyShares;
  // refresh our own share list view when a download into the receive folder finishes
  if (T.State = tsDone) and (T.Kind = tkDownload) then
    SetStatus(Format(L('Downloaded %s → folder %s', 'ดาวน์โหลด %s เสร็จแล้ว → โฟลเดอร์ %s'),
      [T.Title, ExtractFileName(ExcludeTrailingPathDelimiter(FDownloadDir))]));
end;

function TFormMain.NetAsk(Sender: TObject; const FromName, FromIP: string;
  FileCount: Integer; TotalBytes: Int64): Boolean;
begin
  if FClosing then Exit(False);
  Application.Restore;
  Application.BringToFront;
  Result := ThemedAsk(Self, dkQuestion, L('Incoming files', 'มีไฟล์ส่งมาถึงคุณ'),
    Format(L('%s wants to send you %d file(s), %s', '%s ต้องการส่ง %d ไฟล์ ขนาด %s') + #10#10 +
           L('They will be saved in: %s', 'จะบันทึกไว้ที่: %s'),
      [Who(FromName, FromIP), FileCount, FormatBytes(TotalBytes), FDownloadDir]),
    L('Accept', 'รับไฟล์'), L('Decline', 'ปฏิเสธ'));
end;

procedure TFormMain.NetPeer(Sender: TObject; const ID, PeerName, IP: string; Port: Integer;
  const OS, Caps, PeerIcon: string; const Ident: TPeerIdent);
var
  I, J, K: Integer;
  IsNew: Boolean;
  LastName: string;

  function SameMachine(const It: TSideItem): Boolean;
  begin
    Result := (Ident.Machine <> '') and (It.Machine = Ident.Machine) and (It.Port = Port);
  end;

  function SameAddress(const It: TSideItem): Boolean;
  begin
    // the same address but a different known machine is another computer
    Result := (It.IP = IP) and (It.Port = Port) and
      ((Ident.Machine = '') or (It.Machine = '') or (It.Machine = Ident.Machine));
  end;

begin
  if FClosing then Exit;
  I := PeerIndex(ID);
  // A row we already have for this computer: the same machine code (even if
  // it was renamed or changed address), else the same address and port (the
  // program restarted with a new id, or the machine was added by hand).
  // Take over that row instead of adding one.
  if I < 0 then
    for K := 0 to 1 do
    begin
      for J := 0 to High(Sidebar.Items) do
        if (not Sidebar.Items[J].IsMe) and
           (((K = 0) and SameMachine(Sidebar.Items[J])) or ((K = 1) and SameAddress(Sidebar.Items[J]))) then
        begin
          I := J;
          Break;
        end;
      if I >= 0 then Break;
    end;
  if (I >= 0) and (Sender <> nil) and (Sidebar.Items[I].ID <> ID) then
  begin
    if FCurPeer = Sidebar.Items[I].ID then FCurPeer := ID;
    for K := 0 to High(FHistory) do
      if FHistory[K].PeerID = Sidebar.Items[I].ID then FHistory[K].PeerID := ID;
    if not Sidebar.Items[I].Manual then Sidebar.Items[I].ID := ID;
  end;
  IsNew := I < 0;
  if IsNew then
  begin
    SetLength(Sidebar.Items, Length(Sidebar.Items) + 1);
    I := High(Sidebar.Items);
    Sidebar.Items[I] := Default(TSideItem);
    Sidebar.Items[I].ID := ID;
    Sidebar.Items[I].Manual := Sender = nil;
  end;
  if (Sender <> nil) or IsNew then
    if PeerName <> '' then
      Sidebar.Items[I].Title := PeerName
    else
      Sidebar.Items[I].Title := IP;   // no name set by its owner
  Sidebar.Items[I].IP := IP;
  Sidebar.Items[I].Port := Port;
  if OS <> '' then Sidebar.Items[I].OS := OS;
  if PeerIcon <> '' then Sidebar.Items[I].Icon := PeerIcon;
  if (Sender <> nil) and (FKnown.IndexOf(IP) < 0) then
  begin
    FKnown.Insert(0, IP);
    while FKnown.Count > 32 do FKnown.Delete(FKnown.Count - 1);
  end;
  if Caps <> '' then Sidebar.Items[I].Caps := Caps;
  // manual entries (no caps known) are assumed to be LAN Share PCs
  Sidebar.Items[I].CanBrowse := (Sidebar.Items[I].Caps = '') or
    (Pos('bin', Sidebar.Items[I].Caps) > 0);
  Sidebar.Items[I].Online := True;
  Sidebar.Items[I].LastSeen := GetTickCount64;
  // identity
  if Ident.Machine <> '' then
  begin
    Sidebar.Items[I].Host := Ident.Host;
    Sidebar.Items[I].User := Ident.User;
    Sidebar.Items[I].Machine := Ident.Machine;
    Sidebar.Items[I].Version := Ident.Version;
  end;
  if Sidebar.Items[I].FirstSeenAt = 0 then Sidebar.Items[I].FirstSeenAt := Now;
  if Sender <> nil then
  begin
    Sidebar.Items[I].LastSeenAt := Now;
    // names it has used (renamed computers keep one row)
    LastName := Trim(Sidebar.Items[I].Names);
    if Pos(#10, LastName) > 0 then
      LastName := Copy(LastName, LastDelimiter(#10, LastName) + 1, MaxInt);
    if (PeerName <> '') and (PeerName <> LastName) then
      Sidebar.Items[I].Names := Sidebar.Items[I].Names + PeerName + #10;
  end;
  Sidebar.Invalidate;
  if IsNew and (Sender <> nil) then
    if PeerName <> '' then
      SetStatus(Format(L('Found %s (%s)', 'พบเครื่อง %s (%s)'), [PeerName, IP]))
    else
      SetStatus(L('Found ', 'พบเครื่อง ') + IP);
  UpdateHeader;
  if Sidebar.Items[I].ID = FCurPeer then UpdateToolbar;
end;

{ ---------- refresh and right-click menus ---------- }

{ which name/user to send: the machine code is always sent (rows are matched by it) }
procedure TFormMain.ApplyMachine;
begin
  if FDiscovery = nil then Exit;
  if FSendHost then
    FDiscovery.SetMachine(FHostName, FMyUser, FMyMachine)
  else
    FDiscovery.SetMachine('', '', FMyMachine);
end;

{ A second copy on this PC (opened again on another port) keeps its own
  settings file, so the two copies never overwrite each other's shares. It
  starts with the first copy's settings but no shares of its own. }
procedure TFormMain.UseInstanceIni(APort: Integer);
var
  OwnIni, S: string;
  Ini: TIniFile;
  P: TStringArray;
  I, N: Integer;
begin
  OwnIni := ChangeFileExt(FIniName, '') + '-' + IntToStr(APort) + '.ini';
  P := FShares.Paths;
  for I := 0 to High(P) do
    FShares.Remove(P[I]);
  if FileExists(OwnIni) then
  begin
    Ini := TIniFile.Create(OwnIni);
    try
      N := Ini.ReadInteger('Shares', 'Count', 0);
      for I := 0 to N - 1 do
      begin
        S := Ini.ReadString('Shares', 'Item' + IntToStr(I), '');
        if S <> '' then
        begin
          FShares.Add(S);
          if Ini.ReadBool('Shares', 'Write' + IntToStr(I), False) then FShares.SetWritable(S, True);
        end;
      end;
    finally
      Ini.Free;
    end;
  end;
  FIniName := OwnIni;
  SaveSettings;
end;

procedure TFormMain.RefreshPeers;
begin
  if FDiscovery <> nil then FDiscovery.RescanNow;
  FRefreshAt := GetTickCount64;
  Sidebar.Refreshing := True;
  Sidebar.Invalidate;
  SetStatus(L('Looking for computers...', 'กำลังค้นหาเครื่อง...'));
end;

procedure TFormMain.SidebarRefresh(Sender: TObject);
begin
  RefreshPeers;
end;

function TFormMain.MenuPeerIndex: Integer;
begin
  Result := PeerIndex(FMenuPeer);
end;

procedure TFormMain.MnuPeerOpen(Sender: TObject);
var
  I: Integer;
begin
  I := MenuPeerIndex;
  if I < 0 then Exit;
  Sidebar.Selected := I;
  Sidebar.Invalidate;
  SidebarSelect(Sidebar);
end;

procedure TFormMain.MnuPeerIdentity(Sender: TObject);
var
  I: Integer;
begin
  I := MenuPeerIndex;
  if I >= 0 then ShowPeerIdentity(I, Mouse.CursorPos);
end;

procedure TFormMain.MnuPeerCopyIP(Sender: TObject);
var
  I: Integer;
begin
  I := MenuPeerIndex;
  if I < 0 then Exit;
  if Sidebar.Items[I].IsMe then Clipboard.AsText := FWebHost
  else Clipboard.AsText := Sidebar.Items[I].IP;
  SetStatus(L('IP address copied', 'คัดลอก IP แล้ว'));
end;

procedure TFormMain.MnuPeerWeb(Sender: TObject);
var
  I: Integer;
begin
  I := MenuPeerIndex;
  if I < 0 then Exit;
  if Sidebar.Items[I].IsMe then
    OpenURL(Format('http://127.0.0.1:%d/', [FTcpPort]))
  else
    OpenURL(Format('http://%s:%d/', [Sidebar.Items[I].IP, Sidebar.Items[I].Port]));
end;

procedure TFormMain.MnuPeerRemove(Sender: TObject);
var
  I: Integer;
  WasCur: Boolean;
begin
  I := MenuPeerIndex;
  if (I < 0) or Sidebar.Items[I].IsMe then Exit;
  WasCur := Sidebar.Items[I].ID = FCurPeer;
  Delete(Sidebar.Items, I, 1);
  if Sidebar.Selected > I then Dec(Sidebar.Selected)
  else if Sidebar.Selected = I then Sidebar.Selected := -1;
  SaveSettings;            // computers added by IP are kept in the settings
  if WasCur then Navigate(ME_ID, '', False);
  Sidebar.Invalidate;
  UpdateHeader;
end;

{ right click on the computer list: on a row, or on the empty part (-1) }
procedure TFormMain.SidebarContext(Sender: TObject; Index: Integer; const ScreenPt: TPoint);
var
  M: TMenuEntries;
  It: TSideItem;
  HasWeb: Boolean;
begin
  M := nil;
  if Index >= 0 then
  begin
    It := Sidebar.Items[Index];
    FMenuPeer := It.ID;
    HasWeb := It.IsMe or (It.Caps = '') or (Pos('http', It.Caps) > 0);
    AddEntry(M, MenuItem(L('Open', 'เปิด'), ikFolderOpen, @MnuPeerOpen));
    AddEntry(M, MenuItem(L('Identity...', 'ตัวตนของเครื่อง...'), ikComputer, @MnuPeerIdentity));
    AddEntry(M, MenuSep);
    AddEntry(M, MenuItem(L('Copy IP address', 'คัดลอก IP'), ikNetwork, @MnuPeerCopyIP));
    AddEntry(M, MenuItem(L('Open web page', 'เปิดหน้าเว็บ'), ikEye, @MnuPeerWeb, HasWeb and (It.IsMe or It.Online)));
    if (not It.IsMe) and (It.Manual or not It.Online) then
      AddEntry(M, MenuItem(L('Remove from list', 'ลบออกจากรายการ'), ikTrash, @MnuPeerRemove));
    AddEntry(M, MenuSep);
  end;
  AddEntry(M, MenuItem(L('Refresh list', 'รีเฟรชรายการเครื่อง'), ikRefresh, @SidebarRefresh));
  AddEntry(M, MenuItem(L('Connect by IP...', 'เชื่อมต่อด้วย IP...'), ikPlus, @BtnAddPeerClick));
  ShowThemedMenu(Self, ScreenPt, M);
end;

{ right click on the file list (the row under the mouse is already selected) }
procedure TFormMain.FileViewContext(Sender: TObject; const ScreenPt: TPoint);
var
  M: TMenuEntries;
  N: Integer;
  It: TViewItem;
  OneFile, MyRootDir: Boolean;

  procedure Mirror(B: TFlatButton; AIcon: TIconKind; AClick: TNotifyEvent);
  begin
    if B.Visible then AddEntry(M, MenuItem(B.Caption, AIcon, AClick, B.Enabled));
  end;

begin
  M := nil;
  N := FileView.SelCount;
  OneFile := False;
  MyRootDir := False;
  if (N = 1) and (FileView.FocusIndex >= 0) then
  begin
    It := FileView.Item(FileView.FocusIndex);
    OneFile := not It.IsDir;
    MyRootDir := (FCurPeer = ME_ID) and (FCurPath = '') and It.IsDir and DirectoryExists(It.LocalPath);
    AddEntry(M, MenuItem(L('Open', 'เปิด'), ikFolderOpen, @FileViewOpen, True, 'Enter'));
  end;
  Mirror(BtnPreview, ikEye, @BtnPreviewClick);
  Mirror(BtnOpenLocal, ikFolderOpen, @BtnOpenLocalClick);
  if CurCanWrite and OneFile then
    AddEntry(M, MenuItem(L('Edit', 'แก้ไข'), ikEdit, @MnuEdit));
  Mirror(BtnDownload, ikDownload, @BtnDownloadClick);
  if N > 0 then
    AddEntry(M, MenuItem(L('Copy', 'คัดลอก'), ikFilePlus, @FileViewCopy, DragOutSupported, 'Ctrl+C'));
  AddEntry(M, MenuSep);
  if CurCanWrite then
  begin
    Mirror(BtnUpload, ikUpload, @BtnUploadClick);
    AddEntry(M, MenuItem(L('Upload folder...', 'อัปโหลดโฟลเดอร์...'), ikFolderPlus, @MnuUploadFolder, BtnUpload.Enabled));
    Mirror(BtnNewFolder, ikFolderPlus, @BtnNewFolderClick);
    AddEntry(M, MenuItem(L('Rename', 'เปลี่ยนชื่อ'), ikEdit, @FileViewRename, N = 1, 'F2'));
    AddEntry(M, MenuItem(L('Delete', 'ลบ'), ikTrash, @FileViewDelete, N > 0, 'Del'));
    AddEntry(M, MenuSep);
  end;
  if MyRootDir then
  begin
    AddEntry(M, MenuCheck(L('Others can edit (Read + Write)', 'ให้เครื่องอื่นแก้ไขได้ (อ่าน + เขียน)'),
      ikEdit, @MnuToggleWrite, FShares.IsWritable(It.LocalPath)));
    AddEntry(M, MenuSep);
  end;
  Mirror(BtnShareFile, ikFilePlus, @BtnShareFileClick);
  Mirror(BtnShareFolder, ikFolderPlus, @BtnShareFolderClick);
  Mirror(BtnUnshare, ikTrash, @BtnUnshareClick);
  Mirror(BtnSendFile, ikUpload, @BtnSendFileClick);
  Mirror(BtnSendFolder, ikFolderPlus, @BtnSendFolderClick);
  AddEntry(M, MenuSep);
  AddEntry(M, MenuCheck(L('Details', 'รายละเอียด'), ikViewDetails, @MnuViewDetails, FViewMode = vmDetails));
  AddEntry(M, MenuCheck(L('List', 'รายการ'), ikViewList, @MnuViewList, FViewMode = vmList));
  AddEntry(M, MenuCheck(L('Icons', 'ไอคอน'), ikViewIcons, @MnuViewIcons, FViewMode = vmIcons));
  AddEntry(M, MenuSep);
  AddEntry(M, MenuItem(L('Refresh', 'รีเฟรช'), ikRefresh, @BtnRefreshClick, True, 'F5'));
  ShowThemedMenu(Self, ScreenPt, M);
end;

{ ---------- view mode ---------- }

procedure TFormMain.SetViewMode(M: TViewMode);
begin
  FViewMode := M;
  FileView.ViewMode := M;
  case M of
    vmList:  BtnView.Icon := ikViewList;
    vmIcons: BtnView.Icon := ikViewIcons;
  else
    BtnView.Icon := ikViewDetails;
  end;
  BtnView.Invalidate;
end;

procedure TFormMain.BtnViewClick(Sender: TObject);
var
  M: TMenuEntries;
begin
  M := nil;
  AddEntry(M, MenuCheck(L('Details', 'รายละเอียด'), ikViewDetails, @MnuViewDetails, FViewMode = vmDetails));
  AddEntry(M, MenuCheck(L('List', 'รายการ'), ikViewList, @MnuViewList, FViewMode = vmList));
  AddEntry(M, MenuCheck(L('Icons', 'ไอคอน'), ikViewIcons, @MnuViewIcons, FViewMode = vmIcons));
  ShowThemedMenu(Self, BtnView.ClientToScreen(Point(0, BtnView.Height + ScI(4))), M);
end;

procedure TFormMain.MnuViewDetails(Sender: TObject);
begin
  SetViewMode(vmDetails);
  SaveSettings;
end;

procedure TFormMain.MnuViewList(Sender: TObject);
begin
  SetViewMode(vmList);
  SaveSettings;
end;

procedure TFormMain.MnuViewIcons(Sender: TObject);
begin
  SetViewMode(vmIcons);
  SaveSettings;
end;

{ ---------- Read + Write folders ---------- }

{ this PC's own share: let others change it (asks before allowing) }
procedure TFormMain.MnuToggleWrite(Sender: TObject);
var
  It: TViewItem;
  W: Boolean;
begin
  if (FCurPeer <> ME_ID) or (FCurPath <> '') or (FileView.FocusIndex < 0) then Exit;
  It := FileView.Item(FileView.FocusIndex);
  if not It.IsDir then Exit;
  W := not FShares.IsWritable(It.LocalPath);
  if W and not ThemedAsk(Self, dkWarning, L('Let others edit this folder?', 'ให้เครื่องอื่นแก้ไขโฟลเดอร์นี้?'),
    Format(L('Everyone on this network will be able to add, rename, delete and change files in "%s".',
      'ทุกเครื่องในเครือข่ายนี้จะเพิ่ม เปลี่ยนชื่อ ลบ และแก้ไขไฟล์ใน "%s" ได้') + #10#10 +
      L('Deleted files go to the Recycle Bin of this PC.', 'ไฟล์ที่ถูกลบจะอยู่ในถังขยะของเครื่องนี้'), [It.Name]),
    L('Allow editing', 'อนุญาตให้แก้ไข'), L('Cancel', 'ยกเลิก')) then Exit;
  FShares.SetWritable(It.LocalPath, W);
  SaveSettings;
  ShowMyShares;
  if W then
    SetStatus(Format(L('"%s" is Read + Write: others can change it', '"%s" อ่านและเขียนได้: เครื่องอื่นแก้ไขได้'), [It.Name]))
  else
    SetStatus(Format(L('"%s" is read only again', '"%s" กลับเป็นอ่านอย่างเดียว'), [It.Name]));
end;

{ the folder shown belongs to another computer and accepts changes }
function TFormMain.CurCanWrite: Boolean;
var
  I: Integer;
begin
  I := CurItem;
  Result := (FCurPeer <> ME_ID) and (FCurPath <> '') and FCurWritable and (I >= 0) and
    Sidebar.Items[I].Online;
end;

procedure TFormMain.StartWriteOp(Op: Byte; const Paths: TStringArray; const NewName: string);
var
  K: Integer;
  T: TWriteThread;
begin
  K := CurItem;
  if (K < 0) or not CurCanWrite then Exit;
  T := TWriteThread.CreateOp(Sidebar.Items[K].IP, Sidebar.Items[K].Title, Sidebar.Items[K].Port,
    FMyName, Op, Paths, NewName);
  T.Tag := FCurPeer;
  T.OnDone := @WriteDone;
  T.Start;   // quick: no transfer card
end;

procedure TFormMain.WriteDone(T: TWriteThread);
begin
  if FClosing then Exit;
  if T.Ok then
    case T.Op of
      OP_MKDIR:  SetStatus(Format(L('Created folder %s', 'สร้างโฟลเดอร์ %s แล้ว'), [LastSegOf(T.Paths[0])]));
      OP_DELETE: SetStatus(Format(L('Deleted %d item(s) — they are in the Recycle Bin of %s',
                   'ลบ %d รายการแล้ว — อยู่ในถังขยะของ %s'), [Length(T.Paths), T.PeerName]));
      OP_RENAME: SetStatus(L('Renamed', 'เปลี่ยนชื่อแล้ว'));
      OP_UPLOAD: SetStatus(Format(L('Uploaded %s to %s', 'อัปโหลด %s ไปยัง %s แล้ว'), [T.Title, T.PeerName]));
    end
  else
    SetStatus(L('Not done: ', 'ทำไม่สำเร็จ: ') + T.Error, False);
  if T.Tag = FCurPeer then Navigate(FCurPeer, FCurPath, False);   // show the change
end;

procedure TFormMain.UploadPaths(const Paths: array of string);
var
  K, FC, I: Integer;
  SL: TStringList;
  Items: TSendItems;
  Tot: Int64;
  T: TWriteThread;
begin
  K := CurItem;
  if (K < 0) or not CurCanWrite or (Length(Paths) = 0) then Exit;
  SL := TStringList.Create;
  try
    for I := 0 to High(Paths) do SL.Add(Paths[I]);
    Screen.Cursor := crHourGlass;
    try
      BuildSendItems(SL, Items, FC, Tot);
    finally
      Screen.Cursor := crDefault;
    end;
  finally
    SL.Free;
  end;
  if Length(Items) = 0 then Exit;
  T := TWriteThread.CreateUpload(Sidebar.Items[K].IP, Sidebar.Items[K].Title, Sidebar.Items[K].Port,
    FMyName, FCurPath, Items);
  T.Tag := FCurPeer;
  T.OnDone := @WriteDone;
  TrackThread(T);    // with a transfer card
end;

procedure TFormMain.BtnUploadClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  A: array of string;
  I: Integer;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := L('Choose files to add to this folder', 'เลือกไฟล์ที่จะเพิ่มลงในโฟลเดอร์นี้');
    Dlg.Options := Dlg.Options + [ofAllowMultiSelect, ofFileMustExist];
    if Dlg.Execute then
    begin
      SetLength(A, Dlg.Files.Count);
      for I := 0 to Dlg.Files.Count - 1 do A[I] := Dlg.Files[I];
      UploadPaths(A);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TFormMain.MnuUploadFolder(Sender: TObject);
var
  Dlg: TSelectDirectoryDialog;
begin
  Dlg := TSelectDirectoryDialog.Create(Self);
  try
    Dlg.Title := L('Choose a folder to add to this folder', 'เลือกโฟลเดอร์ที่จะเพิ่มลงในโฟลเดอร์นี้');
    if Dlg.Execute then UploadPaths([Dlg.FileName]);
  finally
    Dlg.Free;
  end;
end;

procedure TFormMain.BtnNewFolderClick(Sender: TObject);
var
  N: string;
  P: TStringArray;
begin
  if not CurCanWrite then Exit;
  N := L('New folder', 'โฟลเดอร์ใหม่');
  if not ThemedInput(Self, L('New folder', 'โฟลเดอร์ใหม่'), L('Name of the new folder', 'ชื่อโฟลเดอร์ใหม่'), N) then Exit;
  N := Trim(N);
  if not ValidNewName(N) then
  begin
    SetStatus(L('This name cannot be used', 'ใช้ชื่อนี้ไม่ได้'), False);
    Exit;
  end;
  SetLength(P, 1);
  P[0] := JoinVPath(FCurPath, N);
  StartWriteOp(OP_MKDIR, P);
end;

procedure TFormMain.FileViewRename(Sender: TObject);
var
  It: TViewItem;
  N: string;
  P: TStringArray;
begin
  if not CurCanWrite or (FileView.SelCount <> 1) or (FileView.FocusIndex < 0) then Exit;
  It := FileView.Item(FileView.FocusIndex);
  N := It.Name;
  if not ThemedInput(Self, L('Rename', 'เปลี่ยนชื่อ'), L('New name', 'ชื่อใหม่'), N) then Exit;
  N := Trim(N);
  if (N = It.Name) or (N = '') then Exit;
  if not ValidNewName(N) then
  begin
    SetStatus(L('This name cannot be used', 'ใช้ชื่อนี้ไม่ได้'), False);
    Exit;
  end;
  SetLength(P, 1);
  P[0] := JoinVPath(FCurPath, It.Name);
  StartWriteOp(OP_RENAME, P, N);
end;

procedure TFormMain.FileViewDelete(Sender: TObject);
var
  Idx: TIntArray;
  P: TStringArray;
  I, K: Integer;
begin
  // this PC's list of shares: Delete = unshare (the files stay)
  if (FCurPeer = ME_ID) and (FCurPath = '') then
  begin
    BtnUnshareClick(nil);
    Exit;
  end;
  if not CurCanWrite then Exit;
  Idx := FileView.SelectedIdx;
  if Length(Idx) = 0 then Exit;
  K := CurItem;
  if not ThemedAsk(Self, dkWarning, Format(L('Delete %d item(s)?', 'ลบ %d รายการ?'), [Length(Idx)]),
    Format(L('They are removed from %s and go to the Recycle Bin of that computer.',
      'รายการจะถูกลบออกจาก %s และไปอยู่ในถังขยะของเครื่องนั้น'), [Sidebar.Items[K].Title]),
    L('Delete', 'ลบ'), L('Cancel', 'ยกเลิก')) then Exit;
  SetLength(P, Length(Idx));
  for I := 0 to High(Idx) do
    P[I] := JoinVPath(FCurPath, FileView.Item(Idx[I]).Name);
  StartWriteOp(OP_DELETE, P);
end;

{ ---------- edit a file of another computer ---------- }

{ Fetches the file into a temp folder and opens it in its usual program;
  each time it is saved there, it is copied back (TmrEditTimer). }
procedure TFormMain.MnuEdit(Sender: TObject);
var
  K: Integer;
  It: TViewItem;
  E: TEditSession;
  P: TStringArray;
  T: TDownloadThread;
begin
  K := CurItem;
  if not CurCanWrite or (FileView.SelCount <> 1) or (FileView.FocusIndex < 0) then Exit;
  It := FileView.Item(FileView.FocusIndex);
  if It.IsDir then Exit;
  E := Default(TEditSession);
  E.PeerID := FCurPeer;
  E.IP := Sidebar.Items[K].IP;
  E.Port := Sidebar.Items[K].Port;
  E.PeerTitle := Sidebar.Items[K].Title;
  E.VPath := JoinVPath(FCurPath, It.Name);
  E.Dir := EditRoot + FormatDateTime('yyyymmdd-hhnnsszzz', Now) + PathDelim;
  ForceDirectories(E.Dir);
  SetLength(P, 1);
  P[0] := E.VPath;
  T := TDownloadThread.Create(E.IP, E.PeerTitle, E.Port, FMyName, P, E.Dir);
  E.Serial := T.Serial;
  SetLength(FEdits, Length(FEdits) + 1);
  FEdits[High(FEdits)] := E;
  SetStatus(Format(L('Opening %s for editing...', 'กำลังเปิด %s เพื่อแก้ไข...'), [It.Name]));
  TrackThread(T);
end;

procedure TFormMain.EditArrived(I: Integer);
var
  SR: TSearchRec;
begin
  FEdits[I].LocalFile := '';
  if FindFirst(FEdits[I].Dir + AllFilesMask, faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Attr and faDirectory) = 0 then
      begin
        FEdits[I].LocalFile := FEdits[I].Dir + SR.Name;
        Break;
      end;
    until FindNext(SR) <> 0;
    SysUtils.FindClose(SR);
  end;
  if FEdits[I].LocalFile = '' then
  begin
    Delete(FEdits, I, 1);
    Exit;
  end;
  FEdits[I].Ready := True;
  FEdits[I].Stamp := FileAge(FEdits[I].LocalFile);
  FEdits[I].Pending := FEdits[I].Stamp;
  OpenDocument(FEdits[I].LocalFile);
  SetStatus(Format(L('Editing %s — each time you save it, it is copied back to %s',
    'กำลังแก้ไข %s — ทุกครั้งที่บันทึก จะคัดลอกกลับไปที่ %s'),
    [ExtractFileName(FEdits[I].LocalFile), FEdits[I].PeerTitle]));
end;

{ a saved change: copy it back once the time stamp has stayed the same for
  one tick (the program may still be writing) }
procedure TFormMain.TmrEditTimer(Sender: TObject);
var
  I: Integer;
  A: LongInt;
  T: TWriteThread;
begin
  if FClosing then Exit;
  for I := 0 to High(FEdits) do
  begin
    if not FEdits[I].Ready or FEdits[I].Busy or not FileExists(FEdits[I].LocalFile) then Continue;
    A := FileAge(FEdits[I].LocalFile);
    if (A = -1) or (A = FEdits[I].Stamp) then Continue;
    if A <> FEdits[I].Pending then
    begin
      FEdits[I].Pending := A;   // changed: wait one more tick
      Continue;
    end;
    FEdits[I].Stamp := A;
    FEdits[I].Busy := True;
    T := TWriteThread.CreateReplace(FEdits[I].IP, FEdits[I].PeerTitle, FEdits[I].Port, FMyName,
      FEdits[I].VPath, FEdits[I].LocalFile);
    T.Tag := FEdits[I].PeerID;
    T.OnDone := @EditSaved;
    TrackThread(T);
  end;
end;

procedure TFormMain.EditSaved(T: TWriteThread);
var
  I: Integer;
begin
  if FClosing then Exit;
  for I := 0 to High(FEdits) do
    if FEdits[I].LocalFile = T.LocalFile then
    begin
      FEdits[I].Busy := False;
      if T.Ok then
        SetStatus(Format(L('Saved %s to %s', 'บันทึก %s ไปที่ %s แล้ว'), [T.Title, FEdits[I].PeerTitle]))
      else
        // not retried by itself: saving again in the program tries again
        SetStatus(Format(L('%s was not saved to %s: %s — save it again to retry',
          '%s ยังไม่ถูกบันทึกไปที่ %s: %s — บันทึกอีกครั้งเพื่อลองใหม่'),
          [T.Title, FEdits[I].PeerTitle, T.Error]), False);
      Break;
    end;
  if (T.Tag = FCurPeer) and T.Ok then Navigate(FCurPeer, FCurPath, False);
end;


{ everything known about a computer in the list }
procedure TFormMain.ShowPeerIdentity(Index: Integer; const ScreenPt: TPoint);
var
  It: TSideItem;
  Web: string;
begin
  if (Index < 0) or (Index > High(Sidebar.Items)) then Exit;
  It := Sidebar.Items[Index];
  Web := '';
  if It.IsMe then
  begin
    It.Title := FMyName;
    It.Host := FHostName;
    It.User := FMyUser;
    It.Machine := FMyMachine;
    It.Version := APP_VERSION;
    It.IP := FMyIPs;
    It.OS := GetOSName;
    It.Icon := FMyIcon;
    It.ID := FMyID;
    if FListen <> nil then
    begin
      It.Port := FTcpPort;
      It.Caps := 'bin,http,push,write';
      Web := Format('http://%s:%d', [FWebHost, FTcpPort]);
    end
    else
      It.Port := 0;
  end
  else if (It.Caps = '') or (Pos('http', It.Caps) > 0) then
    Web := Format('http://%s:%d', [It.IP, It.Port]);
  ShowIdentity(Self, It, Web, ScreenPt);
end;

{ a peer closed LAN Share: show it offline at once }
procedure TFormMain.NetPeerGone(Sender: TObject; const ID: string);
var
  I: Integer;
begin
  if FClosing then Exit;
  I := PeerIndex(ID);
  if I < 0 then Exit;
  Sidebar.Items[I].Online := False;
  Sidebar.Invalidate;
  UpdateHeader;
  if ID = FCurPeer then UpdateToolbar;
end;

procedure TFormMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  I: Integer;
begin
  if (Transfers.ActiveCount > 0) and
     not ThemedAsk(Self, dkWarning, L('Transfers in progress', 'ยังมีการถ่ายโอนค้างอยู่'),
       Format(L('%d transfer(s) still running. Closing now stops them unfinished.', 'กำลังถ่ายโอน %d รายการ ถ้าปิดตอนนี้รายการที่ยังไม่เสร็จจะหยุดกลางคัน'),
         [Transfers.ActiveCount]), L('Close', 'ปิดโปรแกรม'), L('Cancel', 'ยกเลิก')) then
  begin
    CanClose := False;
    Exit;
  end;
  SaveSettings;
  FClosing := True;
  ReleaseClipboardFiles;
  for I := 0 to FThreads.Count - 1 do
  begin
    TNetThread(FThreads[I]).OnTransfer := nil;
    TNetThread(FThreads[I]).OnLog := nil;
    TNetThread(FThreads[I]).Cancel;
  end;
  if FListen <> nil then
  begin
    FListen.OnLog := nil;
    FListen.OnAsk := nil;
    FListen.OnTransfer := nil;
    FListen.StopListening;
  end;
  if FDiscovery <> nil then
  begin
    FDiscovery.OnPeer := nil;
    FDiscovery.OnPeerGone := nil;
    FDiscovery.SayGoodbye;     // others show us offline at once
    FDiscovery.StopDiscovery;
  end;
end;

end.
