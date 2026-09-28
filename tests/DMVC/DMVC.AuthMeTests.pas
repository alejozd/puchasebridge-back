unit DMVC.AuthMeTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TAuthMeTests = class
  private
    FServer: TTestServerProcess;
    FToken: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetMe_WithValidToken_ReturnsCodigoYNombre;

    [Test]
    procedure GetMe_WithoutToken_Returns401;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, IdHTTP, DMVC.TestAuthHelper;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TAuthMeTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
  FToken := ObtenerTokenDePrueba(TEST_PORT);
end;

procedure TAuthMeTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TAuthMeTests.GetMe_WithValidToken_ReturnsCodigoYNombre;
var
  LHttp: TIdHTTP;
  LBody: string;
  LJson: TJSONObject;
  LCodigo, LNombre: string;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LBody := LHttp.Get(Format('http://localhost:%d/api/auth/me', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LBody) as TJSONObject;
    try
      Assert.IsNotNull(LJson);
      Assert.IsTrue(LJson.TryGetValue('codigo', LCodigo));
      Assert.IsTrue(LJson.TryGetValue('nombre', LNombre));
      Assert.IsFalse(LCodigo.Trim.IsEmpty);
      Assert.IsFalse(LNombre.Trim.IsEmpty);
    finally
      LJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TAuthMeTests.GetMe_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    try
      LHttp.Get(Format('http://localhost:%d/api/auth/me', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 401');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(401, E.ErrorCode);
    end;
  finally
    LHttp.Free;
  end;
end;

end.
