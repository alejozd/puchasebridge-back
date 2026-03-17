unit FirebirdConnection;

interface

uses
  FireDAC.Comp.Client;

function CrearConexionGlobal: TFDConnection;
function CrearConexionParticular(pCodEmpresa: string): TFDConnection;

implementation

uses
  System.SysUtils, HConfig;

function CrearConexionGlobal: TFDConnection;
var
  Config: THelisaConfig;
begin
  Config := THConfig.GetInstance.Config;

  Result := TFDConnection.Create(nil);
  Result.DriverName := 'FB';

  if Config.Tipo = 'S' then
    Result.Params.Database := Config.RutaBaseDatos + '\helisabd.hgw'
  else
    Result.Params.Database := Config.Servidor + ':' + Config.RutaBaseDatos + '\helisabd.hgw';

  Result.Params.UserName := 'HELISAADMON';
  Result.Params.Password := 'U8JKR@fC';
  Result.LoginPrompt := False;

  Result.Connected := True;
end;

function CrearConexionParticular(pCodEmpresa: string): TFDConnection;
var
  Config: THelisaConfig;
  vBasedeDatos : string;
begin
  Config := THConfig.GetInstance.Config;

  Result := TFDConnection.Create(nil);
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
end;

end.
