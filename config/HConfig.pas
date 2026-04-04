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
  end;

  TLicensingConfig = record
    URLServidor: string;
    Nit: string;
    AppName: string;
    InstalacionHash: string;
  end;

  THConfig = class
  private
    FConfig: THelisaConfig;
    FLicense: TLicensingConfig;
    class var FInstance: THConfig;
    class var FLock: TCriticalSection;
    constructor Create;
    procedure Load;
    function GetConfigPath: string;
  public
    class function GetInstance: THConfig;
    procedure UpdateInstalacionHash(const AHash: string);
    property Config: THelisaConfig read FConfig;
    property License: TLicensingConfig read FLicense;
  end;

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

function THConfig.GetConfigPath: string;
var
  AppPath: string;
begin
  AppPath := TPath.GetDirectoryName(GetModuleName(HInstance));
  Result := TPath.Combine(AppPath, 'config.ini');
end;

procedure THConfig.Load;
var
  Reg: TRegistry;
  Clave: string;
  Ini: TIniFile;
begin
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    Clave := 'Software\Helisa\' + Seccion;

    if not Reg.OpenKeyReadOnly(Clave) then
      raise Exception.Create('No se encontr' + #243 + ' configuraci' + #243 + ' n Helisa en HKLM');

    FConfig.RutaPrograma := Reg.ReadString('Programa');
    FConfig.RutaBaseDatos := Reg.ReadString('Base de datos');
    FConfig.RutaArchivos := Reg.ReadString('Archivos');
    FConfig.Servidor := Reg.ReadString('Servidor');
    FConfig.Tipo := Reg.ReadString('Tipo');
  finally
    Reg.Free;
  end;

  Ini := TIniFile.Create(GetConfigPath);
  try
    FConfig.Empresa := Ini.ReadString('HELISA', 'Empresa', '0');

    FLicense.URLServidor := Ini.ReadString('LICENCIA', 'URLServidor', '');
    FLicense.Nit := Ini.ReadString('LICENCIA', 'Nit', '');
    FLicense.AppName := Ini.ReadString('LICENCIA', 'App', 'purchasebridge');
    FLicense.InstalacionHash := Ini.ReadString('LICENCIA', 'InstalacionHash', '');
  finally
    Ini.Free;
  end;
end;

procedure THConfig.UpdateInstalacionHash(const AHash: string);
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(GetConfigPath);
  try
    Ini.WriteString('LICENCIA', 'InstalacionHash', AHash);
    FLicense.InstalacionHash := AHash;
  finally
    Ini.Free;
  end;
end;

initialization
  THConfig.FLock := TCriticalSection.Create;

finalization
  if THConfig.FInstance <> nil then
    THConfig.FInstance.Free;
  THConfig.FLock.Free;

end.
