unit ServerBootstrap;

interface

procedure StartServer;

implementation

uses
  Winapi.Windows,
  Horse,
  Horse.Jhonson,
  Horse.OctetStream,
  Horse.Exception,
  Horse.HandleException,
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  System.JSON,
  HConfig,
  ProveedorRepository,
  ProductoRepository,
  XMLFacturaService,
  XmlParserService,
  XmlPersistenceService,
  HelisaUtils,
  HelisaService,
  EquivalenciaService,
  DianUnits,
  ValidationService,
  DocumentoService,
  ImportController,
  ProveedorController,
  XmlController,
  XmlValidationController,
  EquivalenciaController,
  HelisaController,
  DocumentosController,
  AuthService,
  AuthController,
  LicenciaController,
  AuthMiddleware,
  CORSMiddleware,
  LicenseMiddleware,
  uStaticFilesMiddleware,
  uLogger,
  ErrorResponseUtils,
  LicenseService,
  uPaths;

var
  GConfigured: Boolean;
  GApplicationStartTicks: UInt64;

function GetServerPort: Integer;
begin
  // Puerto por defecto actual del proyecto.
  Result := 9000;
end;

function GetCurrentUtcIsoTimestamp: string;
begin
  Result := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
end;

function GetUptimeSeconds: Int64;
begin
  Result := (GetTickCount64 - GApplicationStartTicks) div 1000;
end;

function BuildPingResponse: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('status', 'ok');
  Result.AddPair('service', 'PurchaseBridge');
  Result.AddPair('timestamp', GetCurrentUtcIsoTimestamp);
  Result.AddPair('uptime_seconds', TJSONNumber.Create(GetUptimeSeconds));
end;

procedure RegisterMiddleware;
begin
  THorse
    .Use(
      procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
      var
        LStartTick: UInt64;
        LPath: string;
      begin
        LStartTick := GetTickCount64;
        LPath := Req.RawWebRequest.PathInfo;
        if LPath.IsEmpty then
          LPath := Req.PathInfo;

        uLogger.LogInfo(Format('Incoming request: %s %s', [Req.RawWebRequest.Method, LPath]), 'http_request');
      end)
    .Use(
      procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
      begin
        ApplyDynamicCORS(Req, Res, Next);
      end)
    .Use(HandleException(
      procedure(const E: Exception; const Req: THorseRequest; const Res: THorseResponse; var ASendException: Boolean)
      var
        LStatus: Integer;
        LMessage: string;
      begin
        if E is EHorseCallbackInterrupted then
        begin
          ASendException := False;
          Exit;
        end;

        uLogger.LogError(E, 'horse_exception');
        LStatus := Integer(THTTPStatus.InternalServerError);
        LMessage := 'Error interno del servidor';

        if E is EHorseException then
        begin
          LStatus := Integer(EHorseException(E).Status);
          if not EHorseException(E).Error.Trim.IsEmpty then
            LMessage := EHorseException(E).Error;
        end;

        SendErrorResponse(Res, LStatus, LMessage, E.Message);
        ASendException := False;
      end))
    .Use(Jhonson())
    .Use(OctetStream)
    .Use(LicenseGuard)
    .Use(Auth);
end;

procedure RegisterRoutes;
begin
  THorse.Get('/ping',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LPingResponse: TJSONObject;
    begin
      LPingResponse := BuildPingResponse;
      try
        Res.ContentType('application/json')
          .Status(THTTPStatus.OK)
          .Send(LPingResponse.ToJSON);
      finally
        LPingResponse.Free;
      end;
    end);

  ImportController.Registry;
  ProveedorController.Registry;
  XmlController.Registry;
  XmlValidationController.Registry;
  EquivalenciaController.Registry;
  HelisaController.Registry;
  DocumentosController.Registry;
  AuthController.Registry;
  TLicenciaController.Registry;
end;

procedure ConfigureHorse;
begin
  if GConfigured then
    Exit;

  RegisterMiddleware;
  RegisterRoutes;
  RegisterStaticFilesMiddleware('www');
  GConfigured := True;
end;

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
  uLogger.LogInfo('Configuracion cargada correctamente.', 'startup');

  try
    TLicenciaService.InicializarLicencia;
    TLicenciaService.StartPeriodicValidation;
  except
    on E: Exception do
      uLogger.LogError(E, 'startup');
  end;
end;

procedure StartServer;
var
  LPort: Integer;
begin
  InitializeServerDependencies;
  ConfigureHorse;

  LPort := GetServerPort;
  uLogger.LogInfo('Iniciando servidor Horse en puerto ' + IntToStr(LPort) + '...', 'startup');

  THorse.Listen(LPort,
    procedure
    begin
      uLogger.LogInfo('Server is running on port ' + IntToStr(THorse.Port), 'startup');
    end);
end;

initialization
  GConfigured := False;
  GApplicationStartTicks := GetTickCount64;

end.
