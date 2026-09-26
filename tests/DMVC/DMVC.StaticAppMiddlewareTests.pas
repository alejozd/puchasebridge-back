unit DMVC.StaticAppMiddlewareTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TStaticAppMiddlewareTests = class
  private
    FServer: TTestServerProcess;
    FToken: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure ApiRoute_NotSwallowedByStaticMiddleware;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, IdHTTP, DMVC.TestAuthHelper;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TStaticAppMiddlewareTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
  // /api/equivalencias esta protegido por JWT desde Task 4: se necesita un
  // token real para que este test siga probando lo que probaba en Task 3
  // (que /api no es interceptada por el middleware de estaticos, verificado
  // via un 200 real con el JSON del controller, no el fallback html).
  FToken := ObtenerTokenDePrueba(TEST_PORT);
end;

procedure TStaticAppMiddlewareTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TStaticAppMiddlewareTests.ApiRoute_NotSwallowedByStaticMiddleware;
var
  LHttp: TIdHTTP;
  LBody: string;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    // Si el middleware de estaticos se "comiera" esta ruta, devolveria 200
    // con el contenido de index.html en vez de dejarla llegar al controller.
    LBody := LHttp.Get(Format('http://localhost:%d/api/equivalencias', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    Assert.IsFalse(LBody.Contains('<html'), 'La ruta /api no debe ser interceptada por el middleware de estaticos');
  finally
    LHttp.Free;
  end;
end;

end.
