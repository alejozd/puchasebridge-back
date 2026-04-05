program PurchaseBridgeSvcHost;

uses
  Vcl.SvcMgr,
  ServerBootstrap in 'ServerBootstrap.pas',
  ServerMain in 'ServerMain.pas',
  HConfig in 'config\HConfig.pas',
  AuthController in 'controllers\AuthController.pas',
  DocumentosController in 'controllers\DocumentosController.pas',
  EquivalenciaController in 'controllers\EquivalenciaController.pas',
  HelisaController in 'controllers\HelisaController.pas',
  ImportController in 'controllers\ImportController.pas',
  LicenciaController in 'controllers\LicenciaController.pas',
  ProveedorController in 'controllers\ProveedorController.pas',
  XmlController in 'controllers\XmlController.pas',
  XmlValidationController in 'controllers\XmlValidationController.pas',
  FirebirdConnection in 'database\FirebirdConnection.pas',
  AuthMiddleware in 'middleware\AuthMiddleware.pas',
  LicenseMiddleware in 'middleware\LicenseMiddleware.pas',
  ProductoRepository in 'repositories\ProductoRepository.pas',
  ProveedorRepository in 'repositories\ProveedorRepository.pas',
  PurchaseBridge.Service in 'service\PurchaseBridge.Service.pas' {PurchaseBridgeService: TService},
  AuthService in 'services\AuthService.pas',
  DianUnits in 'services\DianUnits.pas',
  DocumentoService in 'services\DocumentoService.pas',
  EquivalenciaService in 'services\EquivalenciaService.pas',
  HelisaService in 'services\HelisaService.pas',
  LicenseService in 'services\LicenseService.pas',
  ValidationService in 'services\ValidationService.pas',
  XMLFacturaService in 'services\XMLFacturaService.pas',
  XmlParserService in 'services\XmlParserService.pas',
  XmlPersistenceService in 'services\XmlPersistenceService.pas',
  ErrorResponseUtils in 'utils\ErrorResponseUtils.pas',
  HelisaUtils in 'utils\HelisaUtils.pas',
  uLogger in 'utils\uLogger.pas',
  uPaths in 'utils\uPaths.pas';

{$R *.RES}

begin
  if not Application.DelayInitialize or Application.Installing then
    Application.Initialize;
  Application.CreateForm(TPurchaseBridgeService, PurchaseBridgeService);
  Application.Run;
end.
