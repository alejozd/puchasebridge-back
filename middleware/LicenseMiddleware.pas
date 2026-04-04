unit LicenseMiddleware;

interface

uses
  Horse,
  System.SysUtils,
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
      if LPath.StartsWith('/licencia') or LPath.StartsWith('/ping') then
      begin
        Next();
        Exit;
      end;

      LIsValid := False;
      if Assigned(TLicenciaService.LicenciaActual) then
      begin
        // Solo permitir si el estado es 'activa' o 'demo' Y no requiere reactivacion
        if (TLicenciaService.LicenciaActual.Estado = 'activa') or
           (TLicenciaService.LicenciaActual.Estado = 'demo') then
        begin
           // Si no es permanente, verificar que aun tenga dias o no haya expirado
           if TLicenciaService.LicenciaActual.EsPermanente then
             LIsValid := True
           else if (TLicenciaService.LicenciaActual.DiasRestantes > 0) or
                   (Date <= TLicenciaService.LicenciaActual.Expira) then
             LIsValid := True;
        end;
      end;

      if LIsValid then
        Next()
      else
        SendErrorResponse(Res, 403, 'Licencia Invalida o Expirada',
          'El sistema requiere una licencia activa para funcionar. Por favor, contacte a soporte o renueve su suscripcion.');
    end;
end;

end.
