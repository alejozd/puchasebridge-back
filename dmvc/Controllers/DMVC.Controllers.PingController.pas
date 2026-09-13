unit DMVC.Controllers.PingController;

interface

uses
  MVCFramework, MVCFramework.Commons;

type
  [MVCPath('/ping')]
  TPingController = class(TMVCController)
  public
    [MVCPath]
    [MVCHTTPMethod([httpGET])]
    procedure Ping;
  end;

implementation

uses
  System.JSON;

procedure TPingController.Ping;
begin
  Render(TJSONObject.Create.AddPair('status', 'ok'));
end;

end.
