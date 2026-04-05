unit ServerMain;

interface

procedure StartServer(const ARunInBackground: Boolean = False; const AMaxStartAttempts: Integer = 3;
  const ARetryDelayMs: Cardinal = 5000);
procedure StopServer;
function IsServerRunning: Boolean;

implementation

uses
  Horse,
  Horse.Jhonson,
  Horse.OctetStream,
  Horse.Exception,
  Horse.HandleException,
  System.SysUtils,
  System.StrUtils,
  System.SyncObjs,
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
  GServerThread: TThread;
  GServerLock: TObject;
  GStopEvent: TEvent;
  GConfigured: Boolean;
  GRunningInBackground: Boolean;
  GStopRequested: Boolean;

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

procedure ConfigureHorse;
begin
  if GConfigured then
    Exit;

  THorse
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
        LogError(E.Message);
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

  THorse.Get('/ping',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      Res.Send('pong');
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

  GConfigured := True;
end;

procedure InitializeServerDependencies;
begin
  // Inicio de configuración (config.ini) y licencia antes de arrancar Horse.
  THConfig.GetInstance;
  Log('Configuracion cargada correctamente.', llInfo);

  try
    TLicenciaService.InicializarLicencia;
    TLicenciaService.StartPeriodicValidation;
  except
    on E: Exception do
    begin
      Log('Error en validacion de licencia: ' + E.Message, llError);
      // El sistema continua cargando pero quedara restringido por middleware.
    end;
  end;
end;

procedure RunServer(const AMaxStartAttempts: Integer; const ARetryDelayMs: Cardinal);
var
  LAttempt: Integer;
begin
  InitializeServerDependencies;
  ConfigureHorse;

  for LAttempt := 1 to AMaxStartAttempts do
  begin
    if GStopRequested then
      Exit;

    try
      Log(Format('Iniciando servidor Horse (intento %d/%d)...', [LAttempt, AMaxStartAttempts]), llInfo);
      // Punto de inicio del servidor HTTP Horse.
      THorse.Listen(9000,
        procedure
        begin
          Log('Server is running on port ' + IntToStr(THorse.Port), llInfo);
        end,
        procedure
        begin
          Log('Server stopped on port ' + IntToStr(THorse.Port), llInfo);
        end);
      Exit;
    except
      on E: Exception do
      begin
        Log(Format('Error iniciando servidor (intento %d/%d): %s', [LAttempt, AMaxStartAttempts, E.Message]), llError);

        if (LAttempt < AMaxStartAttempts) and (not GStopRequested) then
          GStopEvent.WaitFor(ARetryDelayMs)
        else
          raise;
      end;
    end;
  end;
end;

procedure StartServer(const ARunInBackground: Boolean; const AMaxStartAttempts: Integer; const ARetryDelayMs: Cardinal);
begin
  TMonitor.Enter(GServerLock);
  try
    GStopRequested := False;
    GStopEvent.ResetEvent;
    GRunningInBackground := ARunInBackground;

    if ARunInBackground then
    begin
      if Assigned(GServerThread) then
        Exit;

      GServerThread := TThread.CreateAnonymousThread(
        procedure
        begin
          try
            RunServer(AMaxStartAttempts, ARetryDelayMs);
          except
            on E: Exception do
              Log('Fallo fatal iniciando el servidor Horse: ' + E.Message, llError);
          end;
        end);
      GServerThread.FreeOnTerminate := False;
      GServerThread.Start;
      Exit;
    end;
  finally
    TMonitor.Exit(GServerLock);
  end;

  RunServer(AMaxStartAttempts, ARetryDelayMs);
end;

procedure StopServer;
var
  LThread: TThread;
begin
  TMonitor.Enter(GServerLock);
  try
    GStopRequested := True;
    GStopEvent.SetEvent;
    LThread := GServerThread;
  finally
    TMonitor.Exit(GServerLock);
  end;

  try
    // Punto de parada segura del servidor Horse al detener la aplicación/servicio.
    THorse.StopListen;
  except
    on E: Exception do
      Log('Error deteniendo servidor Horse: ' + E.Message, llError);
  end;

  if Assigned(LThread) then
  begin
    LThread.WaitFor;
    TMonitor.Enter(GServerLock);
    try
      FreeAndNil(GServerThread);
    finally
      TMonitor.Exit(GServerLock);
    end;
  end;
end;

function IsServerRunning: Boolean;
begin
  Result := THorse.IsRunning;
end;

initialization
  GServerLock := TObject.Create;
  GStopEvent := TEvent.Create(nil, True, False, '');
  GConfigured := False;
  GStopRequested := False;

finalization
  if GRunningInBackground and Assigned(GServerThread) then
  begin
    GStopRequested := True;
    GStopEvent.SetEvent;
    THorse.StopListen;
    GServerThread.WaitFor;
    FreeAndNil(GServerThread);
  end;

  GStopEvent.Free;
  GServerLock.Free;

end.
