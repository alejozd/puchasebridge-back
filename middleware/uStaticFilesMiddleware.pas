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
  uLogger;

var
  GStaticBasePath: string;

function HasFileExtension(const APath: string): Boolean;
var
  LExt: string;
begin
  LExt := ExtractFileExt(APath);
  Result := not LExt.IsEmpty;
end;

function IsApiOrHealthPath(const APath: string): Boolean;
var
  LPath: string;
begin
  LPath := APath.ToLower;
  Result := LPath.StartsWith('/api/') or 
            (LPath = '/api') or 
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
  else if LExt = '.map' then Result := 'application/json'
  else if LExt = '.txt' then Result := 'text/plain'
  else if LExt = '.xml' then Result := 'application/xml'
  else if LExt = '.pdf' then Result := 'application/pdf'
  else if LExt = '.webp' then Result := 'image/webp'
  else Result := 'application/octet-stream';
end;

procedure RegisterStaticFilesMiddleware(const WWWPath: string);
begin
  GStaticBasePath := TPath.GetFullPath(WWWPath);

  uLogger.LogInfo('Static files middleware path: ' + GStaticBasePath, 'startup');

  // Ruta catch-all para todo lo demás (incluyendo /assets/* y rutas SPA) - REGISTRAR PRIMERO
  THorse.Get('/*',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LRequestPath: string;
      LRelativePath: string;
      LTargetFile: string;
      LFullPath: string;
      LRootWithSlash: string;
      LIndexPath: string;
    begin
      // Excluir rutas de API y health check - dejar que otros middlewares las manejen
      LRequestPath := Req.RawWebRequest.PathInfo;
      
      if IsApiOrHealthPath(LRequestPath) then
      begin
        Next();
        Exit;
      end;

      // Construir path relativo seguro
      LRelativePath := LRequestPath;
      if LRelativePath.StartsWith('/') then
        LRelativePath := LRelativePath.Substring(1);

      // Reemplazar slashes por separador de path del sistema
      LRelativePath := StringReplace(LRelativePath, '/', PathDelim, [rfReplaceAll]);

      // Bloquear directory traversal
      if LRelativePath.Contains('..') then
      begin
        Res.Status(THTTPStatus.Forbidden).Send('Forbidden');
        Exit;
      end;

      // Construir path completo y validar que está dentro del root
      LFullPath := TPath.GetFullPath(TPath.Combine(GStaticBasePath, LRelativePath));
      LRootWithSlash := IncludeTrailingPathDelimiter(TPath.GetFullPath(GStaticBasePath));

      if not StartsText(LRootWithSlash, IncludeTrailingPathDelimiter(LFullPath)) then
      begin
        Res.Status(THTTPStatus.Forbidden).Send('Forbidden');
        Exit;
      end;

      // Verificar si el archivo existe físicamente
      if TFile.Exists(LFullPath) then
      begin
        uLogger.LogDebug('Serving static file: ' + LFullPath, 'static_files');
        Res.Status(THTTPStatus.OK)
          .ContentType(GetMimeTypeFromExtension(LFullPath))
          .SendFile(LFullPath);
        Exit;
      end;

      // Fallback para SPA: si no tiene extensión, servir index.html
      if not HasFileExtension(LRequestPath) then
      begin
        LIndexPath := TPath.Combine(GStaticBasePath, 'index.html');
        if TFile.Exists(LIndexPath) then
        begin
          uLogger.LogInfo('Serving SPA fallback index.html for route: ' + LRequestPath, 'static_files');
          Res.Status(THTTPStatus.OK)
            .ContentType(GetMimeTypeFromExtension(LIndexPath))
            .SendFile(LIndexPath);
          Exit;
        end;
      end;

      // Archivo no encontrado y tiene extensión -> 404 real
      uLogger.LogDebug('File not found: ' + LFullPath, 'static_files');
      Res.Status(THTTPStatus.NotFound).Send('Not Found');
    end);

  // Ruta explícita para la raíz "/" - sirve index.html directamente - REGISTRAR DESPUÉS
  THorse.Get('/',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LIndexPath: string;
    begin
      LIndexPath := TPath.Combine(GStaticBasePath, 'index.html');
      if TFile.Exists(LIndexPath) then
      begin
        uLogger.LogInfo('Serving index.html for root path /', 'static_files');
        Res.Status(THTTPStatus.OK)
          .ContentType(GetMimeTypeFromExtension(LIndexPath))
          .SendFile(LIndexPath);
      end
      else
      begin
        uLogger.LogError('index.html not found at: ' + LIndexPath, 'static_files');
        Res.Status(THTTPStatus.NotFound).Send('Not Found');
      end;
    end);
end;

end.
