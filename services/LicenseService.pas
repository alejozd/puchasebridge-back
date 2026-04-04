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
  TLicenciaInfo = class
  private
    FEstado: string;
    FExpira: TDateTime;
    FDiasRestantes: Integer;
    FMensaje: string;
    FInstalacionHash: string;
    FEsPermanente: Boolean;
  public
    property Estado: string read FEstado write FEstado;
    property Expira: TDateTime read FExpira write FExpira;
    property DiasRestantes: Integer read FDiasRestantes write FDiasRestantes;
    property Mensaje: string read FMensaje write FMensaje;
    property EsPermanente: Boolean read FEsPermanente write FEsPermanente;
    property InstalacionHash: string read FInstalacionHash write FInstalacionHash;
  end;

  TLicenciaService = class
  private
    class var FLicenciaActual: TLicenciaInfo;
    class function GuardarLicenciaLocal(const AJSON: TJSONObject): Boolean;
    class function LeerLicenciaLocal: TJSONObject;
    class function ValidarOffline: Boolean;
    class procedure BloquearSistema(const AMsg: string);
    class function GetLicenseFilePath: string;
    class function CloneJSON(const AJSON: TJSONObject): TJSONObject;
    class function NormalizeURL(const ABaseURL: string): string;
  public
    class function GenerarHashInstalacion: string;
    class procedure InicializarLicencia;
    class function ValidarLicencia(const ANit, AInstalacionHash: string): Boolean;
    class function RegistrarLicencia(const ANit, AInstalacionHash, ACodigo: string): Boolean;
    class function ActivarOnline: Boolean;
    class property LicenciaActual: TLicenciaInfo read FLicenciaActual;
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

{ TLicenciaService }

class procedure TLicenciaService.BloquearSistema(const AMsg: string);
begin
  Log('SISTEMA BLOQUEADO: ' + AMsg, llError);
  Writeln('---------------------------------------------------------');
  Writeln('ERROR DE LICENCIA: ' + AMsg);
  Writeln('El servidor no puede iniciar sin una licencia valida.');
  Writeln('---------------------------------------------------------');
  raise Exception.Create('Licencia Invalida: ' + AMsg);
end;

class function TLicenciaService.CloneJSON(const AJSON: TJSONObject): TJSONObject;
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

class function TLicenciaService.GenerarHashInstalacion: string;
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

class function TLicenciaService.GetLicenseFilePath: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(GetModuleName(HInstance)), 'licencia.json');
end;

class function TLicenciaService.GuardarLicenciaLocal(const AJSON: TJSONObject): Boolean;
var
  LList: TStringList;
begin
  Result := False;
  LList := TStringList.Create;
  try
    try
      if not Assigned(AJSON.GetValue('ultima_validacion')) then
        AJSON.AddPair('ultima_validacion', FormatDateTime('yyyy-mm-dd', Now));
      LList.Text := AJSON.ToJSON;
      LList.SaveToFile(GetLicenseFilePath);
      Result := True;
    except
      on E: Exception do
        Log('Error guardando licencia local: ' + E.Message, llError);
    end;
  finally
    LList.Free;
  end;
end;

class function TLicenciaService.LeerLicenciaLocal: TJSONObject;
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

class function TLicenciaService.NormalizeURL(const ABaseURL: string): string;
begin
  Result := ABaseURL.Trim;
  if Result.IsEmpty then
    raise Exception.Create('La URL del servidor de licencias no esta configurada');

  if Result.EndsWith('/') then
    Result := Result.Substring(0, Result.Length - 1);
end;

class procedure TLicenciaService.InicializarLicencia;
var
  LConfig: TLicensingConfig;
  LHash: string;
begin
  LConfig := THConfig.GetInstance.License;
  if LConfig.URLServidor.Trim.IsEmpty then
    BloquearSistema('URL de licencias no configurada en [LICENCIA] URLServidor');

  LHash := GenerarHashInstalacion;

  Log('Iniciando validacion de licencia...', llInfo);
  if not ValidarLicencia(LConfig.Nit, LHash) then
  begin
    if not ValidarOffline then
    begin
       // En un backend/consola esto debe ser un bloqueo directo si no es interactivo.
       BloquearSistema('No se pudo validar la licencia online ni offline. El sistema requiere registro.');
    end;
  end;
  Log('Licencia procesada correctamente.', llInfo);
