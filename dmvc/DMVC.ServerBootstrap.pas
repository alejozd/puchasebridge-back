unit DMVC.ServerBootstrap;

interface

uses
  IdHTTPWebBrokerBridge;

const
  DEFAULT_DMVC_PORT = 9000;

function CreateAndActivateServer(APort: Integer): TIdHTTPWebBrokerBridge;
procedure InitializeServerDependencies;

implementation

uses
  System.SysUtils,
  Web.WebReq, Web.WebBroker,
  MVCFramework.Commons,
  HConfig, uPaths, uLogger, LicenseService,
  DMVC.WebModule.Main;

procedure LogResolvedPaths;
begin
  uLogger.LogInfo('BasePath: ' + GetBasePath, 'startup_paths');
  uLogger.LogInfo('InputPath: ' + GetInputPath, 'startup_paths');
  uLogger.LogInfo('ProcessedPath: ' + GetProcessedPath, 'startup_paths');
  uLogger.LogInfo('LogsPath: ' + GetLogsPath, 'startup_paths');
end;

procedure InitializeServerDependencies;
begin
  EnsureServiceDirectories;
  LogResolvedPaths;

  THConfig.GetInstance;
  uLogger.LogInfo('Configuracion cargada correctamente (DMVC).', 'startup');

  try
    TLicenciaService.InicializarLicencia;
    TLicenciaService.StartPeriodicValidation;
  except
    on E: Exception do
      uLogger.LogError(E, 'startup');
  end;
end;

function CreateAndActivateServer(APort: Integer): TIdHTTPWebBrokerBridge;
begin
  if WebRequestHandler <> nil then
    WebRequestHandler.WebModuleClass := WebModuleClass;
  WebRequestHandlerProc.MaxConnections := 1024;

  Result := TIdHTTPWebBrokerBridge.Create(nil);
  try
    // Mismo fix de la Fase 1: sin esto Indy rechaza el header Authorization
    // Bearer antes de que llegue al middleware JWT. Ver PurchaseBridgeDMVC.dpr.
    Result.OnParseAuthentication := TMVCParseAuthentication.OnParseAuthentication;
    Result.DefaultPort := APort;
    Result.Active := True;
    uLogger.LogInfo('Server is running on port ' + IntToStr(APort), 'startup');
  except
    Result.Free;
    raise;
  end;
end;

end.
