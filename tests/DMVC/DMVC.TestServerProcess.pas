unit DMVC.TestServerProcess;

interface

uses
  Winapi.Windows, System.SysUtils, System.Diagnostics, IdHTTP;

type
  TTestServerProcess = class
  private
    FProcessInfo: TProcessInformation;
    FRunning: Boolean;
  public
    procedure Start(const AExePath: string; APort: Integer);
    procedure Stop;
    function WaitForReady(APort: Integer; ATimeoutMs: Integer = 8000): Boolean;
  end;

implementation

procedure TTestServerProcess.Start(const AExePath: string; APort: Integer);
var
  LStartupInfo: TStartupInfo;
begin
  FillChar(FProcessInfo, SizeOf(FProcessInfo), 0);
  FillChar(LStartupInfo, SizeOf(LStartupInfo), 0);
  LStartupInfo.cb := SizeOf(LStartupInfo);
  if not CreateProcess(PChar(AExePath), nil, nil, nil, False,
    CREATE_NEW_CONSOLE, nil, PChar(ExtractFilePath(AExePath)), LStartupInfo, FProcessInfo) then
    RaiseLastOSError;
  FRunning := True;
end;

procedure TTestServerProcess.Stop;
begin
  if FRunning then
  begin
    TerminateProcess(FProcessInfo.hProcess, 0);
    WaitForSingleObject(FProcessInfo.hProcess, 3000);
    CloseHandle(FProcessInfo.hProcess);
    CloseHandle(FProcessInfo.hThread);
    FRunning := False;
  end;
end;

function TTestServerProcess.WaitForReady(APort: Integer; ATimeoutMs: Integer): Boolean;
var
  LHttp: TIdHTTP;
  LStopwatch: TStopwatch;
begin
  Result := False;
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.ConnectTimeout := 300;
    LHttp.ReadTimeout := 300;
    LStopwatch := TStopwatch.StartNew;
    while LStopwatch.ElapsedMilliseconds < ATimeoutMs do
    begin
      try
        LHttp.Get(Format('http://localhost:%d/ping', [APort]));
        Exit(True);
      except
        Sleep(200);
      end;
    end;
  finally
    LHttp.Free;
  end;
end;

end.
