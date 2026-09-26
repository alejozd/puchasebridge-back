unit DMVC.TestAuthHelper;

interface

/// <summary>
/// Hace login contra POST /api/auth/login usando las credenciales de
/// [AUTH_TEST] Username/Password del config.ini local (nunca hardcodeadas
/// aqui) y devuelve el JWT crudo devuelto por DMVCFramework (campo "token"
/// del JSON de respuesta, ver MVCFramework.Middleware.JWT.pas
/// TMVCJWTAuthenticationMiddleware.OnBeforeRouting). El caller es responsable
/// de anteponer 'Bearer ' al construir el header Authorization.
/// Lanza una excepcion clara y especifica (no devuelve '' en silencio) si
/// faltan credenciales, si el login falla, o si no se puede conectar al
/// servidor -- para que un test que use este helper falle de forma
/// inequivoca en el punto real del problema, no mas adelante con un 401
/// confuso.
/// </summary>
function ObtenerTokenDePrueba(APort: Integer): string;

implementation

uses
  System.SysUtils, System.Classes, System.IniFiles, System.JSON,
  IdHTTP, IdException, uPaths;

function ObtenerTokenDePrueba(APort: Integer): string;
var
  LIni: TIniFile;
  LUsername, LPassword: string;
  LHttp: TIdHTTP;
  LBodyJson: TJSONObject;
  LPostBody: TStringStream;
  LResponse: string;
  LResponseJson: TJSONValue;
  LTokenValue: TJSONValue;
begin
  Result := '';

  LIni := TIniFile.Create(uPaths.GetConfigPath);
  try
    LUsername := LIni.ReadString('AUTH_TEST', 'Username', '');
    LPassword := LIni.ReadString('AUTH_TEST', 'Password', '');
  finally
    LIni.Free;
  end;

  if LUsername.IsEmpty or LPassword.IsEmpty then
    raise Exception.CreateFmt(
      'DMVC.TestAuthHelper.ObtenerTokenDePrueba: falta la seccion [AUTH_TEST] ' +
      '(Username/Password) en "%s". No se puede obtener un token de prueba ' +
      'sin credenciales configuradas.', [uPaths.GetConfigPath]);

  LHttp := TIdHTTP.Create(nil);
  try
    LBodyJson := TJSONObject.Create;
    try
      LBodyJson.AddPair('username', LUsername);
      LBodyJson.AddPair('password', LPassword);
      LPostBody := TStringStream.Create(LBodyJson.ToJSON, TEncoding.UTF8);
      try
        LHttp.Request.ContentType := 'application/json';
        try
          LResponse := LHttp.Post(Format('http://localhost:%d/api/auth/login', [APort]), LPostBody);
        except
          on E: EIdHTTPProtocolException do
            raise Exception.CreateFmt(
              'DMVC.TestAuthHelper.ObtenerTokenDePrueba: login fallo con HTTP %d ' +
              'para el usuario "%s". Respuesta del servidor: %s',
              [E.ErrorCode, LUsername, E.ErrorMessage]);
          on E: EIdException do
            raise Exception.CreateFmt(
              'DMVC.TestAuthHelper.ObtenerTokenDePrueba: no se pudo conectar a ' +
              'http://localhost:%d/api/auth/login (%s): %s',
              [APort, E.ClassName, E.Message]);
        end;
      finally
        LPostBody.Free;
      end;
    finally
      LBodyJson.Free;
    end;

    LResponseJson := TJSONObject.ParseJSONValue(LResponse);
    try
      if not (LResponseJson is TJSONObject) then
        raise Exception.CreateFmt(
          'DMVC.TestAuthHelper.ObtenerTokenDePrueba: la respuesta de login no es ' +
          'un objeto JSON valido. Cuerpo recibido: %s', [LResponse]);

      LTokenValue := TJSONObject(LResponseJson).Values['token'];
      if not Assigned(LTokenValue) or LTokenValue.Value.IsEmpty then
        raise Exception.CreateFmt(
          'DMVC.TestAuthHelper.ObtenerTokenDePrueba: la respuesta de login no ' +
          'contenia un campo "token" valido. Cuerpo recibido: %s', [LResponse]);

      Result := LTokenValue.Value;
    finally
      LResponseJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

end.
