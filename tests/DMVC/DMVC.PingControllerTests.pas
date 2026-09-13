unit DMVC.PingControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TPingControllerTests = class
  private
    FServer: TTestServerProcess;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetPing_ReturnsOkStatus;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.IOUtils, IdHTTP;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TPingControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT),
    'El servidor DMVC no respondió a tiempo en /ping');
end;

procedure TPingControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TPingControllerTests.GetPing_ReturnsOkStatus;
var
  LHttp: TIdHTTP;
  LBody: string;
  LJson: TJSONObject;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LBody := LHttp.Get(Format('http://localhost:%d/ping', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LBody) as TJSONObject;
    try
      Assert.AreEqual('ok', LJson.GetValue<string>('status'));
    finally
      LJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

end.
