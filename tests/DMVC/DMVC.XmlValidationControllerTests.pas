unit DMVC.XmlValidationControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TXmlValidationControllerTests = class
  private
    FServer: TTestServerProcess;
    FToken: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Validate_WithoutFileName_Returns400;

    [Test]
    procedure Validate_WithNonexistentFile_ReturnsValidoFalse;

    [Test]
    procedure ValidateBatch_WithNonexistentFiles_ReturnsSummary;

    [Test]
    procedure Validate_WithoutToken_Returns401;
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

procedure TXmlValidationControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
  FToken := ObtenerTokenDePrueba(TEST_PORT);
end;

procedure TXmlValidationControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TXmlValidationControllerTests.Validate_WithoutFileName_Returns400;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/json';
    try
      LHttp.Post(Format('http://localhost:%d/api/xml/validate', [TEST_PORT]), LRequest, LResponse);
      Assert.Fail('Se esperaba una excepcion HTTP 400');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(400, E.ErrorCode);
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TXmlValidationControllerTests.Validate_WithNonexistentFile_ReturnsValidoFalse;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
  LJson: TJSONObject;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{"fileName":"__phase4_no_existe__.xml"}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/json';
    LHttp.Post(Format('http://localhost:%d/api/xml/validate', [TEST_PORT]), LRequest, LResponse);
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LResponse.DataString) as TJSONObject;
    try
      Assert.IsNotNull(LJson);
      Assert.IsFalse((LJson.GetValue('valido') as TJSONBool).AsBoolean);
    finally
      LJson.Free;
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TXmlValidationControllerTests.ValidateBatch_WithNonexistentFiles_ReturnsSummary;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
  LJson, LResumen: TJSONObject;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{"files":["__a__.xml","__b__.xml"]}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/json';
    LHttp.Post(Format('http://localhost:%d/api/xml/validate/batch', [TEST_PORT]), LRequest, LResponse);
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LResponse.DataString) as TJSONObject;
    try
      LResumen := LJson.GetValue('resumen') as TJSONObject;
      Assert.AreEqual(2, (LResumen.GetValue('total') as TJSONNumber).AsInt);
      Assert.AreEqual(0, (LResumen.GetValue('validos') as TJSONNumber).AsInt);
      Assert.AreEqual(2, (LResumen.GetValue('conErrores') as TJSONNumber).AsInt);
    finally
      LJson.Free;
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TXmlValidationControllerTests.Validate_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{"fileName":"x.xml"}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.ContentType := 'application/json';
    try
      LHttp.Post(Format('http://localhost:%d/api/xml/validate', [TEST_PORT]), LRequest, LResponse);
      Assert.Fail('Se esperaba una excepcion HTTP 401');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(401, E.ErrorCode);
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

end.
