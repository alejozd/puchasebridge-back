unit HConfig;

interface

uses
  System.SysUtils, System.SyncObjs;

const
  CONFIG_SECRET = 'Alejandro123*-+';

function EncodeBase64WithSecret(const AValue, ASecret: string): string;
function DecodeBase64WithSecret(const AEncodedValue, ASecret: string): string;
function DecodeIfEncoded(const AValue, ASecret: string): string;

type
  THelisaConfig = record
    RutaPrograma: string;
    RutaBaseDatos: string;
    RutaArchivos: string;
    Servidor: string;
    Tipo: string;
    Empresa: string;
    LogLevel: string;
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
  System.IOUtils,
  System.NetEncoding,
  System.StrUtils,
  uPaths;

const
  ENCODED_PREFIX = 'ENC:';

function EncodeBase64WithSecret(const AValue, ASecret: string): string;
var
  Payload: string;
begin
  Payload := ASecret + ':' + AValue;
  Result := ENCODED_PREFIX + TNetEncoding.Base64.Encode(Payload);
end;

function DecodeBase64WithSecret(const AEncodedValue, ASecret: string): string;
var
  Decoded: string;
  SecretPrefix: string;
begin
  SecretPrefix := ASecret + ':';
  Decoded := TNetEncoding.Base64.Decode(AEncodedValue);

  if StartsText(SecretPrefix, Decoded) then
    Result := Copy(Decoded, Length(SecretPrefix) + 1, MaxInt)
  else
    Result := '';
end;

function DecodeIfEncoded(const AValue, ASecret: string): string;
var
  EncodedPart: string;
  DecodedValue: string;
begin
  Result := AValue;

  if not StartsText(ENCODED_PREFIX, AValue) then
    Exit;

  EncodedPart := Copy(AValue, Length(ENCODED_PREFIX) + 1, MaxInt);

  try
    DecodedValue := DecodeBase64WithSecret(EncodedPart, ASecret);
    if DecodedValue <> '' then
      Result := DecodedValue;
  except
    Result := AValue;
  end;
end;

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
begin
  Result := uPaths.GetConfigPath;
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
    FConfig.LogLevel := Ini.ReadString('LOGGING', 'LogLevel', 'INFO').ToUpper;

    FLicense.URLServidor := DecodeIfEncoded(
      Ini.ReadString('LICENCIA', 'URLServidor', ''), CONFIG_SECRET
    );
    FLicense.Nit := Ini.ReadString('LICENCIA', 'Nit', '');
    FLicense.AppName := Ini.ReadString('LICENCIA', 'App', 'PurchaseBridge');
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
