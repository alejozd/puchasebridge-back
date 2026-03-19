unit AuthMiddleware;

interface

uses
  Horse,
  System.SysUtils,
  System.JSON,
  AuthService;

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
  LResponse: TJSONObject;
begin
  LPath := NormalizePath(Req.RawWebRequest.PathInfo);
  if (LPath = '/auth/login') or
     (LPath = '/ping') then
  begin
    Next();
    Exit;
  end;

  LToken := Req.Headers['Authorization'];

  if LToken.IsEmpty then
  begin
    LResponse := TJSONObject.Create;
    LResponse.AddPair('success', TJSONBool.Create(False));
    LResponse.AddPair('message', 'Token requerido');
    Res.Status(THTTPStatus.Unauthorized).Send(LResponse);
    Exit;
  end;

  if not LToken.StartsWith('Bearer ', True) then
  begin
    LResponse := TJSONObject.Create;
    LResponse.AddPair('success', TJSONBool.Create(False));
    LResponse.AddPair('message', 'Token inválido');
    Res.Status(THTTPStatus.Unauthorized).Send(LResponse);
    Exit;
  end;

  LToken := LToken.Replace('Bearer ', '', [rfReplaceAll, rfIgnoreCase]).Trim;

  LSession := AuthService.ValidateToken(LToken);

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
