unit DMVC.Middleware.HttpLogger;

interface

uses
  MVCFramework;

type
  // Mide la duracion desde OnBeforeRouting hasta OnAfterControllerAction y
  // loguea con el mismo filtro que uHttpLoggerMiddleware.pas (Horse): siempre
  // loguea errores (status >= 400), excluye assets/estaticos, siempre loguea
  // api/auth/licencia/ping.
  TPurchaseBridgeTraceMiddleware = class(TInterfacedObject, IMVCMiddleware)
  private const
    START_TICK_KEY = 'purchasebridge.trace.starttick';
    function ShouldLogRequest(const APath: string; AStatus: Integer): Boolean;
  protected
    procedure OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
    procedure OnBeforeControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      var AHandled: Boolean);
    procedure OnAfterControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      const AHandled: Boolean);
    procedure OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
  end;

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, uLogger;

{ TPurchaseBridgeTraceMiddleware }

function TPurchaseBridgeTraceMiddleware.ShouldLogRequest(const APath: string; AStatus: Integer): Boolean;
begin
  if AStatus >= 400 then
    Exit(True);

  if StartsText('/assets/', APath) or
     StartsText('/.well-known/', APath) or
     SameText(APath, '/favicon.ico') or
     SameText(APath, '/login') or
     StartsText('/app/', APath) then
    Exit(False);

  if StartsText('/api/', APath) or
     StartsText('/auth/', APath) or
     StartsText('/xml/', APath) or
     StartsText('/licencia/', APath) or
     SameText(APath, '/ping') then
    Exit(True);

  Result := True;
end;

procedure TPurchaseBridgeTraceMiddleware.OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
begin
  AContext.Data[START_TICK_KEY] := IntToStr(Int64(TThread.GetTickCount64));
end;

procedure TPurchaseBridgeTraceMiddleware.OnBeforeControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; var AHandled: Boolean);
begin
  // No-op.
end;

procedure TPurchaseBridgeTraceMiddleware.OnAfterControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; const AHandled: Boolean);
var
  LStartTickStr: string;
  LStartTick: Int64;
  LDuration: Int64;
  LPath: string;
  LStatus: Integer;
begin
  LPath := AContext.Request.RawWebRequest.PathInfo;
  LStatus := AContext.Response.StatusCode;

  if AContext.Data.TryGetValue(START_TICK_KEY, LStartTickStr) and TryStrToInt64(LStartTickStr, LStartTick) then
    LDuration := Int64(TThread.GetTickCount64) - LStartTick
  else
    LDuration := -1;

  if ShouldLogRequest(LPath, LStatus) then
    uLogger.LogInfo(Format('%s %s -> %d (%dms)',
      [AContext.Request.HTTPMethodAsString, LPath, LStatus, LDuration]), 'http');
end;

procedure TPurchaseBridgeTraceMiddleware.OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
begin
  // No-op.
end;

end.
