unit DMVC.XmlControllerReadTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TXmlControllerReadTests = class
  private
    FServer: TTestServerProcess;
    FToken: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetFiles_ReturnsJsonArray;

    [Test]
    procedure GetFiles_WithoutToken_Returns401;

    [Test]
    procedure GetFileById_WithInvalidId_Returns400;

    [Test]
    procedure GetFileById_WithNonexistentId_Returns404;

    [Test]
    procedure Parse_WithoutFileName_Returns400;

    [Test]
    procedure Parse_WithNonexistentFile_Returns404;

    [Test]
    procedure Parse_WithValidXml_ReturnsSuccessAndParsedData;

    [Test]
    procedure Parse_WithoutToken_Returns401;

    [Test]
    procedure GetProductosPendientes_WithoutFileName_Returns400;

    [Test]
    procedure GetProductosPendientes_WithNonexistentFileName_Returns404;

    [Test]
    procedure GetProductosDocumento_WithoutFileName_Returns400;

    [Test]
    procedure GetProductosDocumento_WithNonexistentFileName_Returns404;

    [Test]
    procedure GetDashboardMetrics_ReturnsJsonWithCounts;
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

procedure TXmlControllerReadTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
  FToken := ObtenerTokenDePrueba(TEST_PORT);
end;

procedure TXmlControllerReadTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TXmlControllerReadTests.GetFiles_ReturnsJsonArray;
var
  LHttp: TIdHTTP;
  LBody: string;
  LJson: TJSONValue;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LBody := LHttp.Get(Format('http://localhost:%d/api/xml/files', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LBody);
    try
      Assert.IsTrue(LJson is TJSONArray);
    finally
      LJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TXmlControllerReadTests.GetFiles_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    try
      LHttp.Get(Format('http://localhost:%d/api/xml/files', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 401');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(401, E.ErrorCode);
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TXmlControllerReadTests.GetFileById_WithInvalidId_Returns400;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    try
      LHttp.Get(Format('http://localhost:%d/api/xml/files/abc', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 400');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(400, E.ErrorCode);
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TXmlControllerReadTests.GetFileById_WithNonexistentId_Returns404;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    try
      LHttp.Get(Format('http://localhost:%d/api/xml/files/999999999', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 404');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(404, E.ErrorCode);
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TXmlControllerReadTests.Parse_WithoutFileName_Returns400;
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
      LHttp.Post(Format('http://localhost:%d/api/xml/parse', [TEST_PORT]), LRequest, LResponse);
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

procedure TXmlControllerReadTests.Parse_WithNonexistentFile_Returns404;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{"fileName":"__PHASE4TEST_NOEXISTE__.xml"}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/json';
    try
      LHttp.Post(Format('http://localhost:%d/api/xml/parse', [TEST_PORT]), LRequest, LResponse);
      Assert.Fail('Se esperaba una excepcion HTTP 404');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(404, E.ErrorCode);
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TXmlControllerReadTests.Parse_WithValidXml_ReturnsSuccessAndParsedData;
const
  TEST_FILE_NAME = '__PHASE4TEST_PARSE__.xml';
  TEST_XML =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<Invoice>' +
    '<AccountingSupplierParty><Party><PartyTaxScheme>' +
    '<CompanyID>000000000-TEST</CompanyID>' +
    '</PartyTaxScheme></Party></AccountingSupplierParty>' +
    '<InvoiceLine>' +
    '<ID>1</ID>' +
    '<InvoicedQuantity unitCode="94">1</InvoicedQuantity>' +
    '<LineExtensionAmount>100</LineExtensionAmount>' +
    '<Item><Description>Producto de prueba Fase 4</Description>' +
    '<SellersItemIdentification><ID>__PHASE4TEST_REF__</ID></SellersItemIdentification>' +
    '</Item>' +
    '</InvoiceLine>' +
    '<LegalMonetaryTotal>' +
    '<LineExtensionAmount>100</LineExtensionAmount>' +
    '<TaxExclusiveAmount>100</TaxExclusiveAmount>' +
    '<TaxInclusiveAmount>119</TaxInclusiveAmount>' +
    '</LegalMonetaryTotal>' +
    '<TaxTotal><TaxAmount>19</TaxAmount></TaxTotal>' +
    '</Invoice>';
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
  LInputPath, LFullFile: string;
  LJson, LProveedor: TJSONObject;
begin
  LInputPath := TPath.Combine(TPath.GetDirectoryName(ServerExePath), 'Input');
  if not TDirectory.Exists(LInputPath) then
    TDirectory.CreateDirectory(LInputPath);
  LFullFile := TPath.Combine(LInputPath, TEST_FILE_NAME);
  TFile.WriteAllText(LFullFile, TEST_XML, TEncoding.UTF8);
  try
    LHttp := TIdHTTP.Create(nil);
    LRequest := TStringStream.Create('{"fileName":"' + TEST_FILE_NAME + '"}', TEncoding.UTF8);
    LResponse := TStringStream.Create;
    try
      LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
      LHttp.Request.ContentType := 'application/json';
      LHttp.Post(Format('http://localhost:%d/api/xml/parse', [TEST_PORT]), LRequest, LResponse);
      Assert.AreEqual(200, LHttp.ResponseCode);
      LJson := TJSONObject.ParseJSONValue(LResponse.DataString) as TJSONObject;
      try
        Assert.IsNotNull(LJson);
        Assert.IsTrue((LJson.GetValue('success') as TJSONBool).AsBoolean, 'success debe ser true');
        LProveedor := LJson.GetValue('proveedor') as TJSONObject;
        Assert.AreEqual('000000000-TEST', LProveedor.GetValue('nit').Value);
        Assert.IsTrue((LJson.GetValue('productos') as TJSONArray).Count = 1);
      finally
        LJson.Free;
      end;
    finally
      LRequest.Free;
      LResponse.Free;
      LHttp.Free;
    end;
  finally
    if TFile.Exists(LFullFile) then
      TFile.Delete(LFullFile);
  end;
end;

procedure TXmlControllerReadTests.Parse_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.ContentType := 'application/json';
    try
      LHttp.Post(Format('http://localhost:%d/api/xml/parse', [TEST_PORT]), LRequest, LResponse);
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

procedure TXmlControllerReadTests.GetProductosPendientes_WithoutFileName_Returns400;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    try
      LHttp.Get(Format('http://localhost:%d/api/xml/productos/pendientes', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 400');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(400, E.ErrorCode);
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TXmlControllerReadTests.GetProductosPendientes_WithNonexistentFileName_Returns404;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    try
      LHttp.Get(Format('http://localhost:%d/api/xml/productos/pendientes?fileName=__PHASE4TEST_NOEXISTE__.xml', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 404');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(404, E.ErrorCode);
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TXmlControllerReadTests.GetProductosDocumento_WithoutFileName_Returns400;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    try
      LHttp.Get(Format('http://localhost:%d/api/xml/productos/documento', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 400');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(400, E.ErrorCode);
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TXmlControllerReadTests.GetProductosDocumento_WithNonexistentFileName_Returns404;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    try
      LHttp.Get(Format('http://localhost:%d/api/xml/productos/documento?fileName=__PHASE4TEST_NOEXISTE__.xml', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 404');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(404, E.ErrorCode);
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TXmlControllerReadTests.GetDashboardMetrics_ReturnsJsonWithCounts;
var
  LHttp: TIdHTTP;
  LBody: string;
  LJson: TJSONObject;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LBody := LHttp.Get(Format('http://localhost:%d/api/dashboard/metrics', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LBody) as TJSONObject;
    try
      Assert.IsNotNull(LJson);
      Assert.IsNotNull(LJson.GetValue('total'), 'total');
      Assert.IsNotNull(LJson.GetValue('cargados'), 'cargados');
      Assert.IsNotNull(LJson.GetValue('pendientes'), 'pendientes');
      Assert.IsNotNull(LJson.GetValue('listos'), 'listos');
      Assert.IsNotNull(LJson.GetValue('procesados'), 'procesados');
      Assert.IsNotNull(LJson.GetValue('errores'), 'errores');
      Assert.IsNotNull(LJson.GetValue('procesadosHoy'), 'procesadosHoy');
      Assert.IsNotNull(LJson.GetValue('erroresHoy'), 'erroresHoy');
    finally
      LJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

end.
