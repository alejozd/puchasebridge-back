unit AuthMiddleware;

interface

uses
  Horse,
  System.SysUtils,
  AuthService,
  ErrorResponseUtils;

procedure Auth(Req: THorseRequest; Res: THorseResponse; Next: TProc);

implementation

uses
  System.StrUtils;

function NormalizePath(const APath: string): string;
begin
  Result := APath.Trim.ToLower;
  if (Result.Length > 1) and Result.EndsWith('/') then
    Result := Result.Substring(0, Result.Length - 1);
end;

function HasFileExtension(const APath: string): Boolean;
var
  LExt: string;
begin
  LExt := ExtractFileExt(APath);
  Result := not LExt.IsEmpty;
end;

function IsPublicPath(const APath: string): Boolean;
var
  LPath: string;
begin
  LPath := APath.ToLower;
  
  // Rutas públicas explícitas
  Result := (LPath = '/auth/login') or
            (LPath = '/api/auth/login') or
            (LPath = '/ping') or
            (LPath = '/') or
            (LPath = '');
  
  if Result then
    Exit;
  
  // Archivos estáticos con extensión son públicos (JS, CSS, imágenes, etc.)
  // Esto permite que el SPA cargue sus recursos sin autenticación
  if HasFileExtension(LPath) then
    Exit(True);
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
  
  // Verificar si es una ruta pública (login, ping, archivos estáticos)
  if IsPublicPath(LPath) then
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

  Req.Session(TSessionInfoObj.Create(LSession));
  try
    Next();
  finally
    if Req.Session<TObject> <> nil then
      Req.Session<TObject>.Free;
  end;
end;

end.
