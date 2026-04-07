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

function NormalizeRequestPath(const APath: string): string;
begin
  Result := APath.Trim;
  if Result.IsEmpty then
    Exit('/');

  if not Result.StartsWith('/') then
    Result := '/' + Result;
end;

function IsExcludedPath(const APath: string): Boolean;
var
  LPath: string;
begin
  LPath := APath.ToLower;
  // Rutas que no deben ser manejadas por el fallback de SPA
  Result := LPath.StartsWith('/api/') or (LPath = '/api') or
            LPath.StartsWith('/auth/') or (LPath = '/auth') or
            LPath.StartsWith('/licencia/') or (LPath = '/licencia') or
            LPath.StartsWith('/assets/') or (LPath = '/assets') or
            (LPath = '/ping');
end;

function IsTextMime(const AMime: string): Boolean;
var
  LMime: string;
begin
  LMime := AMime.ToLower;
  Result := LMime.StartsWith('text/') or
            LMime.Contains('javascript') or
            LMime.Contains('json') or
            LMime.Contains('xml') or
            LMime.Contains('svg');
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
  else if LExt = '.map' then Result := 'application/json'
  else if LExt = '.txt' then Result := 'text/plain'
  else if LExt = '.xml' then Result := 'application/xml'
  else if LExt = '.pdf' then Result := 'application/pdf'
  else if LExt = '.webp' then Result := 'image/webp'
  else Result := 'application/octet-stream';

  if IsTextMime(Result) and (not ContainsText(Result, 'charset=')) then
    Result := Result + '; charset=utf-8';
end;

function TryBuildSafePath(const ARequestPath: string; out AResolvedPath: string): Boolean;
var
  LRelativePath: string;
  LFullPath: string;
  LRootWithSlash: string;
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

  LFullPath := TPath.GetFullPath(TPath.Combine(GStaticBasePath, LRelativePath));
  LRootWithSlash := IncludeTrailingPathDelimiter(TPath.GetFullPath(GStaticBasePath));

  if not StartsText(LRootWithSlash, IncludeTrailingPathDelimiter(LFullPath)) then
    Exit;

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

  LRequestPath := NormalizeRequestPath(APath);

  // 1. Si es una ruta de API/Auth conocida, no intentamos servir archivos estáticos (excepto assets)
  if IsExcludedPath(LRequestPath) and (not LRequestPath.StartsWith('/assets/')) then
    Exit;

  // 2. Intentar encontrar el archivo físico
  if not TryBuildSafePath(LRequestPath, LTargetFile) then
    Exit;

  if TFile.Exists(LTargetFile) then
  begin
    uLogger.LogInfo('Serving static file: ' + LTargetFile, 'static_files');
    Res.Status(THTTPStatus.OK)
      .SendFile(LTargetFile, GetMimeTypeFromExtension(LTargetFile));
    Result := True;
    Exit;
  end;

  // 3. Fallback para SPA:
  // Solo si es GET/HEAD, no tiene extensión, no es una ruta excluida (incluyendo assets), y existe index.html
  if (SameText(Req.RawWebRequest.Method, 'GET') or SameText(Req.RawWebRequest.Method, 'HEAD')) and
     (not IsExcludedPath(LRequestPath)) and
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

  if GStaticBasePath.IsEmpty then
    GStaticBasePath := ResolvePathFromBase('www');

  GStaticBasePath := TPath.GetFullPath(GStaticBasePath);

  uLogger.LogInfo('Static files middleware path: ' + GStaticBasePath, 'startup');

  // Catch-all route for static files and SPA fallback
  THorse.All('/*',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      if (SameText(Req.RawWebRequest.Method, 'GET') or SameText(Req.RawWebRequest.Method, 'HEAD')) and
         TryServeStaticRequest(Req.RawWebRequest.PathInfo, Req, Res) then
        raise EHorseCallbackInterrupted.Create;

      Next();
    end);
end;

end.
