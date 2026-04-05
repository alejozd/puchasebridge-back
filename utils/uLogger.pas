unit uLogger;

interface

uses
  System.SysUtils;

type
  TLogLevel = (llInfo, llWarn, llError, llDebug);

procedure Log(const Msg: string; Level: TLogLevel = llInfo); overload;
procedure Log(const Msg: string; Level: TLogLevel; const Context: string); overload;
procedure LogInfo(const Msg: string; const Context: string = '');
procedure LogError(const Msg: string; const Context: string = ''); overload;
procedure LogError(const E: Exception; const Context: string = ''); overload;
procedure LogDebug(const Msg: string; const Context: string = '');

implementation

uses
  System.DateUtils,
  System.StrUtils,
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
    LogsDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'logs');
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

function GetIsoTimestamp: string;
begin
  Result := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
end;

function SanitizeInlineText(const Value: string): string;
begin
  Result := Value.Replace(sLineBreak, ' ').Replace(#10, ' ').Replace(#13, ' ').Trim;
end;

function BuildLogLine(const Msg: string; Level: TLogLevel; const Context: string): string;
var
  LContext: string;
begin
  LContext := Context.Trim;
  if LContext.IsEmpty then
    Exit(Format('[%s] [%s] %s', [GetIsoTimestamp, LevelToString(Level), Msg]));

  Result := Format('[%s] [%s] [%s] %s', [GetIsoTimestamp, LevelToString(Level), LContext, Msg]);
end;

procedure Log(const Msg: string; Level: TLogLevel; const Context: string);
var
  Line: string;
begin
  {$IFDEF RELEASE}
  // En producción ignorar DEBUG
  if Level = llDebug then Exit;
  {$ENDIF}

  Line := BuildLogLine(Msg, Level, Context);

  WriteToFile(Line);
end;

procedure Log(const Msg: string; Level: TLogLevel);
begin
  Log(Msg, Level, '');
end;

procedure LogInfo(const Msg: string; const Context: string);
begin
  Log(Msg, llInfo, Context);
end;

procedure LogError(const Msg: string; const Context: string);
begin
  Log(Msg, llError, Context);
end;

procedure LogError(const E: Exception; const Context: string);
var
  LMessage: string;
  LStack: string;
begin
  if E = nil then
  begin
    Log('Unknown exception', llError, Context);
    Exit;
  end;

  LMessage := Format('Exception [%s]: %s', [E.ClassName, E.Message]);

  LStack := SanitizeInlineText(E.StackTrace);
  if not LStack.IsEmpty then
    LMessage := LMessage + ' | stack: ' + LStack;

  Log(LMessage, llError, Context);
end;

procedure LogDebug(const Msg: string; const Context: string);
begin
  Log(Msg, llDebug, Context);
end;

initialization
  LogLock := TCriticalSection.Create;

finalization
  LogLock.Free;

end.
