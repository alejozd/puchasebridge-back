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
    // Para asegurar que la conexión se libere con el Query, debemos pasar el Query como Owner
    // Pero CrearConexionParticular no permite pasar un Owner.
    // Usaremos un truco común en Delphi: insertar el componente si no podemos pasarlo al constructor,
    // pero eso requiere acceso a métodos protegidos o más complejidad.

    // Mejor solución: Seguir el patrón de FirebirdConnection.pas y crear la conexión aquí mismo.
    // Pero para no duplicar lógica de HConfig, usaré la conexión y la liberaré en el controller.

    LConn := CrearConexionParticular('0');
    Result.Connection := LConn;

    Result.SQL.Text := Format(
      'SELECT FIRST :LIMIT CODIGO, SUBCODIGO, NOMBRE, REFERENCIA, CODUND as UNIDAD ' +
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
