unit AuthMiddleware;

interface

uses
  Horse,
  System.SysUtils,
  AuthService,
  ErrorResponseUtils;

procedure Auth(Req: THorseRequest; Res: THorseResponse; Next: TProc);

implementation

function NormalizePath(const APath: string): string;
begin
  Result := APath.Trim.ToLower;
  if (Result.Length > 1) and Result.EndsWith('/') then
    Result := Result.Substring(0, Result.Length - 1);
end;

procedure Auth(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LToken: string;
  LSession: TSessionInfo;
  LPath: string;
begin
  // CRITICO: nunca bloquear preflight en autenticacion
  if SameText(Req.RawWebRequest.Method, 'OPTIONS') then
  begin
    Next();
    Exit;
  end;

  LPath := NormalizePath(Req.RawWebRequest.PathInfo);
  if (LPath = '/api/auth/login') or
     (LPath = '/ping') then
  begin
    Next();
    Exit;
  end;

  LToken := Req.Headers['Authorization'];

  if LToken.IsEmpty then
  begin
    SendErrorResponse(Res, Integer(THTTPStatus.Unauthorized), 'Sesión expirada');
    Exit;
  end;

  if not LToken.StartsWith('Bearer ', True) then
  begin
    SendErrorResponse(Res, Integer(THTTPStatus.Unauthorized), 'Sesión expirada');
    Exit;
  end;

  LToken := LToken.Replace('Bearer ', '', [rfReplaceAll, rfIgnoreCase]).Trim;

  try
    LSession := AuthService.ValidateToken(LToken);
  except
    on E: Exception do
    begin
      LogError(E.Message);
      SendErrorResponse(Res, Integer(THTTPStatus.Unauthorized), 'Sesión expirada', E.Message);
      Exit;
    end;
  end;

  // Inyectar usuario en el contexto
  Req.Session(TSessionInfoObj.Create(LSession));
  try
    Next();
  finally
    if Req.Session<TObject> <> nil then
      Req.Session<TObject>.Free;
  end;
end;

end.
