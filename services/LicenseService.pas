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
    class function CloneJSON(const AJSON: TJSONObject): TJSONObject;
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

class procedure TLicenseService.InicializarLicencia;
begin
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
        SetLength(LHeaders, 1);
        LHeaders[0] := TNetHeader.Create('Content-Type', 'application/json');

        LResponse := LHTTP.Post(LConfig.URLServidor + '/api/licencias/activar', LBody, nil, LHeaders);

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
          else if Assigned(LValue) then
            LValue.Free;
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
  LJSON, LResponseJSON, LClone: TJSONObject;
  LBody: TStringStream;
  LConfig: TLicensingConfig;
  LValue, LEstadoValue: TJSONValue;
  LHeaders: TNetHeaders;
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
        SetLength(LHeaders, 1);
        LHeaders[0] := TNetHeader.Create('Content-Type', 'application/json');

        LResponse := LHTTP.Post(LConfig.URLServidor + '/api/licencias/validar', LBody, nil, LHeaders);

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
              end;
            finally
              LResponseJSON.Free;
            end;
          end
          else if Assigned(LValue) then
            LValue.Free;
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

    // Explicit string cast and explicit use of 2-parameter TryISO8601ToDate (most compatible)
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
