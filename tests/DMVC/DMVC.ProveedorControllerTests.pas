unit DMVC.ProveedorControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TProveedorControllerTests = class
  private
    FServer: TTestServerProcess;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetProveedor_NitInexistente_ReturnsExisteFalse;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, IdHTTP;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TProveedorControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
end;

procedure TProveedorControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TProveedorControllerTests.GetProveedor_NitInexistente_ReturnsExisteFalse;
var
  LHttp: TIdHTTP;
  LBody: string;
  LJson: TJSONObject;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    // anio=2025 pinned explicitly: ObtenerProveedorPorNit defaults to the CURRENT
    // calendar year's CPMAxxxx table when anio is omitted, and this live Helisa
    // instance does not yet have a CPMA2026 table provisioned (confirmed via a
    // read-only probe against years 2020-2027, all using the fake test NIT only)
    // - see task-3-report.md "Credential unblock" section for details. Not a bug
    // in this migration; ProveedorRepository.pas / ValidarAnio are unchanged.
    LBody := LHttp.Get(Format('http://localhost:%d/api/proveedor/000000000-TEST?anio=2025', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LBody) as TJSONObject;
    try
      Assert.IsFalse(LJson.GetValue<Boolean>('existe'));
    finally
      LJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

end.
