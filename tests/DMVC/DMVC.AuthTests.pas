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
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Classes, IdHTTP, IdException;

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
      LBodyJson.AddPair('username', '__usuario_inexistente_phase3_test__');
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

end.
