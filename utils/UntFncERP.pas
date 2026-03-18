unit UntFncERP;

interface

uses
  Classes, Controls, Windows, Dialogs, SysUtils,
  StrUtils, IBX.IBDatabase, IBX.IBDatabaseInfo, IBX.IBQuery, IBX.IBSQL;
Type
  CcTiposCartera  = record (* Longitud del registro = 900 bytes *)
    CodigoTipo          : integer;
    NombreTipo          : string[40];
    Conexiones          : string[60];
    Identidad           : string[25];
    Nombre              : string[25];
    Local               : string[25];
    Representante       : string[25];
    EncargadoPagos      : string[25];
    EncargadoCompras    : string[25];
    DireccionEntregas   : string[25];
    Zona                : string[25];
    Grupo               : string[25];
    CampoLibreUno       : string[25];
    CampoLibreDos       : string[25];
    Observaciones       : string[25];
    Ordenamiento        : string[12];
    ManejoCte           : string[1];
    SugerirCte          : string[1];
    PorcentajeCte       : integer;
    NegociableCte       : string[1];
    AjusteAlPesoCte     : string[1];
    DiasCte             : SmallInt;
    ManejoMor           : string[1];
    SugerirMor          : string[1];
    PorcentajeMor       : Integer;
    NegociableMor       : string[1];
    AjusteAlPesoMor     : string[1];
    DiasMor             : SmallInt;
    Tac                 : SmallInt;
    TipoCalculoMor      : string[1];
    PendientesMes       : string[1];
    Reservado1          : string[250];
    Reservado2          : string[180];
  end;
  ArchivoCcTiposCartera      = file of CcTiposCartera;

  const
  Antes1900 = 811332;
  prEstructuraContable   = 0;
  prCoCuentasEspeciales  = 1;
  prCcTiposCartera       = 2;

  procedure fnCcTiposCartera(ArchivoParametros: string; var ArrayTiposCartera: array of CcTiposCartera);
  function PrimerRegistroEnParametros(Parametro : Byte): SmallInt;

  function GetLengthDocumentNumber(pType: string; pQry: TIBSQL): Integer;
  function GetDocumentNumber(pType, pNumber: string; pQry: TIBSQL; pDefaultLength: Word = 0; pFillZeros: String = 'S'): String;
  function IncDocumentoERP(Texto, pTipo: string; pQry: TIBSQL; pFillZeros: String = 'S'): string;
  function RemoveZerosFromLeft(pConsec: String): String;
  function IncBankCheckERP(pValue: String): String;
  function DateToHeDate(Fecha : TDate): integer;
  function DiasDelMes(XAno, XMes: integer): integer;
  function CodificarFecha(CAno, CMes, CDia: Word): Integer;
  function EsAnoBisiesto(CAno: Word): Boolean;

implementation

procedure fnCcTiposCartera(ArchivoParametros: string; var ArrayTiposCartera: array of CcTiposCartera);
var
  I: word;
  Puntero : SmallInt;
  Archivo : ArchivoCcTiposCartera;
