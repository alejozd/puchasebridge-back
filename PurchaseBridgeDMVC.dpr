program PurchaseBridgeDMVC;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Web.WebReq,
  Web.WebBroker,
  IdHTTPWebBrokerBridge,
  DMVC.WebModule.Main in 'dmvc\DMVC.WebModule.Main.pas',
  DMVC.Controllers.PingController in 'dmvc\Controllers\DMVC.Controllers.PingController.pas';

procedure RunServer(APort: Integer);
var
  LServer: TIdHTTPWebBrokerBridge;
begin
  Writeln(Format('Starting PurchaseBridge DMVC server on port %d', [APort]));
  LServer := TIdHTTPWebBrokerBridge.Create(nil);
  try
    LServer.DefaultPort := APort;
    LServer.Active := True;
    Readln;
  finally
    LServer.Free;
  end;
end;

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    if WebRequestHandler <> nil then
      WebRequestHandler.WebModuleClass := WebModuleClass;
    WebRequestHandlerProc.MaxConnections := 1024;
    RunServer(9091);
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
