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
  TValidationResult = (vrValid, vrInvalid, vrConnectionError);

  TLicenciaInfo = class
  private
    FEstado: string;
    FExpira: TDateTime;
    FDiasRestantes: Integer;
    FMensaje: string;
    FInstalacionHash: string;
    FEsPermanente: Boolean;
    FTipoLicencia: string;
  public
    property Estado: string read FEstado write FEstado;
    property Expira: TDateTime read FExpira write FExpira;
    property DiasRestantes: Integer read FDiasRestantes write FDiasRestantes;
    property Mensaje: string read FMensaje write FMensaje;
    property EsPermanente: Boolean read FEsPermanente write FEsPermanente;
    property TipoLicencia: string read FTipoLicencia write FTipoLicencia;
    property InstalacionHash: string read FInstalacionHash write FInstalacionHash;
  end;

  TLicenciaService = class
  private
    class var FLicenciaActual: TLicenciaInfo;
    class var FIsValidating: Boolean;
    class var FSistemaBloqueado: Boolean;
    class function GuardarLicenciaLocal(const AJSON: TJSONObject): Boolean;
    class function LeerLicenciaLocal: TJSONObject;
    class function ValidarOffline: Boolean;
    class procedure BloquearSistema(const AMsg: string);
    class function GetLicenseFilePath: string;
    class function CloneJSON(const AJSON: TJSONObject): TJSONObject;
    class function NormalizeURL(const ABaseURL: string): string;
    class procedure ParseLicenseResponse(const AResponseJSON: TJSONObject);
    class procedure LimpiarLicenciaLocal;
  public
    class function GenerarHashInstalacion: string;
    class procedure InicializarLicencia;
    class function ValidarLicencia(const ANit, AInstalacionHash: string): TValidationResult;
    class function RegistrarLicencia(const ANit, AInstalacionHash, ACodigo: string): Boolean;
    class function ActivarOnline: Boolean;
    class procedure StartPeriodicValidation;
    class property LicenciaActual: TLicenciaInfo read FLicenciaActual;
    class property SistemaBloqueado: Boolean read FSistemaBloqueado;
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
  FSistemaBloqueado := True;
  Log('SISTEMA BLOQUEADO: ' + AMsg, llError);
end;

class procedure TLicenciaService.LimpiarLicenciaLocal;
begin
  if TFile.Exists(GetLicenseFilePath) then
    TFile.Delete(GetLicenseFilePath);
  if Assigned(FLicenciaActual) then
    FreeAndNil(FLicenciaActual);
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

class procedure TLicenciaService.ParseLicenseResponse(const AResponseJSON: TJSONObject);
var
  LExpiraValue, LDiasValue, LTipoValue: TJSONValue;
begin
  if not Assigned(FLicenciaActual) then FLicenciaActual := TLicenciaInfo.Create;

  FLicenciaActual.Estado := AResponseJSON.GetValue('estado').Value;

  LTipoValue := AResponseJSON.GetValue('tipo_licencia');
  if Assigned(LTipoValue) and not (LTipoValue is TJSONNull) then
    FLicenciaActual.TipoLicencia := LTipoValue.Value
  else if FLicenciaActual.TipoLicencia.Trim.IsEmpty then
    FLicenciaActual.TipoLicencia := 'demo';

  LDiasValue := AResponseJSON.GetValue('dias_restantes');
  FLicenciaActual.EsPermanente := not Assigned(LDiasValue) or (LDiasValue is TJSONNull);

  if not FLicenciaActual.EsPermanente then
  begin
    FLicenciaActual.DiasRestantes := StrToIntDef(LDiasValue.Value, 0);
    LExpiraValue := AResponseJSON.GetValue('expira');
    if Assigned(LExpiraValue) and not (LExpiraValue is TJSONNull) then
    begin
      if TryISO8601ToDate(string(LExpiraValue.Value), FLicenciaActual.FExpira) then
        Log('Licencia parseada - Tipo: ' + FLicenciaActual.TipoLicencia +
            ', Expiracion: ' + DateToStr(FLicenciaActual.FExpira), llDebug);
    end;
  end
  else
    Log('Licencia parseada - Tipo: ' + FLicenciaActual.TipoLicencia + ' (Permanente)', llDebug);
end;

