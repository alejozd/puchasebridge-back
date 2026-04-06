unit CORSMiddleware;

interface

uses
  Horse;

procedure ApplyDynamicCORS(Req: THorseRequest; Res: THorseResponse; Next: TProc);

implementation

uses
  System.SysUtils;

procedure ApplyDynamicCORS(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LOrigin: string;
begin
  LOrigin := Trim(Req.Headers['Origin']);

  if not LOrigin.IsEmpty then
    Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Origin', LOrigin);

  Res.RawWebResponse.SetCustomHeader('Vary', 'Origin');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Credentials', 'true');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, Accept');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');

  if SameText(Req.RawWebRequest.Method, 'OPTIONS') then
  begin
    Res.Status(THTTPStatus.OK).Send('');
    Exit;
  end;

  Next();
end;

end.
