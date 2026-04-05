program PurchaseBridge;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  ServerBootstrap in 'ServerBootstrap.pas',
  HConfig in 'config\HConfig.pas',
  FirebirdConnection in 'database\FirebirdConnection.pas',
  ProveedorRepository in 'repositories\ProveedorRepository.pas',
  ProductoRepository in 'repositories\ProductoRepository.pas',
  XMLFacturaService in 'services\XMLFacturaService.pas',
  XmlParserService in 'services\XmlParserService.pas',
  XmlPersistenceService in 'services\XmlPersistenceService.pas',
  HelisaUtils in 'utils\HelisaUtils.pas',
  HelisaService in 'services\HelisaService.pas',
  EquivalenciaService in 'services\EquivalenciaService.pas',
  DianUnits in 'services\DianUnits.pas',
  ValidationService in 'services\ValidationService.pas',
  DocumentoService in 'services\DocumentoService.pas',
  ImportController in 'controllers\ImportController.pas',
  ProveedorController in 'controllers\ProveedorController.pas',
  XmlController in 'controllers\XmlController.pas',
  XmlValidationController in 'controllers\XmlValidationController.pas',
  EquivalenciaController in 'controllers\EquivalenciaController.pas',
  HelisaController in 'controllers\HelisaController.pas',
  DocumentosController in 'controllers\DocumentosController.pas',
  AuthService in 'services\AuthService.pas',
  AuthController in 'controllers\AuthController.pas',
  LicenciaController in 'controllers\LicenciaController.pas',
  AuthMiddleware in 'middleware\AuthMiddleware.pas',
  LicenseMiddleware in 'middleware\LicenseMiddleware.pas',
  uLogger in 'utils\uLogger.pas',
  uPaths in 'utils\uPaths.pas',
  ErrorResponseUtils in 'utils\ErrorResponseUtils.pas',
  LicenseService in 'services\LicenseService.pas';

begin
  try
    StartServer;
  except
    on E: Exception do
    begin
      Log('Fallo fatal en ejecucion de consola: ' + E.Message, llError);
      Halt(1);
    end;
  end;
end.
