unit LicenciaController;

interface

uses
  Horse,
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  LicenseService,
  HConfig,
  uLogger;

type
  TLicenciaController = class
  public
    class procedure GetEstado(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure Registrar(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure ActivarOnline(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    class procedure Registry;
  end;

implementation

{ TLicenciaController }

class procedure TLicenciaController.GetEstado(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LConfig: TLicensingConfig;
  LResponse: TJSONObject;
begin
  LConfig := THConfig.GetInstance.License;

  // Refrescar estado validando contra el servidor
  TLicenciaService.ValidarLicencia(LConfig.Nit, LConfig.InstalacionHash);

  if Assigned(TLicenciaService.LicenciaActual) then
  begin
    LResponse := TJSONObject.Create;
    try
      LResponse.AddPair('estado', TLicenciaService.LicenciaActual.Estado);

      if TLicenciaService.LicenciaActual.Mensaje = 'Licencia requiere reactivaci' + #243 + ' n' then
      begin
        LResponse.AddPair('expira', TJSONNull.Create);
        LResponse.AddPair('dias_restantes', TJSONNumber.Create(0));
        LResponse.AddPair('mensaje', TLicenciaService.LicenciaActual.Mensaje);
        LResponse.AddPair('detalle', 'Licencia activa sin expiraci' + #243 + ' n calculada');
        LResponse.AddPair('requiere_reactivacion', TJSONBool.Create(True));
      end
      else if TLicenciaService.LicenciaActual.EsPermanente then
      begin
        LResponse.AddPair('expira', TJSONNull.Create);
        LResponse.AddPair('dias_restantes', TJSONNull.Create);
        LResponse.AddPair('mensaje_vencimiento', 'Licencia permanente');
      end
      else
      begin
        LResponse.AddPair('expira', DateToISO8601(TLicenciaService.LicenciaActual.Expira));
        LResponse.AddPair('dias_restantes', TJSONNumber.Create(TLicenciaService.LicenciaActual.DiasRestantes));
      end;

      LResponse.AddPair('instalacion_hash', LConfig.InstalacionHash);
      if TLicenciaService.LicenciaActual.TipoLicencia.Trim.IsEmpty then
        LResponse.AddPair('tipo_licencia', 'demo')
      else
        LResponse.AddPair('tipo_licencia', TLicenciaService.LicenciaActual.TipoLicencia);
      Res.Send(LResponse.ToJSON);
    finally
      LResponse.Free;
    end;
  end
  else
  begin
    Res.Status(THTTPStatus.NotFound).Send('No se pudo obtener el estado de la licencia');
  end;
end;

class procedure TLicenciaController.Registrar(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LCodigo: string;
  LConfig: TLicensingConfig;
  LSuccess: Boolean;
  LResponse: TJSONObject;
begin
  LBody := Req.Body<TJSONObject>;
  if not Assigned(LBody) or not LBody.TryGetValue('codigo', LCodigo) then
  begin
    Res.Status(THTTPStatus.BadRequest).Send('C' + #243 + ' digo de registro no proporcionado');
    Exit;
  end;

  LConfig := THConfig.GetInstance.License;
  Log('Intento de registro de licencia con c' + #243 + ' digo: ' + LCodigo, llInfo);

  LSuccess := TLicenciaService.RegistrarLicencia(LConfig.Nit, LConfig.InstalacionHash, LCodigo);

  LResponse := TJSONObject.Create;
  try
    if not LSuccess and Assigned(TLicenciaService.LicenciaActual) and
       (TLicenciaService.LicenciaActual.Mensaje = 'Licencia no v' + #225 + ' lida para este equipo') then
    begin
      LResponse.AddPair('error', TLicenciaService.LicenciaActual.Mensaje);
    end
    else
    begin
      LResponse.AddPair('success', TJSONBool.Create(LSuccess));
      if LSuccess and Assigned(TLicenciaService.LicenciaActual) then
        LResponse.AddPair('mensaje', TLicenciaService.LicenciaActual.Mensaje)
      else
        LResponse.AddPair('mensaje', 'Error al registrar la licencia. Verifique el c' + #243 + ' digo o la conexi' + #243 + ' n.');
    end;

    Res.Send(LResponse.ToJSON);
  finally
    LResponse.Free;
  end;
end;

class procedure TLicenciaController.ActivarOnline(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LSuccess: Boolean;
  LResponse: TJSONObject;
begin
  Log('Intento de activacion online de licencia', llInfo);

  LSuccess := TLicenciaService.ActivarOnline;

  LResponse := TJSONObject.Create;
  try
    LResponse.AddPair('success', TJSONBool.Create(LSuccess));
    if LSuccess and Assigned(TLicenciaService.LicenciaActual) then
    begin
      LResponse.AddPair('estado', TLicenciaService.LicenciaActual.Estado);

      if TLicenciaService.LicenciaActual.Mensaje = 'Licencia requiere reactivaci' + #243 + ' n' then
      begin
        LResponse.AddPair('expira', TJSONNull.Create);
        LResponse.AddPair('dias_restantes', TJSONNumber.Create(0));
        LResponse.AddPair('mensaje', TLicenciaService.LicenciaActual.Mensaje);
        LResponse.AddPair('detalle', 'Licencia activa sin expiraci' + #243 + ' n calculada');
        LResponse.AddPair('requiere_reactivacion', TJSONBool.Create(True));
      end
      else if TLicenciaService.LicenciaActual.EsPermanente then
      begin
        LResponse.AddPair('expira', TJSONNull.Create);
        LResponse.AddPair('dias_restantes', TJSONNull.Create);
        LResponse.AddPair('mensaje_vencimiento', 'Licencia permanente');
      end
      else
      begin
        LResponse.AddPair('expira', DateToISO8601(TLicenciaService.LicenciaActual.Expira));
        LResponse.AddPair('dias_restantes', TJSONNumber.Create(TLicenciaService.LicenciaActual.DiasRestantes));
      end;

    if TLicenciaService.LicenciaActual.TipoLicencia.Trim.IsEmpty then
      LResponse.AddPair('tipo_licencia', 'demo')
    else
      LResponse.AddPair('tipo_licencia', TLicenciaService.LicenciaActual.TipoLicencia);
    end
    else
    begin
      LResponse.AddPair('mensaje', 'Error al activar la licencia online. Verifique su conexi' + #243 + ' n.');
    end;

    Res.Send(LResponse.ToJSON);
  finally
    LResponse.Free;
  end;
end;

class procedure TLicenciaController.Registry;
begin
  THorse.Get('/licencia/estado', GetEstado);
  THorse.Get('/api/licencia/estado', GetEstado);
  THorse.Post('/licencia/registrar', Registrar);
  THorse.Post('/api/licencia/registrar', Registrar);
  THorse.Post('/licencia/activar', Registrar);
  THorse.Post('/api/licencia/activar', Registrar);
  THorse.Post('/licencia/activar-online', ActivarOnline);
  THorse.Post('/api/licencia/activar-online', ActivarOnline);
end;

end.
