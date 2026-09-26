unit DMVC.Middleware.CORS;

interface

uses
  MVCFramework;

type
  // Refleja el Origin recibido tal cual (sin whitelist) y responde 200 vacio
  // a los preflight OPTIONS. Preserva EXACTAMENTE el comportamiento de
  // CORSMiddleware.pas (Horse) -- no se cambia a un origen fijo como hace
  // NexoPago, porque eso podria romper el frontend actual sin que se haya
  // pedido ese cambio.
  TPurchaseBridgeCORSMiddleware = class(TInterfacedObject, IMVCMiddleware)
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
  System.SysUtils, System.Classes, MVCFramework.Commons;

{ TPurchaseBridgeCORSMiddleware }

procedure TPurchaseBridgeCORSMiddleware.OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
var
  LOrigin: string;
begin
  LOrigin := Trim(AContext.Request.Headers['Origin']);

  if not LOrigin.IsEmpty then
    AContext.Response.SetCustomHeader('Access-Control-Allow-Origin', LOrigin);

  AContext.Response.SetCustomHeader('Vary', 'Origin');
  AContext.Response.SetCustomHeader('Access-Control-Allow-Credentials', 'true');
  AContext.Response.SetCustomHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, Accept');
  AContext.Response.SetCustomHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');

  if AContext.Request.HTTPMethod = httpOPTIONS then
  begin
    AContext.Response.RawWebResponse.StatusCode := HTTP_STATUS.OK;
    AContext.Response.RawWebResponse.Content := '';
    // A zero-length ContentStream (rather than relying on Content := '' alone)
    // is required to get a genuinely empty body: Indy's
    // TIdHTTPResponseInfo.WriteHeader (IdCustomHTTPServer.pas) substitutes a
    // "<HTML><BODY><B>200 OK</B></BODY></HTML>" placeholder whenever
    // ContentText is empty AND no ContentStream is assigned, for any status
    // other than 204/304/1xx/HEAD. Assigning an (empty) stream makes it take
    // the ContentStream branch instead, which correctly sends zero bytes.
    // WebBroker owns freeing it (TWebResponse.FreeContentStream defaults
    // True; TIdHTTPWebBrokerBridge explicitly sets the Indy-side
    // FreeContentStream to False so it isn't double-freed).
    AContext.Response.RawWebResponse.ContentStream := TMemoryStream.Create;
    // IMPORTANT: setting AHandled := True here skips MVCEngine's routing, but
    // TMVCEngine.InternalExecuteAction only sets its own Result := True deep
    // inside the successful-routing branch that this skips -- it never
    // becomes True just because a middleware set AHandled. Under this app's
    // hosting (raw IdHTTPWebBrokerBridge, see PurchaseBridgeDMVC.dpr), that
    // False Result flows back through TWebRequestHandler.HandleRequest's own
    // "if Result and not Response.Sent then Response.SendResponse" guard, so
    // our headers/status/content would otherwise be silently discarded.
    // TMVCEngine's own OnBeforeDispatch exception handler works around the
    // exact same issue by calling AResponse.SendResponse explicitly before
    // declaring itself handled (see MVCFramework.pas), so we do the same
    // here. Confirmed empirically with both fixes together.
    AContext.Response.RawWebResponse.SendResponse;
    AHandled := True;
  end;
end;

procedure TPurchaseBridgeCORSMiddleware.OnBeforeControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; var AHandled: Boolean);
begin
  // No-op.
end;

procedure TPurchaseBridgeCORSMiddleware.OnAfterControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; const AHandled: Boolean);
begin
  // No-op.
end;

procedure TPurchaseBridgeCORSMiddleware.OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
begin
  // No-op.
end;

end.
