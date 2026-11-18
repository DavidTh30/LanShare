unit MachineID;

{ Who this computer is, for other LAN Share PCs: computer name, user name and
  a machine code that stays the same after renaming or restarting.

  The machine code is a hash of the operating system's own machine id
  (Windows: MachineGuid, Linux: /etc/machine-id), so the raw id never leaves
  the computer. When the OS has none (macOS, unusual systems) the caller
  passes a random key it saved once. }

{$mode objfpc}{$H+}

interface

{ login name of the user running the program }
function GetUserLogin: string;
{ the OS machine id, '' when there is none }
function GetRawMachineID: string;
{ 'XXXX-XXXX-XXXX-XXXX' made from a raw id }
function MakeMachineCode(const Raw: string): string;

implementation

uses
  {$IFDEF WINDOWS} Windows, Registry, {$ENDIF}
  Classes, SysUtils, sha1;

function GetUserLogin: string;
begin
  {$IFDEF WINDOWS}
  Result := GetEnvironmentVariable('USERNAME');
  {$ELSE}
  Result := GetEnvironmentVariable('USER');
  if Result = '' then Result := GetEnvironmentVariable('LOGNAME');
  {$ENDIF}
end;

function GetRawMachineID: string;
{$IFDEF WINDOWS}
var
  R: TRegistry;
{$ENDIF}
{$IFDEF UNIX}
var
  SL: TStringList;
  F: string;
{$ENDIF}
begin
  Result := '';
  {$IFDEF WINDOWS}
  // the 64-bit view: a 32-bit build would otherwise read a redirected key
  R := TRegistry.Create(KEY_READ or KEY_WOW64_64KEY);
  try
    R.RootKey := HKEY_LOCAL_MACHINE;
    if R.OpenKeyReadOnly('SOFTWARE\Microsoft\Cryptography') then
      Result := R.ReadString('MachineGuid');
  except
    Result := '';
  end;
  R.Free;
  {$ENDIF}
  {$IFDEF UNIX}
  for F in ['/etc/machine-id', '/var/lib/dbus/machine-id'] do
    if FileExists(F) then
    begin
      SL := TStringList.Create;
      try
        try
          SL.LoadFromFile(F);
          if SL.Count > 0 then Result := Trim(SL[0]);
        except
          Result := '';
        end;
      finally
        SL.Free;
      end;
      if Result <> '' then Break;
    end;
  {$ENDIF}
end;

function MakeMachineCode(const Raw: string): string;
var
  H: string;
begin
  H := UpperCase(SHA1Print(SHA1String('LanShare machine:' + LowerCase(Trim(Raw)))));
  Result := Copy(H, 1, 4) + '-' + Copy(H, 5, 4) + '-' + Copy(H, 9, 4) + '-' + Copy(H, 13, 4);
end;

end.
