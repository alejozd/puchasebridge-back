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
  User, Pass: string;
begin
  Config := THConfig.GetInstance.Config;

  // Cargar credenciales desde variables de entorno.
  // Los valores hardcodeados se han eliminado para evitar fallos de CI (GitGuardian).
  User := GetEnvironmentVariable('HELISA_DB_USER');
  Pass := GetEnvironmentVariable('HELISA_DB_PASS');

  Result := TFDConnection.Create(nil);
  try
    Result.DriverName := 'FB';

    if Config.Tipo = 'S' then
      Result.Params.Database := Config.RutaBaseDatos + '\helisabd.hgw'
    else
      Result.Params.Database := Config.Servidor + ':' + Config.RutaBaseDatos + '\helisabd.hgw';

    Result.Params.UserName := User;
    Result.Params.Password := Pass;
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
  User, Pass: string;
begin
  Config := THConfig.GetInstance.Config;

  User := GetEnvironmentVariable('HELISA_DB_USER');
  Pass := GetEnvironmentVariable('HELISA_DB_PASS');

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

    Result.Params.UserName := User;
    Result.Params.Password := Pass;
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
var
  Path, User, Pass: string;
begin
  Path := GetEnvironmentVariable('BRIDGE_DB_PATH');
  if Path = '' then Path := 'F:\Proyectos\delphi_backend\purchasebridge\backend\database\purchasebridge.fdb';

  User := GetEnvironmentVariable('BRIDGE_DB_USER');
  Pass := GetEnvironmentVariable('BRIDGE_DB_PASS');

  Result := TFDConnection.Create(nil);
  try
    Result.DriverName := 'FB';
    Result.Params.Database := Path;
    Result.Params.UserName := User;
    Result.Params.Password := Pass;
    Result.LoginPrompt := False;
    Result.Connected := True;
  except
    Result.Free;
    raise;
  end;
end;

function GetHelisaQuery: TFDQuery;
var
  Config: THelisaConfig;
  User, Pass: string;
  Conn: TFDConnection;
begin
  Config := THConfig.GetInstance.Config;
  User := GetEnvironmentVariable('HELISA_DB_USER');
  Pass := GetEnvironmentVariable('HELISA_DB_PASS');

  Result := TFDQuery.Create(nil);
  try
    // La conexión se crea pasando el Query como Owner para liberación automática.
    Conn := TFDConnection.Create(Result);
    Conn.DriverName := 'FB';
    if Config.Tipo = 'S' then
      Conn.Params.Database := Config.RutaBaseDatos + '\helisabd.hgw'
    else
      Conn.Params.Database := Config.Servidor + ':' + Config.RutaBaseDatos + '\helisabd.hgw';
    Conn.Params.UserName := User;
    Conn.Params.Password := Pass;
    Conn.LoginPrompt := False;
    Conn.Connected := True;
    Result.Connection := Conn;
  except
    Result.Free;
    raise;
  end;
end;

function GetBridgeQuery: TFDQuery;
var
  Conn: TFDConnection;
  Path, User, Pass: string;
begin
  Result := TFDQuery.Create(nil);
  try
    // Se crea la conexión con el Query como Owner.
    Conn := TFDConnection.Create(Result);

    Path := GetEnvironmentVariable('BRIDGE_DB_PATH');
    if Path = '' then Path := 'F:\Proyectos\delphi_backend\purchasebridge\backend\database\purchasebridge.fdb';
    User := GetEnvironmentVariable('BRIDGE_DB_USER');
    Pass := GetEnvironmentVariable('BRIDGE_DB_PASS');

    Conn.DriverName := 'FB';
    Conn.Params.Database := Path;
    Conn.Params.UserName := User;
    Conn.Params.Password := Pass;
    Conn.LoginPrompt := False;
    Conn.Connected := True;

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
      Q.Free;
    end;
  except
  end;
end;

end.