end;

class function TLicenciaService.ActivarOnline: Boolean;
var
  LHTTP: TNetHTTPClient;
  LResponse: IHTTPResponse;
  LJSON, LResponseJSON, LClone: TJSONObject;
  LBody: TStringStream;
  LConfig: TLicensingConfig;
  LValue, LExpiraValue, LDiasValue: TJSONValue;
  LHeaders: TNetHeaders;
  LURL: string;
begin
  Result := False;
  LConfig := THConfig.GetInstance.License;

  try
    LURL := NormalizeURL(LConfig.URLServidor) + '/api/licencias/activar-online';
  except
    on E: Exception do
    begin
      Log('Error en configuracion de URL: ' + E.Message, llError);
      Exit;
    end;
  end;

  LHTTP := TNetHTTPClient.Create(nil);
  LJSON := TJSONObject.Create;
  try
    LJSON.AddPair('nit', LConfig.Nit);
    LJSON.AddPair('instalacion_hash', LConfig.InstalacionHash);
    LJSON.AddPair('app', LConfig.AppName);

    LBody := TStringStream.Create(LJSON.ToJSON, TEncoding.UTF8);
    try
      try
        SetLength(LHeaders, 1);
        LHeaders[0].Name := 'Content-Type';
        LHeaders[0].Value := 'application/json';

        LResponse := LHTTP.Post(LURL, LBody, nil, LHeaders);
        Log('Respuesta servidor (activar-online): ' + LResponse.ContentAsString, llDebug);

        if LResponse.StatusCode = 200 then
        begin
          LValue := TJSONObject.ParseJSONValue(LResponse.ContentAsString);
          if LValue is TJSONObject then
          begin
            LResponseJSON := TJSONObject(LValue);
            try
              if not Assigned(FLicenciaActual) then FLicenciaActual := TLicenciaInfo.Create;

              FLicenciaActual.Estado := LResponseJSON.GetValue('estado').Value;

              LDiasValue := LResponseJSON.GetValue('dias_restantes');
              FLicenciaActual.EsPermanente := not Assigned(LDiasValue) or (LDiasValue is TJSONNull);

              if not FLicenciaActual.EsPermanente then
              begin
                FLicenciaActual.DiasRestantes := StrToIntDef(LDiasValue.Value, 0);
                LExpiraValue := LResponseJSON.GetValue('expira');
                if Assigned(LExpiraValue) and not (LExpiraValue is TJSONNull) then
                  TryISO8601ToDate(string(LExpiraValue.Value), FLicenciaActual.FExpira);
              end;

              LClone := CloneJSON(LResponseJSON);
              try
                GuardarLicenciaLocal(LClone);
              finally
                LClone.Free;
              end;

              Log('Activacion online exitosa. Estado: ' + FLicenciaActual.Estado, llInfo);
              Result := True;
            finally
              LResponseJSON.Free;
            end;
          end
          else if Assigned(LValue) then
            LValue.Free;
        end
        else
          Log('Error en activacion online (Status ' + IntToStr(LResponse.StatusCode) + '): ' + LResponse.ContentAsString, llWarn);
      except
        on E: Exception do
          Log('Error de conexion al activar licencia online: ' + E.Message, llError);
      end;
    finally
      LBody.Free;
    end;
  finally
    LJSON.Free;
    LHTTP.Free;
  end;
end;

class function TLicenciaService.RegistrarLicencia(const ANit, AInstalacionHash, ACodigo: string): Boolean;
var
  LHTTP: TNetHTTPClient;
  LResponse: IHTTPResponse;
  LJSON, LResponseJSON, LClone: TJSONObject;
  LBody: TStringStream;
  LConfig: TLicensingConfig;
  LValue, LExpiraValue, LDiasValue: TJSONValue;
  LHeaders: TNetHeaders;
  LURL: string;
