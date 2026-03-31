unit uLogger;

interface

type
  TLogLevel = (llInfo, llWarn, llError, llDebug);

procedure Log(const Msg: string; Level: TLogLevel = llInfo);

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.SyncObjs;

var
  LogLock: TCriticalSection;

procedure WriteToFile(const Text: string);
var
  LogFile: TextFile;
  LogsDir, FileName: string;
begin
  LogLock.Acquire;
  try
    LogsDir := 'logs';
    if not TDirectory.Exists(LogsDir) then
      TDirectory.CreateDirectory(LogsDir);

    FileName := TPath.Combine(LogsDir, 'app.log');

    AssignFile(LogFile, FileName);

    if FileExists(FileName) then
      Append(LogFile)
    else
      Rewrite(LogFile);

    WriteLn(LogFile, Text);
    CloseFile(LogFile);
  finally
    LogLock.Release;
  end;
end;

function LevelToString(Level: TLogLevel): string;
begin
  case Level of
    llInfo: Result := 'INFO';
    llWarn: Result := 'WARN';
    llError: Result := 'ERROR';
    llDebug: Result := 'DEBUG';
  end;
end;

procedure Log(const Msg: string; Level: TLogLevel);
var
  Line: string;
begin
  {$IFDEF RELEASE}
  // En producción ignorar DEBUG
  if Level = llDebug then Exit;
  {$ENDIF}

  Line := Format(
    '[%s] [%s] %s',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), LevelToString(Level), Msg]
  );

  WriteToFile(Line);
end;

initialization
  LogLock := TCriticalSection.Create;

finalization
  LogLock.Free;

end.
