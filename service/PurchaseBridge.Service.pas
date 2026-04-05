unit PurchaseBridge.Service;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  Vcl.SvcMgr;

type
  TPurchaseBridgeService = class(TService)
    procedure ServiceStart(Sender: TService; var Started: Boolean);
    procedure ServiceStop(Sender: TService; var Stopped: Boolean);
  public
    function GetServiceController: TServiceController; override;
  end;

var
  PurchaseBridgeService: TPurchaseBridgeService;

implementation

uses
  ServerMain,
  uLogger;

{$R *.dfm}

procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  PurchaseBridgeService.Controller(CtrlCode);
end;

function TPurchaseBridgeService.GetServiceController: TServiceController;
begin
  Result := ServiceController;
end;

procedure TPurchaseBridgeService.ServiceStart(Sender: TService; var Started: Boolean);
begin
  try
    Log('PurchaseBridgeService iniciando...', llInfo);

    // Inicio del backend Horse en hilo separado para no bloquear el SCM.
    StartServer(True, 3, 5000);

    Log('PurchaseBridgeService iniciado.', llInfo);
    Started := True;
  except
    on E: Exception do
    begin
      Log('Error iniciando PurchaseBridgeService: ' + E.Message, llError);
      Started := False;
    end;
  end;
end;

procedure TPurchaseBridgeService.ServiceStop(Sender: TService; var Stopped: Boolean);
begin
  try
    Log('PurchaseBridgeService deteniendose...', llInfo);

    // Parada segura del backend Horse al recibir STOP del servicio.
    StopServer;

    Log('PurchaseBridgeService detenido.', llInfo);
    Stopped := True;
  except
    on E: Exception do
    begin
      Log('Error deteniendo PurchaseBridgeService: ' + E.Message, llError);
      Stopped := False;
    end;
  end;
end;

end.
