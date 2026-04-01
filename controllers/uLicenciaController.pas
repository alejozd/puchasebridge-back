unit uLicenciaController;

interface

uses
  Horse,
  System.JSON,
  System.SysUtils,
  LicenciaService,
  ErrorResponseUtils;

procedure Registry;

implementation

procedure ActivarLicencia(Req: THorseRequest; Res: THorseResponse);
var
  LBody: TJSONObject;
  LNit, LInstalacionId: string;
  LResult: TJSONObject;
begin
  try
    LBody := Req.Body<TJSONObject>;
    if not Assigned(LBody) then
      raise EHorseException.New.Status(THTTPStatus.BadRequest).Error('Cuerpo de solicitud inválido');

    if not LBody.TryGetValue('nit', LNit) or (LNit.Trim.IsEmpty) then
      raise EHorseException.New.Status(THTTPStatus.BadRequest).Error('El NIT es obligatorio');

    if not LBody.TryGetValue('instalacion_id', LInstalacionId) or (LInstalacionId.Trim.IsEmpty) then
      raise EHorseException.New.Status(THTTPStatus.BadRequest).Error('El instalacion_id es obligatorio');

    LResult := LicenciaService.Activar(LNit, LInstalacionId);
    Res.Send<TJSONObject>(LResult);
  except
    on E: EHorseException do
      SendErrorResponse(Res, Integer(E.Status), E.Error, E.Message);
    on E: Exception do
      SendErrorResponse(Res, Integer(THTTPStatus.InternalServerError), 'Error interno del servidor', E.Message);
  end;
end;

procedure ValidarLicencia(Req: THorseRequest; Res: THorseResponse);
var
  LBody: TJSONObject;
  LNit, LInstalacionId: string;
  LResult: TJSONObject;
begin
  try
    LBody := Req.Body<TJSONObject>;
    if not Assigned(LBody) then
      raise EHorseException.New.Status(THTTPStatus.BadRequest).Error('Cuerpo de solicitud inválido');

    if not LBody.TryGetValue('nit', LNit) or (LNit.Trim.IsEmpty) then
      raise EHorseException.New.Status(THTTPStatus.BadRequest).Error('El NIT es obligatorio');

    if not LBody.TryGetValue('instalacion_id', LInstalacionId) or (LInstalacionId.Trim.IsEmpty) then
      raise EHorseException.New.Status(THTTPStatus.BadRequest).Error('El instalacion_id es obligatorio');

    LResult := LicenciaService.Validar(LNit, LInstalacionId);
    Res.Send<TJSONObject>(LResult);
  except
    on E: EHorseException do
      SendErrorResponse(Res, Integer(E.Status), E.Error, E.Message);
    on E: Exception do
      SendErrorResponse(Res, Integer(THTTPStatus.InternalServerError), 'Error interno del servidor', E.Message);
  end;
end;

procedure Registry;
begin
  THorse.Post('/licencia/activar', ActivarLicencia);
  THorse.Post('/licencia/validar', ValidarLicencia);
end;

end.
