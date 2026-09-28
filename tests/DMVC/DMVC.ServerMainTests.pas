unit DMVC.ServerMainTests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDMVCServerMainTests = class
  public
    // NOTE on test port: DMVC.ServerMain.StartServer keeps EXACT signature
    // parity with Horse's ServerMain.StartServer (no port parameter) --
    // required for Task 3's Windows Service wrapper to call it unchanged.
    // Instead of binding the real production port (9000), this test sets
    // DMVC.ServerMain.GTestPortOverride to a dedicated test-only port (9098),
    // distinct from the 9091 used by the rest of the suite (TTestServerProcess)
    // and the 9099 used by Task 1's DMVC.ServerBootstrapTests.
    [Test]
    procedure StartServer_Background_ThenStop_NoException;

    // NOTE: StartServer_RetriesOnFailure (retry-count verification when the
    // configured port is already occupied) is NOT automated here. Attempts to
    // reliably force TIdHTTPWebBrokerBridge.Active := True to fail by
    // pre-binding another bridge instance to the same test port proved
    // unreliable in local runs (Indy/Winsock socket reuse semantics on
    // Windows do not consistently raise on the second bind attempt within
    // the same process, making the resulting test flaky). Per the plan's
    // explicit fallback instruction, this is documented as a manual
    // verification step instead:
    //   1. Start any process listening on DMVC.ServerBootstrap.DEFAULT_DMVC_PORT
    //      (e.g. run PurchaseBridgeDMVC.exe on port 9000).
    //   2. Call DMVC.ServerMain.StartServer(False, 3, 500) from a second
    //      process/instance.
    //   3. Observe (via uLogger output) 3 logged "startup attempt" failures
    //      before the exception is re-raised, matching AMaxStartAttempts.
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  DMVC.ServerMain;

const
  TEST_ONLY_PORT = 9098;

procedure TDMVCServerMainTests.StartServer_Background_ThenStop_NoException;
var
  LDeadline: TDateTime;
  LIsRunning: Boolean;
begin
  DMVC.ServerMain.GTestPortOverride := TEST_ONLY_PORT;
  try
    Assert.WillNotRaise(
      procedure
      begin
        DMVC.ServerMain.StartServer(True, 1, 100);
      end);

    LIsRunning := False;
    LDeadline := IncSecond(Now, 5);
    while Now < LDeadline do
    begin
      if DMVC.ServerMain.IsServerRunning then
      begin
        LIsRunning := True;
        Break;
      end;
      Sleep(50);
    end;

    Assert.IsTrue(LIsRunning, 'Expected IsServerRunning to become True within the timeout');

    Assert.WillNotRaise(
      procedure
      begin
        DMVC.ServerMain.StopServer;
      end);

    Assert.IsFalse(DMVC.ServerMain.IsServerRunning);
  finally
    DMVC.ServerMain.GTestPortOverride := 0;
  end;
end;

end.
