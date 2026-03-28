unit EquivalenciaService;

interface

uses
  System.SysUtils,
  System.JSON,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection;

function BuscarEquivalencia(AReferenciaH: string; AUnidadH: string): TFDQuery; overload;
function BuscarEquivalencia(AConnection: TFDConnection; AReferenciaH: string; AUnidadH: string): TFDQuery; overload;
function BuscarEquivalenciaXML(AReferenciaXML: string; AUnidadXML: string): TFDQuery;
function ExisteEquivalencia(AReferenciaH: string; AUnidadH: string): Boolean;
function GetIDEquivalencia(AReferenciaH, AUnidadH: string): Integer; overload;
function GetIDEquivalencia(AConnection: TFDConnection; AReferenciaH, AUnidadH: string): Integer; overload;

function CrearEquivalencia(
  ACodigoH: Integer;
  ASubCodigoH: Integer;
  ANombreH: string;
  AReferenciaP: string;
  AUnidadP: string;
  AUnidadH: string;
  AReferenciaH: string;
  AFactor: Double
): Integer; overload;

function CrearEquivalencia(
  AConnection: TFDConnection;
  ACodigoH: Integer;
  ASubCodigoH: Integer;
  ANombreH: string;
  AReferenciaP: string;
  AUnidadP: string;
  AUnidadH: string;
  AReferenciaH: string;
  AFactor: Double
): Integer; overload;

function ObtenerEquivalenciaJSON(AReferenciaH: string; AUnidadH: string): string;

// Nuevas funciones
function ListarEquivalencias(const AReferenciaH, AUnidadH: string; ALimite: Integer): TFDQuery;
function EliminarEquivalencia(const AReferenciaH, AUnidadH: string): Boolean;

implementation

function BuscarEquivalencia(AReferenciaH: string; AUnidadH: string): TFDQuery;
begin
  Result := BuscarEquivalencia(nil, AReferenciaH, AUnidadH);
end;

function BuscarEquivalencia(AConnection: TFDConnection; AReferenciaH: string; AUnidadH: string): TFDQuery;
begin
  if AReferenciaH.Trim.IsEmpty or AUnidadH.Trim.IsEmpty then
    raise Exception.Create('Referencia XML y Unidad XML son obligatorias para buscar equivalencia');

  if Assigned(AConnection) then
  begin
    Result := TFDQuery.Create(nil);
    Result.Connection := AConnection;
  end
  else
    Result := GetBridgeQuery;

  try
    Result.SQL.Text := 'SELECT * FROM EQUIVALENCIA WHERE REFERENCIAH = :REF AND UNIDADH = :UNI';
    Result.ParamByName('REF').AsString := AReferenciaH;
    Result.ParamByName('UNI').AsString := AUnidadH;
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function BuscarEquivalenciaXML(AReferenciaXML: string; AUnidadXML: string): TFDQuery;
begin
  if AReferenciaXML.Trim.IsEmpty or AUnidadXML.Trim.IsEmpty then
    raise Exception.Create('Referencia XML y Unidad XML son obligatorias para buscar equivalencia');

  Result := GetBridgeQuery;
  try
    Result.SQL.Text :=
      'SELECT * FROM EQUIVALENCIA ' +
      'WHERE REFERENCIA_XML = :REF AND UNIDAD_XML = :UNI';
    Result.ParamByName('REF').AsString := AReferenciaXML;
    Result.ParamByName('UNI').AsString := AUnidadXML;
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function ExisteEquivalencia(AReferenciaH: string; AUnidadH: string): Boolean;
var
  Q: TFDQuery;
begin
  Q := BuscarEquivalencia(AReferenciaH, AUnidadH);
  try
    Result := not Q.IsEmpty;
  finally
    Q.Free;
  end;
end;

function GetIDEquivalencia(AReferenciaH, AUnidadH: string): Integer;
begin
  Result := GetIDEquivalencia(nil, AReferenciaH, AUnidadH);
end;

function GetIDEquivalencia(AConnection: TFDConnection; AReferenciaH, AUnidadH: string): Integer;
var
  Q: TFDQuery;
begin
  Result := 0;
  Q := BuscarEquivalencia(AConnection, AReferenciaH, AUnidadH);
  try
    if not Q.IsEmpty then
      Result := Q.FieldByName('ID').AsInteger;
  finally
    Q.Free;
  end;
end;

function CrearEquivalencia(
  ACodigoH: Integer;
  ASubCodigoH: Integer;
  ANombreH: string;
  AReferenciaP: string;
  AUnidadP: string;
  AUnidadH: string;
  AReferenciaH: string;
  AFactor: Double
): Integer;
begin
  Result := CrearEquivalencia(nil, ACodigoH, ASubCodigoH, ANombreH, AReferenciaP, AUnidadP, AUnidadH, AReferenciaH, AFactor);
end;

function CrearEquivalencia(
  AConnection: TFDConnection;
  ACodigoH: Integer;
  ASubCodigoH: Integer;
  ANombreH: string;
  AReferenciaP: string;
  AUnidadP: string;
  AUnidadH: string;
  AReferenciaH: string;
  AFactor: Double
): Integer;
var
  Q: TFDQuery;
  LConnOwn: Boolean;
