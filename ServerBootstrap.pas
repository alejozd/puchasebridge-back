unit ServerBootstrap;

interface

procedure StartServer;

implementation

uses
  Horse,
  Horse.Jhonson,
  Horse.OctetStream,
  Horse.Exception,
  Horse.HandleException,
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  System.StrUtils,
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
  LicenseMiddleware,
  uLogger,
  ErrorResponseUtils,
  LicenseService;

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
  Result := (TThread.GetTickCount64 - GApplicationStartTicks) div 1000;
end;

function BuildPingResponse: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('status', 'ok');
  Result.AddPair('service', 'PurchaseBridge');
  Result.AddPair('timestamp', GetCurrentUtcIsoTimestamp);
  Result.AddPair('uptime_seconds', TJSONNumber.Create(GetUptimeSeconds));
end;

function IsAllowedOrigin(const AOrigin: string): Boolean;
begin
  Result := MatchText(AOrigin, ['http://localhost:5173', 'http://127.0.0.1:5173']);
end;

procedure ApplyCORSHeaders(const Req: THorseRequest; const Res: THorseResponse);
var
  LOrigin: string;
begin
  LOrigin := Req.Headers['Origin'];
  if IsAllowedOrigin(LOrigin) then
    Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Origin', LOrigin)
  else
    Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Origin', 'http://localhost:5173');

  Res.RawWebResponse.SetCustomHeader('Vary', 'Origin');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Credentials', 'true');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, Accept');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Max-Age', '86400');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Expose-Headers', 'Content-Disposition, Content-Type');
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
        LStartTick := TThread.GetTickCount64;
        LPath := Req.RawWebRequest.PathInfo;
        if LPath.IsEmpty then
          LPath := Req.PathInfo;

        uLogger.LogInfo(Format('Incoming request: %s %s', [Req.RawWebRequest.Method, LPath]), 'http_request');
        Next();
        uLogger.LogInfo(
          Format('Completed request: %s %s -> %d (%d ms)',
            [Req.RawWebRequest.Method, LPath, Res.RawWebResponse.StatusCode, TThread.GetTickCount64 - LStartTick]),
          'http_request'
        );
      end)
    .Use(
      procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
      begin
        ApplyCORSHeaders(Req, Res);

        if SameText(Req.RawWebRequest.Method, 'OPTIONS') then
        begin
          Res.Status(THTTPStatus.OK).Send('');
          raise EHorseCallbackInterrupted.Create;
        end;

        Next();
      end)
    .Use(HandleException(
      procedure(const E: Exception; const Req: THorseRequest; const Res: THorseResponse; var ASendException: Boolean)
      var
        LStatus: Integer;
        LMessage: string;
      begin
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
  GConfigured := True;
end;

procedure InitializeServerDependencies;
begin
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
  GApplicationStartTicks := TThread.GetTickCount64;

end.
