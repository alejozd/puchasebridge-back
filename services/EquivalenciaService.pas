unit EquivalenciaService;

interface

uses
  System.SysUtils,
  System.JSON,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection;

function BuscarEquivalencia(AReferenciaH: string; AUnidadH: string): TFDQuery;
function ExisteEquivalencia(AReferenciaH: string; AUnidadH: string): Boolean;
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
function ObtenerEquivalenciaJSON(AReferenciaH: string; AUnidadH: string): string;

// Nuevas funciones
function ListarEquivalencias(const AReferenciaH, AUnidadH: string; ALimite: Integer): TFDQuery;
function EliminarEquivalencia(const AReferenciaH, AUnidadH: string): Boolean;

implementation

function BuscarEquivalencia(AReferenciaH: string; AUnidadH: string): TFDQuery;
begin
  if AReferenciaH.Trim.IsEmpty or AUnidadH.Trim.IsEmpty then
    raise Exception.Create('Referencia XML y Unidad XML son obligatorias para buscar equivalencia');

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
  if AReferenciaH.Trim.IsEmpty or AUnidadH.Trim.IsEmpty then
    raise Exception.Create('Referencia XML y Unidad XML son obligatorias');

  if ExisteEquivalencia(AReferenciaH, AUnidadH) then
    raise Exception.CreateFmt('Ya existe una equivalencia para la referencia XML %s y unidad %s', [AReferenciaH, AUnidadH]);

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
