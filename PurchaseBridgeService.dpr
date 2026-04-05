program PurchaseBridgeSvcHost;

uses
  Vcl.SvcMgr,
  PurchaseBridge.Service in 'service\PurchaseBridge.Service.pas',
  ServerMain in 'ServerMain.pas';

{$R *.RES}

begin
  if not Application.DelayInitialize or Application.Installing then
    Application.Initialize;
  Application.CreateForm(TPurchaseBridgeService, PurchaseBridgeService);
  Application.Run;
end.
