unit LicenseService;

interface

uses
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  System.Net.HttpClient,
  System.Net.HttpClientComponent,
  System.IOUtils,
  System.Classes,
  HConfig,
  uLogger;

type
  TLicenseService = class
  private
    class function GetInstalacionHash: string;
    class procedure GuardarLicenciaLocal(const AJSON: TJSONObject);
    class function LeerLicenciaLocal: TJSONObject;
    class function ValidarOffline: Boolean;
    class procedure BloquearSistema(const AMsg: string);
    class function GetLicenseFilePath: string;
  public
    class procedure InicializarLicencia;
    class function ActivarLicencia: Boolean;
    class function ValidarLicencia: Boolean;
  end;

implementation

uses
  Winapi.Windows,
  System.Hash;

const
  UNLEN = 256;

{ TLicenseService }

class procedure TLicenseService.BloquearSistema(const AMsg: string);
begin
  Log('SISTEMA BLOQUEADO: ' + AMsg, llError);
  Writeln('---------------------------------------------------------');
  Writeln('ERROR DE LICENCIA: ' + AMsg);
  Writeln('El servidor no puede iniciar sin una licencia valida.');
  Writeln('---------------------------------------------------------');
  // En una aplicación de consola como esta, podemos lanzar una excepción
  // que detendrá el flujo antes de que Horse inicie.
  raise Exception.Create('Licencia Invalida: ' + AMsg);
end;

class function TLicenseService.GetInstalacionHash: string;
var
  ComputerName: array[0..MAX_COMPUTERNAME_LENGTH] of Char;
  Size: DWORD;
  UserName: array[0..UNLEN] of Char;
  UserSize: DWORD;
  RawString: string;
  VolumeSerialNumber: DWORD;
  MaximumComponentLength: DWORD;
  FileSystemFlags: DWORD;
begin
  Size := MAX_COMPUTERNAME_LENGTH + 1;
  GetComputerName(ComputerName, Size);

  UserSize := UNLEN + 1;
  GetUserName(UserName, UserSize);

  VolumeSerialNumber := 0;
  GetVolumeInformation('C:\', nil, 0, @VolumeSerialNumber, MaximumComponentLength, FileSystemFlags, nil, 0);

  RawString := string(ComputerName) + '|' + string(UserName) + '|' + IntToHex(VolumeSerialNumber, 8);
  Result := THashSHA2.GetHashString(RawString);
end;

class function TLicenseService.GetLicenseFilePath: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(GetModuleName(HInstance)), 'licencia.json');
end;

class procedure TLicenseService.GuardarLicenciaLocal(const AJSON: TJSONObject);
var
  LList: TStringList;
begin
  LList := TStringList.Create;
  try
    if not Assigned(AJSON.GetValue('ultima_validacion')) then
      AJSON.AddPair('ultima_validacion', FormatDateTime('yyyy-mm-dd', Now));
    LList.Text := AJSON.ToJSON;
    LList.SaveToFile(GetLicenseFilePath);
  finally
    LList.Free;
  end;
end;

class function TLicenseService.LeerLicenciaLocal: TJSONObject;
var
  LContent: string;
begin
  Result := nil;
  if TFile.Exists(GetLicenseFilePath) then
  begin
    try
      LContent := TFile.ReadAllText(GetLicenseFilePath);
      Result := TJSONObject.ParseJSONValue(LContent) as TJSONObject;
    except
      on E: Exception do
        Log('Error leyendo licencia local: ' + E.Message, llError);
    end;
  end;
end;

class procedure TLicenseService.InicializarLicencia;
begin
  Log('Iniciando validacion de licencia...', llInfo);
  if not ValidarLicencia then
  begin
    if not ValidarOffline then
    begin
       // Intentar activar automáticamente si no hay nada
       if not ActivarLicencia then
         BloquearSistema('No se pudo validar ni activar la licencia online, y no hay respaldo local valido.');
    end;
  end;
  Log('Licencia validada correctamente.', llInfo);
end;

class function TLicenseService.ActivarLicencia: Boolean;
var
  LHTTP: TNetHTTPClient;
  LResponse: IHTTPResponse;
  LJSON, LClone: TJSONObject;
  LBody: TStringStream;
  LConfig: TLicensingConfig;