begin
  Result := False;
  LConfig := THConfig.GetInstance.License;

  try
    LURL := NormalizeURL(LConfig.URLServidor) + '/api/licencias/registrar';
  except
    on E: Exception do
    begin
      Log('Error en configuracion de URL: ' + E.Message, llError);
      Exit;
    end;
  end;

  LHTTP := TNetHTTPClient.Create(nil);
  LJSON := TJSONObject.Create;
  try
    LJSON.AddPair('nit', ANit);
    LJSON.AddPair('instalacion_hash', AInstalacionHash);
    LJSON.AddPair('codigo', ACodigo);

    LBody := TStringStream.Create(LJSON.ToJSON, TEncoding.UTF8);
    try
      try
        SetLength(LHeaders, 1);
        LHeaders[0].Name := 'Content-Type';
        LHeaders[0].Value := 'application/json';

        LResponse := LHTTP.Post(LURL, LBody, nil, LHeaders);
        Log('Respuesta servidor (registrar): ' + LResponse.ContentAsString, llDebug);

        if LResponse.StatusCode = 200 then
        begin
          LValue := TJSONObject.ParseJSONValue(LResponse.ContentAsString);
          if LValue is TJSONObject then
          begin
            LResponseJSON := TJSONObject(LValue);
            try
              if not Assigned(FLicenciaActual) then FLicenciaActual := TLicenciaInfo.Create;

              FLicenciaActual.Estado := LResponseJSON.GetValue('estado').Value;

              LDiasValue := LResponseJSON.GetValue('dias_restantes');
              FLicenciaActual.EsPermanente := not Assigned(LDiasValue) or (LDiasValue is TJSONNull);

              if not FLicenciaActual.EsPermanente then
              begin
                FLicenciaActual.DiasRestantes := StrToIntDef(LDiasValue.Value, 0);
                LExpiraValue := LResponseJSON.GetValue('expira');
                if Assigned(LExpiraValue) and not (LExpiraValue is TJSONNull) then
                  TryISO8601ToDate(string(LExpiraValue.Value), FLicenciaActual.FExpira);
              end;

              FLicenciaActual.Mensaje := LResponseJSON.GetValue('mensaje').Value;

              // Obtener hash del servidor para validación
              if Assigned(LResponseJSON.GetValue('instalacion_hash')) then
                FLicenciaActual.InstalacionHash := LResponseJSON.GetValue('instalacion_hash').Value;

              Log('Instalacion Hash LOCAL: ' + AInstalacionHash, llInfo);
              Log('Instalacion Hash CODIGO: ' + FLicenciaActual.InstalacionHash, llInfo);

              if not FLicenciaActual.InstalacionHash.IsEmpty and
                 (FLicenciaActual.InstalacionHash <> AInstalacionHash) then
              begin
                FLicenciaActual.Mensaje := 'Licencia no v' + #225 + ' lida para este equipo';
                Exit(False);
              end;

              LClone := CloneJSON(LResponseJSON);
              try
                GuardarLicenciaLocal(LClone);
              finally
                LClone.Free;
              end;

              Log('Registro de licencia exitoso. Estado: ' + FLicenciaActual.Estado, llInfo);
              Result := True;
            finally
              LResponseJSON.Free;
            end;
          end
          else if Assigned(LValue) then
            LValue.Free;
        end
        else
          Log('Error en registro (Status ' + IntToStr(LResponse.StatusCode) + '): ' + LResponse.ContentAsString, llWarn);
      except
        on E: Exception do
          Log('Error de conexion al registrar licencia: ' + E.Message, llError);
      end;
    finally
      LBody.Free;
    end;
  finally
    LJSON.Free;
    LHTTP.Free;
  end;
end;

class function TLicenciaService.ValidarLicencia(const ANit, AInstalacionHash: string): Boolean;
var
  LHTTP: TNetHTTPClient;
  LResponse: IHTTPResponse;
  LJSON, LResponseJSON, LClone: TJSONObject;
  LBody: TStringStream;
  LConfig: TLicensingConfig;
  LValue, LEstadoValue, LExpiraValue, LDiasValue: TJSONValue;
  LHeaders: TNetHeaders;
  LURL: string;
