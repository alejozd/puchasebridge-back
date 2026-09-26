unit DMVC.CORSMiddlewareTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TCORSMiddlewareTests = class
  private
    FServer: TTestServerProcess;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Get_ReflectsOriginHeader;

    [Test]
    procedure Options_ReturnsOkWithEmptyBody;
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

procedure TCORSMiddlewareTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
end;

procedure TCORSMiddlewareTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TCORSMiddlewareTests.Get_ReflectsOriginHeader;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Origin', 'http://example-test.local');
    LHttp.Get(Format('http://localhost:%d/ping', [TEST_PORT]));
    // NOTE: Indy's TIdHTTP.Response.CustomHeaders only ever holds headers the
    // CLIENT sends; parsed response headers land in RawHeaders instead (see
    // TIdEntityHeaderInfo.ProcessHeaders / TIdResponseHeaderInfo.ProcessHeaders
    // in IdHTTPHeaderInfo.pas -- neither ever touches FCustomHeaders). Reading
    // an arbitrary response header like Access-Control-Allow-Origin must go
    // through RawHeaders, confirmed empirically: RawHeaders.Text showed the
    // header on the wire correctly while CustomHeaders.Values stayed empty.
    Assert.AreEqual('http://example-test.local', LHttp.Response.RawHeaders.Values['Access-Control-Allow-Origin']);
    Assert.AreEqual('true', LHttp.Response.RawHeaders.Values['Access-Control-Allow-Credentials']);
  finally
    LHttp.Free;
  end;
end;

procedure TCORSMiddlewareTests.Options_ReturnsOkWithEmptyBody;
var
  LHttp: TIdHTTP;
  LResponse: string;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LResponse := LHttp.Options(Format('http://localhost:%d/api/equivalencias', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    Assert.AreEqual('', LResponse);
  finally
    LHttp.Free;
  end;
end;

end.
