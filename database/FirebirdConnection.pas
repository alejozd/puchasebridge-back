unit FirebirdConnection;

interface

uses
  FireDAC.Comp.Client;

function CrearConexionGlobal: TFDConnection;
function CrearConexionParticular(pCodEmpresa: string): TFDConnection;

// Nuevas funciones para soporte multibase de datos
function GetHelisaConnection: TFDConnection;
function GetHelisaParticularConnection: TFDConnection;
function GetBridgeConnection: TFDConnection;
function GetHelisaQuery: TFDQuery;
function GetBridgeQuery: TFDQuery;
function TestBridgeConnection: Boolean;

implementation

uses
  System.SysUtils, System.IniFiles, System.IOUtils, HConfig, uPaths;

type
  TDBConfig = record
    User: string;
    Pass: string;
    Path: string;
  end;

function LoadDBConfig(const Section: string): TDBConfig;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(GetConfigPath);
  try
    if Section = 'HELISA' then
    begin
      Result.User := DecodeIfEncoded(
        Ini.ReadString('HELISA', 'User', 'HELISAADMON'), CONFIG_SECRET
      );
      Result.Pass := DecodeIfEncoded(
        Ini.ReadString('HELISA', 'Pass', ''), CONFIG_SECRET
      );
      Result.Path := '';
    end
    else if Section = 'BRIDGE' then
    begin
      Result.User := DecodeIfEncoded(
        Ini.ReadString('BRIDGE', 'User', 'SYSDBA'), CONFIG_SECRET
      );
      Result.Pass := DecodeIfEncoded(
        Ini.ReadString('BRIDGE', 'Pass', ''), CONFIG_SECRET
      );
      Result.Path := ResolvePathFromBase(
        Ini.ReadString('BRIDGE', 'Path', TPath.Combine('database', 'purchasebridge.fdb'))
      );
    end;
  finally
    Ini.Free;
  end;
end;

function CrearConexionGlobal: TFDConnection;
var
  Config: THelisaConfig;
  DBConfig: TDBConfig;
begin
  Config := THConfig.GetInstance.Config;
  DBConfig := LoadDBConfig('HELISA');

  Result := TFDConnection.Create(nil);
  try
    Result.DriverName := 'FB';

    if Config.Tipo = 'S' then
      Result.Params.Database := Config.RutaBaseDatos + '\helisabd.hgw'
    else
      Result.Params.Database := Config.Servidor + ':' + Config.RutaBaseDatos + '\helisabd.hgw';

    Result.Params.UserName := DBConfig.User;
    Result.Params.Password := DBConfig.Pass;
    Result.Params.Values['CharacterSet'] := 'UTF8';
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
  DBConfig: TDBConfig;
begin
  Config := THConfig.GetInstance.Config;
  DBConfig := LoadDBConfig('HELISA');

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

    Result.Params.UserName := DBConfig.User;
    Result.Params.Password := DBConfig.Pass;
    Result.Params.Values['CharacterSet'] := 'UTF8';
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

function GetHelisaParticularConnection: TFDConnection;
var
  Config: THelisaConfig;
begin
  Config := THConfig.GetInstance.Config;
  Result := CrearConexionParticular(Config.Empresa);
end;

function GetBridgeConnection: TFDConnection;
var
  DBConfig: TDBConfig;
begin
  DBConfig := LoadDBConfig('BRIDGE');

  Result := TFDConnection.Create(nil);
  try
    Result.DriverName := 'FB';
    Result.Params.Database := DBConfig.Path;
    Result.Params.UserName := DBConfig.User;
    Result.Params.Password := DBConfig.Pass;
    Result.Params.Values['CharacterSet'] := 'UTF8';
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
  DBConfig: TDBConfig;
  Conn: TFDConnection;
begin
  Config := THConfig.GetInstance.Config;
  DBConfig := LoadDBConfig('HELISA');

  Result := TFDQuery.Create(nil);
  try
    Conn := TFDConnection.Create(Result);
    Conn.DriverName := 'FB';
    if Config.Tipo = 'S' then
      Conn.Params.Database := Config.RutaBaseDatos + '\helisabd.hgw'
    else
      Conn.Params.Database := Config.Servidor + ':' + Config.RutaBaseDatos + '\helisabd.hgw';
    Conn.Params.UserName := DBConfig.User;
    Conn.Params.Password := DBConfig.Pass;
    Conn.Params.Values['CharacterSet'] := 'UTF8';
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
  DBConfig: TDBConfig;
begin
  DBConfig := LoadDBConfig('BRIDGE');

  Result := TFDQuery.Create(nil);
  try
    Conn := TFDConnection.Create(Result);
    Conn.DriverName := 'FB';
    Conn.Params.Database := DBConfig.Path;
    Conn.Params.UserName := DBConfig.User;
    Conn.Params.Password := DBConfig.Pass;
    Conn.Params.Values['CharacterSet'] := 'UTF8';
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
