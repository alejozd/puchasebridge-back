unit DMVC.ImportControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TImportControllerTests = class
  private
    FServer: TTestServerProcess;
    FToken: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure PostFacturaXML_WithEmptyBody_Returns400;

    [Test]
    procedure PostFacturaXML_WithValidXML_ReturnsProveedorYProductos;

    [Test]
    procedure PostFacturaXML_WithoutToken_Returns401;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Classes, IdHTTP, DMVC.TestAuthHelper;

const
  TEST_PORT = 9091;
  // NOTA (hallazgo empirico, ver Step 3 del plan): TXMLNodeList.FindNode(nombre)
  // en la RTL de Delphi (Xml.XMLDoc/Xml.xmldom, no especifico de ADOM/MSXML)
  // filtra ademas por el namespace URI propio del nodo padre sobre el que se
  // llama ChildNodes -- si el padre y el hijo buscado estan en namespaces XML
  // DIFERENTES (p.ej. cac:PartyTaxScheme buscando cbc:CompanyID), la busqueda
  // falla silenciosamente (sin excepcion, simplemente no encuentra el nodo)
  // aunque el nombre calificado coincida literalmente. Los URIs reales de UBL
  // (CommonAggregateComponents-2 para cac, CommonBasicComponents-2 para cbc)
  // SON namespaces distintos, así que un XML de factura real con esos URIs
  // reproduciria el mismo problema de extraccion via TXMLFacturaService.Parsear
  // -- esto es un hallazgo sobre services/XMLFacturaService.pas (archivo Horse,
  // fuera de alcance para modificar en esta task) que se documenta para
  // reporte, no se corrige aqui. Para que este test XML de prueba SI se parsee
  // correctamente con el codigo actual (sin tocarlo), cac y cbc se declaran
  // aqui apuntando al MISMO URI ficticio -- asi el chequeo de namespace de
  // NodeMatches siempre coincide y el test ejercita el resto del flujo real
  // (Parsear + las dos consultas de solo lectura contra Helisa).
  TEST_XML =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<Invoice xmlns:cac="urn:phase4test:ubl" ' +
    'xmlns:cbc="urn:phase4test:ubl">' +
    '<cbc:IssueDate>2024-05-22</cbc:IssueDate>' +
    '<cac:AccountingSupplierParty>' +
    '<cac:Party>' +
    '<cac:PartyTaxScheme>' +
    '<cbc:CompanyID>000000000-TEST</cbc:CompanyID>' +
    '</cac:PartyTaxScheme>' +
    '</cac:Party>' +
    '</cac:AccountingSupplierParty>' +
    '<cac:InvoiceLine>' +
    '<cac:Item>' +
    '<cbc:Description>Producto de prueba Fase 4</cbc:Description>' +
    '<cac:SellersItemIdentification>' +
    '<cbc:ID>__PHASE4TEST_REF__</cbc:ID>' +
    '</cac:SellersItemIdentification>' +
    '</cac:Item>' +
    '</cac:InvoiceLine>' +
    '</Invoice>';

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TImportControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
  FToken := ObtenerTokenDePrueba(TEST_PORT);
end;

procedure TImportControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TImportControllerTests.PostFacturaXML_WithEmptyBody_Returns400;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/xml';
    try
      LHttp.Post(Format('http://localhost:%d/factura/xml', [TEST_PORT]), LRequest, LResponse);
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

procedure TImportControllerTests.PostFacturaXML_WithValidXML_ReturnsProveedorYProductos;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
  LJson: TJSONObject;
  LProveedor: TJSONObject;
  LProductos: TJSONArray;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create(TEST_XML, TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/xml';
    LHttp.Post(Format('http://localhost:%d/factura/xml', [TEST_PORT]), LRequest, LResponse);
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LResponse.DataString) as TJSONObject;
    try
      Assert.IsNotNull(LJson);
      LProveedor := LJson.GetValue('proveedor') as TJSONObject;
      Assert.AreEqual('000000000-TEST', LProveedor.GetValue('nit').Value);
      Assert.IsFalse((LProveedor.GetValue('existe') as TJSONBool).AsBoolean);
      LProductos := LJson.GetValue('productos') as TJSONArray;
      Assert.AreEqual(1, LProductos.Count);
      Assert.IsFalse(((LProductos.Items[0] as TJSONObject).GetValue('existe') as TJSONBool).AsBoolean);
    finally
      LJson.Free;
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TImportControllerTests.PostFacturaXML_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create(TEST_XML, TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.ContentType := 'application/xml';
    try
      LHttp.Post(Format('http://localhost:%d/factura/xml', [TEST_PORT]), LRequest, LResponse);
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
