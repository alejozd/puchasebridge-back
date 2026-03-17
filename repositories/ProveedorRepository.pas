unit ProveedorRepository;

interface

uses
  System.SysUtils,
  HConfig,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Stan.Intf,
  FireDAC.DApt;

type
  TProveedorInfo = record
    Existe: Boolean;
    Codigo: string;
  end;

  function ExisteProveedor(Codigo: string): Boolean;
  function ValidarAnio(const Anio: string): string;
  function ObtenerProveedorPorNit(NitProveedor: string; Anio: string): TProveedorInfo;

implementation

uses FirebirdConnection, FireDAC.Comp.Client, FireDAC.Stan.Param;

function ValidarAnio(const Anio: string): string;
var
  Dummy: Integer;
begin
  if (Length(Anio) = 4) and TryStrToInt(Anio, Dummy) then
    Result := Anio
  else
    Result := FormatDateTime('yyyy', Now);
end;

function ExisteProveedor(Codigo: string): Boolean;
var
  Conn: TFDConnection;
  Q: TFDQuery;
begin
  Conn := CrearConexionParticular('00');
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text := 'select codigo from proveedores where codigo = :codigo';
    Q.ParamByName('codigo').AsString := Codigo;
    Q.Open;
    Result := not Q.IsEmpty;
  finally
    Q.Free;
    Conn.Free;
  end;
end;

function ObtenerProveedorPorNit(NitProveedor: string; Anio: string): TProveedorInfo;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  TableName: string;
begin
  Anio := ValidarAnio(Anio);
  TableName := 'CPMA' + Anio;
  
  Result.Existe := False;
  Result.Codigo := '';

  Conn := CrearConexionParticular('0');
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text := Format('select codigo from %s where TRIM(IDENTIDAD) = :IDENTIDAD', [TableName]);
    Q.ParamByName('IDENTIDAD').AsString := NitProveedor;
    Q.Open;
    
    if not Q.IsEmpty then
    begin
      Result.Existe := True;
      Result.Codigo := Q.FieldByName('codigo').AsString;
    end;
  finally
    Q.Free;
    Conn.Free;
  end;
end;

end.
