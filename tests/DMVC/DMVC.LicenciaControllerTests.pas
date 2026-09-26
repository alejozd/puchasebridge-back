unit DMVC.LicenciaControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TLicenciaControllerTests = class
  private
    FServer: TTestServerProcess;
    FToken: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Registrar_WithoutCodigo_Returns400;

    [Test]
    procedure GetEstado_WithoutToken_Returns401;

    [Test]
    procedure Registrar_WithoutToken_Returns401;

    [Test]
    procedure ActivarOnline_WithoutToken_Returns401;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Classes, IdHTTP,
  DMVC.TestAuthHelper;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TLicenciaControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
  FToken := ObtenerTokenDePrueba(TEST_PORT);
end;

procedure TLicenciaControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TLicenciaControllerTests.Registrar_WithoutCodigo_Returns400;
var
  LHttp: TIdHTTP;
  LBodyJson: TJSONObject;
  LPostBody: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LBodyJson := TJSONObject.Create;
    try
      LPostBody := TStringStream.Create(LBodyJson.ToJSON, TEncoding.UTF8);
      try
        LHttp.Request.ContentType := 'application/json';
        try
          LHttp.Post(Format('http://localhost:%d/api/licencia/registrar', [TEST_PORT]), LPostBody);
          Assert.Fail('Se esperaba una excepcion HTTP 400');
        except
          on E: EIdHTTPProtocolException do
            Assert.AreEqual(400, E.ErrorCode);
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

procedure TLicenciaControllerTests.GetEstado_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    try
      LHttp.Get(Format('http://localhost:%d/api/licencia/estado', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 401');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(401, E.ErrorCode);
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TLicenciaControllerTests.Registrar_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
  LBodyJson: TJSONObject;
  LPostBody: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LBodyJson := TJSONObject.Create;
    try
      LBodyJson.AddPair('codigo', 'X');
      LPostBody := TStringStream.Create(LBodyJson.ToJSON, TEncoding.UTF8);
      try
        LHttp.Request.ContentType := 'application/json';
        try
          LHttp.Post(Format('http://localhost:%d/api/licencia/registrar', [TEST_PORT]), LPostBody);
          Assert.Fail('Se esperaba una excepcion HTTP 401');
        except
          on E: EIdHTTPProtocolException do
            Assert.AreEqual(401, E.ErrorCode);
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

procedure TLicenciaControllerTests.ActivarOnline_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
  LPostBody: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LPostBody := TStringStream.Create('', TEncoding.UTF8);
  try
    LHttp.Request.ContentType := 'application/json';
    try
      LHttp.Post(Format('http://localhost:%d/api/licencia/activar-online', [TEST_PORT]), LPostBody);
      Assert.Fail('Se esperaba una excepcion HTTP 401');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(401, E.ErrorCode);
    end;
  finally
    LPostBody.Free;
    LHttp.Free;
  end;
end;

end.
