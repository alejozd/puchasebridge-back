unit HConfig;

interface

uses
  System.SysUtils, System.SyncObjs;

type
  THelisaConfig = record
    RutaPrograma: string;
    RutaBaseDatos: string;
    RutaArchivos: string;
    Servidor: string;
    Tipo: string;
    Empresa: string;
    UnidadesPath: string;
  end;

  THConfig = class
  private
    FConfig: THelisaConfig;
    class var FInstance: THConfig;
    class var FLock: TCriticalSection;
    constructor Create;
    procedure Load;
  public
    class function GetInstance: THConfig;
    property Config: THelisaConfig read FConfig;
  end;

function GetUnidadesPath: string;

const
  Seccion = 'Software Administrativo y de Gestion 2';

implementation

uses
  System.Win.Registry,
  Winapi.Windows,
  System.IniFiles,
  System.IOUtils;

{ THConfig }

constructor THConfig.Create;
begin
  Load;
end;

class function THConfig.GetInstance: THConfig;
begin
  if FInstance = nil then
  begin
    FLock.Enter;
    try
      if FInstance = nil then
        FInstance := THConfig.Create;
    finally
      FLock.Leave;
    end;
  end;
  Result := FInstance;
end;

procedure THConfig.Load;
var
  Reg: TRegistry;
  Clave: string;
  Ini: TIniFile;
  AppPath: string;
begin
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    Clave := 'Software\Helisa\' + Seccion;

    if Reg.OpenKeyReadOnly(Clave) then
    begin
      FConfig.RutaPrograma := Reg.ReadString('Programa');
      FConfig.RutaBaseDatos := Reg.ReadString('Base de datos');
      FConfig.RutaArchivos := Reg.ReadString('Archivos');
      FConfig.Servidor := Reg.ReadString('Servidor');
      FConfig.Tipo := Reg.ReadString('Tipo');
    end;
  finally
    Reg.Free;
  end;

  AppPath := TPath.GetDirectoryName(GetModuleName(HInstance));
  Ini := TIniFile.Create(TPath.Combine(AppPath, 'config.ini'));
  try
    FConfig.Empresa := Ini.ReadString('HELISA', 'Empresa', '0');
    FConfig.UnidadesPath := Ini.ReadString('DIAN', 'UnidadesPath', '');
  finally
    Ini.Free;
  end;
end;

function GetUnidadesPath: string;
var
  LConfig: THelisaConfig;
  LAppPath: string;
begin
  LConfig := THConfig.GetInstance.Config;
  Result := LConfig.UnidadesPath;

  if (Result <> '') and not TPath.IsPathRooted(Result) then
  begin
    LAppPath := TPath.GetDirectoryName(GetModuleName(HInstance));
    Result := TPath.Combine(LAppPath, Result);
  end;
end;

initialization
  THConfig.FLock := TCriticalSection.Create;

finalization
  if THConfig.FInstance <> nil then
    THConfig.FInstance.Free;
  THConfig.FLock.Free;

end.
