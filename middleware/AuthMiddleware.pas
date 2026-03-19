unit AuthMiddleware;

interface

uses
  Horse,
  System.SysUtils,
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
begin
  if SameText(Req.RawWebRequest.Method, 'OPTIONS') then
  begin
    Next();
    Exit;
  end;

  LPath := NormalizePath(Req.RawWebRequest.PathInfo);
  if (LPath = '/auth/login') or
     (LPath = '/ping') then
  begin
    Next();
    Exit;
  end;

  LToken := Req.Headers['Authorization'];

  if LToken.IsEmpty then
    raise EHorseException.New.Status(THTTPStatus.Unauthorized).Error('Token requerido');

  if not LToken.StartsWith('Bearer ', True) then
    raise EHorseException.New.Status(THTTPStatus.Unauthorized).Error('Token inválido');

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
