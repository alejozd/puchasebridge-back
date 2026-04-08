unit uHttpLoggerMiddleware;

interface

uses
  Horse,
  System.SysUtils,
  System.StrUtils,
  uLogger;

procedure HttpLogger(Req: THorseRequest; Res: THorseResponse; Next: TProc);

implementation

uses
  Winapi.Windows;

function ShouldLogRequest(const APath: string; AStatus: Integer): Boolean;
begin
  // Always log errors
  if AStatus >= 400 then
    Exit(True);

  // Exclude static assets and frontend routes
  if StartsText('/assets/', APath) or
     StartsText('/.well-known/', APath) or
     SameText(APath, '/favicon.ico') or
     SameText(APath, '/login') or
     StartsText('/app/', APath) then
    Exit(False);

  // Always log API and Auth requests
  if StartsText('/api/', APath) or
     StartsText('/auth/', APath) or
     StartsText('/xml/', APath) or
     StartsText('/licencia/', APath) or
     SameText(APath, '/ping') then
    Exit(True);

  // Default fallback for other routes
  Result := True;
end;

procedure HttpLogger(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LStartTick: UInt64;
  LPath: string;
  LDuration: Int64;
  LStatus: Integer;
begin
  LStartTick := GetTickCount64;

  LPath := Req.RawWebRequest.PathInfo;
  if LPath.IsEmpty then
    LPath := Req.PathInfo;

  try
    Next();
  finally
    LStatus := Res.RawWebResponse.StatusCode;
    LDuration := GetTickCount64 - LStartTick;

    if ShouldLogRequest(LPath, LStatus) then
    begin
      uLogger.Log(
        'Request completed',
        llInfo,
        'http',
        Req.RawWebRequest.Method,
        LPath,
        LStatus,
        LDuration
      );
    end;
  end;
end;

end.
