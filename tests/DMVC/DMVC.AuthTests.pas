unit DMVC.AuthTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TAuthTests = class
  private
    FServer: TTestServerProcess;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetEquivalencias_WithoutToken_Returns401;

    [Test]
    procedure Ping_WithoutToken_StillReturns200;

    [Test]
    procedure Login_WithNonexistentUser_Returns401;

    [Test]
    procedure Login_WithWrongPassword_Returns401;

    [Test]
    procedure GetEquivalencias_WithInvalidToken_Returns401;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Classes, System.IniFiles,
  IdHTTP, IdException, uPaths;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TAuthTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
end;

procedure TAuthTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TAuthTests.GetEquivalencias_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    try
      LHttp.Get(Format('http://localhost:%d/api/equivalencias', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 401');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(401, E.ErrorCode, 'Debe responder 401 sin token');
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TAuthTests.Ping_WithoutToken_StillReturns200;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Get(Format('http://localhost:%d/ping', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode, '/ping debe seguir siendo publico');
  finally
    LHttp.Free;
  end;
end;

procedure TAuthTests.Login_WithNonexistentUser_Returns401;
var
  LHttp: TIdHTTP;
  LBodyJson: TJSONObject;
  LPostBody: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LBodyJson := TJSONObject.Create;
    try
      // 'noexiste123' (11 chars) cabe dentro de USUARIOS.NOMBRE VARCHAR(15) en
      // Helisa: a diferencia de un username mas largo que la columna, este SI
      // llega a ejecutar el SELECT contra la base y ejercita la rama real de
      // "usuario no encontrado" en OnAuthentication, no solo el guard de
      // longitud.
      LBodyJson.AddPair('username', 'noexiste123');
      LBodyJson.AddPair('password', 'cualquier-clave');
      LPostBody := TStringStream.Create(LBodyJson.ToJSON, TEncoding.UTF8);
      try
        LHttp.Request.ContentType := 'application/json';
        try
          LHttp.Post(Format('http://localhost:%d/api/auth/login', [TEST_PORT]), LPostBody);
          Assert.Fail('Se esperaba una excepcion HTTP 401 para un usuario inexistente');
        except
          on E: EIdHTTPProtocolException do
            Assert.AreEqual(401, E.ErrorCode, 'Login con usuario inexistente debe responder 401');
        end;
      finally
        LPostBody.Free;
      end;
    finally
      LBodyJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TAuthTests.Login_WithWrongPassword_Returns401;
var
  LIni: TIniFile;
  LUsername: string;
  LHttp: TIdHTTP;
  LBodyJson: TJSONObject;
  LPostBody: TStringStream;
begin
  // Usa el usuario REAL de Helisa configurado en [AUTH_TEST] Username de
  // config.ini -- mismo mecanismo de lectura que DMVC.TestAuthHelper.pas, sin
  // hardcodear el username aqui. La clave es deliberadamente incorrecta: un
  // intento de login con clave erronea solo hace un SELECT + comparacion de
  // string contra Helisa (sin escritura), misma clase de seguridad que los
  // demas tests que usan credenciales reales.
  LIni := TIniFile.Create(uPaths.GetConfigPath);
  try
    LUsername := LIni.ReadString('AUTH_TEST', 'Username', '');
  finally
    LIni.Free;
  end;

  Assert.IsFalse(LUsername.IsEmpty,
    'Falta [AUTH_TEST] Username en config.ini para poder ejecutar este test');

  LHttp := TIdHTTP.Create(nil);
  try
    LBodyJson := TJSONObject.Create;
    try
      LBodyJson.AddPair('username', LUsername);
      LBodyJson.AddPair('password', 'esta-clave-es-incorrecta-a-proposito');
      LPostBody := TStringStream.Create(LBodyJson.ToJSON, TEncoding.UTF8);
      try
        LHttp.Request.ContentType := 'application/json';
        try
          LHttp.Post(Format('http://localhost:%d/api/auth/login', [TEST_PORT]), LPostBody);
          Assert.Fail('Se esperaba una excepcion HTTP 401 para una clave incorrecta');
        except
          on E: EIdHTTPProtocolException do
            Assert.AreEqual(401, E.ErrorCode, 'Login con clave incorrecta debe responder 401');
        end;
      finally
        LPostBody.Free;
      end;
    finally
      LBodyJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TAuthTests.GetEquivalencias_WithInvalidToken_Returns401;
var
  LHttp: TIdHTTP;
begin
  // Prueba que el middleware JWT valida realmente la firma/estructura del
  // token, no solo la presencia del header Authorization.
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer esto-no-es-un-jwt-valido');
    try
      LHttp.Get(Format('http://localhost:%d/api/equivalencias', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 401 para un token invalido');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(401, E.ErrorCode, 'Debe responder 401 con un token invalido');
    end;
  finally
    LHttp.Free;
  end;
end;

end.