class procedure TLicenciaService.StartPeriodicValidation;
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      while True do
      begin
        // Esperar 24 horas
        TThread.Sleep(24 * 60 * 60 * 1000);

        if FIsValidating then Continue;

        FIsValidating := True;
        try
          Log('Validaci' + #243 + ' n peri' + #243 + ' dica de licencia ejecutada', llInfo);
          try
            InicializarLicencia;
            Log('Licencia v' + #225 + ' lida', llInfo);
          except
            on E: Exception do
            begin
              Log('Licencia expirada o inv' + #225 + ' lida detectada en validaci' + #243 + ' n peri' + #243 + ' dica: ' + E.Message, llError);
              // En un backend Horse, si la licencia expira en runtime,
              // la siguiente peticion fallara porque InicializarLicencia
              // habra actualizado FLicenciaActual o habra lanzado excepcion.
            end;
          end;
        finally
          FIsValidating := False;
        end;
      end;
    end
  ).Start;
end;

class procedure TLicenciaService.InicializarLicencia;
var
  LConfig: TLicensingConfig;
  LHash: string;
  LResult: TValidationResult;
begin
  LConfig := THConfig.GetInstance.License;
  if LConfig.URLServidor.Trim.IsEmpty then
    BloquearSistema('URL de licencias no configurada en [LICENCIA] URLServidor');

  LHash := GenerarHashInstalacion;

  Log('Iniciando validacion de licencia (Sincronizacion obligatoria)...', llInfo);

  LResult := ValidarLicencia(LConfig.Nit, LHash);

  case LResult of
    vrValid:
    begin
      FSistemaBloqueado := False;
      Log('Licencia procesada correctamente.', llInfo);
    end;

    vrInvalid:
    begin
      Log('Acceso denegado: Servidor rechaza licencia', llWarn);
      if Assigned(FLicenciaActual) and not FLicenciaActual.Mensaje.IsEmpty then
        BloquearSistema(FLicenciaActual.Mensaje)
      else
        BloquearSistema('Licencia expirada o bloqueada por el servidor');
    end;

    vrConnectionError:
    begin
      Log('Fallback a licencia local (sin conexion)', llInfo);
      if not ValidarOffline then
      begin
        BloquearSistema('No se pudo validar la licencia online ni offline. El sistema requiere registro.');
      end
      else
      begin
        FSistemaBloqueado := False;
        Log('Licencia procesada correctamente (Modo Offline).', llInfo);
      end;
    end;
  end;
end;

class function TLicenciaService.ActivarOnline: Boolean;
var
  LHTTP: TNetHTTPClient;
  LResponse: IHTTPResponse;
  LJSON, LResponseJSON, LClone: TJSONObject;
  LBody: TStringStream;
  LConfig: TLicensingConfig;
  LValue, LServerExp: TJSONValue;
  LHeaders: TNetHeaders;
  LURL: string;
  LTipo: string;
  LDias: Integer;
  LExpiraTmp: TDateTime;
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

        if LResponse.StatusCode = 200 then
        begin
          LValue := TJSONObject.ParseJSONValue(LResponse.ContentAsString);
          if LValue is TJSONObject then
          begin
            LResponseJSON := TJSONObject(LValue);
            try
              // Cálculo de expiración según tipo_licencia detectado
              LTipo := 'demo';
              if Assigned(LResponseJSON.GetValue('tipo_licencia')) then
                LTipo := LResponseJSON.GetValue('tipo_licencia').Value;

              Log('Activacion online detectada - Tipo: ' + LTipo, llInfo);

              // Priorizar fecha_expiracion enviada por el servidor
              LServerExp := LResponseJSON.GetValue('fecha_expiracion');
              if not Assigned(LServerExp) then LServerExp := LResponseJSON.GetValue('expira');

              // Limpiar campos para estandarizar
              if LResponseJSON.GetValue('expira') <> nil then LResponseJSON.RemovePair('expira').Free;
              if LResponseJSON.GetValue('dias_restantes') <> nil then LResponseJSON.RemovePair('dias_restantes').Free;
              if LResponseJSON.GetValue('fecha_activacion') <> nil then LResponseJSON.RemovePair('fecha_activacion').Free;

              if LTipo = 'permanente' then
              begin
                LResponseJSON.AddPair('expira', TJSONNull.Create);
                LResponseJSON.AddPair('dias_restantes', TJSONNull.Create);
                Log('Activacion permanente completada.', llInfo);
              end
              else if Assigned(LServerExp) and not (LServerExp is TJSONNull) then
              begin
                LResponseJSON.AddPair('expira', TJSONString.Create(LServerExp.Value));
                Log('Usando expiracion definida por el servidor: ' + LServerExp.Value, llInfo);
              end
              else
              begin
                LDias := 0;
                if LTipo = 'anual' then
                begin
                  if Assigned(LResponseJSON.GetValue('dias_licencia')) then
                    LDias := StrToIntDef(LResponseJSON.GetValue('dias_licencia').Value, 365)
                  else
                    LDias := 365;
                end
                else
                begin
                  if Assigned(LResponseJSON.GetValue('dias_demo')) then
                    LDias := StrToIntDef(LResponseJSON.GetValue('dias_demo').Value, 15)
                  else
                    LDias := 15;
                end;

                LExpiraTmp := IncDay(Now, LDias);
                LResponseJSON.AddPair('expira', DateToISO8601(LExpiraTmp));
                LResponseJSON.AddPair('dias_restantes', TJSONNumber.Create(LDias));
                Log('Expiracion calculada: ' + DateToStr(LExpiraTmp) + ' (' + IntToStr(LDias) + ' dias)', llInfo);
              end;
              LResponseJSON.AddPair('fecha_activacion', DateToISO8601(Now));

              ParseLicenseResponse(LResponseJSON);

              // Validación: requiere reactivación
              if (FLicenciaActual.Estado = 'activa') and
                 (FLicenciaActual.DiasRestantes = 0) and
                 (not FLicenciaActual.EsPermanente) and
                 (not Assigned(LResponseJSON.GetValue('expira')) or (LResponseJSON.GetValue('expira') is TJSONNull)) then
              begin
                FLicenciaActual.Mensaje := 'Licencia requiere reactivaci' + #243 + ' n';
                FSistemaBloqueado := True;
                Result := False;
              end
              else
              begin
                FSistemaBloqueado := False;
                Result := True;
              end;

              if FLicenciaActual.Estado <> 'bloqueado' then
              begin
                LClone := CloneJSON(LResponseJSON);
                try
                  GuardarLicenciaLocal(LClone);
                finally
                  LClone.Free;
                end;
              end;

              Log('Activacion online exitosa. Estado: ' + FLicenciaActual.Estado + ' (Resultado: ' + BoolToStr(Result, True) + ')', llInfo);
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
  LValue: TJSONValue;
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

        if LResponse.StatusCode = 200 then
        begin
          LValue := TJSONObject.ParseJSONValue(LResponse.ContentAsString);
          if LValue is TJSONObject then
          begin
            LResponseJSON := TJSONObject(LValue);
            try
              ParseLicenseResponse(LResponseJSON);

              // Validación: requiere reactivación
              if (FLicenciaActual.Estado = 'activa') and
                 (FLicenciaActual.DiasRestantes = 0) and
                 (not FLicenciaActual.EsPermanente) and
                 (not Assigned(LResponseJSON.GetValue('expira')) or (LResponseJSON.GetValue('expira') is TJSONNull)) then
              begin
                FLicenciaActual.Mensaje := 'Licencia requiere reactivaci' + #243 + ' n';
                FSistemaBloqueado := True;
                Result := False;
              end
              else
              begin
                FSistemaBloqueado := False;
                Result := True;
              end;

              if Assigned(LResponseJSON.GetValue('mensaje')) then
                FLicenciaActual.Mensaje := LResponseJSON.GetValue('mensaje').Value;

              // Obtener hash del servidor para validación
              if Assigned(LResponseJSON.GetValue('instalacion_hash')) then
                FLicenciaActual.InstalacionHash := LResponseJSON.GetValue('instalacion_hash').Value;

              if not FLicenciaActual.InstalacionHash.IsEmpty and
                 (FLicenciaActual.InstalacionHash <> AInstalacionHash) then
              begin
                FLicenciaActual.Mensaje := 'Licencia no v' + #225 + ' lida para este equipo';
                Result := False;
              end;

              if Result and (FLicenciaActual.Estado <> 'bloqueado') then
              begin
                LClone := CloneJSON(LResponseJSON);
                try
                  GuardarLicenciaLocal(LClone);
                finally
                  LClone.Free;
                end;
              end;

              Log('Registro de licencia exitoso. Estado: ' + FLicenciaActual.Estado, llInfo);
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

class function TLicenciaService.ValidarLicencia(const ANit, AInstalacionHash: string): TValidationResult;
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
  Result := vrConnectionError;
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

        if LResponse.StatusCode = 404 then
        begin
          Log('No existe licencia en servidor. Limpiando datos locales...', llWarn);
          LimpiarLicenciaLocal;
          Log('Creando nueva licencia demo...', llInfo);
          if ActivarOnline then
             Result := vrValid
          else
             Result := vrInvalid;
          Exit;
        end;

        if LResponse.StatusCode = 200 then
        begin
          LValue := TJSONObject.ParseJSONValue(LResponse.ContentAsString);
          if LValue is TJSONObject then
          begin
            LResponseJSON := TJSONObject(LValue);
            try
              ParseLicenseResponse(LResponseJSON);

              // Validación: requiere reactivación
              if (FLicenciaActual.Estado = 'activa') and
                 (FLicenciaActual.DiasRestantes = 0) and
                 (not FLicenciaActual.EsPermanente) and
                 (not Assigned(LResponseJSON.GetValue('expira')) or (LResponseJSON.GetValue('expira') is TJSONNull)) then
              begin
                FLicenciaActual.Mensaje := 'Licencia requiere reactivaci' + #243 + ' n';
                Result := vrInvalid;
              end
              else if (FLicenciaActual.Estado = 'bloqueado') then
              begin
                Log('Servidor responde licencia bloqueada', llWarn);
                Result := vrInvalid;
              end
              else if not FLicenciaActual.EsPermanente and (Date > FLicenciaActual.Expira) then
              begin
                Log('Servidor responde licencia expirada', llWarn);
                FLicenciaActual.Mensaje := 'Licencia expirada';
                Result := vrInvalid;
              end
              else
              begin
                FSistemaBloqueado := False;
                Result := vrValid;
              end;

              if (FLicenciaActual.Estado <> 'bloqueado') then
              begin
                LClone := CloneJSON(LResponseJSON);
                try
                  GuardarLicenciaLocal(LClone);
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
  LEstadoValue, LExpiraStr, LTipoValue: TJSONValue;
  LDateStr: string;
begin
  Result := False;
  LJSON := LeerLicenciaLocal;
  if Assigned(LJSON) then
  begin
    Log('Usando licencia local...', llInfo);
  try
    LEstadoValue := LJSON.GetValue('estado');
    LExpiraStr := LJSON.GetValue('expira');

    if not Assigned(LEstadoValue) or not Assigned(LExpiraStr) then
      Exit(False);

    if LEstadoValue.Value = 'bloqueado' then Exit(False);

    if not Assigned(FLicenciaActual) then FLicenciaActual := TLicenciaInfo.Create;
    FLicenciaActual.Estado := LEstadoValue.Value;

    LTipoValue := LJSON.GetValue('tipo_licencia');
    if Assigned(LTipoValue) and not (LTipoValue is TJSONNull) then
      FLicenciaActual.TipoLicencia := LTipoValue.Value
    else if FLicenciaActual.TipoLicencia.Trim.IsEmpty then
      FLicenciaActual.TipoLicencia := 'demo';

    if LExpiraStr is TJSONNull then
    begin
      // Validación: requiere reactivación (offline)
      // Se diferencia de permanente porque permanente tiene dias_restantes null
      if (FLicenciaActual.Estado = 'activa') and
         Assigned(LJSON.GetValue('dias_restantes')) and
         not (LJSON.GetValue('dias_restantes') is TJSONNull) and
         (StrToIntDef(LJSON.GetValue('dias_restantes').Value, -1) = 0) then
      begin
        FLicenciaActual.Mensaje := 'Licencia requiere reactivaci' + #243 + ' n';
        Result := False;
      end
      else
      begin
        FLicenciaActual.EsPermanente := True;
        Log('Validacion offline exitosa. Licencia permanente.', llInfo);
        Result := True;
      end;
    end
    else
    begin
      LDateStr := string(LExpiraStr.Value);
      if TryISO8601ToDate(LDateStr, LExpira) then
      begin
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
end;

initialization

finalization
  if Assigned(TLicenciaService.FLicenciaActual) then
    TLicenciaService.FLicenciaActual.Free;

end.
