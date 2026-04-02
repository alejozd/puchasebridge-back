unit LicenseService;

interface

uses
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  System.Net.HttpClient,
  System.Net.HttpClientComponent,
  System.Net.URLClient,
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
    class function CloneJSON(const AJSON: TJSONObject): TJSONObject;
    class function NormalizeURL(const ABaseURL: string): string;
  public
    class procedure InicializarLicencia;
    class function ActivarLicencia: Boolean;
    class function ValidarLicencia: Boolean;
  end;

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows,
  System.Hash;
{$ELSE}
uses
  System.Hash;
{$ENDIF}

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
  raise Exception.Create('Licencia Invalida: ' + AMsg);
end;

class function TLicenseService.CloneJSON(const AJSON: TJSONObject): TJSONObject;
var
  LValue: TJSONValue;
begin
  Result := nil;
  LValue := TJSONObject.ParseJSONValue(AJSON.ToJSON);
  if LValue is TJSONObject then
    Result := TJSONObject(LValue)
  else if Assigned(LValue) then
    LValue.Free;
end;

class function TLicenseService.GetInstalacionHash: string;
var
  RawString: string;
  LConfig: THConfig;
{$IFDEF MSWINDOWS}
  ComputerName: array[0..MAX_COMPUTERNAME_LENGTH] of Char;
  Size: DWORD;
  UserName: array[0..UNLEN] of Char;
  UserSize: DWORD;
  VolumeSerialNumber: DWORD;
  MaximumComponentLength: DWORD;
  FileSystemFlags: DWORD;
{$ENDIF}
begin
  LConfig := THConfig.GetInstance;
  Result := LConfig.License.InstalacionHash;

  if Result.IsEmpty then
  begin
    Log('Generando nuevo hash de instalacion...', llInfo);
{$IFDEF MSWINDOWS}
    Size := MAX_COMPUTERNAME_LENGTH + 1;
    GetComputerName(ComputerName, Size);

    UserSize := UNLEN + 1;
    GetUserName(UserName, UserSize);

    VolumeSerialNumber := 0;
    GetVolumeInformation('C:\', nil, 0, @VolumeSerialNumber, MaximumComponentLength, FileSystemFlags, nil, 0);

    RawString := string(ComputerName) + '|' + string(UserName) + '|' + IntToHex(VolumeSerialNumber, 8);
{$ELSE}
    RawString := 'NON_WINDOWS_MACHINE';
{$ENDIF}
    Result := THashSHA2.GetHashString(RawString);
    LConfig.UpdateInstalacionHash(Result);
    Log('Nuevo hash generado y guardado: ' + Result, llInfo);
  end
  else
  begin
    Log('Usando hash de instalacion persistido: ' + Result, llDebug);
  end;
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
  LValue: TJSONValue;
begin
  Result := nil;
  if TFile.Exists(GetLicenseFilePath) then
  begin
    try
      LContent := TFile.ReadAllText(GetLicenseFilePath);
      LValue := TJSONObject.ParseJSONValue(LContent);
      if LValue is TJSONObject then
        Result := TJSONObject(LValue)
      else if Assigned(LValue) then
        LValue.Free;
    except
      on E: Exception do
        Log('Error leyendo licencia local: ' + E.Message, llError);
    end;
  end;
end;

class function TLicenseService.NormalizeURL(const ABaseURL: string): string;
begin
  Result := ABaseURL.Trim;
  if Result.IsEmpty then
    raise Exception.Create('La URL del servidor de licencias no esta configurada');

  if Result.EndsWith('/') then
    Result := Result.Substring(0, Result.Length - 1);
end;

class procedure TLicenseService.InicializarLicencia;
var
  LConfig: TLicensingConfig;
begin
  LConfig := THConfig.GetInstance.License;
  if LConfig.URLServidor.Trim.IsEmpty then
    BloquearSistema('URL de licencias no configurada en [LICENCIA] URLServidor');

  Log('Iniciando validacion de licencia...', llInfo);
  if not ValidarLicencia then
  begin
    if not ValidarOffline then
    begin
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
  LJSON, LResponseJSON, LClone: TJSONObject;
  LBody: TStringStream;
  LConfig: TLicensingConfig;
  LValue: TJSONValue;
  LHeaders: TNetHeaders;
  LURL: string;
begin
  Result := False;
  LConfig := THConfig.GetInstance.License;

  if LConfig.Nit.IsEmpty then
  begin
    Log('NIT no configurado en config.ini [LICENCIA]', llError);
    Exit;
  end;

  try
    LURL := NormalizeURL(LConfig.URLServidor) + '/api/licencias/activar';
  except
    on E: Exception do
    begin
      Log('Error en configuracion de URL: ' + E.Message, llError);
      Exit;
    end;
  end;

{$IFDEF MSWINDOWS}
  OutputDebugString(PChar('Licencias URL Base: ' + LConfig.URLServidor));
  OutputDebugString(PChar('Endpoint activar: ' + LURL));
{$ENDIF}

  LHTTP := TNetHTTPClient.Create(nil);
  LJSON := TJSONObject.Create;
  try
    LJSON.AddPair('nit', LConfig.Nit);
    LJSON.AddPair('instalacion_hash', GetInstalacionHash);
    LJSON.AddPair('app', LConfig.AppName);

    LBody := TStringStream.Create(LJSON.ToJSON, TEncoding.UTF8);
    try
      try
        SetLength(LHeaders, 1);
        LHeaders[0].Name := 'Content-Type';
        LHeaders[0].Value := 'application/json';

        LResponse := LHTTP.Post(LURL, LBody, nil, LHeaders);

        if LResponse.StatusCode = 200 then
        begin
          Log('Activacion exitosa.', llInfo);
          LValue := TJSONObject.ParseJSONValue(LResponse.ContentAsString);
          if LValue is TJSONObject then
          begin
            LResponseJSON := TJSONObject(LValue);
            try
              LClone := CloneJSON(LResponseJSON);
              if Assigned(LClone) then
              try
                GuardarLicenciaLocal(LClone);
                Result := True;
              finally
                LClone.Free;
              end;
            finally
              LResponseJSON.Free;
            end;
          end
          else
          begin
            Log('JSON de activacion invalido recibido del servidor', llError);
            if Assigned(LValue) then LValue.Free;
          end;
        end
        else
        begin
          Log('Error en activacion (Status ' + IntToStr(LResponse.StatusCode) + '): ' + LResponse.ContentAsString, llWarn);
        end;
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
  LJSON, LResponseJSON, LClone: TJSONObject;
  LBody: TStringStream;
  LConfig: TLicensingConfig;
  LValue, LEstadoValue: TJSONValue;
  LHeaders: TNetHeaders;
  LURL: string;
begin
  Result := False;
  LConfig := THConfig.GetInstance.License;

  if LConfig.Nit.IsEmpty then Exit;

  try
    LURL := NormalizeURL(LConfig.URLServidor) + '/api/licencias/validar';
  except
    on E: Exception do
    begin
      Log('Error en configuracion de URL: ' + E.Message, llError);
      Exit;
    end;
  end;

{$IFDEF MSWINDOWS}
  OutputDebugString(PChar('Licencias URL Base: ' + LConfig.URLServidor));
  OutputDebugString(PChar('Endpoint validar: ' + LURL));
{$ENDIF}

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
        SetLength(LHeaders, 1);
        LHeaders[0].Name := 'Content-Type';
        LHeaders[0].Value := 'application/json';

        LResponse := LHTTP.Post(LURL, LBody, nil, LHeaders);

        if LResponse.StatusCode = 200 then
        begin
          LValue := TJSONObject.ParseJSONValue(LResponse.ContentAsString);
          if LValue is TJSONObject then
          begin
            LResponseJSON := TJSONObject(LValue);
            try
              LEstadoValue := LResponseJSON.GetValue('estado');
              if Assigned(LEstadoValue) and (LEstadoValue.Value <> 'bloqueado') then
              begin
                LClone := CloneJSON(LResponseJSON);
                if Assigned(LClone) then
                try
                  GuardarLicenciaLocal(LClone);
                  Result := True;
                finally
                  LClone.Free;
                end;
              end
              else if Assigned(LEstadoValue) and (LEstadoValue.Value = 'bloqueado') then
              begin
                Log('La licencia ha sido bloqueada por el servidor', llWarn);
              end;
            finally
              LResponseJSON.Free;
            end;
          end
          else
          begin
            Log('JSON de validacion invalido recibido del servidor', llError);
            if Assigned(LValue) then LValue.Free;
          end;
        end
        else
        begin
          Log('Error en validacion (Status ' + IntToStr(LResponse.StatusCode) + '): ' + LResponse.ContentAsString, llDebug);
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
  LExpira: TDateTime;
  LEstado, LExpiraStr: TJSONValue;
  LDateStr: string;
begin
  Result := False;
  LJSON := LeerLicenciaLocal;
  if Assigned(LJSON) then
  try
    LEstado := LJSON.GetValue('estado');
    LExpiraStr := LJSON.GetValue('expira');

    if not Assigned(LEstado) or not Assigned(LExpiraStr) then
      Exit(False);

    if LEstado.Value = 'bloqueado' then Exit(False);

    LDateStr := string(LExpiraStr.Value);
    if TryISO8601ToDate(LDateStr, LExpira) then
    begin
      if Date <= LExpira then
      begin
        Log('Validacion offline exitosa. Expira: ' + DateToStr(TDate(LExpira)), llInfo);
        Result := True;
      end
      else
        Log('Licencia local expirada: ' + DateToStr(TDate(LExpira)), llWarn);
    end;
  finally
    LJSON.Free;
  end;
end;

end.
