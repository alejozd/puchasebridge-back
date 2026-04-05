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
  System.Classes,
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

type
  TServerRunner = class(TThread)
  protected
    procedure Execute; override;
  public
    constructor Create;
  end;

var
  GServerThread: TServerRunner;
  GServerLock: TCriticalSection;
  GStopEvent: TEvent;
  GConfigured: Boolean;
  GRunningInBackground: Boolean;
  GStopRequested: Boolean;
  GMaxStartAttempts: Integer;
  GRetryDelayMs: Cardinal;

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
  THConfig.GetInstance;
  Log('Configuracion cargada correctamente.', llInfo);

  try
    TLicenciaService.InicializarLicencia;
    TLicenciaService.StartPeriodicValidation;
  except
    on E: Exception do
    begin
      Log('Error en validacion de licencia: ' + E.Message, llError);
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

{ TServerRunner }

constructor TServerRunner.Create;
begin
  inherited Create(True);
  FreeOnTerminate := False;
end;

procedure TServerRunner.Execute;
begin
  try
    RunServer(GMaxStartAttempts, GRetryDelayMs);
  except
    on E: Exception do
      Log('Fallo fatal iniciando el servidor Horse: ' + E.Message, llError);
  end;
end;

procedure StartServer(const ARunInBackground: Boolean; const AMaxStartAttempts: Integer; const ARetryDelayMs: Cardinal);
begin
  GServerLock.Acquire;
  try
    GStopRequested := False;
    GStopEvent.ResetEvent;
    GRunningInBackground := ARunInBackground;
    GMaxStartAttempts := AMaxStartAttempts;
    GRetryDelayMs := ARetryDelayMs;

    if ARunInBackground then
    begin
      if Assigned(GServerThread) then
        Exit;

      GServerThread := TServerRunner.Create;
      GServerThread.Start;
      Exit;
    end;
  finally
    GServerLock.Release;
  end;

  RunServer(AMaxStartAttempts, ARetryDelayMs);
end;

procedure StopServer;
begin
  GServerLock.Acquire;
  try
    GStopRequested := True;
    GStopEvent.SetEvent;
  finally
    GServerLock.Release;
  end;

  try
    // Punto de parada segura del servidor Horse al detener la aplicación/servicio.
    THorse.StopListen;
  except
    on E: Exception do
      Log('Error deteniendo servidor Horse: ' + E.Message, llError);
  end;

  GServerLock.Acquire;
  try
    if Assigned(GServerThread) then
    begin
      GServerThread.WaitFor;
      FreeAndNil(GServerThread);
    end;
  finally
    GServerLock.Release;
  end;
end;

function IsServerRunning: Boolean;
begin
  Result := THorse.IsRunning;
end;

initialization
  GServerLock := TCriticalSection.Create;
  GStopEvent := TEvent.Create(nil, True, False, '');
  GConfigured := False;
  GStopRequested := False;
  GMaxStartAttempts := 3;
  GRetryDelayMs := 5000;

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
