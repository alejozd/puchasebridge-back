unit LicenseMiddleware;

interface

uses
  Horse,
  System.SysUtils,
  System.JSON,
  LicenseService,
  ErrorResponseUtils;

function LicenseGuard: THorseCallback;

implementation

function LicenseGuard: THorseCallback;
begin
  Result :=
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LPath: string;
      LIsValid: Boolean;
    begin
      LPath := Req.RawWebRequest.PathInfo;

      // Permitir siempre el acceso a los endpoints de licencia para poder activar/ver estado
      if LPath.Contains('/licencia') or LPath.StartsWith('/ping') then
        Exit;

      if not TLicenciaService.SistemaBloqueado then
        Exit;

      Res.Status(403).Send(TJSONObject.Create
        .AddPair('ok', TJSONBool.Create(False))
        .AddPair('mensaje', TJSONString.Create('Sistema bloqueado por licencia expirada'))
      );
      raise EHorseCallbackInterrupted.Create;
    end;
end;

end.
