unit uLogger;

interface

uses
  System.SysUtils, System.JSON;

type
  TLogLevel = (llDebug, llInfo, llWarn, llError);

procedure Log(const Msg: string; Level: TLogLevel = llInfo; const AType: string = 'system'); overload;
procedure Log(const Msg: string; Level: TLogLevel; const AType, AMethod, APath: string; AStatus: Integer; ADuration: Int64); overload;
procedure LogInfo(const Msg: string; const AType: string = 'system');
procedure LogWarn(const Msg: string; const AType: string = 'system');
procedure LogError(const Msg: string; const AType: string = 'error'); overload;
procedure LogError(const E: Exception; const AType: string = 'error'; const APath: string = ''); overload;
procedure LogDebug(const Msg: string; const AType: string = 'debug');

implementation

uses
  System.DateUtils,
  System.IOUtils,
  System.SyncObjs,
  uPaths,
  HConfig;

var
  LogLock: TCriticalSection;

function LevelToString(Level: TLogLevel): string;
begin
  case Level of
    llDebug: Result := 'DEBUG';
    llInfo: Result := 'INFO';
    llWarn: Result := 'WARN';
    llError: Result := 'ERROR';
  else
    Result := 'INFO';
  end;
end;

function StringToLevel(const S: string): TLogLevel;
begin
  if S = 'DEBUG' then Exit(llDebug);
  if S = 'WARN' then Exit(llWarn);
  if S = 'ERROR' then Exit(llError);
  Result := llInfo;
end;

function ShouldLog(Level: TLogLevel): Boolean;
var
  ConfigLevel: TLogLevel;
begin
  try
    ConfigLevel := StringToLevel(THConfig.GetInstance.Config.LogLevel);
    Result := Ord(Level) >= Ord(ConfigLevel);
  except
    Result := Ord(Level) >= Ord(llInfo);
  end;
end;

procedure WriteToFile(const Text: string);
var
  LogFile: TextFile;
  LogsDir, FileName: string;
begin
  LogLock.Acquire;
  try
    LogsDir := GetLogsPath;
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

function GetIsoTimestamp: string;
begin
  Result := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
end;

procedure InternalLog(Level: TLogLevel; const Msg, AType, AMethod, APath: string; AStatus: Integer; ADuration: Int64; E: Exception = nil);
var
  LJSON: TJSONObject;
begin
  if not ShouldLog(Level) then
    Exit;

  LJSON := TJSONObject.Create;
  try
    LJSON.AddPair('timestamp', GetIsoTimestamp);
    LJSON.AddPair('level', LevelToString(Level));
    LJSON.AddPair('type', AType);

    if not AMethod.IsEmpty then
      LJSON.AddPair('method', AMethod);

    if not APath.IsEmpty then
      LJSON.AddPair('path', APath);

    if AStatus <> 0 then
      LJSON.AddPair('status', TJSONNumber.Create(AStatus));

    if ADuration >= 0 then
      LJSON.AddPair('duration_ms', TJSONNumber.Create(ADuration));

    LJSON.AddPair('message', Msg);

    if E <> nil then
    begin
      LJSON.AddPair('exception', E.ClassName);
      if not E.StackTrace.IsEmpty then
        LJSON.AddPair('stack', E.StackTrace.Replace(sLineBreak, ' | '));
    end;

    WriteToFile(LJSON.ToJSON);
  finally
    LJSON.Free;
  end;
end;

procedure Log(const Msg: string; Level: TLogLevel; const AType: string);
begin
  InternalLog(Level, Msg, AType, '', '', 0, -1);
end;

procedure Log(const Msg: string; Level: TLogLevel; const AType, AMethod, APath: string; AStatus: Integer; ADuration: Int64);
begin
  InternalLog(Level, Msg, AType, AMethod, APath, AStatus, ADuration);
end;

procedure LogInfo(const Msg: string; const AType: string);
begin
  Log(Msg, llInfo, AType);
end;

procedure LogWarn(const Msg: string; const AType: string);
begin
  Log(Msg, llWarn, AType);
end;

procedure LogError(const Msg: string; const AType: string);
begin
  Log(Msg, llError, AType);
end;

procedure LogError(const E: Exception; const AType: string; const APath: string);
var
  LMsg: string;
begin
  if E <> nil then
    LMsg := E.Message
  else
    LMsg := 'Unknown error';

  InternalLog(llError, LMsg, AType, '', APath, 0, -1, E);
end;

procedure LogDebug(const Msg: string; const AType: string);
begin
  Log(Msg, llDebug, AType);
end;

initialization
  LogLock := TCriticalSection.Create;

finalization
  LogLock.Free;

end.