begin
  Result := False;
  LConfig := THConfig.GetInstance.License;

  if LConfig.Nit.IsEmpty then
  begin
    Log('NIT no configurado en config.ini [LICENCIA]', llError);
    Exit;
  end;

  LHTTP := TNetHTTPClient.Create(nil);
  LJSON := TJSONObject.Create;
  try
    LJSON.AddPair('nit', LConfig.Nit);
    LJSON.AddPair('instalacion_hash', GetInstalacionHash);
    LJSON.AddPair('app', LConfig.AppName);

    LBody := TStringStream.Create(LJSON.ToJSON, TEncoding.UTF8);
    try
      try
        LHTTP.ContentType := 'application/json';
        LResponse := LHTTP.Post(LConfig.URLServidor + '/api/licencias/activar', LBody);

        if LResponse.StatusCode = 200 then
        begin
          Log('Activacion exitosa.', llInfo);
          LJSON.Free;
          LJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
          LClone := LJSON.Clone as TJSONObject;
          try
            GuardarLicenciaLocal(LClone);
          finally
            LClone.Free;
          end;
          Result := True;
        end
        else
          Log('Error en activacion: ' + LResponse.ContentAsString, llWarn);
      except
        on E: Exception do
          Log('Error de conexion al activar licencia: ' + E.Message, llError);
      end;
    finally
      LBody.Free;
    end;
  finally
    LJSON.Free;
    LHTTP.Free;
  end;
end;

class function TLicenseService.ValidarLicencia: Boolean;
var
  LHTTP: TNetHTTPClient;
  LResponse: IHTTPResponse;
  LJSON, LClone: TJSONObject;
  LBody: TStringStream;
  LConfig: TLicensingConfig;
begin
  Result := False;
  LConfig := THConfig.GetInstance.License;

  if LConfig.Nit.IsEmpty then Exit;

  LHTTP := TNetHTTPClient.Create(nil);
  LHTTP.ConnectionTimeout := 5000;
  LHTTP.ResponseTimeout := 5000;

  LJSON := TJSONObject.Create;
  try
    LJSON.AddPair('nit', LConfig.Nit);
    LJSON.AddPair('instalacion_hash', GetInstalacionHash);
    LJSON.AddPair('app', LConfig.AppName);

    LBody := TStringStream.Create(LJSON.ToJSON, TEncoding.UTF8);
    try
      try
        LHTTP.ContentType := 'application/json';
        LResponse := LHTTP.Post(LConfig.URLServidor + '/api/licencias/validar', LBody);

        if LResponse.StatusCode = 200 then
        begin
          LJSON.Free;
          LJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
          if Assigned(LJSON) and (LJSON.GetValue('estado').Value <> 'bloqueado') then
          begin
            LClone := LJSON.Clone as TJSONObject;
            try
              GuardarLicenciaLocal(LClone);
            finally
              LClone.Free;
            end;
            Result := True;
          end;
        end;
      except
        on E: Exception do
          Log('Error de conexion al validar licencia (posible modo offline): ' + E.Message, llDebug);
      end;
    finally
      LBody.Free;
    end;
  finally
    LJSON.Free;
    LHTTP.Free;
  end;
end;

class function TLicenseService.ValidarOffline: Boolean;
var
  LJSON: TJSONObject;
  LExpira: TDate;
  LEstado: string;
begin
  Result := False;
  LJSON := LeerLicenciaLocal;
  if Assigned(LJSON) then
  try
    LEstado := LJSON.GetValue('estado').Value;
    if LEstado = 'bloqueado' then Exit(False);

    if TryISO8601ToDate(LJSON.GetValue('expira').Value, LExpira) then
    begin
      if Date <= LExpira then
      begin
        Log('Validacion offline exitosa. Expira: ' + DateToStr(LExpira), llInfo);
        Result := True;
      end
      else
        Log('Licencia local expirada: ' + DateToStr(LExpira), llWarn);
    end;
  finally
    LJSON.Free;
  end;
end;

end.
