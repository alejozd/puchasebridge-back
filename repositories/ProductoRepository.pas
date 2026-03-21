unit ProductoRepository;

interface

uses
  System.SysUtils,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection,
  ProveedorRepository; // For ValidarAnio

function ExisteProducto(Referencia, Nombre, Anio: string): Boolean;
function BuscarProductos(const AFiltro: string; ALimite: Integer; const AAnio: string): TFDQuery;

implementation

function ExisteProducto(Referencia, Nombre, Anio: string): Boolean;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  TableName: string;
begin
  // Los productos en Helisa están en la tabla INMAXXXX (independiente del año)
  TableName := 'INMAXXXX';
  
  Conn := CrearConexionParticular('0');
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text := Format('select CODIGO from %s where REFERENCIA = :REFERENCIA and NOMBRE = :NOMBRE', [TableName]);
    Q.ParamByName('REFERENCIA').AsString := Referencia;
    Q.ParamByName('NOMBRE').AsString := Nombre;
    Q.Open;
    Result := not Q.IsEmpty;
  finally
    Q.Free;
    Conn.Free;
  end;
end;

function BuscarProductos(const AFiltro: string; ALimite: Integer; const AAnio: string): TFDQuery;
var
  TableName: string;
  LConn: TFDConnection;
begin
  // Los productos en Helisa están en la tabla INMAXXXX (independiente del año)
  TableName := 'INMAXXXX';

  Result := TFDQuery.Create(nil);
  try
    LConn := CrearConexionParticular('0');
    Result.Connection := LConn;

    // Firebird 3.0+ uses FIRST SKIP or ROWS to limit
    // NOTA: Se usa SUBCODIGO como UNIDADH temporalmente mientras se determina el campo real de unidad.
    Result.SQL.Text := Format(
      'SELECT FIRST :LIMIT CODIGO, SUBCODIGO, NOMBRE, REFERENCIA, SUBCODIGO as UNIDADH ' +
      'FROM %s ' +
      'WHERE NOMBRE LIKE :FILTRO OR REFERENCIA LIKE :FILTRO ' +
      'ORDER BY NOMBRE', [TableName]);

    Result.ParamByName('LIMIT').AsInteger := ALimite;
    Result.ParamByName('FILTRO').AsString := '%' + AFiltro.ToUpper + '%';
    Result.Open;
  except
    if Assigned(Result.Connection) then
      Result.Connection.Free;
    Result.Free;
    raise;
  end;
end;

end.
