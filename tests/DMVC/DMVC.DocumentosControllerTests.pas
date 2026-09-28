unit DMVC.DocumentosControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TDocumentosControllerTests = class
  private
    FServer: TTestServerProcess;
    FToken: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Procesar_WithEmptyFiles_ReturnsEmptyArrays;

    [Test]
    procedure Procesar_WithNonexistentFile_ReturnsArchivoNoEncontrado;

    [Test]
    procedure Procesar_WithoutToken_Returns401;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Classes, IdHTTP, DMVC.TestAuthHelper;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TDocumentosControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
  FToken := ObtenerTokenDePrueba(TEST_PORT);
end;

procedure TDocumentosControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TDocumentosControllerTests.Procesar_WithEmptyFiles_ReturnsEmptyArrays;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
  LJson: TJSONObject;
  LProcesados, LErrores: TJSONArray;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{"files":[]}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/json';
    LHttp.Post(Format('http://localhost:%d/documentos/procesar', [TEST_PORT]), LRequest, LResponse);
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LResponse.DataString) as TJSONObject;
    try
      Assert.IsNotNull(LJson);
      LProcesados := LJson.GetValue('procesados') as TJSONArray;
      LErrores := LJson.GetValue('errores') as TJSONArray;
      Assert.AreEqual(0, LProcesados.Count);
      Assert.AreEqual(0, LErrores.Count);
    finally
      LJson.Free;
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TDocumentosControllerTests.Procesar_WithNonexistentFile_ReturnsArchivoNoEncontrado;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
  LJson: TJSONObject;
  LProcesados, LErrores: TJSONArray;
  LErrorObj: TJSONObject;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{"files":["__PHASE4TEST_NOEXISTE__.xml"]}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/json';
    LHttp.Post(Format('http://localhost:%d/documentos/procesar', [TEST_PORT]), LRequest, LResponse);
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LResponse.DataString) as TJSONObject;
    try
      Assert.IsNotNull(LJson);
      LProcesados := LJson.GetValue('procesados') as TJSONArray;
      LErrores := LJson.GetValue('errores') as TJSONArray;
      Assert.AreEqual(0, LProcesados.Count);
      Assert.AreEqual(1, LErrores.Count);
      LErrorObj := LErrores.Items[0] as TJSONObject;
      Assert.AreEqual('__PHASE4TEST_NOEXISTE__.xml', LErrorObj.GetValue('fileName').Value);
      Assert.AreEqual('Archivo no encontrado', LErrorObj.GetValue('error').Value);
    finally
      LJson.Free;
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TDocumentosControllerTests.Procesar_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{"files":[]}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.ContentType := 'application/json';
    try
      LHttp.Post(Format('http://localhost:%d/documentos/procesar', [TEST_PORT]), LRequest, LResponse);
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
