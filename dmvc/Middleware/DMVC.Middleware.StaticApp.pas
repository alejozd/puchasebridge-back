unit DMVC.Middleware.StaticApp;

interface

uses
  System.SysUtils,
  MVCFramework,
  MVCFramework.Middleware.StaticFiles;

type
  TPurchaseBridgeStaticAppMiddleware = class(TInterfacedObject, IMVCMiddleware)
  private
    fInnerStatic: IMVCMiddleware;
    function IsExcludedPath(const APath: string): Boolean;
  protected
    procedure OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
    procedure OnBeforeControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      var AHandled: Boolean);
    procedure OnAfterControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      const AHandled: Boolean);
    procedure OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
  public
    constructor Create(const ADocumentRoot: string);
  end;

implementation

{ TPurchaseBridgeStaticAppMiddleware }

constructor TPurchaseBridgeStaticAppMiddleware.Create(const ADocumentRoot: string);
begin
  inherited Create;
  fInnerStatic := TMVCStaticFilesMiddleware.Create('/', ADocumentRoot, 'index.html', True);
end;

function TPurchaseBridgeStaticAppMiddleware.IsExcludedPath(const APath: string): Boolean;
var
  LPath: string;
begin
  LPath := APath.ToLower;
  Result := LPath.StartsWith('/api') or
            LPath.StartsWith('/auth') or
            LPath.StartsWith('/licencia') or
            LPath.StartsWith('/factura') or
            LPath.StartsWith('/documentos') or
            (LPath = '/ping');
end;

procedure TPurchaseBridgeStaticAppMiddleware.OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
begin
  if IsExcludedPath(AContext.Request.PathInfo) then
  begin
    AHandled := False;
    Exit;
  end;
  fInnerStatic.OnBeforeRouting(AContext, AHandled);
end;

procedure TPurchaseBridgeStaticAppMiddleware.OnBeforeControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; var AHandled: Boolean);
begin
  // No-op: toda la logica corre en OnBeforeRouting, igual que el middleware de stock.
end;

procedure TPurchaseBridgeStaticAppMiddleware.OnAfterControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; const AHandled: Boolean);
begin
  // No-op.
end;

procedure TPurchaseBridgeStaticAppMiddleware.OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
begin
  // No-op.
end;

end.
