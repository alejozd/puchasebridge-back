unit uStaticFilesMiddleware;

interface

uses
  Horse;

procedure RegisterStaticFilesMiddleware(const WWWPath: string);

implementation

uses
  SysUtils,
  Classes,
  uPaths
  ;

var
  GStaticRoot: string;

function EnsureLeadingSlash(const APath: string): string;
begin
  Result := APath;
  if (Result = '') or (Result[1] <> '/') then
    Result := '/' + Result;
end;

function NormalizeWebPath(const APath: string): string;
var
  LPath: string;
begin
  LPath := StringReplace(APath, '\\', '/', [rfReplaceAll]);
  if LPath = '' then
    LPath := '/';

  LPath := EnsureLeadingSlash(LPath);

  Result := LPath;
end;

function IsApiOrHealthRoute(const APath: string): Boolean;
var
  LPath: string;
begin
  LPath := LowerCase(APath);
  Result := (LPath = '/ping') or (LPath = '/ping/') or (LPath = '/api') or (Copy(LPath, 1, 5) = '/api/');
end;

function IsFileRequest(const APath: string): Boolean;
begin
  Result := ExtractFileExt(APath) <> '';
end;

function IsTextContentType(const AContentType: string): Boolean;
var
  LContentType: string;
begin
  LContentType := LowerCase(AContentType);
  Result := (Copy(LContentType, 1, 5) = 'text/') or
            (Pos('javascript', LContentType) > 0) or
            (Pos('json', LContentType) > 0) or
            (Pos('xml', LContentType) > 0) or
            (Pos('svg', LContentType) > 0);
end;

function GetMimeTypeByExtension(const AExtension: string): string;
var
  LExt: string;
begin
  LExt := LowerCase(AExtension);


  if LExt = '.html' then Result := 'text/html'
  else if LExt = '.htm' then Result := 'text/html'
  else if LExt = '.js' then Result := 'application/javascript'
  else if LExt = '.mjs' then Result := 'application/javascript'
  else if LExt = '.css' then Result := 'text/css'
  else if LExt = '.json' then Result := 'application/json'
  else if LExt = '.map' then Result := 'application/json'
  else if LExt = '.txt' then Result := 'text/plain'
  else if LExt = '.xml' then Result := 'application/xml'
  else if LExt = '.svg' then Result := 'image/svg+xml'
  else if LExt = '.png' then Result := 'image/png'
  else if LExt = '.jpg' then Result := 'image/jpeg'
  else if LExt = '.jpeg' then Result := 'image/jpeg'
  else if LExt = '.gif' then Result := 'image/gif'
  else if LExt = '.ico' then Result := 'image/x-icon'
  else if LExt = '.webp' then Result := 'image/webp'
  else if LExt = '.woff' then Result := 'font/woff'
  else if LExt = '.woff2' then Result := 'font/woff2'
  else if LExt = '.ttf' then Result := 'font/ttf'
  else if LExt = '.otf' then Result := 'font/otf'
  else if LExt = '.eot' then Result := 'application/vnd.ms-fontobject'
  else if LExt = '.pdf' then Result := 'application/pdf'
  else if LExt = '.wasm' then Result := 'application/wasm'
  else
    Result := 'application/octet-stream';
end;

function BuildContentType(const AFileName: string): string;
begin
  Result := GetMimeTypeByExtension(ExtractFileExt(AFileName));
  if IsTextContentType(Result) then
    Result := Result + '; charset=utf-8';
end;

function SanitizeAndResolve(const AWebPath: string): string;
var
  LRelativePath: string;
  LCombinedPath: string;
  LResolvedPath: string;
  LRootWithSlash: string;
begin
  LRelativePath := AWebPath;
  if (LRelativePath <> '') and (LRelativePath[1] = '/') then
    Delete(LRelativePath, 1, 1);

  LRelativePath := StringReplace(LRelativePath, '/', PathDelim, [rfReplaceAll]);
  LCombinedPath := IncludeTrailingPathDelimiter(GStaticRoot) + LRelativePath;
  LResolvedPath := ExpandFileName(LCombinedPath);

  LRootWithSlash := IncludeTrailingPathDelimiter(GStaticRoot);
  if Pos(UpperCase(LRootWithSlash), UpperCase(LResolvedPath)) <> 1 then
    Result := ''
  else
    Result := LResolvedPath;
end;

procedure SendStaticFile(const AFileName: string; Res: THorseResponse);
var
  LContentType: string;
begin
  LContentType := BuildContentType(AFileName);
  Res.Status(200).SendFile(AFileName, LContentType);
end;

procedure RegisterStaticFilesMiddleware(const WWWPath: string);
begin
  GStaticRoot := ResolvePathFromBase(WWWPath);
  
  // Registrar ruta para servir index.html en la raiz
  THorse.Get('/',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LIndexPath: string;
    begin
      LIndexPath := SanitizeAndResolve('index.html');
      if (LIndexPath <> '') and FileExists(LIndexPath) then
      begin
        SendStaticFile(LIndexPath, Res);
      end
      else
      begin
        Res.Status(404).ContentType('application/json; charset=utf-8')
          .Send('{"error":"index.html no encontrado"}');
      end;
    end);
  
  // Assets y otros archivos estaticos
  THorse.Get('/assets/:filename',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LFileName: string;
      LResolvedPath: string;
    begin
      LFileName := Req.Params['filename'];
      LResolvedPath := SanitizeAndResolve('assets/' + LFileName);
      if (LResolvedPath <> '') and FileExists(LResolvedPath) then
      begin
        SendStaticFile(LResolvedPath, Res);
      end
      else
      begin
        Res.Status(404).ContentType('application/json; charset=utf-8')
          .Send('{"error":"Archivo no encontrado"}');
      end;
    end);
    
  // Favicon y otros archivos en la raiz
  THorse.Get('/:filename',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LFileName: string;
      LResolvedPath: string;
    begin
      LFileName := Req.Params['filename'];
      // Ignorar rutas que son APIs
      if (LFileName = 'api') or (LFileName = 'ping') or (LFileName = 'licencia') then
      begin
        Next();
        Exit;
      end;
      
      LResolvedPath := SanitizeAndResolve(LFileName);
      if (LResolvedPath <> '') and FileExists(LResolvedPath) then
      begin
        SendStaticFile(LResolvedPath, Res);
      end
      else
      begin
        Next();
      end;
    end);
end;

end.
