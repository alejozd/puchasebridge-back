unit DMVC.XmlControllerWriteTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TXmlControllerWriteTests = class
  private
    FServer: TTestServerProcess;
    FToken: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Upload_WithoutFile_Returns400;

    [Test]
    procedure Upload_WithNonXmlExtension_Returns400;

    [Test]
    procedure Upload_WithValidXmlFile_UpsertsStaging;

    [Test]
    procedure Upload_WithoutToken_Returns401;

    [Test]
    procedure ProcesarBatch_WithoutIds_Returns400;

    [Test]
    procedure ProcesarBatch_WithFicticiousId_MarksProcesado;

    [Test]
    procedure ProcesarBatch_WithoutToken_Returns401;

    [Test]
    procedure Homologar_WithMissingReferenciaXml_Returns500;

    [Test]
    procedure Homologar_WithValidFicticiousMapping_CreatesEquivalencia;

    [Test]
    procedure Homologar_WithoutToken_Returns401;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Classes,
  IdHTTP, IdMultipartFormData, FirebirdConnection, FireDAC.Comp.Client,
  DMVC.TestAuthHelper;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

function ServerInputPath: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(ServerExePath), 'Input');
end;

procedure TXmlControllerWriteTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
  FToken := ObtenerTokenDePrueba(TEST_PORT);
end;

procedure TXmlControllerWriteTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TXmlControllerWriteTests.Upload_WithoutFile_Returns400;
var
  LHttp: TIdHTTP;
  LForm: TIdMultiPartFormDataStream;
  LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LForm := TIdMultiPartFormDataStream.Create;
  LResponse := TStringStream.Create;
  try
    LForm.AddFormField('note', 'sin archivo adjunto');
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := LForm.RequestContentType;
    try
      LHttp.Post(Format('http://localhost:%d/xml/upload', [TEST_PORT]), LForm, LResponse);
      Assert.Fail('Se esperaba una excepcion HTTP 400');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(400, E.ErrorCode);
    end;
  finally
    LForm.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TXmlControllerWriteTests.Upload_WithNonXmlExtension_Returns400;
const
  TEMP_FILE_NAME = '__phase4test_upload_bad_ext__.txt';
var
  LHttp: TIdHTTP;
  LForm: TIdMultiPartFormDataStream;
  LResponse: TStringStream;
  LTempFile: string;
begin
  LTempFile := TPath.Combine(TPath.GetTempPath, TEMP_FILE_NAME);
  TFile.WriteAllText(LTempFile, 'contenido de prueba, no es xml', TEncoding.UTF8);
  try
    LHttp := TIdHTTP.Create(nil);
    LForm := TIdMultiPartFormDataStream.Create;
    LResponse := TStringStream.Create;
    try
      LForm.AddFile('file', LTempFile, 'text/plain');
      LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
      LHttp.Request.ContentType := LForm.RequestContentType;
      try
        LHttp.Post(Format('http://localhost:%d/xml/upload', [TEST_PORT]), LForm, LResponse);
        Assert.Fail('Se esperaba una excepcion HTTP 400');
      except
        on E: EIdHTTPProtocolException do
          Assert.AreEqual(400, E.ErrorCode);
      end;
    finally
      LForm.Free;
      LResponse.Free;
      LHttp.Free;
    end;
  finally
    if TFile.Exists(LTempFile) then
      TFile.Delete(LTempFile);
  end;
end;

procedure TXmlControllerWriteTests.Upload_WithValidXmlFile_UpsertsStaging;
const
  TEST_FILE_NAME = '__phase4test_upload__.xml';
  TEST_XML = '<?xml version="1.0" encoding="UTF-8"?><Invoice><Dummy/></Invoice>';
var
  LHttp: TIdHTTP;
  LForm: TIdMultiPartFormDataStream;
  LResponse: TStringStream;
  LTempFile, LUploadedFile: string;
  LJson: TJSONObject;
  LCleanupQuery: TFDQuery;
