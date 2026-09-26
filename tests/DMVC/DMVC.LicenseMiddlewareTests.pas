unit DMVC.LicenseMiddlewareTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TLicenseMiddlewareTests = class
  private
    FServer: TTestServerProcess;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Ping_NeverBlockedByLicense;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, IdHTTP;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TLicenseMiddlewareTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
end;

procedure TLicenseMiddlewareTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TLicenseMiddlewareTests.Ping_NeverBlockedByLicense;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Get(Format('http://localhost:%d/ping', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode, '/ping nunca debe ser bloqueado por el guard de licencia');
  finally
    LHttp.Free;
  end;
end;

end.
