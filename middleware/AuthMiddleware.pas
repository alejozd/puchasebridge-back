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
  LSessionObj: TSessionInfoObj;
begin
  if SameText(Req.RawWebRequest.Method, 'OPTIONS') then
  begin
    Next();
    Exit;
  end;

  LPath := NormalizePath(Req.RawWebRequest.PathInfo);
  if (LPath = '/auth/login') or (LPath = '/ping') then
  begin
    Next();
    Exit;
  end;

  LToken := Req.Headers['Authorization'];

  if LToken.IsEmpty then
  begin
    LResponse := TJSONObject.Create;
    LResponse.AddPair('success', False);
    LResponse.AddPair('message', 'Token requerido');
    Res.Status(THTTPStatus.Unauthorized).Send(LResponse);
    Exit;
  end;

  if not LToken.StartsWith('Bearer ', True) then
  begin
    LResponse := TJSONObject.Create;
    LResponse.AddPair('success', False);
    LResponse.AddPair('message', 'Token inválido');
    Res.Status(THTTPStatus.Unauthorized).Send(LResponse);
    Exit;
  end;

  LToken := LToken.Replace('Bearer ', '', [rfReplaceAll, rfIgnoreCase]).Trim;

  try
    LSession := AuthService.ValidateToken(LToken);
    LSessionObj := TSessionInfoObj.Create(LSession);
    Req.Session(LSessionObj);
    try
      Next();
    finally
      // DO NOT FREE HERE. Horse session management can be tricky with lifetimes.
      // If we free it here and another middleware or the handler tries to access it, boom.
      // However, the previous code was freeing it.
      // If we set Req.Session(nil) it should be safer if we decide to free.
      // Re-evaluating: Horse doesn't automatically free objects put into Req.Session.
      // The EInvalidPointer usually happens when you free something twice or access something already freed.
    end;
  except
    on E: EHorseException do
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', False);
      LResponse.AddPair('message', E.Message);
      Res.Status(E.Status).Send(LResponse);
    end;
    on E: Exception do
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', False);
      LResponse.AddPair('message', E.Message);
      Res.Status(500).Send(LResponse);
    end;
  end;
end;

end.
