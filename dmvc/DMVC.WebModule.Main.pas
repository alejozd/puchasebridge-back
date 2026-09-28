unit DMVC.WebModule.Main;

interface

uses
  System.SysUtils, System.Classes, System.IniFiles, Web.HTTPApp,
  MVCFramework, MVCFramework.JWT, MVCFramework.Middleware.JWT,
  uPaths;

type
  TPurchaseBridgeDMVCWebModule = class(TWebModule)
  private
    FEngine: TMVCEngine;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  WebModuleClass: TComponentClass = TPurchaseBridgeDMVCWebModule;

implementation

uses
  DMVC.Controllers.PingController,
  DMVC.Controllers.EquivalenciaController,
  DMVC.Controllers.ProveedorController,
  DMVC.Controllers.HelisaController,
  DMVC.Controllers.LicenciaController,
  DMVC.Controllers.XmlValidationController,
  DMVC.Controllers.ImportController,
  DMVC.Controllers.DocumentosController,
  DMVC.Controllers.AuthController,
  DMVC.Middleware.HttpLogger,
  DMVC.Middleware.CORS,
  DMVC.Middleware.License,
  DMVC.Middleware.StaticApp,
  DMVC.Security.JWTClaims,
  DMVC.Security.AuthHandler;

function GetJWTSecret: string;
var
  LIni: TIniFile;
begin
  LIni := TIniFile.Create(uPaths.GetConfigPath);
  try
    Result := LIni.ReadString('AUTH', 'JWTSecret', '');
  finally
    LIni.Free;
  end;
  if Length(Result) < 32 then
    raise Exception.Create('config.ini debe tener [AUTH] JWTSecret con al menos 32 caracteres. ' +
      'Un secreto vacio o corto permite falsificar tokens JWT validos.');
end;

constructor TPurchaseBridgeDMVCWebModule.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEngine := TMVCEngine.Create(Self);
  FEngine.AddMiddleware(TPurchaseBridgeTraceMiddleware.Create);
  FEngine.AddMiddleware(TPurchaseBridgeCORSMiddleware.Create);
  FEngine.AddMiddleware(TPurchaseBridgeLicenseMiddleware.Create);
  FEngine.AddMiddleware(TPurchaseBridgeStaticAppMiddleware.Create(
    ExtractFilePath(ParamStr(0)) + 'www'));
  FEngine.AddMiddleware(TMVCJWTAuthenticationMiddleware.Create(
    TPurchaseBridgeAuthHandler.Create,
    SetupPurchaseBridgeJWTClaims,
    GetJWTSecret,
    '/api/auth/login',
    [TJWTCheckableClaim.ExpirationTime, TJWTCheckableClaim.NotBefore, TJWTCheckableClaim.IssuedAt],
    30));
  FEngine.AddController(TPingController);
  FEngine.AddController(TEquivalenciaController);
  FEngine.AddController(TProveedorController);
  FEngine.AddController(THelisaController);
  FEngine.AddController(TLicenciaController);
  FEngine.AddController(TXmlValidationController);
  FEngine.AddController(TImportController);
  FEngine.AddController(TDocumentosController);
  FEngine.AddController(TAuthController);
end;

destructor TPurchaseBridgeDMVCWebModule.Destroy;
begin
  FEngine.Free;
  inherited;
end;

end.
