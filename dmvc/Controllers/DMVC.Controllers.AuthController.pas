unit DMVC.Controllers.AuthController;

interface

uses
  MVCFramework, MVCFramework.Commons;

type
  [MVCPath('/')]
  TAuthController = class(TMVCController)
  public
    [MVCPath('/api/auth/me')]
    [MVCHTTPMethod([httpGET])]
    procedure GetMe;
  end;

implementation

uses
  System.JSON;

procedure TAuthController.GetMe;
var
  LResponse: TJSONObject;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  LResponse := TJSONObject.Create;
  try
    LResponse.AddPair('codigo', Context.LoggedUser.CustomData['codigo']);
    LResponse.AddPair('nombre', Context.LoggedUser.CustomData['nombre']);
    Render(LResponse.ToJSON);
  finally
    LResponse.Free;
  end;
end;

end.
