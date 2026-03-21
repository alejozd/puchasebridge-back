unit EquivalenciaService;

interface

uses
  System.SysUtils,
  System.JSON,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection;

function BuscarEquivalencia(AReferenciaP: string; AUnidadP: string): TFDQuery;
function ExisteEquivalencia(AReferenciaP: string; AUnidadP: string): Boolean;
procedure CrearEquivalencia(
  ACodigoH: Integer;
  ASubCodigoH: Integer;
  ANombreH: string;
  AReferenciaH: string;
  AUnidadH: string;
  AUnidadP: string;
  AReferenciaP: string;
  AFactor: Double
);
function ObtenerEquivalenciaJSON(AReferenciaP: string; AUnidadP: string): string;

// Nuevas funciones
function ListarEquivalencias(const AReferenciaP, AUnidadP: string; ALimite: Integer): TFDQuery;
function EliminarEquivalencia(const AReferenciaP, AUnidadP: string): Boolean;

implementation

function BuscarEquivalencia(AReferenciaP: string; AUnidadP: string): TFDQuery;
begin
  if AReferenciaP.Trim.IsEmpty or AUnidadP.Trim.IsEmpty then
    raise Exception.Create('Referencia y Unidad son obligatorias para buscar equivalencia');

  Result := GetBridgeQuery;
  try
    Result.SQL.Text := 'SELECT * FROM EQUIVALENCIA WHERE REFERENCIAP = :REF AND UNIDADP = :UNI';
    Result.ParamByName('REF').AsString := AReferenciaP;
    Result.ParamByName('UNI').AsString := AUnidadP;
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function ExisteEquivalencia(AReferenciaP: string; AUnidadP: string): Boolean;
var
  Q: TFDQuery;
begin
  Q := BuscarEquivalencia(AReferenciaP, AUnidadP);
  try
    Result := not Q.IsEmpty;
  finally
    Q.Free;
  end;
end;

procedure CrearEquivalencia(
  ACodigoH: Integer;
  ASubCodigoH: Integer;
  ANombreH: string;
  AReferenciaH: string;
  AUnidadH: string;
  AUnidadP: string;
  AReferenciaP: string;
  AFactor: Double
);
var
  Q: TFDQuery;
begin
  if AReferenciaP.Trim.IsEmpty or AUnidadP.Trim.IsEmpty then
    raise Exception.Create('Referencia y Unidad del proveedor son obligatorias');

  if ExisteEquivalencia(AReferenciaP, AUnidadP) then
    raise Exception.CreateFmt('Ya existe una equivalencia para la referencia %s y unidad %s', [AReferenciaP, AUnidadP]);

  Q := GetBridgeQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO EQUIVALENCIA (CODIGOH, SUBCODIGOH, NOMBREH, REFERENCIAH, UNIDADH, UNIDADP, REFERENCIAP, FACTOR) ' +
      'VALUES (:CODIGOH, :SUBCODIGOH, :NOMBREH, :REFERENCIAH, :UNIDADH, :UNIDADP, :REFERENCIAP, :FACTOR)';

    Q.ParamByName('CODIGOH').AsInteger := ACodigoH;
    Q.ParamByName('SUBCODIGOH').AsInteger := ASubCodigoH;
    Q.ParamByName('NOMBREH').AsString := ANombreH;
    Q.ParamByName('REFERENCIAH').AsString := AReferenciaH;
    Q.ParamByName('UNIDADH').AsString := AUnidadH;
    Q.ParamByName('UNIDADP').AsString := AUnidadP;
    Q.ParamByName('REFERENCIAP').AsString := AReferenciaP;
    Q.ParamByName('FACTOR').AsFloat := AFactor;

    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function ObtenerEquivalenciaJSON(AReferenciaP: string; AUnidadP: string): string;
var
  Q: TFDQuery;
  JSON: TJSONObject;
begin
  Result := '{}';
  if AReferenciaP.Trim.IsEmpty or AUnidadP.Trim.IsEmpty then
    Exit;

  Q := BuscarEquivalencia(AReferenciaP, AUnidadP);
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

function ListarEquivalencias(const AReferenciaP, AUnidadP: string; ALimite: Integer): TFDQuery;
var
  SQL: string;
begin
  Result := GetBridgeQuery;
  try
    SQL := 'SELECT FIRST :LIMIT * FROM EQUIVALENCIA WHERE 1=1';

    if not AReferenciaP.Trim.IsEmpty then
      SQL := SQL + ' AND REFERENCIAP = :REFP';

    if not AUnidadP.Trim.IsEmpty then
      SQL := SQL + ' AND UNIDADP = :UNIP';

    Result.SQL.Text := SQL;
    Result.ParamByName('LIMIT').AsInteger := ALimite;

    if not AReferenciaP.Trim.IsEmpty then
      Result.ParamByName('REFP').AsString := AReferenciaP;

    if not AUnidadP.Trim.IsEmpty then
      Result.ParamByName('UNIP').AsString := AUnidadP;

    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function EliminarEquivalencia(const AReferenciaP, AUnidadP: string): Boolean;
var
  Q: TFDQuery;
begin
  if AReferenciaP.Trim.IsEmpty or AUnidadP.Trim.IsEmpty then
    raise Exception.Create('Referencia y Unidad son obligatorias para eliminar');

  Q := GetBridgeQuery;
  try
    Q.SQL.Text := 'DELETE FROM EQUIVALENCIA WHERE REFERENCIAP = :REFP AND UNIDADP = :UNIP';
    Q.ParamByName('REFP').AsString := AReferenciaP;
    Q.ParamByName('UNIP').AsString := AUnidadP;
    Q.ExecSQL;
    Result := Q.RowsAffected > 0;
  finally
    Q.Free;
  end;
end;

end.
