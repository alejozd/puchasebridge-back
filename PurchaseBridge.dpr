program PurchaseBridge;

{$APPTYPE CONSOLE}

uses
  Horse,
  Horse.Jhonson,
  Horse.OctetStream,
  Horse.Exception,
  Horse.HandleException,
  System.SysUtils,
  System.StrUtils,
  HConfig in 'config\HConfig.pas',
  FirebirdConnection in 'database\FirebirdConnection.pas',
  ProveedorRepository in 'repositories\ProveedorRepository.pas',
  ProductoRepository in 'repositories\ProductoRepository.pas',
  XMLFacturaService in 'services\XMLFacturaService.pas',
  XmlParserService in 'services\XmlParserService.pas',
  XmlPersistenceService in 'services\XmlPersistenceService.pas',
  HelisaUtils in 'utils\HelisaUtils.pas',
  HelisaService in 'services\HelisaService.pas',
  EquivalenciaService in 'services\EquivalenciaService.pas',
  DianUnits in 'services\DianUnits.pas',
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
  AuthMiddleware in 'middleware\AuthMiddleware.pas',
  LicenseService in 'services\LicenseService.pas',
  uLogger in 'utils\uLogger.pas',
  ErrorResponseUtils in 'utils\ErrorResponseUtils.pas';

function IsAllowedOrigin(const AOrigin: string): Boolean;
begin
  Result := MatchText(AOrigin, ['http://localhost:5173', 'http://127.0.0.1:5173']);
end;

procedure InicializarLicencia;
var
  LService: TLicenciaService;
  LInfo: TLicenciaInfo;
  LHash: string;
  LNit: string;
  LCodigo: string;
begin
  LInfo := nil;
  LHash := THConfig.GetInstance.Config.InstalacionHash;
  if LHash.IsEmpty then
  begin
    LHash := TLicenciaService.GenerarHashInstalacion;
    THConfig.GetInstance.UpdateInstalacionHash(LHash);
    Log('Nuevo Hash de Instalacion generado: ' + LHash, llInfo);
  end;

  LNit := THConfig.GetInstance.Config.Nit;
  LService := TLicenciaService.Create(THConfig.GetInstance.Config.URLServidorLicencia);
  try
    Log('Validando licencia para NIT: ' + LNit, llInfo);
    if not LService.ValidarLicencia(LNit, LHash, LInfo) then
    begin
      Log('Licencia no valida. Estado: ' + LInfo.Estado, llWarn);
      Writeln('La licencia actual no es valida o ha expirado (Estado: ' + LInfo.Estado + ').');

      if LInfo.Estado = 'bloqueado' then
      begin
        Log('Sistema bloqueado por el servidor de licencias.', llError);
        raise Exception.Create('Acceso denegado: El sistema se encuentra bloqueado.');
      end;

      Write('Ingrese codigo de activacion: ');
      Readln(LCodigo);

      LInfo.Free;
      if LService.RegistrarLicencia(LNit, LHash, LCodigo, LInfo) then
      begin
        Writeln('Activacion exitosa! Estado: ' + LInfo.Estado + '. Expira: ' + DateToStr(LInfo.Expira));
        Log('Activacion exitosa.', llInfo);
      end
      else
      begin
        Log('Fallo la activacion: ' + LInfo.Mensaje, llError);
        raise Exception.Create('Error de activacion: ' + LInfo.Mensaje);
      end;
    end
    else
    begin
      Log('Licencia validada correctamente. Estado: ' + LInfo.Estado, llInfo);
      if LInfo.Estado = 'demo' then
      begin
        Writeln('ADVERTENCIA: El sistema esta operando en modo DEMO. Dias restantes: ' + IntToStr(LInfo.DiasRestantes));
        Log('Sistema en modo DEMO. Dias restantes: ' + IntToStr(LInfo.DiasRestantes), llWarn);
      end;
    end;
  finally
    LInfo.Free;
    LService.Free;
  end;
end;

procedure ApplyCORSHeaders(const Req: THorseRequest; const Res: THorseResponse);
var
  LOrigin: string;
begin
  LOrigin := Req.Headers['Origin'];
  if IsAllowedOrigin(LOrigin) then
    Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Origin', LOrigin)
  else
    Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Origin', 'http://localhost:5173');

  Res.RawWebResponse.SetCustomHeader('Vary', 'Origin');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Credentials', 'true');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, Accept');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Max-Age', '86400');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Expose-Headers', 'Content-Disposition, Content-Type');
end;

begin
  // Initialize configuration and licensing at startup
  try
    THConfig.GetInstance;
    Log('Configuracion cargada correctamente.', llInfo);
    InicializarLicencia;
  except
    on E: Exception do
    begin
      Writeln('Error en el inicio del sistema: ' + E.Message);
      Log('Error en el inicio del sistema: ' + E.Message, llError);
      Exit;
    end;
  end;

  THorse
    .Use(
      procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
      begin
        ApplyCORSHeaders(Req, Res);

        if SameText(Req.RawWebRequest.Method, 'OPTIONS') then
        begin
          Res.Status(THTTPStatus.OK).Send('');
          raise EHorseCallbackInterrupted.Create;
        end;

        Next();
      end)
    .Use(HandleException(
      procedure(const E: Exception; const Req: THorseRequest; const Res: THorseResponse; var ASendException: Boolean)
      var
        LStatus: Integer;
        LMessage: string;
      begin
        LogError(E.Message);
        LStatus := Integer(THTTPStatus.InternalServerError);
        LMessage := 'Error interno del servidor';

        if E is EHorseException then
        begin
          LStatus := Integer(EHorseException(E).Status);
          if not EHorseException(E).Error.Trim.IsEmpty then
            LMessage := EHorseException(E).Error;
        end;

        SendErrorResponse(Res, LStatus, LMessage, E.Message);
        ASendException := False;
      end))
    .Use(Jhonson())
    .Use(OctetStream)
    .Use(Auth);

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
      Log('Server is running on port ' + IntToStr(THorse.Port), llInfo);
      Log('Press Enter to stop the server...', llInfo);
    end);
end.
