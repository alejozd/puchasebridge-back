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

const
  Seccion = 'Software Administrativo y de Gestion 2';

implementation

uses
  System.Win.Registry,
  Winapi.Windows;

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
end;

initialization
  THConfig.FLock := TCriticalSection.Create;

finalization
  if THConfig.FInstance <> nil then
    THConfig.FInstance.Free;
  THConfig.FLock.Free;

end.
