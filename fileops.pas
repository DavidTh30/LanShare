unit FileOps;

{ File operations for folders that others may change (Read + Write shares).
  Deleting moves to the Recycle Bin / Trash where possible, so a mistake made
  from another computer can be undone on this one. }

{$mode objfpc}{$H+}

interface

{ Moves a file or folder to the Recycle Bin (Windows) or the freedesktop
  Trash (Linux, same drive only); deletes it for good when that is not
  possible (e.g. a network drive). True when it is gone. }
function RemoveToTrash(const Path: string): Boolean;
{ Puts Src in place of Dst (Dst may exist): used to save an edited file
  without leaving a half-written one behind. }
function ReplaceFileWith(const Src, Dst: string): Boolean;
{ A name another computer may give a file or folder: no path separators,
  no '.' or '..', and nothing this OS would change or refuse. }
function ValidNewName(const Name: string): Boolean;
{ deletes a file or a whole folder for good }
function DeleteTree(const Path: string): Boolean;

implementation

uses
  {$IFDEF WINDOWS} Windows, ShellApi, {$ENDIF}
  {$IFDEF UNIX} BaseUnix, {$ENDIF}
  Classes, SysUtils, DateUtils;

function DeleteTree(const Path: string): Boolean;
var
  SR: TSearchRec;
  P: string;
begin
  if not DirectoryExists(Path) then Exit(SysUtils.DeleteFile(Path));
  P := IncludeTrailingPathDelimiter(Path);
  if FindFirst(P + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      if (SR.Attr and faDirectory <> 0) and (SR.Attr and faSymLink = 0) then
        DeleteTree(P + SR.Name)
      else
        SysUtils.DeleteFile(P + SR.Name);
    until FindNext(SR) <> 0;
    SysUtils.FindClose(SR);
  end;
  Result := RemoveDir(Path);
end;

{$IFDEF WINDOWS}
function RemoveToTrash(const Path: string): Boolean;
var
  Op: TSHFileOpStructW;
  W: UnicodeString;
begin
  W := UnicodeString(ExcludeTrailingPathDelimiter(Path)) + #0#0;   // double-null list
  FillChar(Op, SizeOf(Op), 0);
  Op.wFunc := FO_DELETE;
  Op.pFrom := PWideChar(W);
  Op.fFlags := FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI;
  Result := (SHFileOperationW(@Op) = 0) and not Op.fAnyOperationsAborted;
  if Result then Result := not (FileExists(Path) or DirectoryExists(Path));
  if not Result then Result := DeleteTree(Path);
end;
{$ELSE}
function RemoveToTrash(const Path: string): Boolean;
var
  Home, Trash, Name, Target: string;
  N: Integer;
  Info: TStringList;
begin
  Result := False;
  {$IFDEF LINUX}
  // freedesktop.org Trash in the user's home (works when on the same drive)
  Home := GetEnvironmentVariable('XDG_DATA_HOME');
  if Home = '' then Home := IncludeTrailingPathDelimiter(GetUserDir) + '.local/share';
  Trash := IncludeTrailingPathDelimiter(Home) + 'Trash/';
  if ForceDirectories(Trash + 'files') and ForceDirectories(Trash + 'info') then
  begin
    Name := ExtractFileName(ExcludeTrailingPathDelimiter(Path));
    Target := Name;
    N := 1;
    while FileExists(Trash + 'files/' + Target) or DirectoryExists(Trash + 'files/' + Target)
      or FileExists(Trash + 'info/' + Target + '.trashinfo') do
    begin
      Inc(N);
      Target := Name + '.' + IntToStr(N);
    end;
    if fpRename(ExcludeTrailingPathDelimiter(Path), Trash + 'files/' + Target) = 0 then
    begin
      Info := TStringList.Create;
      try
        Info.Add('[Trash Info]');
        Info.Add('Path=' + ExpandFileName(ExcludeTrailingPathDelimiter(Path)));
        Info.Add('DeletionDate=' + FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
        try
          Info.SaveToFile(Trash + 'info/' + Target + '.trashinfo');
        except
          // the file is in the trash folder anyway
        end;
      finally
        Info.Free;
      end;
      Exit(True);
    end;
  end;
  {$ENDIF}
  Result := DeleteTree(Path);
end;
{$ENDIF}

function ReplaceFileWith(const Src, Dst: string): Boolean;
begin
  {$IFDEF WINDOWS}
  Result := MoveFileExW(PWideChar(UnicodeString(Src)), PWideChar(UnicodeString(Dst)),
    MOVEFILE_REPLACE_EXISTING or MOVEFILE_COPY_ALLOWED);
  {$ELSE}
  Result := fpRename(Src, Dst) = 0;   // replaces atomically
  {$ENDIF}
end;

function ValidNewName(const Name: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (Name = '') or (Name = '.') or (Name = '..') or (Length(Name) > 255) then Exit;
  for I := 1 to Length(Name) do
  begin
    if (Name[I] < ' ') or (Name[I] = '/') or (Name[I] = '\') then Exit;
    {$IFDEF WINDOWS}
    if Pos(Name[I], '<>:"|?*') > 0 then Exit;
    {$ENDIF}
  end;
  {$IFDEF WINDOWS}
  // Windows drops trailing dots and spaces
  if Name[Length(Name)] in ['.', ' '] then Exit;
  {$ENDIF}
  Result := True;
end;

end.
