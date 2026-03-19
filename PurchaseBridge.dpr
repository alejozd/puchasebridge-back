program PurchaseBridge;

{$APPTYPE CONSOLE}

uses
  Horse,
  Horse.Jhonson,
  Horse.OctetStream,
  Horse.HandleException,
  System.SysUtils,
  System.StrUtils,
  HConfig in 'config\HConfig.pas',
  FirebirdConnection in 'database\FirebirdConnection.pas',
  ProveedorRepository in 'repositories\ProveedorRepository.pas',
  ProductoRepository in 'repositories\ProductoRepository.pas',
  XMLFacturaService in 'services\XMLFacturaService.pas',
  XmlParserService in 'services\XmlParserService.pas',
  HelisaUtils in 'utils\HelisaUtils.pas',
  HelisaService in 'services\HelisaService.pas',
  EquivalenciaService in 'services\EquivalenciaService.pas',
  ValidationService in 'services\ValidationService.pas',
  DocumentoService in 'services\DocumentoService.pas',
  ImportController in 'controllers\ImportController.pas',
  ProveedorController in 'controllers\ProveedorController.pas',
  XmlController in 'controllers\XmlController.pas',
  XmlValidationController in 'controllers\XmlValidationController.pas',
  EquivalenciaController in 'controllers\EquivalenciaController.pas',
  HelisaController in 'controllers\HelisaController.pas',
  DocumentosController in 'controllers\DocumentosController.pas',
  AuthService in 'services\AuthService.pas',
  AuthController in 'controllers\AuthController.pas',
  AuthMiddleware in 'middleware\AuthMiddleware.pas';

function IsAllowedOrigin(const AOrigin: string): Boolean;
begin
  Result := MatchText(AOrigin, ['http://localhost:5173', 'http://127.0.0.1:5173']);
end;

procedure ApplyCORSHeaders(const Req: THorseRequest; const Res: THorseResponse);
var
  LOrigin: string;
  LRequestHeaders: string;
  LRequestMethod: string;
begin
  LOrigin := Req.Headers['Origin'];
  if IsAllowedOrigin(LOrigin) then
    Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Origin', LOrigin)
  else
    Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Origin', 'http://localhost:5173');

  Res.RawWebResponse.SetCustomHeader('Vary', 'Origin');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Credentials', 'true');

  LRequestHeaders := Req.Headers['Access-Control-Request-Headers'];
  if LRequestHeaders.IsEmpty then
    LRequestHeaders := 'Content-Type, Authorization, X-Requested-With';
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Headers', LRequestHeaders);

  LRequestMethod := Req.Headers['Access-Control-Request-Method'];
  if LRequestMethod.IsEmpty then
    LRequestMethod := 'GET, POST, PUT, PATCH, DELETE, OPTIONS';
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Methods', LRequestMethod);
  Res.RawWebResponse.SetCustomHeader('Access-Control-Max-Age', '86400');
end;

begin
  // Initialize configuration at startup
  try
    THConfig.GetInstance;
    Writeln('Configuracion cargada correctamente.');
  except
    on E: Exception do
    begin
      Writeln('Error cargando configuracion: ' + E.Message);
      Exit;
    end;
  end;

  THorse
    .Use(HandleException)
    .Use(
      procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
      begin
        ApplyCORSHeaders(Req, Res);

        if SameText(Req.RawWebRequest.Method, 'OPTIONS') then
        begin
          Res.Status(THTTPStatus.OK).Send('');
          Exit;
        end;

        Next();
      end)
    .Use(Jhonson())
    .Use(OctetStream)
    .Use(Auth);

  THorse.All('/auth/login',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      if SameText(Req.RawWebRequest.Method, 'OPTIONS') then
      begin
        ApplyCORSHeaders(Req, Res);
        Res.Status(THTTPStatus.OK).Send('');
        Exit;
      end;

      Next();
    end);

  THorse.Get('/ping',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      Res.Send('pong');
    end);

  ImportController.Registry;
  ProveedorController.Registry;
  XmlController.Registry;
  XmlValidationController.Registry;
  EquivalenciaController.Registry;
  HelisaController.Registry;
  DocumentosController.Registry;
  AuthController.Registry;

  THorse.Listen(9000,
    procedure
    begin
      Writeln('Server is running on port ' + IntToStr(THorse.Port));
      Writeln('Press Enter to stop the server...');
    end);
end.
