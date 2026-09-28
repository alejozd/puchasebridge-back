program PurchaseBridgeSvcHost;

{$R *.res}

uses
  Vcl.SvcMgr,
  DMVC.ServerBootstrap in 'dmvc\DMVC.ServerBootstrap.pas',
  DMVC.ServerMain in 'dmvc\DMVC.ServerMain.pas',
  DMVC.WebModule.Main in 'dmvc\DMVC.WebModule.Main.pas',
  DMVC.Controllers.AuthController in 'dmvc\Controllers\DMVC.Controllers.AuthController.pas',
  DMVC.Controllers.DocumentosController in 'dmvc\Controllers\DMVC.Controllers.DocumentosController.pas',
  DMVC.Controllers.EquivalenciaController in 'dmvc\Controllers\DMVC.Controllers.EquivalenciaController.pas',
  DMVC.Controllers.HelisaController in 'dmvc\Controllers\DMVC.Controllers.HelisaController.pas',
  DMVC.Controllers.ImportController in 'dmvc\Controllers\DMVC.Controllers.ImportController.pas',
  DMVC.Controllers.LicenciaController in 'dmvc\Controllers\DMVC.Controllers.LicenciaController.pas',
  DMVC.Controllers.PingController in 'dmvc\Controllers\DMVC.Controllers.PingController.pas',
  DMVC.Controllers.ProveedorController in 'dmvc\Controllers\DMVC.Controllers.ProveedorController.pas',
  DMVC.Controllers.XmlController in 'dmvc\Controllers\DMVC.Controllers.XmlController.pas',
  DMVC.Controllers.XmlValidationController in 'dmvc\Controllers\DMVC.Controllers.XmlValidationController.pas',
  DMVC.DTOs.Equivalencia in 'dmvc\DTOs\DMVC.DTOs.Equivalencia.pas',
  DMVC.DTOs.EquivalenciaCreate in 'dmvc\DTOs\DMVC.DTOs.EquivalenciaCreate.pas',
  DMVC.DTOs.Helisa in 'dmvc\DTOs\DMVC.DTOs.Helisa.pas',
  DMVC.DTOs.Proveedor in 'dmvc\DTOs\DMVC.DTOs.Proveedor.pas',
  DMVC.Middleware.CORS in 'dmvc\Middleware\DMVC.Middleware.CORS.pas',
  DMVC.Middleware.HttpLogger in 'dmvc\Middleware\DMVC.Middleware.HttpLogger.pas',
  DMVC.Middleware.License in 'dmvc\Middleware\DMVC.Middleware.License.pas',
  DMVC.Middleware.StaticApp in 'dmvc\Middleware\DMVC.Middleware.StaticApp.pas',
  DMVC.Security.AuthHandler in 'dmvc\Security\DMVC.Security.AuthHandler.pas',
  DMVC.Security.JWTClaims in 'dmvc\Security\DMVC.Security.JWTClaims.pas',
  HConfig in 'config\HConfig.pas',
  FirebirdConnection in 'database\FirebirdConnection.pas',
  ProductoRepository in 'repositories\ProductoRepository.pas',
  ProveedorRepository in 'repositories\ProveedorRepository.pas',
  PurchaseBridge.Service in 'service\PurchaseBridge.Service.pas' {PurchaseBridgeService: TService},
  DianUnits in 'services\DianUnits.pas',
  DocumentoService in 'services\DocumentoService.pas',
  EquivalenciaService in 'services\EquivalenciaService.pas',
  HelisaService in 'services\HelisaService.pas',
  LicenseService in 'services\LicenseService.pas',
  ValidationService in 'services\ValidationService.pas',
  XMLFacturaService in 'services\XMLFacturaService.pas',
  XmlParserService in 'services\XmlParserService.pas',
  XmlPersistenceService in 'services\XmlPersistenceService.pas',
  HelisaUtils in 'utils\HelisaUtils.pas',
  uLogger in 'utils\uLogger.pas',
  uPaths in 'utils\uPaths.pas';

begin
  if not Application.DelayInitialize or Application.Installing then
    Application.Initialize;
  Application.CreateForm(TPurchaseBridgeService, PurchaseBridgeService);
  Application.Run;
end.
