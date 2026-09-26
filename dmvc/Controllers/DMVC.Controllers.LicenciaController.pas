unit DMVC.Controllers.LicenciaController;

interface

uses
  MVCFramework, MVCFramework.Commons;

type
  [MVCPath('/')]
  TLicenciaController = class(TMVCController)
  public
    [MVCPath('/licencia/estado')]
    [MVCPath('/api/licencia/estado')]
    [MVCHTTPMethod([httpGET])]
    procedure GetEstado;

    [MVCPath('/licencia/registrar')]
    [MVCPath('/api/licencia/registrar')]
    [MVCPath('/licencia/activar')]
    [MVCPath('/api/licencia/activar')]
    [MVCHTTPMethod([httpPOST])]
    procedure Registrar;

    [MVCPath('/licencia/activar-online')]
    [MVCPath('/api/licencia/activar-online')]
    [MVCHTTPMethod([httpPOST])]
    procedure ActivarOnline;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.DateUtils,
  LicenseService, HConfig, uLogger;

procedure BuildEstadoFields(const AResponse: TJSONObject);
begin
  AResponse.AddPair('estado', TLicenciaService.LicenciaActual.Estado);

  if TLicenciaService.LicenciaActual.Mensaje = 'Licencia requiere reactivaci' + #243 + ' n' then
  begin
    AResponse.AddPair('expira', TJSONNull.Create);
    AResponse.AddPair('dias_restantes', TJSONNumber.Create(0));
    AResponse.AddPair('mensaje', TLicenciaService.LicenciaActual.Mensaje);
    AResponse.AddPair('detalle', 'Licencia activa sin expiraci' + #243 + 'n calculada');
    AResponse.AddPair('requiere_reactivacion', TJSONBool.Create(True));
  end
  else if TLicenciaService.LicenciaActual.EsPermanente then
  begin
    AResponse.AddPair('expira', TJSONNull.Create);
    AResponse.AddPair('dias_restantes', TJSONNull.Create);
    AResponse.AddPair('mensaje_vencimiento', 'Licencia permanente');
  end
  else
  begin
    AResponse.AddPair('expira', DateToISO8601(TLicenciaService.LicenciaActual.Expira));
    AResponse.AddPair('dias_restantes', TJSONNumber.Create(TLicenciaService.LicenciaActual.DiasRestantes));
  end;

  if TLicenciaService.LicenciaActual.TipoLicencia.Trim.IsEmpty then
    AResponse.AddPair('tipo_licencia', 'demo')
  else
    AResponse.AddPair('tipo_licencia', TLicenciaService.LicenciaActual.TipoLicencia);
end;

procedure TLicenciaController.GetEstado;
var
  LConfig: TLicensingConfig;
  LResponse: TJSONObject;
begin
  LConfig := THConfig.GetInstance.License;

  TLicenciaService.ValidarLicencia(LConfig.Nit, LConfig.InstalacionHash);

  if Assigned(TLicenciaService.LicenciaActual) then
  begin
    LResponse := TJSONObject.Create;
    try
      BuildEstadoFields(LResponse);
      LResponse.AddPair('instalacion_hash', LConfig.InstalacionHash);
      ContentType := TMVCMediaType.APPLICATION_JSON;
      Render(LResponse.ToJSON);
    finally
      LResponse.Free;
    end;
  end
  else
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'No se pudo obtener el estado de la licencia');
end;

procedure TLicenciaController.Registrar;
var
  LBody: TJSONObject;
  LCodigo: string;
  LConfig: TLicensingConfig;
  LSuccess: Boolean;
  LResponse: TJSONObject;
begin
  LBody := TJSONObject.ParseJSONValue(Context.Request.Body) as TJSONObject;
  try
    if not Assigned(LBody) or not LBody.TryGetValue('codigo', LCodigo) then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'C' + #243 + 'digo de registro no proporcionado');
  finally
    LBody.Free;
  end;

  LConfig := THConfig.GetInstance.License;
  Log('Intento de registro de licencia con c' + #243 + 'digo: ' + LCodigo, llInfo);

  LSuccess := TLicenciaService.RegistrarLicencia(LConfig.Nit, LConfig.InstalacionHash, LCodigo);

  LResponse := TJSONObject.Create;
  try
    if not LSuccess and Assigned(TLicenciaService.LicenciaActual) and
       (TLicenciaService.LicenciaActual.Mensaje = 'Licencia no v' + #225 + ' lida para este equipo') then
      LResponse.AddPair('error', TLicenciaService.LicenciaActual.Mensaje)
    else
    begin
      LResponse.AddPair('success', TJSONBool.Create(LSuccess));
      if LSuccess and Assigned(TLicenciaService.LicenciaActual) then
        LResponse.AddPair('mensaje', TLicenciaService.LicenciaActual.Mensaje)
      else
        LResponse.AddPair('mensaje', 'Error al registrar la licencia. Verifique el c' + #243 + 'digo o la conexi' + #243 + 'n.');
    end;

    ContentType := TMVCMediaType.APPLICATION_JSON;
    Render(LResponse.ToJSON);
  finally
    LResponse.Free;
  end;
end;

procedure TLicenciaController.ActivarOnline;
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
      BuildEstadoFields(LResponse)
    else
      LResponse.AddPair('mensaje', 'Error al activar la licencia online. Verifique su conexi' + #243 + 'n.');

    ContentType := TMVCMediaType.APPLICATION_JSON;
    Render(LResponse.ToJSON);
  finally
    LResponse.Free;
  end;
end;

end.
