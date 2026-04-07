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
  // Rutas que no deben ser manejadas por el middleware de archivos estáticos
  Result := LPath.StartsWith('/api/') or (LPath = '/api') or
            LPath.StartsWith('/auth/') or (LPath = '/auth') or
            LPath.StartsWith('/licencia/') or (LPath = '/licencia') or
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
  if not LRequestPath.StartsWith('/') then
    LRequestPath := '/' + LRequestPath;

  // 1. Excluir rutas de API y autenticación
  if IsExcludedPath(LRequestPath) then
    Exit;

  // 2. Intentar servir archivo físico directamente
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

  // 3. SPA Fallback: servir index.html para rutas que no tienen extensión (rutas de React Router)
  // No aplicar si la ruta es /assets/ o tiene extensión
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

  // Usamos una ruta catch-all registrada al final de las rutas de Horse
  THorse.Get('/*',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LPath: string;
    begin
      LPath := Req.RawWebRequest.PathInfo;
      if LPath.IsEmpty then
        LPath := Req.PathInfo;

      if TryServeStaticRequest(LPath, Req, Res) then
        raise EHorseCallbackInterrupted.Create;

      Next();
    end);
end;

end.
