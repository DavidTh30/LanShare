program LanShare;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, MainForm, LanNet, UITheme, UIWidgets, SettingsDlg;

{$R *.res}

begin
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Title := 'LAN Share';
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
