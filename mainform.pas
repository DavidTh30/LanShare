unit MainForm;

{ LAN Share main window.
  Left: every computer running LAN Share on the LAN ("เครื่องนี้" first).
  Right: an Explorer-like view of the selected computer's shared folders.
    - เครื่องนี้  : manage what this computer shares (add / remove)
    - other PCs : browse their shares, download files/folders, or send files to them
  Bottom: transfers with progress. The UI is drawn with BGRABitmap (see UIWidgets). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, IniFiles,
  LCLIntf, LCLType, BGRABitmapTypes, LanNet, UITheme, UIWidgets, SettingsDlg;

type
  TNavEntry = record
    PeerID: string;
    Path: string;
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
    FileView: TFileView;
    Transfers: TTransfersView;
    TmrPeers: TTimer;
    TmrStatus: TTimer;

    FTcpPort: Integer;
    FMyID, FMyIPs, FWebURL: string;
    FMyName: string;           // name others see; '' = not set (nothing is shown)
    FMyIcon: string;           // '<kind>.<color>' shown to others
    FTheme: TThemeKind;        // as chosen (thAuto follows the OS)
    FShownTheme: TThemeKind;   // palette currently on screen
    FHostName: string;         // real computer name: never sent unless chosen
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

    procedure BuildUI;
    function MkBtn(AParent: TWinControl; const ACaption: string; AIcon: TIconKind;
      AStyle: TButtonStyle; AAlign: TAlign; AClick: TNotifyEvent): TFlatButton;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure StartNetwork;
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
    procedure TransfersCancel(Sender: TObject);
    procedure TmrPeersTimer(Sender: TObject);
    procedure TmrStatusTimer(Sender: TObject);

    procedure NetLog(Sender: TObject; const Msg: string);
    procedure NetTransfer(const T: TTransferInfo);
    function NetAsk(Sender: TObject; const FromName, FromIP: string;
      FileCount: Integer; TotalBytes: Int64): Boolean;
    procedure NetPeer(Sender: TObject; const ID, PeerName, IP: string; Port: Integer;
      const OS, Caps, PeerIcon: string);
    procedure BrowseDone(B: TBrowseThread);
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
  Randomize;
  FMyID := IntToHex(Random($7FFFFFFF), 8) + IntToHex(GetTickCount64 and $FFFF, 4);
  IPs := GetLocalIPs;
  FMyIPs := '';
  for I := 0 to High(IPs) do
  begin
    if FMyIPs <> '' then FMyIPs := FMyIPs + ', ';
    FMyIPs := FMyIPs + IPs[I];
  end;
  if FMyIPs = '' then FMyIPs := 'ไม่พบ IP';
  // address phones can open in a browser: the default-route address first,
  // else the usual home/office ranges
  FWebURL := GetPrimaryIP;
  if FWebURL = '' then
    for I := 0 to High(IPs) do
      if Copy(IPs[I], 1, 8) = '192.168.' then begin FWebURL := IPs[I]; Break; end;
  if FWebURL = '' then
    for I := 0 to High(IPs) do
      if Copy(IPs[I], 1, 3) = '10.' then begin FWebURL := IPs[I]; Break; end;
  if (FWebURL = '') and (Length(IPs) > 0) then FWebURL := IPs[0];
  if FWebURL <> '' then FWebURL := Format('http://%s:%d', [FWebURL, FTcpPort]);

  {$IFDEF WINDOWS}
  // portable: settings next to the exe
  FIniName := ChangeFileExt(Application.ExeName, '.ini');
  {$ELSE}
  // GetAppConfigDir names the folder after Application.Title ("LAN Share"),
  // so take its parent (~/.config, honours XDG_CONFIG_HOME) and fix the name.
  FIniName := ExtractFilePath(ExcludeTrailingPathDelimiter(GetAppConfigDir(False)))
    + 'LanShare' + PathDelim;
  ForceDirectories(FIniName);
  FIniName := FIniName + 'LanShare.ini';
  {$ENDIF}

  FShares := TShareList.Create;
  FThreads := TList.Create;
  FKnown := TStringList.Create;
  BuildUI;
  LoadSettings;
  ApplyTheme;
  StartNetwork;
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
  BtnSettings := MkBtn(Header, 'ตั้งค่า', ikGear, bsNormal, alRight, @BtnSettingsClick);
  BtnSettings.BorderSpacing.Right := ScI(14);
  BtnSettings.Hint := 'ชื่อและไอคอนที่เครื่องอื่นเห็น';
  BtnSettings.ShowHint := True;
  Header.RightReserve := BtnSettings.Width + ScI(22);

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
  SetLength(Sidebar.Items, 1);
  Sidebar.Items[0].ID := ME_ID;
  Sidebar.Items[0].IsMe := True;
  Sidebar.Items[0].Online := True;
  Sidebar.Items[0].Title := 'เครื่องนี้';

  BtnAddPeer := MkBtn(Sidebar, 'เชื่อมต่อด้วย IP', ikPlus, bsNormal, alBottom, @BtnAddPeerClick);
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
  BtnBack.Hint := 'ย้อนกลับ (Backspace)';
  BtnUp.Hint := 'ขึ้นหนึ่งระดับ';
  BtnRefresh.Hint := 'รีเฟรช';
  BtnBack.ShowHint := True;
  BtnUp.ShowHint := True;
  BtnRefresh.ShowHint := True;

  // right-aligned actions (created right-to-left)
  BtnDownload := MkBtn(Toolbar, 'ดาวน์โหลด', ikDownload, bsAccent, alRight, @BtnDownloadClick);
  BtnSendFolder := MkBtn(Toolbar, 'ส่งโฟลเดอร์', ikFolderPlus, bsNormal, alRight, @BtnSendFolderClick);
  BtnSendFile := MkBtn(Toolbar, 'ส่งไฟล์', ikUpload, bsNormal, alRight, @BtnSendFileClick);
  BtnUnshare := MkBtn(Toolbar, 'เลิกแชร์', ikTrash, bsDanger, alRight, @BtnUnshareClick);
  BtnShareFolder := MkBtn(Toolbar, 'แชร์โฟลเดอร์', ikFolderPlus, bsAccent, alRight, @BtnShareFolderClick);
  BtnShareFile := MkBtn(Toolbar, 'แชร์ไฟล์', ikFilePlus, bsNormal, alRight, @BtnShareFileClick);
  BtnOpenLocal := MkBtn(Toolbar, 'เปิดในเครื่อง', ikFolderOpen, bsNormal, alRight, @BtnOpenLocalClick);
  BtnPreview := MkBtn(Toolbar, 'ดูตัวอย่าง', ikEye, bsNormal, alRight, @BtnPreviewClick);
  BtnPreview.Hint := 'เปิดดูในเบราว์เซอร์: หน้า Markdown (.md) รูป PDF วิดีโอ';
  BtnPreview.ShowHint := True;
  // LCL orders controls with the same Align by their Left: make it explicit
  BtnBack.Left := 0;
  BtnUp.Left := 100;
  BtnRefresh.Left := 200;
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

  TmrPeers := TTimer.Create(Self);
  TmrPeers.Interval := 3000;
  TmrPeers.OnTimer := @TmrPeersTimer;

  TmrStatus := TTimer.Create(Self);
  TmrStatus.Enabled := False;
  TmrStatus.Interval := 6000;
  TmrStatus.OnTimer := @TmrStatusTimer;
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
      if (S <> '') and (FileExists(S) or DirectoryExists(S)) then FShares.Add(S);
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
      NetPeer(nil, 'manual:' + IP + ':' + IntToStr(Port), IP, IP, Port, '', '', '');
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
      Ini.EraseSection('Known');
      Ini.WriteInteger('Known', 'Count', FKnown.Count);
      for I := 0 to FKnown.Count - 1 do
        Ini.WriteString('Known', 'Item' + IntToStr(I), FKnown[I]);
      Ini.EraseSection('Shares');
      P := FShares.Paths;
      Ini.WriteInteger('Shares', 'Count', Length(P));
      for I := 0 to High(P) do
        Ini.WriteString('Shares', 'Item' + IntToStr(I), P[I]);
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
    // settings are optional (folder may be read-only)
  end;
end;

{ ---------- network start ---------- }

procedure TFormMain.StartNetwork;
var
  I: Integer;
begin
  try
    FListen := TListenThread.Create(FTcpPort, FShares);
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
    FListen.ThemeCssFunc := @UITheme.ThemeCssByName;
    FListen.Start;
  except
    on E: Exception do
    begin
      FListen := nil;
      MessageDlg('LAN Share', 'เปิดตัวรับการเชื่อมต่อไม่ได้: ' + E.Message, mtError, [mbOK], 0);
    end;
  end;
  try
    FDiscovery := TDiscoveryThread.Create(FMyID, FMyName, FMyIcon, FTcpPort);
    FDiscovery.OnPeer := @NetPeer;
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
  if FWebURL <> '' then
    Header.SubTitle := 'มือถือเปิดในเบราว์เซอร์ได้ที่ ' + FWebURL
  else
    Header.SubTitle := Format('%s  •  พอร์ต %d', [FMyIPs, FTcpPort]);
  if FMyName <> '' then Header.SubTitle := FMyName + '  •  ' + Header.SubTitle;
  if not TmrStatus.Enabled then
  begin
    Online := 0;
    for I := 0 to High(Sidebar.Items) do
      if (not Sidebar.Items[I].IsMe) and Sidebar.Items[I].Online then Inc(Online);
    if FListen = nil then
    begin
      Header.Status := 'รับไฟล์ไม่ได้ (พอร์ตถูกใช้)';
      Header.StatusOK := False;
    end
    else
    begin
      Header.Status := Format('ออนไลน์  •  แชร์สาธารณะ %d รายการ  •  พบ %d เครื่อง', [FShares.Count, Online]);
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
        Sidebar.Items[I].Subtitle := Format('แชร์สาธารณะ %d รายการ', [FShares.Count]);
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
  BtnSendFile.Visible := not IsMe;
  BtnSendFolder.Visible := not IsMe;
  BtnDownload.Visible := not IsMe;
  BtnDownload.Enabled := HasSel and (FileView.ErrorText = '');
  BtnSendFile.Enabled := Online;
  BtnSendFolder.Enabled := Online;
  BtnBack.Enabled := Length(FHistory) > 0;
  BtnUp.Enabled := FCurPath <> '';
  BtnRefresh.Enabled := True;
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
    PathBar.Segments[0] := 'เครื่องนี้ — สิ่งที่ฉันแชร์'
  else
    PathBar.Segments[0] := Sidebar.Items[I].Title;
  for K := 0 to High(Parts) do
    PathBar.Segments[K + 1] := Parts[K];
  PathBar.Invalidate;

  if FCurPeer = ME_ID then
    ShowMyShares
  else if not Sidebar.Items[I].CanBrowse then
  begin
    FileView.SetItems(nil);
    FileView.Col3Title := 'แก้ไขล่าสุด';
    FileView.EmptyTitle := Sidebar.Items[I].Title;
    FileView.EmptyText := 'อุปกรณ์นี้ยังเปิดให้ดูไฟล์ไม่ได้ แต่ส่งไฟล์มาที่เครื่องนี้ได้';
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
    FileView.Col3Title := 'ตำแหน่งในเครื่องนี้';
    FileView.EmptyTitle := 'ยังไม่ได้แชร์ไฟล์หรือโฟลเดอร์';
    FileView.EmptyText := 'สิ่งที่แชร์ที่นี่ทุกเครื่องในวง LAN เห็นได้ — กด "แชร์โฟลเดอร์" หรือลากไฟล์มาวาง';
    E := FShares.RootEntries;
  end
  else
  begin
    // inside a shared folder: show what the other machines see there
    FileView.Col3Title := 'แก้ไขล่าสุด';
    FileView.EmptyTitle := 'โฟลเดอร์นี้ว่างเปล่า';
    FileView.EmptyText := 'ไฟล์ที่ใส่ในโฟลเดอร์นี้ เครื่องอื่นจะเห็นทันที';
    try
      if FShares.Resolve(FCurPath, Local) and DirectoryExists(Local) then
        E := ListLocalDir(Local)
      else
      begin
        FileView.SetItems(nil);
        FileView.ErrorText := 'โฟลเดอร์นี้ถูกลบ ย้าย หรือเลิกแชร์แล้ว';
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
      V[I].Info := E[I].LocalPath;
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
  FileView.Col3Title := 'แก้ไขล่าสุด';
  FileView.EmptyTitle := 'ไม่มีไฟล์';
  if FCurPath = '' then
    FileView.EmptyText := 'เครื่องนี้ยังไม่ได้แชร์อะไร'
  else
    FileView.EmptyText := 'โฟลเดอร์นี้ว่างเปล่า';
  FileView.SetItems(nil);
  FileView.IsLoading := True;
  FileView.Invalidate;
  Inc(FBrowseSeq);
  B := TBrowseThread.Create(Sidebar.Items[I].IP, Sidebar.Items[I].Port, FMyName, FCurPath, FBrowseSeq);
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
  end;
  FileView.SetItems(V);
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
  SetStatus(Format('แชร์เพิ่ม %d รายการ', [Length(Paths)]));
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
  if FCurPeer = ME_ID then
    AddShares(FileNames)
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
    Dlg.Title := 'เลือกโฟลเดอร์สำหรับเก็บไฟล์ที่ได้รับ';
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
  if not InputQuery('เชื่อมต่อด้วย IP',
    'ใส่ IP หรือชื่อเครื่อง (ระบุพอร์ตได้ เช่น 192.168.1.20:50505)', S) then Exit;
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
  NetPeer(nil, ID, IP, IP, Port, '', '', '');
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
    Dlg.Title := 'เลือกไฟล์ที่จะแชร์';
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
    Dlg.Title := 'เลือกโฟลเดอร์ที่จะแชร์ให้เครื่องอื่นเปิดดู';
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
  SetStatus(Format('เลิกแชร์ %d รายการ (ไฟล์จริงยังอยู่)', [Length(Idx)]));
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
    Dlg.Title := 'เลือกไฟล์ที่จะส่ง';
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
    Dlg.Title := 'เลือกโฟลเดอร์ที่จะส่ง';
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
  I: Integer;
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

procedure TFormMain.ApplyTheme;
begin
  SetTheme(FTheme);
  FShownTheme := ResolveTheme(FTheme);
  Color := BGRAToColor(clBg);
  InvalidateTree(Self);
  if FListen <> nil then FListen.ThemeCss := UITheme.ThemeCss;   // phones follow the theme
end;

procedure TFormMain.BtnSettingsClick(Sender: TObject);
var
  N, Ic, OldName: string;
  Th: TThemeKind;
begin
  N := FMyName;
  OldName := FMyName;
  Ic := FMyIcon;
  Th := FTheme;
  if EditIdentity(Self, N, Ic, Th, FHostName) then
  begin
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
      SetStatus('เครื่องอื่นจะเห็นชื่อ "' + FMyName + '"');
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
  SetStatus(Msg, Pos('ไม่สำเร็จ', Msg) = 0);
end;

procedure TFormMain.NetTransfer(const T: TTransferInfo);
begin
  if FClosing then Exit;
  if FThreads.IndexOf(T.Thread) < 0 then
  begin
    if IsActiveState(T.State) then FThreads.Add(T.Thread);
  end
  else if not IsActiveState(T.State) then
    FThreads.Remove(T.Thread);   // the thread frees itself right after this call
  Transfers.UpdateFrom(T);
  // new files arrived in a folder we are looking at
  if (T.State = tsDone) and (T.Kind = tkReceive) and (FCurPeer = ME_ID) and (FCurPath <> '') then
    ShowMyShares;
  // refresh our own share list view when a download into the receive folder finishes
  if (T.State = tsDone) and (T.Kind = tkDownload) then
    SetStatus(Format('ดาวน์โหลด %s เสร็จแล้ว → โฟลเดอร์ %s',
      [T.Title, ExtractFileName(ExcludeTrailingPathDelimiter(FDownloadDir))]));
end;

function TFormMain.NetAsk(Sender: TObject; const FromName, FromIP: string;
  FileCount: Integer; TotalBytes: Int64): Boolean;
begin
  if FClosing then Exit(False);
  Application.Restore;
  Application.BringToFront;
  Result := MessageDlg('มีไฟล์ส่งมาถึงคุณ',
    Format('%s ต้องการส่ง %d ไฟล์ ขนาด %s'#13#10#13#10 +
           'จะบันทึกไว้ที่: %s'#13#10#13#10'ต้องการรับหรือไม่?',
      [Who(FromName, FromIP), FileCount, FormatBytes(TotalBytes), FDownloadDir]),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes;
end;

procedure TFormMain.NetPeer(Sender: TObject; const ID, PeerName, IP: string; Port: Integer;
  const OS, Caps, PeerIcon: string);
var
  I, J: Integer;
  IsNew: Boolean;
begin
  if FClosing then Exit;
  I := PeerIndex(ID);
  // a broadcast from a machine that was added by hand: merge into that entry
  if I < 0 then
    for J := 0 to High(Sidebar.Items) do
      if Sidebar.Items[J].Manual and (Sidebar.Items[J].IP = IP) and (Sidebar.Items[J].Port = Port) then
      begin
        I := J;
        Break;
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
  Sidebar.Invalidate;
  if IsNew and (Sender <> nil) then
    if PeerName <> '' then
      SetStatus(Format('พบเครื่อง %s (%s)', [PeerName, IP]))
    else
      SetStatus('พบเครื่อง ' + IP);
  UpdateHeader;
  if Sidebar.Items[I].ID = FCurPeer then UpdateToolbar;
end;

procedure TFormMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  I: Integer;
begin
  if (Transfers.ActiveCount > 0) and
     (MessageDlg('LAN Share', 'ยังมีการถ่ายโอนค้างอยู่ ต้องการปิดโปรแกรมหรือไม่?',
       mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
  begin
    CanClose := False;
    Exit;
  end;
  SaveSettings;
  FClosing := True;
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
    FDiscovery.StopDiscovery;
  end;
end;

end.
