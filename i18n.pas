unit I18n;

{ Interface language. Every text in the program is written as
    L('English text', 'ข้อความภาษาไทย')
  so both versions stay side by side. English is the default. }

{$mode objfpc}{$H+}

interface

type
  TLang = (lnEnglish, lnThai);

const
  LANG_CODES: array[TLang] of string = ('en', 'th');
  LANG_NAMES: array[TLang] of string = ('English', 'ไทย');

var
  Lang: TLang = lnEnglish;

{ the text in the current language }
function L(const En, Th: string): string;
function LangFromCode(const S: string): TLang;

implementation

uses
  SysUtils;

function L(const En, Th: string): string;
begin
  if Lang = lnThai then Result := Th else Result := En;
end;

function LangFromCode(const S: string): TLang;
var
  X: TLang;
begin
  for X := Low(TLang) to High(TLang) do
    if LANG_CODES[X] = LowerCase(Trim(S)) then Exit(X);
  Result := lnEnglish;
end;

end.
