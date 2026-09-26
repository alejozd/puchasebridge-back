unit DMVC.Middleware.License;

interface

uses
  MVCFramework;

type
  TPurchaseBridgeLicenseMiddleware = class(TInterfacedObject, IMVCMiddleware)
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
  System.SysUtils, System.JSON, MVCFramework.Commons, LicenseService;

{ TPurchaseBridgeLicenseMiddleware }

procedure TPurchaseBridgeLicenseMiddleware.OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
var
  LPath: string;
  LJson: TJSONObject;
begin
  LPath := AContext.Request.RawWebRequest.PathInfo;

  if LPath.Contains('/licencia') or LPath.StartsWith('/ping') then
    Exit;

  if not TLicenciaService.SistemaBloqueado then
    Exit;

  LJson := TJSONObject.Create;
  try
    LJson.AddPair('ok', TJSONBool.Create(False));
    LJson.AddPair('mensaje', 'Sistema bloqueado por licencia expirada');
    AContext.Response.RawWebResponse.StatusCode := 403;
    AContext.Response.RawWebResponse.ContentType := TMVCMediaType.APPLICATION_JSON + '; charset=utf-8';
    AContext.Response.RawWebResponse.Content := LJson.ToJSON;
    // CRITICO (descubierto empiricamente en la Task 1 de esta fase, ver
    // DMVC.Middleware.CORS.pas): bajo el hosting TIdHTTPWebBrokerBridge de
    // este proyecto, TMVCEngine.InternalExecuteAction.Result NUNCA se vuelve
    // True solo porque un middleware puso AHandled:=True en OnBeforeRouting
    // -- eso deja que TWebRequestHandler.HandleRequest omita el envio de la
    // respuesta por completo (status/headers/body quedan descartados en
    // silencio), sin importar si el body esta vacio o no. Hay que llamar
    // SendResponse explicitamente ANTES de marcar AHandled, igual que hace
    // TMVCEngine.OnBeforeDispatch en su propio manejo de excepciones.
    AContext.Response.RawWebResponse.SendResponse;
  finally
    LJson.Free;
  end;
  AHandled := True;
end;

procedure TPurchaseBridgeLicenseMiddleware.OnBeforeControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; var AHandled: Boolean);
begin
  // No-op.
end;

procedure TPurchaseBridgeLicenseMiddleware.OnAfterControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; const AHandled: Boolean);
begin
  // No-op.
end;

procedure TPurchaseBridgeLicenseMiddleware.OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
begin
  // No-op.
end;

end.
