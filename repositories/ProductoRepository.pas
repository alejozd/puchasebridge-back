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
  Anio := ValidarAnio(Anio);
  TableName := 'INMA' + Anio;
  
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
  TableName := 'INMA' + ValidarAnio(AAnio);

  Result := TFDQuery.Create(nil);
  try
    LConn := CrearConexionParticular('0');
    LConn.Owner := Result; // Ensure connection is freed with query
    Result.Connection := LConn;

    // Firebird 3.0+ uses FIRST SKIP or ROWS to limit
    Result.SQL.Text := Format(
      'SELECT FIRST :LIMIT CODIGO, SUBCODIGO, NOMBRE, REFERENCIA, CODUND as UNIDAD ' +
      'FROM %s ' +
      'WHERE NOMBRE LIKE :FILTRO OR REFERENCIA LIKE :FILTRO ' +
      'ORDER BY NOMBRE', [TableName]);

    Result.ParamByName('LIMIT').AsInteger := ALimite;
    Result.ParamByName('FILTRO').AsString := '%' + AFiltro.ToUpper + '%';
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

end.
