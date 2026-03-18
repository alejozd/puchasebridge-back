unit HelisaUtils;

interface

uses
  System.SysUtils,
  System.DateUtils,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param;

function DateToHeDate(ADate: TDateTime): Integer;
function FormatDocumentNumber(const AType: string; AConsecutive: Integer): string;

implementation

function DateToHeDate(ADate: TDateTime): Integer;
var
  XAno, XMes, XDia: Word;
  I: Word;
  CDia: Integer;
  Antes1900: Integer;
const
  DiasPorMes: array[1..12] of Integer = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

  function EsAnoBisiesto(CAno: Word): Boolean;
  begin
    Result := (CAno mod 4 = 0) and ((CAno mod 100 <> 0) or (CAno mod 400 = 0));
  end;

  function DiasDelMes(XAno, XMes: Integer): Integer;
  begin
    Result := DiasPorMes[XMes];
    if (XMes = 2) and EsAnoBisiesto(XAno) then
      Inc(Result);
  end;

begin
  Antes1900 := 811332;
  DecodeDate(ADate, XAno, XMes, XDia);
  CDia := XDia;
  for I := 1 to XMes - 1 do
    Inc(CDia, DiasDelMes(XAno, I));
  I := XAno - 1;
  Result := I * 427 + I div 4 - I div 100 + I div 400 + CDia - Antes1900;
end;

function FormatDocumentNumber(const AType: string; AConsecutive: Integer): string;
begin
  // TIPO debe ocupar 4 caracteres (relleno con espacios)
  // Concatenar con CONSECUTIVO (relleno con ceros hasta 8 para que de un total razonable,
  // aunque Helisa suele usar 8 para el consecutivo segun UntFncERP)
  Result := Format('%-4s%08d', [AType, AConsecutive]);
end;

end.