begin
  FillChar(ArrayTiposCartera, SizeOf(ArrayTiposCartera), #0);
  AssignFile(Archivo, ArchivoParametros);
  try
    Reset(Archivo);
  except
    on T: EInOutError do
      if T.ErrorCode = 2 then begin
        raise Exception.Create('Archivo ' + ArchivoParametros + ' no existe');
        Exit;
      end;
  end;
  try
    for Puntero := PrimerRegistroEnParametros(prCcTiposCartera) to PrimerRegistroEnParametros(prCcTiposCartera) + 19 do begin
      I := Puntero-PrimerRegistroEnParametros(prCcTiposCartera);
      Seek(Archivo, Puntero);
      Read(Archivo, ArrayTiposCartera[I]);
      if (ArrayTiposCartera[I].Tac < 1) or (ArrayTiposCartera[I].Tac > 12) then begin
        ArrayTiposCartera[I].Tac:= 1;
      end;
      if (ArrayTiposCartera[I].CodigoTipo < 1) or
         (ArrayTiposCartera[I].CodigoTipo > 20) then
        FillChar(ArrayTiposCartera[I], SizeOf(ArrayTiposCartera[I]), #0);
    end;
  finally
    CloseFile(Archivo);
  end;
end;

function PrimerRegistroEnParametros(Parametro : Byte): SmallInt;
const
  Registros : array [0..12, 0..1] of Integer = ((1,400),  (* EstructuraContable  *)
                                               (1,1600),  (* CoCuentasEspeciales *)
                                               (20,900),  (* CcTiposCartera      *)
                                               (1,400),   (* CeParametros        *)
                                               (500,300), (* GyPParametros       *)
                                               (500,300), (* AjParametros        *)
                                               (20,900),  (* cpParametros        *)
                                               (1,500),   (* teCuentasEspeciales *)
                                               (1,1000),  (* baCuentasEspeciales *)
                                               (1,1000),  (* ccCuentasEspeciales *)
                                               (1,400),   (* InParametros *)
                                               (1,400),   (* VeParametros *)
                                               (1,400));  (* CmParametros *)
var
  Tempo: Byte;
  BytesUsados: integer;
begin
  Result := -1;
  BytesUsados := 0;
  for Tempo := 0 to Parametro do begin
    if (BytesUsados mod Registros[Tempo, 1]) = 0 then
      Result := (BytesUsados div Registros[Tempo, 1])
    else
      Result := Trunc(BytesUsados / Registros[Tempo, 1]) + 1;
    BytesUsados := Registros[Tempo, 1] * (Registros[Tempo, 0] + Result);
  end;
  if Result < 0 then raise Exception.Create('Parametro fuera de rango');
end;

function GetLengthDocumentNumber(pType: string; pQry: TIBSQL): Integer;
var
  vSQL: TIBQuery;
  vTran: TIBTransaction;
begin
  vTran                := TIBTransaction.Create(Nil);
  vTran.DefaultDatabase:= pQry.Database;
  vTran.Active         := True;

  vSQL            := TIBQuery.Create(nil);
  vSQL.Database   := pQry.Database;
  vSQL.Transaction:= vTran;

  vSQL.SQL.Clear;
  vSQL.SQL.Add('select valor(tamano_consecutivo) o_length from DOCUMENTOS where prefijo = :tipo');
  vSQL.ParamByName('tipo').AsString:= pType;
  vSQL.Open;
  if vSQL.FieldByName('o_length').AsInteger > 7 then
    Result:= vSQL.FieldByName('o_length').AsInteger
  else
    Result:= 8;

  vTran.Commit;
  vSQL.Close;
  vTran.Active := False;
  FreeandNil(vSQL);
  FreeandNil(vTran);
end;

function GetDocumentNumber(pType, pNumber: string; pQry: TIBSQL; pDefaultLength: Word = 0; pFillZeros: String = 'S'): String;
var
  vLength: Integer;
begin
  if pFillZeros = 'S' then begin
    if pDefaultLength = 0 then begin
      vLength:= GetLengthDocumentNumber(pType, pQry);
      Result:= RightStr(StringOfChar('0', vLength - Length(pNumber)) + pNumber, vLength);
    end
    else
      Result:= RightStr(StringOfChar('0', pDefaultLength - Length(pNumber)) + pNumber, pDefaultLength);
  end
  else
    Result:= RemoveZerosFromLeft(pNumber);
end;

function IncDocumentoERP(Texto, pTipo: string; pQry: TIBSQL; pFillZeros: String = 'S'): string;
  var Tempo, Conteo: word;
      Simbolos, Numeros: string;
begin
  Result    := '';
  Numeros   := '';
  Simbolos  := StringOfChar(#10, Length(Texto));
  for Tempo:= 1 to Length(Texto) do begin
    if (Texto[Tempo] in ['0'..'9']) then
      Numeros:= Numeros + Texto[Tempo]
    else
      Simbolos[Tempo]:= Texto[Tempo];
  end;
  if Numeros = '' then
    Numeros:= '0';
  Numeros:= StringOfChar('0', 40) + IncBankCheckERP(Numeros);
  Conteo:= Length(Numeros);
  if pFillZeros = 'S' then begin
    for Tempo:= Length(Simbolos) downto 1 do begin
      if Simbolos[Tempo] = #10 then begin
        Result:= Numeros[Conteo] + Result;
        Conteo:= Conteo - 1;
      end
      else begin
        Result:= Simbolos[Tempo] + Result;
      end
    end;
    Result:= GetDocumentNumber(pTipo, Result, pQry, 0, pFillZeros);
  end
  else begin
    Simbolos:= StringOfChar(#10, Length(InttoStr(StrtoInt(Numeros))));
    Conteo:= Length(InttoStr(StrtoInt(Numeros)));
    Numeros:= InttoStr(StrtoInt(Numeros));
    for Tempo:= Length(Simbolos) downto 1 do begin
      if Simbolos[Tempo] = #10 then begin
        Result:= Numeros[Conteo] + Result;
        Conteo:= Conteo - 1;
      end
      else begin
        Result:= Simbolos[Tempo] + Result;
      end
    end;
    Result:= StringReplace(Result, pTipo, '', [rfReplaceAll]);
  end;
end;

function RemoveZerosFromLeft(pConsec: String): String;
var
  i: Word;
begin
  Result:= pConsec;
  i:= 1;
  while (Length(Result) > 0) and (Result[i] = '0') do
    Result:= RightStr(Result, Length(Result) - 1);
end;

function IncBankCheckERP(pValue: String): String;
var
  i: Word;
begin
  if pValue = '' then
    pValue := '0';
  Result:= pValue;
  i:= Length(Result);
  Result[i]:= RightStr(InttoStr(StrtoInt(Result[i]) + 1), 1)[1];
  while (Result[i] = '0') and (i > 1) do begin
    Result[i - 1]:= RightStr(InttoStr(StrtoInt(Result[i - 1]) + 1), 1)[1];
    Dec(i);
  end;
  if Result[1] = '0' then
    Result:= '1' + Result;
  if Length(Result) > 40 then
   Result:= '0';
end;

function DateToHeDate(Fecha : TDate): integer;
var
  XAno, XMes, XDia: Word;
begin
  DecodeDate(Fecha, XAno, XMes, XDia);
  Result := CodificarFecha(XAno, XMes, XDia);
end;

function CodificarFecha(CAno, CMes, CDia: Word): integer;
Var
  I: Word;
begin
  Result := 0;
  if (CAno >= 1) and (CAno <= 9999) and (CMes >= 1) and (CMes <= 14) and
    (CDia >= 1) and (CDia <= DiasDelMes(CAno,CMes)) then
  begin
    for I := 1 to CMes - 1 do
      Inc(CDia, DiasDelMes(CAno,I));
    I := CAno - 1;
    Result:= I * 427 + I div 4 - I div 100 + I div 400 + CDia - Antes1900;
  end;
end;

function DiasDelMes(XAno, XMes: integer): integer;
const
  DiasPorMes: array[1..14] of integer = (31,28,31,30,31,30,31,31,30,31,30,31,31,31);
begin
  Result:= DiasPorMes[XMes];
  if (XMes=2) and EsAnoBisiesto(XAno) then Inc(Result);
end;

function EsAnoBisiesto(CAno: Word): Boolean;
begin
  Result := (CAno mod 4 = 0) and ((CAno mod 100 <> 0) or (CAno mod 400 = 0));
end;

end.
