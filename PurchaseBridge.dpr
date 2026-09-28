program PurchaseBridge;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  IdHTTPWebBrokerBridge,
  DMVC.ServerBootstrap in 'dmvc\DMVC.ServerBootstrap.pas',
  DMVC.WebModule.Main in 'dmvc\DMVC.WebModule.Main.pas',
  DMVC.Controllers.PingController in 'dmvc\Controllers\DMVC.Controllers.PingController.pas';

procedure RunServer(APort: Integer);
var
  LServer: TIdHTTPWebBrokerBridge;
begin
  Writeln(Format('Starting PurchaseBridge DMVC server on port %d', [APort]));
  DMVC.ServerBootstrap.InitializeServerDependencies;
  LServer := DMVC.ServerBootstrap.CreateAndActivateServer(APort);
  try
    Readln;
  finally
    LServer.Free;
  end;
end;

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    RunServer(StrToIntDef(ParamStr(1), 9000));
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