begin
  LTempFile := TPath.Combine(TPath.GetTempPath, TEST_FILE_NAME);
  TFile.WriteAllText(LTempFile, TEST_XML, TEncoding.UTF8);
  LUploadedFile := TPath.Combine(ServerInputPath, TEST_FILE_NAME);
  try
    LHttp := TIdHTTP.Create(nil);
    LForm := TIdMultiPartFormDataStream.Create;
    LResponse := TStringStream.Create;
    try
      LForm.AddFile('file', LTempFile, 'text/xml');
      LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
      LHttp.Request.ContentType := LForm.RequestContentType;
      LHttp.Post(Format('http://localhost:%d/xml/upload', [TEST_PORT]), LForm, LResponse);
      Assert.AreEqual(200, LHttp.ResponseCode, 'Upload debe responder 200/OK: ' + LResponse.DataString);
      LJson := TJSONObject.ParseJSONValue(LResponse.DataString) as TJSONObject;
      try
        Assert.IsNotNull(LJson);
        Assert.IsTrue((LJson.GetValue('success') as TJSONBool).AsBoolean, 'success debe ser true');
        Assert.AreEqual(TEST_FILE_NAME, LJson.GetValue('fileName').Value);
      finally
        LJson.Free;
      end;
    finally
      LForm.Free;
      LResponse.Free;
      LHttp.Free;
    end;
  finally
    if TFile.Exists(LUploadedFile) then
      TFile.Delete(LUploadedFile);
    if TFile.Exists(LTempFile) then
      TFile.Delete(LTempFile);
    LCleanupQuery := FirebirdConnection.GetBridgeQuery;
    try
      LCleanupQuery.SQL.Text := 'DELETE FROM XML_FILES WHERE FILE_NAME = :FNAME';
      LCleanupQuery.ParamByName('FNAME').AsString := TEST_FILE_NAME;
      LCleanupQuery.ExecSQL;
    finally
      LCleanupQuery.Free;
    end;
  end;
end;

procedure TXmlControllerWriteTests.Upload_WithoutToken_Returns401;
const
  TEMP_FILE_NAME = '__phase4test_upload_noauth__.xml';
var
  LHttp: TIdHTTP;
  LForm: TIdMultiPartFormDataStream;
  LResponse: TStringStream;
  LTempFile: string;
begin
  LTempFile := TPath.Combine(TPath.GetTempPath, TEMP_FILE_NAME);
  TFile.WriteAllText(LTempFile, '<Invoice/>', TEncoding.UTF8);
  try
    LHttp := TIdHTTP.Create(nil);
    LForm := TIdMultiPartFormDataStream.Create;
    LResponse := TStringStream.Create;
    try
      LForm.AddFile('file', LTempFile, 'text/xml');
      LHttp.Request.ContentType := LForm.RequestContentType;
      try
        LHttp.Post(Format('http://localhost:%d/xml/upload', [TEST_PORT]), LForm, LResponse);
        Assert.Fail('Se esperaba una excepcion HTTP 401');
      except
        on E: EIdHTTPProtocolException do
          Assert.AreEqual(401, E.ErrorCode);
      end;
    finally
      LForm.Free;
      LResponse.Free;
      LHttp.Free;
    end;
  finally
    if TFile.Exists(LTempFile) then
      TFile.Delete(LTempFile);
  end;
end;

procedure TXmlControllerWriteTests.ProcesarBatch_WithoutIds_Returns400;
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
      LHttp.Post(Format('http://localhost:%d/xml/procesar', [TEST_PORT]), LRequest, LResponse);
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

procedure TXmlControllerWriteTests.ProcesarBatch_WithFicticiousId_MarksProcesado;
const
  TEST_FILE_NAME = '__phase4test_procesar__.xml';
var
  LInsertQuery: TFDQuery;
  LFileId: Integer;
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
  LJson: TJSONObject;
  LProcesadosArr: TJSONArray;
begin
  LFileId := 0;
  LInsertQuery := FirebirdConnection.GetBridgeQuery;
  try
    LInsertQuery.SQL.Text :=
      'INSERT INTO XML_FILES (FILE_NAME, ESTADO, FECHA_CARGA) ' +
      'VALUES (:FNAME, ''CARGADO'', CURRENT_TIMESTAMP) RETURNING ID';
    LInsertQuery.ParamByName('FNAME').AsString := TEST_FILE_NAME;
    LInsertQuery.Open;
    LFileId := LInsertQuery.FieldByName('ID').AsInteger;
  finally
    LInsertQuery.Free;
  end;

  try
    LHttp := TIdHTTP.Create(nil);
    LRequest := TStringStream.Create(Format('{"ids":[%d]}', [LFileId]), TEncoding.UTF8);
    LResponse := TStringStream.Create;
    try
      LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
      LHttp.Request.ContentType := 'application/json';
      LHttp.Post(Format('http://localhost:%d/xml/procesar', [TEST_PORT]), LRequest, LResponse);
      Assert.AreEqual(200, LHttp.ResponseCode, 'ProcesarBatch debe responder 200/OK: ' + LResponse.DataString);
      LJson := TJSONObject.ParseJSONValue(LResponse.DataString) as TJSONObject;
      try
        Assert.IsNotNull(LJson);
        LProcesadosArr := LJson.GetValue('procesados') as TJSONArray;
        Assert.AreEqual(1, LProcesadosArr.Count, 'El ID ficticio debe aparecer en procesados');
        Assert.AreEqual(LFileId, (LProcesadosArr.Items[0] as TJSONNumber).AsInt);
      finally
        LJson.Free;
      end;
    finally
      LRequest.Free;
      LResponse.Free;
      LHttp.Free;
    end;
  finally
    LInsertQuery := FirebirdConnection.GetBridgeQuery;
    try
      LInsertQuery.SQL.Text := 'DELETE FROM XML_FILES WHERE ID = :ID';
      LInsertQuery.ParamByName('ID').AsInteger := LFileId;
      LInsertQuery.ExecSQL;
    finally
      LInsertQuery.Free;
    end;
  end;
