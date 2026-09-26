program PurchaseBridgeDMVC;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Web.WebReq,
  Web.WebBroker,
  IdHTTPWebBrokerBridge,
  MVCFramework.Commons,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  DMVC.WebModule.Main in 'dmvc\DMVC.WebModule.Main.pas',
  DMVC.Controllers.PingController in 'dmvc\Controllers\DMVC.Controllers.PingController.pas';

procedure RunServer(APort: Integer);
var
  LServer: TIdHTTPWebBrokerBridge;
begin
  Writeln(Format('Starting PurchaseBridge DMVC server on port %d', [APort]));
  LServer := TIdHTTPWebBrokerBridge.Create(nil);
  try
    // Sin esto, Indy (TIdHTTPServer, envuelto por TIdHTTPWebBrokerBridge)
    // intercepta el header Authorization el mismo y rechaza cualquier
    // esquema que no sea Basic/Digest con 401 "Unsupported authorization
    // scheme" ANTES de que la request llegue a WebBroker/DMVC -- por lo que
    // ningun Bearer token, ni siquiera uno valido, llegaria nunca al
    // middleware JWT. Patron verbatim del sample oficial de DMVCFramework
    // (samples\jsonwebtoken\JWTServer.dpr).
    LServer.OnParseAuthentication := TMVCParseAuthentication.OnParseAuthentication;
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
    RunServer(StrToIntDef(ParamStr(1), 9091));
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
