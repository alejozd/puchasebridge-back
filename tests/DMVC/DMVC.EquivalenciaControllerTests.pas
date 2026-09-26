unit DMVC.EquivalenciaControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TEquivalenciaControllerTests = class
  private
    FServer: TTestServerProcess;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetEquivalencias_ReturnsJsonArray;
    [Test]
    procedure GetEquivalencias_WithTaggedRow_ReturnsCorrectFields;
    [Test]
    procedure CreateThenDeleteEquivalencia_RoundTrips;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Classes, IdHTTP,
  FirebirdConnection, FireDAC.Comp.Client;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TEquivalenciaControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
end;

procedure TEquivalenciaControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TEquivalenciaControllerTests.GetEquivalencias_ReturnsJsonArray;
var
  LHttp: TIdHTTP;
  LBody: string;
  LJson: TJSONValue;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LBody := LHttp.Get(Format('http://localhost:%d/api/equivalencias?limite=5', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LBody);
    try
      Assert.IsTrue(LJson is TJSONArray, 'La respuesta debe ser un array JSON, no un objeto envuelto');
    finally
      LJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TEquivalenciaControllerTests.GetEquivalencias_WithTaggedRow_ReturnsCorrectFields;
const
  TAG_REF = '__PHASE2TEST_LIST_REF__';
  // UNIDADH/UNIDADP are VARCHAR(5)/VARCHAR(10); keep this <= 5 chars to fit the narrower column.
  TAG_UNI = 'P2TU';
var
  LInsertQuery: TFDQuery;
  LHttp: TIdHTTP;
  LBody: string;
  LArray: TJSONArray;
  LItem: TJSONObject;
begin
  LInsertQuery := FirebirdConnection.GetBridgeQuery;
  try
    LInsertQuery.SQL.Text :=
      'INSERT INTO EQUIVALENCIA (CODIGOH, SUBCODIGOH, NOMBREH, REFERENCIAH, UNIDADH, UNIDADP, REFERENCIAP, FACTOR) ' +
      'VALUES (777777, 3, ''Test Fase 2 List'', :REFH, :UNIH, :UNIP, :REFP, 2.5)';
    LInsertQuery.ParamByName('REFH').AsString := TAG_REF;
    LInsertQuery.ParamByName('UNIH').AsString := TAG_UNI;
    LInsertQuery.ParamByName('UNIP').AsString := TAG_UNI;
    LInsertQuery.ParamByName('REFP').AsString := TAG_REF;
    LInsertQuery.ExecSQL;
  finally
    LInsertQuery.Free;
  end;

  try
    LHttp := TIdHTTP.Create(nil);
    try
      LBody := LHttp.Get(Format('http://localhost:%d/api/equivalencias?referenciaP=%s&limite=50',
        [TEST_PORT, TAG_REF]));
      Assert.AreEqual(200, LHttp.ResponseCode);
      LArray := TJSONObject.ParseJSONValue(LBody) as TJSONArray;
      try
        Assert.AreEqual(1, LArray.Count, 'Debe encontrar exactamente la fila insertada por el test');
        LItem := LArray.Items[0] as TJSONObject;
        Assert.AreEqual(777777, LItem.GetValue<Integer>('codigoH'));
        Assert.AreEqual(3, LItem.GetValue<Integer>('subCodigoH'));
        Assert.AreEqual('Test Fase 2 List', LItem.GetValue<string>('nombreH'));
        Assert.AreEqual(TAG_REF, LItem.GetValue<string>('referenciaH'));
        Assert.AreEqual(TAG_UNI, LItem.GetValue<string>('unidadH'));
      finally
        LArray.Free;
      end;
    finally
      LHttp.Free;
    end;
  finally
    LInsertQuery := FirebirdConnection.GetBridgeQuery;
    try
      LInsertQuery.SQL.Text := 'DELETE FROM EQUIVALENCIA WHERE REFERENCIAH = :REFH AND UNIDADH = :UNIH';
      LInsertQuery.ParamByName('REFH').AsString := TAG_REF;
      LInsertQuery.ParamByName('UNIH').AsString := TAG_UNI;
      LInsertQuery.ExecSQL;
    finally
      LInsertQuery.Free;
    end;
  end;
end;

procedure TEquivalenciaControllerTests.CreateThenDeleteEquivalencia_RoundTrips;
const
  TEST_REF = 'P2T2REF'; // cabe en REFERENCIAP(50)/REFERENCIAH(40)
  TEST_UNI = 'P2T2'; // 4 caracteres — DEBE caber en UNIDADH VARCHAR(5)
var
  LHttp: TIdHTTP;
  LBodyJson: TJSONObject;
  LPostBody: TStringStream;
  LResponse: string;
  LDeleteUrl: string;
  LCleanupQuery: TFDQuery;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    try
      // 1. Crear — referenciaH/unidadH se envian IGUALES a referenciaP/unidadP a
      // proposito, para que el DELETE (que filtra por REFERENCIAH/UNIDADH, ver
      // nota de comportamiento preexistente) despues SI encuentre la fila.
      LBodyJson := TJSONObject.Create;
      try
        LBodyJson.AddPair('codigoH', TJSONNumber.Create(999999));
        LBodyJson.AddPair('subCodigoH', TJSONNumber.Create(1));
        LBodyJson.AddPair('nombreH', 'Test Phase2');
        LBodyJson.AddPair('referenciaH', TEST_REF);
        LBodyJson.AddPair('unidadH', TEST_UNI);
        LBodyJson.AddPair('referenciaP', TEST_REF);
        LBodyJson.AddPair('unidadP', TEST_UNI);
        LBodyJson.AddPair('factor', TJSONNumber.Create(1.5));

        LPostBody := TStringStream.Create(LBodyJson.ToJSON, TEncoding.UTF8);
        try
          LHttp.Request.ContentType := 'application/json';
          LResponse := LHttp.Post(Format('http://localhost:%d/api/equivalencia', [TEST_PORT]), LPostBody);
          Assert.AreEqual(200, LHttp.ResponseCode, 'Create debe responder 200/OK: ' + LResponse);
        finally
          LPostBody.Free;
        end;
      finally
        LBodyJson.Free;
      end;

      // 2. Borrar lo recien creado via la API (es lo que este test principalmente
      // verifica) y confirmar que el borrado reporta exito.
      LDeleteUrl := Format('http://localhost:%d/api/equivalencia?referenciaP=%s&unidadP=%s',
        [TEST_PORT, TEST_REF, TEST_UNI]);
      LResponse := LHttp.Delete(LDeleteUrl);
      Assert.AreEqual(200, LHttp.ResponseCode, 'Delete debe responder 200/OK: ' + LResponse);
    finally
      // Cleanup incondicional de respaldo: si el create o el delete via HTTP
      // fallaron a mitad de camino (assertion failure), este DELETE crudo por
      // SQL garantiza que la fila de prueba no quede huerfana en la base,
      // igual que el patron ya establecido en GetEquivalencias_WithTaggedRow_
      // ReturnsCorrectFields (Task 1).
      LCleanupQuery := FirebirdConnection.GetBridgeQuery;
      try
        LCleanupQuery.SQL.Text := 'DELETE FROM EQUIVALENCIA WHERE REFERENCIAH = :REFH AND UNIDADH = :UNIH';
        LCleanupQuery.ParamByName('REFH').AsString := TEST_REF;
        LCleanupQuery.ParamByName('UNIH').AsString := TEST_UNI;
        LCleanupQuery.ExecSQL;
      finally
        LCleanupQuery.Free;
      end;
    end;
  finally
    LHttp.Free;
  end;
end;

end.