end;

procedure TXmlControllerWriteTests.ProcesarBatch_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{"ids":[1]}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.ContentType := 'application/json';
    try
      LHttp.Post(Format('http://localhost:%d/xml/procesar', [TEST_PORT]), LRequest, LResponse);
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

procedure TXmlControllerWriteTests.Homologar_WithMissingReferenciaXml_Returns500;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  // NOTA: preserva un quirk del Horse original a proposito (ver plan Task 6b,
  // "Notas de fidelidad") -- los campos requeridos faltantes generan una
  // excepcion generica que termina como 500, NO 400. No "corregir" a 400.
  LRequest := TStringStream.Create('{}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/json';
    try
      LHttp.Post(Format('http://localhost:%d/xml/homologar', [TEST_PORT]), LRequest, LResponse);
      Assert.Fail('Se esperaba una excepcion HTTP 500');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(500, E.ErrorCode);
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TXmlControllerWriteTests.Homologar_WithValidFicticiousMapping_CreatesEquivalencia;
const
  TAG_REF_XML = '__PHASE4TEST_XML_REF__';
  TAG_UNI_XML = 'ZZ99';
  TAG_REF_ERP = '__PHASE4TEST_ERP_REF__';
  // EQUIVALENCIA.UNIDADH es VARCHAR(5) (ver database/scripts/create_tables.txt) --
  // "ZZ99" cabe en ese ancho y no sigue el patron de ningun codigo DIAN real
  // (letras/digitos de 2-3 caracteres como '94'/'KGM'/'NIU'), a diferencia de
  // un marcador largo tipo "__PHASE4TEST_UNI__" que revienta con string
  // right truncation al intentar escribirse en esa columna.
  TAG_UNI_ERP = 'ZZ99';
var
  LHttp: TIdHTTP;
  LBodyJson: TJSONObject;
  LRequest, LResponse: TStringStream;
  LJson: TJSONObject;
  LCleanupQuery: TFDQuery;
begin
  LHttp := TIdHTTP.Create(nil);
  LBodyJson := TJSONObject.Create;
  try
    LBodyJson.AddPair('referenciaXml', TAG_REF_XML);
    LBodyJson.AddPair('unidadXml', TAG_UNI_XML);
    LBodyJson.AddPair('codigoH', TJSONNumber.Create(999998));
    LBodyJson.AddPair('nombreH', 'Test Fase4 Homologar');
    LBodyJson.AddPair('referenciaErp', TAG_REF_ERP);
    LBodyJson.AddPair('unidadErp', TAG_UNI_ERP);
    LBodyJson.AddPair('factor', TJSONNumber.Create(1));

    LRequest := TStringStream.Create(LBodyJson.ToJSON, TEncoding.UTF8);
    LResponse := TStringStream.Create;
    try
      LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
      LHttp.Request.ContentType := 'application/json';
      LHttp.Post(Format('http://localhost:%d/xml/homologar', [TEST_PORT]), LRequest, LResponse);
      Assert.AreEqual(200, LHttp.ResponseCode, 'Homologar debe responder 200/OK: ' + LResponse.DataString);
      LJson := TJSONObject.ParseJSONValue(LResponse.DataString) as TJSONObject;
      try
        Assert.IsNotNull(LJson);
        Assert.IsTrue((LJson.GetValue('success') as TJSONBool).AsBoolean, 'success debe ser true');
      finally
        LJson.Free;
      end;
    finally
      LRequest.Free;
      LResponse.Free;
    end;
  finally
    LBodyJson.Free;
    LHttp.Free;
    LCleanupQuery := FirebirdConnection.GetBridgeQuery;
    try
      LCleanupQuery.SQL.Text := 'DELETE FROM EQUIVALENCIA WHERE REFERENCIAP = :REFP';
      LCleanupQuery.ParamByName('REFP').AsString := TAG_REF_XML;
      LCleanupQuery.ExecSQL;
    finally
      LCleanupQuery.Free;
    end;
  end;
end;

procedure TXmlControllerWriteTests.Homologar_WithoutToken_Returns401;
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
      LHttp.Post(Format('http://localhost:%d/xml/homologar', [TEST_PORT]), LRequest, LResponse);
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
