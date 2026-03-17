unit ProductoRepository;

interface

uses
  System.SysUtils,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection,
  ProveedorRepository; // For ValidarAnio

function ExisteProducto(Referencia, Nombre, Anio: string): Boolean;

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

end.
