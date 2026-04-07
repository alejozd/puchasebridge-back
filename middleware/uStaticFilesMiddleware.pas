unit uStaticFilesMiddleware;

interface

uses
  Horse;

procedure RegisterStaticFilesMiddleware(const WWWPath: string);

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,
  uLogger,
  uPaths;

var
  GStaticBasePath: string;

function IsExcludedPath(const APath: string): Boolean;
var
  LPath: string;
begin
  LPath := APath.ToLower;
  if not LPath.StartsWith('/') then LPath := '/' + LPath;
  // Rutas que no deben ser manejadas por el fallback de SPA.
  Result := LPath.StartsWith('/api') or
            LPath.StartsWith('/auth') or
            LPath.StartsWith('/licencia') or
            (LPath = '/ping');
end;

function GetMimeTypeFromExtension(const AFileName: string): string;
var
  LExt: string;
begin
  LExt := LowerCase(ExtractFileExt(AFileName));
  if LExt = '.html' then Result := 'text/html'
  else if LExt = '.htm' then Result := 'text/html'
  else if LExt = '.js' then Result := 'application/javascript'
  else if LExt = '.css' then Result := 'text/css'
  else if LExt = '.json' then Result := 'application/json'
  else if LExt = '.png' then Result := 'image/png'
  else if (LExt = '.jpg') or (LExt = '.jpeg') then Result := 'image/jpeg'
  else if LExt = '.gif' then Result := 'image/gif'
  else if LExt = '.svg' then Result := 'image/svg+xml'
  else if LExt = '.ico' then Result := 'image/x-icon'
  else if LExt = '.woff' then Result := 'font/woff'
  else if LExt = '.woff2' then Result := 'font/woff2'
  else if LExt = '.ttf' then Result := 'font/ttf'
  else if LExt = '.webp' then Result := 'image/webp'
  else Result := 'application/octet-stream';

  // Add charset for text types
  if (Result.StartsWith('text/')) or (Result.Contains('javascript')) or (Result.Contains('json')) then
    Result := Result + '; charset=utf-8';
end;

function TryBuildSafePath(const ARequestPath: string; out AResolvedPath: string): Boolean;
var
  LRelativePath: string;
  LFullPath: string;
  LRootPath: string;
begin
  Result := False;
  AResolvedPath := '';

  LRelativePath := ARequestPath;
  if LRelativePath.StartsWith('/') then
    LRelativePath := LRelativePath.Substring(1);

  if LRelativePath.IsEmpty then
    LRelativePath := 'index.html';

  LRelativePath := StringReplace(LRelativePath, '/', PathDelim, [rfReplaceAll]);

  if LRelativePath.Contains('..') then
    Exit;

  LRootPath := TPath.GetFullPath(GStaticBasePath);
  LFullPath := TPath.GetFullPath(TPath.Combine(LRootPath, LRelativePath));

  // Security check: resolved path must be within root path
  if not StartsText(IncludeTrailingPathDelimiter(LRootPath), LFullPath) then
  begin
     // Fallback for files directly in the root
     if not StartsText(IncludeTrailingPathDelimiter(LRootPath), IncludeTrailingPathDelimiter(TPath.GetDirectoryName(LFullPath))) then
       Exit;
  end;

  AResolvedPath := LFullPath;
  Result := True;
end;

function TryServeStaticRequest(const APath: string; const Req: THorseRequest; Res: THorseResponse): Boolean;
var
  LRequestPath: string;
  LTargetFile: string;
  LIndexPath: string;
begin
  Result := False;

  LRequestPath := APath;
  if not LRequestPath.StartsWith('/') then LRequestPath := '/' + LRequestPath;

  // 1. Exclude API/Auth/Licencia/Ping
  if IsExcludedPath(LRequestPath) then
    Exit;

  // 2. Try physical file
  if TryBuildSafePath(LRequestPath, LTargetFile) then
  begin
    if TFile.Exists(LTargetFile) then
    begin
      uLogger.LogInfo('Serving static file: ' + LTargetFile, 'static_files');
      Res.Status(THTTPStatus.OK)
        .SendFile(LTargetFile, GetMimeTypeFromExtension(LTargetFile));
      Result := True;
      Exit;
    end;
  end;

  // 3. SPA Fallback
  // Only if no extension, not in /assets/, and index.html exists.
  // Note: Method check (GET/HEAD) is already done by the caller.
  if (not LRequestPath.ToLower.StartsWith('/assets/')) and
     ExtractFileExt(LRequestPath).IsEmpty then
  begin
    LIndexPath := TPath.Combine(GStaticBasePath, 'index.html');
    if TFile.Exists(LIndexPath) then
    begin
      uLogger.LogInfo('Serving SPA fallback index: ' + LIndexPath + ' for route ' + LRequestPath, 'static_files');
      Res.Status(THTTPStatus.OK)
        .SendFile(LIndexPath, GetMimeTypeFromExtension(LIndexPath));
      Result := True;
      Exit;
    end;
  end;
end;

procedure RegisterStaticFilesMiddleware(const WWWPath: string);
begin
  GStaticBasePath := ResolvePathFromBase(WWWPath);
  if GStaticBasePath.IsEmpty then GStaticBasePath := ResolvePathFromBase('www');
  GStaticBasePath := TPath.GetFullPath(GStaticBasePath);

  uLogger.LogInfo('Static files middleware path: ' + GStaticBasePath, 'startup');

  THorse.Use(
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LPath: string;
    begin
      // Only handle GET and HEAD
      if not (SameText(Req.RawWebRequest.Method, 'GET') or SameText(Req.RawWebRequest.Method, 'HEAD')) then
      begin
        Next();
        Exit;
      end;

      LPath := Req.PathInfo;
      if LPath.IsEmpty then LPath := '/';

      if TryServeStaticRequest(LPath, Req, Res) then
        Exit;

      Next();
    end);
end;

end.