begin
  if AReferenciaH.Trim.IsEmpty or AUnidadH.Trim.IsEmpty then
    raise Exception.Create('Referencia XML y Unidad XML son obligatorias');

  LConnOwn := not Assigned(AConnection);
  if LConnOwn then
    AConnection := GetBridgeConnection;

  try
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := AConnection;

      // Check if it already exists to avoid duplicate errors
      Q.SQL.Text := 'SELECT ID FROM EQUIVALENCIA WHERE REFERENCIAH = :REF AND UNIDADH = :UNI';
      Q.ParamByName('REF').AsString := AReferenciaH;
      Q.ParamByName('UNI').AsString := AUnidadH;
      Q.Open;

      if not Q.IsEmpty then
      begin
        Result := Q.FieldByName('ID').AsInteger;
        Exit;
      end;
      Q.Close;

      Q.SQL.Text :=
        'INSERT INTO EQUIVALENCIA (CODIGOH, SUBCODIGOH, NOMBREH, REFERENCIAH, UNIDADH, UNIDADP, REFERENCIAP, FACTOR) ' +
        'VALUES (:CODIGOH, :SUBCODIGOH, :NOMBREH, :REFERENCIAH, :UNIDADH, :UNIDADP, :REFERENCIAP, :FACTOR) RETURNING ID';

      Q.ParamByName('CODIGOH').AsInteger := ACodigoH;
      Q.ParamByName('SUBCODIGOH').AsInteger := ASubCodigoH;
      Q.ParamByName('NOMBREH').AsString := ANombreH;
      Q.ParamByName('REFERENCIAH').AsString := AReferenciaH;
      Q.ParamByName('UNIDADH').AsString := AUnidadH;
      Q.ParamByName('UNIDADP').AsString := AUnidadP;
      Q.ParamByName('REFERENCIAP').AsString := AReferenciaP;
      Q.ParamByName('FACTOR').AsFloat := AFactor;

      Q.Open;
      Result := Q.FieldByName('ID').AsInteger;
    finally
      Q.Free;
    end;
  finally
    if LConnOwn then
      AConnection.Free;
  end;
end;

function ObtenerEquivalenciaJSON(AReferenciaH: string; AUnidadH: string): string;
var
  Q: TFDQuery;
  JSON: TJSONObject;
begin
  Result := '{}';
  if AReferenciaH.Trim.IsEmpty or AUnidadH.Trim.IsEmpty then
    Exit;

  Q := BuscarEquivalencia(AReferenciaH, AUnidadH);
  try
    if not Q.IsEmpty then
    begin
      JSON := TJSONObject.Create;
      try
        JSON.AddPair('codigoh', TJSONNumber.Create(Q.FieldByName('CODIGOH').AsInteger));
        JSON.AddPair('subcodigoh', TJSONNumber.Create(Q.FieldByName('SUBCODIGOH').AsInteger));
        JSON.AddPair('nombreh', Q.FieldByName('NOMBREH').AsString);
        JSON.AddPair('referenciah', Q.FieldByName('REFERENCIAH').AsString);
        JSON.AddPair('unidadh', Q.FieldByName('UNIDADH').AsString);
        JSON.AddPair('unidadp', Q.FieldByName('UNIDADP').AsString);
        JSON.AddPair('referenciap', Q.FieldByName('REFERENCIAP').AsString);
        JSON.AddPair('factor', TJSONNumber.Create(Q.FieldByName('FACTOR').AsFloat));
        Result := JSON.ToJSON;
      finally
        JSON.Free;
      end;
    end;
  finally
    Q.Free;
  end;
end;

function ListarEquivalencias(const AReferenciaH, AUnidadH: string; ALimite: Integer): TFDQuery;
var
  SQL: string;
begin
  Result := GetBridgeQuery;
  try
    SQL := 'SELECT FIRST :LIMIT * FROM EQUIVALENCIA WHERE 1=1';

    if not AReferenciaH.Trim.IsEmpty then
      SQL := SQL + ' AND REFERENCIAH = :REFX';

    if not AUnidadH.Trim.IsEmpty then
      SQL := SQL + ' AND UNIDADH = :UNIX';

    Result.SQL.Text := SQL;
    Result.ParamByName('LIMIT').AsInteger := ALimite;

    if not AReferenciaH.Trim.IsEmpty then
      Result.ParamByName('REFX').AsString := AReferenciaH;

    if not AUnidadH.Trim.IsEmpty then
      Result.ParamByName('UNIX').AsString := AUnidadH;

    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function EliminarEquivalencia(const AReferenciaH, AUnidadH: string): Boolean;
var
  Q: TFDQuery;
begin
  if AReferenciaH.Trim.IsEmpty or AUnidadH.Trim.IsEmpty then
    raise Exception.Create('Referencia XML y Unidad XML son obligatorias para eliminar');

  Q := GetBridgeQuery;
  try
    Q.SQL.Text := 'DELETE FROM EQUIVALENCIA WHERE REFERENCIAH = :REFX AND UNIDADH = :UNIX';
    Q.ParamByName('REFX').AsString := AReferenciaH;
    Q.ParamByName('UNIX').AsString := AUnidadH;
    Q.ExecSQL;
    Result := Q.RowsAffected > 0;
  finally
    Q.Free;
  end;
end;

end.
