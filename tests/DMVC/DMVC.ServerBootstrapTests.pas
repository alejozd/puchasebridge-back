unit DMVC.ServerBootstrapTests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDMVCServerBootstrapTests = class
  public
    [Test]
    procedure InitializeServerDependencies_DoesNotRaise_WhenLicenciaSectionMissing;

    [Test]
    procedure CreateAndActivateServer_ThenFree_DoesNotRaise;
  end;

implementation

uses
  System.SysUtils,
  IdHTTPWebBrokerBridge,
  DMVC.ServerBootstrap;

const
  TEST_ONLY_PORT = 9099;

procedure TDMVCServerBootstrapTests.InitializeServerDependencies_DoesNotRaise_WhenLicenciaSectionMissing;
begin
  Assert.WillNotRaise(
    procedure
    begin
      DMVC.ServerBootstrap.InitializeServerDependencies;
    end);
end;

procedure TDMVCServerBootstrapTests.CreateAndActivateServer_ThenFree_DoesNotRaise;
var
  LServer: TIdHTTPWebBrokerBridge;
begin
  LServer := nil;
  try
    Assert.WillNotRaise(
      procedure
      begin
        LServer := DMVC.ServerBootstrap.CreateAndActivateServer(TEST_ONLY_PORT);
      end);

    Assert.IsNotNull(LServer);
    Assert.IsTrue(LServer.Active);
  finally
    if Assigned(LServer) then
    begin
      LServer.Active := False;
      LServer.Free;
    end;
  end;
end;

end.
