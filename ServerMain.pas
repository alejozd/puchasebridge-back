unit ServerMain;

interface

procedure StartServer(const ARunInBackground: Boolean = False; const AMaxStartAttempts: Integer = 3;
  const ARetryDelayMs: Cardinal = 5000);
procedure StopServer;
function IsServerRunning: Boolean;

implementation

uses
  Horse,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  ServerBootstrap,
  uLogger;

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
      uLogger.LogInfo(Format('Iniciando servidor Horse (intento %d/%d)...', [LAttempt, GMaxStartAttempts]), 'startup');
      ServerBootstrap.StartServer;
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
      uLogger.LogInfo(Format('Iniciando servidor Horse (intento %d/%d)...', [LAttempt, AMaxStartAttempts]), 'startup');
      ServerBootstrap.StartServer;
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

  try
    THorse.StopListen;
  except
    on E: Exception do
      uLogger.LogError(E, 'shutdown');
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
