unit AuthController;

interface

procedure Registry;

implementation

uses
  Horse,
  System.JSON,
  System.SysUtils,
  AuthService;

procedure Login(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LUsuario, LClave: string;
  LResponse: TJSONObject;
begin
  try
    LBody := Req.Body<TJSONObject>;
    if not Assigned(LBody) then
      raise EHorseException.Create(THTTPStatus.BadRequest, 'Cuerpo de solicitud inválido');

    if not LBody.TryGetValue('usuario', LUsuario) or not LBody.TryGetValue('clave', LClave) then
      raise EHorseException.Create(THTTPStatus.BadRequest, 'Parámetros "usuario" y "clave" son obligatorios');

    LResponse := AuthService.Login(LUsuario, LClave);
    Res.Send<TJSONObject>(LResponse);
  except
    on E: EHorseException do
      Res.Status(E.Status).Send(TJSONObject.Create.AddPair('error', E.Error));
    on E: Exception do
      Res.Status(THTTPStatus.InternalServerError).Send(TJSONObject.Create.AddPair('error', E.Message));
  end;
end;

procedure Registry;
begin
  THorse.Post('/auth/login', Login);
end;

end.
