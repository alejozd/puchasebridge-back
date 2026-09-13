unit DMVC.WebModule.Main;

interface

uses
  System.SysUtils, System.Classes, Web.HTTPApp,
  MVCFramework;

type
  TPurchaseBridgeDMVCWebModule = class(TWebModule)
  private
    FEngine: TMVCEngine;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  WebModuleClass: TComponentClass = TPurchaseBridgeDMVCWebModule;

implementation

uses
  DMVC.Controllers.PingController;

constructor TPurchaseBridgeDMVCWebModule.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEngine := TMVCEngine.Create(Self);
  FEngine.AddController(TPingController);
end;

destructor TPurchaseBridgeDMVCWebModule.Destroy;
begin
  FEngine.Free;
  inherited;
end;

end.
