unit DMVC.ServerMain;

interface

procedure StartServer(const ARunInBackground: Boolean = False; const AMaxStartAttempts: Integer = 3;
  const ARetryDelayMs: Cardinal = 5000);
procedure StopServer;
function IsServerRunning: Boolean;

var
  // Seam solo para tests: si es > 0, se usa en vez de DEFAULT_DMVC_PORT.
  // La firma publica de StartServer se mantiene identica a la de Horse
  // (ServerMain.pas) a proposito -- la Task 3 depende de que el Windows
  // Service pueda llamarla sin cambios -- asi que el puerto de prueba se
  // inyecta por esta variable, no por un parametro nuevo.
  GTestPortOverride: Integer = 0;

implementation

uses
  IdHTTPWebBrokerBridge,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  DMVC.ServerBootstrap,
  uLogger;

function GetEffectivePort: Integer;
begin
  if GTestPortOverride > 0 then
    Result := GTestPortOverride
  else
    Result := DMVC.ServerBootstrap.DEFAULT_DMVC_PORT;
end;

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
  GRunningInBackground: Boolean;
  GStopRequested: Boolean;
  GMaxStartAttempts: Integer;
  GRetryDelayMs: Cardinal;
  GServerInstance: TIdHTTPWebBrokerBridge;

{ TServerRunner }

constructor TServerRunner.Create;
begin
  inherited Create(True);
  FreeOnTerminate := False;
end;

procedure TServerRunner.Execute;
var
  LAttempt: Integer;
begin
  for LAttempt := 1 to GMaxStartAttempts do
  begin
    if GStopRequested then
      Exit;

    try
      uLogger.LogInfo(Format('Iniciando servidor DMVC (intento %d/%d)...', [LAttempt, GMaxStartAttempts]), 'startup');
      DMVC.ServerBootstrap.InitializeServerDependencies;
      GServerLock.Acquire;
      try
        GServerInstance := DMVC.ServerBootstrap.CreateAndActivateServer(GetEffectivePort);
        // Si StopServer/finalization ya pidieron parar mientras este intento
        // seguia bloqueado bindeando el puerto (CreateAndActivateServer),
        // el listener recien creado se apaga aqui mismo en vez de quedar
        // huerfano -- StopServer nunca lo veria a tiempo para desactivarlo.
        if GStopRequested then
        begin
          GServerInstance.Active := False;
          FreeAndNil(GServerInstance);
        end;
      finally
        GServerLock.Release;
      end;
      Exit;
    except
      on E: Exception do
      begin
        uLogger.LogError(E, Format('startup attempt %d/%d', [LAttempt, GMaxStartAttempts]));

        if (LAttempt < GMaxStartAttempts) and (not GStopRequested) then
          GStopEvent.WaitFor(GRetryDelayMs)
        else
          raise;
      end;
    end;
  end;
end;

procedure StartServer(const ARunInBackground: Boolean; const AMaxStartAttempts: Integer; const ARetryDelayMs: Cardinal);
var
  LAttempt: Integer;
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

  for LAttempt := 1 to AMaxStartAttempts do
  begin
    if GStopRequested then
      Exit;

    try
      uLogger.LogInfo(Format('Iniciando servidor DMVC (intento %d/%d)...', [LAttempt, AMaxStartAttempts]), 'startup');
      DMVC.ServerBootstrap.InitializeServerDependencies;
      GServerLock.Acquire;
      try
        GServerInstance := DMVC.ServerBootstrap.CreateAndActivateServer(GetEffectivePort);
        if GStopRequested then
        begin
          GServerInstance.Active := False;
          FreeAndNil(GServerInstance);
        end;
      finally
        GServerLock.Release;
      end;
      Exit;
    except
      on E: Exception do
      begin
        uLogger.LogError(E, Format('startup attempt %d/%d', [LAttempt, AMaxStartAttempts]));

        if (LAttempt < AMaxStartAttempts) and (not GStopRequested) then
          GStopEvent.WaitFor(ARetryDelayMs)
        else
          raise;
      end;
    end;
  end;
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

  GServerLock.Acquire;
  try
    try
      if Assigned(GServerInstance) then
      begin
        GServerInstance.Active := False;
        FreeAndNil(GServerInstance);
      end;
    except
      on E: Exception do
        uLogger.LogError(E, 'shutdown');
    end;
  finally
    GServerLock.Release;
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
  GServerLock.Acquire;
  try
    Result := Assigned(GServerInstance) and GServerInstance.Active;
  finally
    GServerLock.Release;
  end;
end;

initialization
  GServerLock := TCriticalSection.Create;
  GStopEvent := TEvent.Create(nil, True, False, '');
  GStopRequested := False;
  GMaxStartAttempts := 3;
  GRetryDelayMs := 5000;

finalization
  if GRunningInBackground and Assigned(GServerThread) then
  begin
    GStopRequested := True;
    GStopEvent.SetEvent;
    GServerLock.Acquire;
    try
      if Assigned(GServerInstance) then
      begin
        GServerInstance.Active := False;
        FreeAndNil(GServerInstance);
      end;
    finally
      GServerLock.Release;
    end;
    GServerThread.WaitFor;
    FreeAndNil(GServerThread);
  end;

  GStopEvent.Free;
  GServerLock.Free;

end.