begin
  Result := False;
  LConfig := THConfig.GetInstance.License;

  try
    LURL := NormalizeURL(LConfig.URLServidor) + '/api/licencias/validar';
  except
    on E: Exception do
    begin
      Log('Error en configuracion de URL: ' + E.Message, llError);
      Exit;
    end;
  end;

  LHTTP := TNetHTTPClient.Create(nil);
  LHTTP.ConnectionTimeout := 5000;
  LHTTP.ResponseTimeout := 5000;

  LJSON := TJSONObject.Create;
  try
    LJSON.AddPair('nit', ANit);
    LJSON.AddPair('instalacion_hash', AInstalacionHash);

    LBody := TStringStream.Create(LJSON.ToJSON, TEncoding.UTF8);
    try
      try
        SetLength(LHeaders, 1);
        LHeaders[0].Name := 'Content-Type';
        LHeaders[0].Value := 'application/json';

        LResponse := LHTTP.Post(LURL, LBody, nil, LHeaders);
        Log('Respuesta servidor (validar): ' + LResponse.ContentAsString, llDebug);

        if LResponse.StatusCode = 200 then
        begin
          LValue := TJSONObject.ParseJSONValue(LResponse.ContentAsString);
          if LValue is TJSONObject then
          begin
            LResponseJSON := TJSONObject(LValue);
            try
              if not Assigned(FLicenciaActual) then FLicenciaActual := TLicenciaInfo.Create;

              LEstadoValue := LResponseJSON.GetValue('estado');
              if Assigned(LEstadoValue) then
              begin
                FLicenciaActual.Estado := LEstadoValue.Value;

                LDiasValue := LResponseJSON.GetValue('dias_restantes');
                FLicenciaActual.EsPermanente := not Assigned(LDiasValue) or (LDiasValue is TJSONNull);

                if not FLicenciaActual.EsPermanente then
                begin
                  FLicenciaActual.DiasRestantes := StrToIntDef(LDiasValue.Value, 0);
                  LExpiraValue := LResponseJSON.GetValue('expira');
                  if Assigned(LExpiraValue) and not (LExpiraValue is TJSONNull) then
                    TryISO8601ToDate(string(LExpiraValue.Value), FLicenciaActual.FExpira);
                end;

                if (FLicenciaActual.Estado <> 'bloqueado') then
                begin
                  LClone := CloneJSON(LResponseJSON);
                  try
                    GuardarLicenciaLocal(LClone);
                  finally
                    LClone.Free;
                  end;
                  Result := True;
                end;
              end;
            finally
              LResponseJSON.Free;
            end;
          end
          else if Assigned(LValue) then
            LValue.Free;
        end
        else
          Log('Error en validacion (Status ' + IntToStr(LResponse.StatusCode) + '): ' + LResponse.ContentAsString, llDebug);
      except
        on E: Exception do
          Log('Error de conexion al validar licencia: ' + E.Message, llDebug);
      end;
    finally
      LBody.Free;
    end;
  finally
    LJSON.Free;
    LHTTP.Free;
  end;
end;

class function TLicenciaService.ValidarOffline: Boolean;
var
  LJSON: TJSONObject;
  LExpira: TDateTime;
  LEstadoValue, LExpiraStr: TJSONValue;
  LDateStr: string;
begin
  Result := False;
  LJSON := LeerLicenciaLocal;
  if Assigned(LJSON) then
  try
    LEstadoValue := LJSON.GetValue('estado');
    LExpiraStr := LJSON.GetValue('expira');

    if not Assigned(LEstadoValue) or not Assigned(LExpiraStr) then
      Exit(False);

    if LEstadoValue.Value = 'bloqueado' then Exit(False);

    if LExpiraStr is TJSONNull then
    begin
      if not Assigned(FLicenciaActual) then FLicenciaActual := TLicenciaInfo.Create;
      FLicenciaActual.Estado := LEstadoValue.Value;
      FLicenciaActual.EsPermanente := True;
      Log('Validacion offline exitosa. Licencia permanente.', llInfo);
      Result := True;
    end
    else
    begin
      LDateStr := string(LExpiraStr.Value);
      if TryISO8601ToDate(LDateStr, LExpira) then
      begin
        if not Assigned(FLicenciaActual) then FLicenciaActual := TLicenciaInfo.Create;
        FLicenciaActual.Estado := LEstadoValue.Value;
        FLicenciaActual.Expira := LExpira;
        FLicenciaActual.DiasRestantes := DaysBetween(Now, LExpira);
        FLicenciaActual.EsPermanente := False;

        if Date <= LExpira then
        begin
          Log('Validacion offline exitosa. Expira: ' + DateToStr(TDate(LExpira)), llInfo);
          Result := True;
        end
        else
          Log('Licencia local expirada: ' + DateToStr(TDate(LExpira)), llWarn);
      end;
    end;
  finally
    LJSON.Free;
  end;
end;

initialization

finalization
  if Assigned(TLicenciaService.FLicenciaActual) then
    TLicenciaService.FLicenciaActual.Free;

end.
