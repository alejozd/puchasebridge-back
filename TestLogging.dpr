program TestLogging;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.JSON,
  System.IOUtils,
  uLogger in 'utils/uLogger.pas',
  uPaths in 'utils/uPaths.pas',
  HConfig in 'config/HConfig.pas';

procedure TestJsonFormat;
var
  LogContent: string;
  LogLines: TArray<string>;
  JSON: TJSONObject;
  LogsFile: string;
begin
  Writeln('Testing JSON format...');

  uLogger.LogInfo('Test message', 'test_type');

  LogsFile := TPath.Combine(GetLogsPath, 'app.log');
  if not FileExists(LogsFile) then
    raise Exception.Create('Log file not created');

  LogContent := TFile.ReadAllText(LogsFile);
  LogLines := LogContent.Split([sLineBreak], TStringSplitOptions.ExcludeEmpty);

  JSON := TJSONObject.ParseJSONValue(LogLines[High(LogLines)]) as TJSONObject;
  try
    if not Assigned(JSON) then
      raise Exception.Create('Invalid JSON format in log');

    Writeln('JSON validation passed: ' + JSON.ToJSON);

    if JSON.GetValue('message').Value <> 'Test message' then
      raise Exception.Create('Message mismatch');

    if JSON.GetValue('type').Value <> 'test_type' then
      raise Exception.Create('Type mismatch');

    if not Assigned(JSON.GetValue('timestamp')) then
      raise Exception.Create('Missing timestamp');

    if not Assigned(JSON.GetValue('level')) then
      raise Exception.Create('Missing level');
  finally
    JSON.Free;
  end;
end;

procedure TestHttpLog;
var
  LogLines: TArray<string>;
  JSON: TJSONObject;
  LogsFile: string;
begin
  Writeln('Testing HTTP log format...');

  uLogger.Log('HTTP completed', llInfo, 'http', 'GET', '/api/test', 200, 50);

  LogsFile := TPath.Combine(GetLogsPath, 'app.log');
  LogLines := TFile.ReadAllText(LogsFile).Split([sLineBreak], TStringSplitOptions.ExcludeEmpty);

  JSON := TJSONObject.ParseJSONValue(LogLines[High(LogLines)]) as TJSONObject;
  try
    Writeln('HTTP JSON: ' + JSON.ToJSON);
    if JSON.GetValue('method').Value <> 'GET' then raise Exception.Create('Method mismatch');
    if JSON.GetValue('path').Value <> '/api/test' then raise Exception.Create('Path mismatch');
    if (JSON.GetValue('status') as TJSONNumber).AsInt <> 200 then raise Exception.Create('Status mismatch');
    if (JSON.GetValue('duration_ms') as TJSONNumber).AsInt <> 50 then raise Exception.Create('Duration mismatch');
  finally
    JSON.Free;
  end;
end;

begin
  try
    TestJsonFormat;
    TestHttpLog;
    Writeln('All logging tests passed!');
  except
    on E: Exception do
    begin
      Writeln('Test failed: ' + E.Message);
      Halt(1);
    end;
  end;
end.
