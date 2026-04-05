unit uPaths;

interface

uses
  System.SysUtils;

function GetBasePath: string;
function GetInputPath: string;
function GetProcessedPath: string;
function GetLogsPath: string;
function GetOutputPath: string;
function GetConfigPath: string;
function ResolvePathFromBase(const APath: string): string;
procedure EnsureServiceDirectories;

implementation

uses
  System.IOUtils;

function GetBasePath: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
end;

function GetInputPath: string;
begin
  Result := TPath.Combine(GetBasePath, 'Input');
end;

function GetProcessedPath: string;
begin
  Result := TPath.Combine(GetBasePath, 'Processed');
end;

function GetLogsPath: string;
begin
  Result := TPath.Combine(GetBasePath, 'Logs');
end;

function GetOutputPath: string;
begin
  Result := TPath.Combine(GetBasePath, 'Output');
end;

function GetConfigPath: string;
begin
  Result := TPath.Combine(GetBasePath, 'config.ini');
end;

function IsAbsolutePath(const APath: string): Boolean;
begin
  Result :=
    (APath.Length >= 2) and (APath[2] = ':') or
    APath.StartsWith('\\') or
    APath.StartsWith('/');
end;

function ResolvePathFromBase(const APath: string): string;
var
  LTrimmedPath: string;
begin
  LTrimmedPath := APath.Trim;
  if LTrimmedPath.IsEmpty then
    Exit(LTrimmedPath);

  if IsAbsolutePath(LTrimmedPath) then
    Exit(LTrimmedPath);

  Result := TPath.GetFullPath(TPath.Combine(GetBasePath, LTrimmedPath));
end;

procedure EnsureServiceDirectories;
begin
  ForceDirectories(GetInputPath);
  ForceDirectories(GetProcessedPath);
  ForceDirectories(GetLogsPath);
end;

end.
