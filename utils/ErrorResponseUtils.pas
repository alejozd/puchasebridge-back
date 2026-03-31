unit ErrorResponseUtils;

interface

uses
  Horse,
  System.JSON,
  System.SysUtils;

procedure LogError(const AMessage: string);
procedure SendErrorResponse(const Res: THorseResponse; const AStatus: Integer; const AMessage: string; const ADetail: string = '');

implementation

procedure LogError(const AMessage: string);
begin
  Writeln(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' [ERROR] ' + AMessage);
end;

procedure SendErrorResponse(const Res: THorseResponse; const AStatus: Integer; const AMessage: string; const ADetail: string = '');
var
  LResponse: TJSONObject;
begin
  LResponse := TJSONObject.Create;
  LResponse.AddPair('success', TJSONBool.Create(False));
  LResponse.AddPair('message', AMessage);

  if not ADetail.Trim.IsEmpty then
    LResponse.AddPair('detail', ADetail);

  Res.Status(AStatus).Send(LResponse);
end;

end.
