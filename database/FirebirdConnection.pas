unit FirebirdConnection;

interface

uses
  FireDAC.Comp.Client;

function CrearConexionGlobal: TFDConnection;
function CrearConexionParticular(pCodEmpresa: string): TFDConnection;

// Nuevas funciones para soporte multibase de datos
function GetHelisaConnection: TFDConnection;
function GetBridgeConnection: TFDConnection;
function GetHelisaQuery: TFDQuery;
function GetBridgeQuery: TFDQuery;
function TestBridgeConnection: Boolean;

implementation

uses
  System.SysUtils, HConfig;

function CrearConexionGlobal: TFDConnection;
var
  Config: THelisaConfig;
begin
  Config := THConfig.GetInstance.Config;

  Result := TFDConnection.Create(nil);
  try
    Result.DriverName := 'FB';

    if Config.Tipo = 'S' then
      Result.Params.Database := Config.RutaBaseDatos + '\helisabd.hgw'
    else
      Result.Params.Database := Config.Servidor + ':' + Config.RutaBaseDatos + '\helisabd.hgw';

    Result.Params.UserName := 'HELISAADMON';
    Result.Params.Password := 'U8JKR@fC';
    Result.LoginPrompt := False;

    Result.Connected := True;
  except
    Result.Free;
    raise;
  end;
end;

function CrearConexionParticular(pCodEmpresa: string): TFDConnection;
var
  Config: THelisaConfig;
  vBasedeDatos : string;
begin
  Config := THConfig.GetInstance.Config;

  Result := TFDConnection.Create(nil);
  try
    Result.DriverName := 'FB';

    if StrToInt(pCodEmpresa) < 10 then
      vBasedeDatos := 'heli0' + pCodEmpresa + 'bd.hgw'
    else
      vBasedeDatos := 'heli' + pCodEmpresa + 'bd.hgw';

    if Config.Tipo = 'S' then
        Result.Params.Database := Config.RutaBaseDatos + '\' + vBasedeDatos
      else
        Result.Params.Database := Config.Servidor + ':' + Config.RutaBaseDatos + '\' + vBasedeDatos;

    Result.Params.UserName := 'HELISAADMON';
    Result.Params.Password := 'U8JKR@fC';
    Result.LoginPrompt := False;

    Result.Connected := True;
  except
    Result.Free;
    raise;
  end;
end;

function GetHelisaConnection: TFDConnection;
begin
  Result := CrearConexionGlobal;
end;

function GetBridgeConnection: TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    Result.DriverName := 'FB';
    Result.Params.Database := 'F:\Proyectos\delphi_backend\purchasebridge\backend\database\purchasebridge.fdb';
    Result.Params.UserName := 'SYSDBA';
    Result.Params.Password := 'B8@AjN?Z';
    Result.LoginPrompt := False;
    Result.Connected := True;
  except
    Result.Free;
    raise;
  end;
end;

function GetHelisaQuery: TFDQuery;
var
  Conn: TFDConnection;
begin
  Result := TFDQuery.Create(nil);
  try
    Conn := GetHelisaConnection;
    Conn.Owner := Result; // La query se vuelve dueña de la conexión para liberarla automáticamente
    Result.Connection := Conn;
  except
    Result.Free;
    raise;
  end;
end;

function GetBridgeQuery: TFDQuery;
var
  Conn: TFDConnection;
begin
  Result := TFDQuery.Create(nil);
  try
    Conn := GetBridgeConnection;
    Conn.Owner := Result; // La query se vuelve dueña de la conexión para liberarla automáticamente
    Result.Connection := Conn;
  except
    Result.Free;
    raise;
  end;
end;

function TestBridgeConnection: Boolean;
var
  Q: TFDQuery;
begin
  Result := False;
  try
    Q := GetBridgeQuery;
    try
      Q.SQL.Text := 'SELECT 1 FROM RDB$DATABASE';
      Q.Open;
      Result := not Q.IsEmpty;
    finally
      Q.Free; // Libera el query y por ende la conexión (por ser el Owner)
    end;
  except
    // Retornar false si no se puede conectar o ejecutar la consulta
  end;
end;

end.
