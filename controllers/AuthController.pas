unit AuthController;

interface

procedure Registry;

implementation

uses
  Horse,
  System.JSON,
  System.SysUtils,
  AuthService,
  ErrorResponseUtils;

procedure Login(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LUsuario, LClave: string;
  LResponse: TJSONObject;
begin
  try
    LBody := Req.Body<TJSONObject>;
    if not Assigned(LBody) then
      raise EHorseException.New.Status(THTTPStatus.BadRequest).Error('Cuerpo de solicitud inválido');

    if not LBody.TryGetValue('usuario', LUsuario) or not LBody.TryGetValue('clave', LClave) then
      raise EHorseException.New.Status(THTTPStatus.BadRequest).Error('Parámetros "usuario" y "clave" son obligatorios');

    LResponse := AuthService.Login(LUsuario, LClave);
    Res.Send<TJSONObject>(LResponse);
  except
    on E: EHorseException do
    begin
      LogError(E.Message);
      SendErrorResponse(Res, Integer(E.Status), E.Error, E.Message);
    end;
    on E: Exception do
    begin
      LogError(E.Message);
      SendErrorResponse(Res, Integer(THTTPStatus.InternalServerError), 'Error interno del servidor', E.Message);
    end;
  end;
end;

procedure Registry;
begin
  THorse.Post('/auth/login', Login);
  THorse.Post('/api/auth/login', Login);
end;

end.
