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
  System.Classes,
  uLogger,
  uPaths;

var
  GStaticBasePath: string;

function IsExcludedPath(const APath: string): Boolean;
var
  LPath: string;
begin
  LPath := APath.ToLower;
  if (not LPath.IsEmpty) and (not LPath.StartsWith('/')) then LPath := '/' + LPath;
  // Rutas que no deben ser manejadas por el middleware de archivos estáticos
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

  LRootPath := IncludeTrailingPathDelimiter(TPath.GetFullPath(GStaticBasePath));
  LFullPath := TPath.GetFullPath(TPath.Combine(LRootPath, LRelativePath));

  // Verificación de seguridad: el archivo resuelto debe estar dentro del directorio base
  if not StartsText(LRootPath, LFullPath) then
    Exit;

  AResolvedPath := LFullPath;
  Result := True;
end;

procedure RegisterStaticFilesMiddleware(const WWWPath: string);
begin
  GStaticBasePath := ResolvePathFromBase(WWWPath);
  if GStaticBasePath.IsEmpty then GStaticBasePath := ResolvePathFromBase('www');
  GStaticBasePath := TPath.GetFullPath(GStaticBasePath);

  uLogger.LogInfo('Static files middleware path: ' + GStaticBasePath, 'startup');

  // Usamos THorse.Use para asegurar que capturamos todas las rutas que no fueron manejadas previamente,
  // incluyendo la raíz "/" y las rutas de SPA.
  THorse.Use(
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LPath: string;
      LTargetFile: string;
      LIndexPath: string;
    begin
      // Solo manejamos GET y HEAD para archivos estáticos y SPA
      if not (SameText(Req.RawWebRequest.Method, 'GET') or SameText(Req.RawWebRequest.Method, 'HEAD')) then
      begin
        Next();
        Exit;
      end;

      // Obtener el path de la petición
      LPath := Req.PathInfo;
      if LPath.IsEmpty then
        LPath := Req.RawWebRequest.PathInfo;
      if LPath.IsEmpty then
        LPath := '/';

      // Si es una ruta excluida (API, Auth, Licencia), pasamos al siguiente handler
      if IsExcludedPath(LPath) then
      begin
        Next();
        Exit;
      end;

      // 1. Intentar servir archivo físico directamente
      if TryBuildSafePath(LPath, LTargetFile) and TFile.Exists(LTargetFile) then
      begin
        uLogger.LogInfo('Serving static file: ' + LTargetFile, 'static_files');
        Res.Status(THTTPStatus.OK).SendFile(LTargetFile, GetMimeTypeFromExtension(LTargetFile));
        // IMPORTANTE: raise EHorseCallbackInterrupted para detener la cadena y evitar 404
        raise EHorseCallbackInterrupted.Create;
      end;

      // 2. Fallback para SPA: servir index.html para rutas que no tienen extensión (rutas de React Router)
      // No aplicar si la ruta es /assets/ o tiene extensión
      if (not LPath.ToLower.StartsWith('/assets/')) and ExtractFileExt(LPath).IsEmpty then
      begin
        LIndexPath := TPath.Combine(GStaticBasePath, 'index.html');
        if TFile.Exists(LIndexPath) then
        begin
          uLogger.LogInfo('Serving SPA fallback index: ' + LIndexPath + ' for route ' + LPath, 'static_files');
          Res.Status(THTTPStatus.OK).SendFile(LIndexPath, GetMimeTypeFromExtension(LIndexPath));
          raise EHorseCallbackInterrupted.Create;
        end;
      end;

      Next();
    end);
end;

end.
