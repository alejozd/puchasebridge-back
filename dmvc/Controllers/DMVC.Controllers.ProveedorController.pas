unit DMVC.Controllers.ProveedorController;

interface

uses
  MVCFramework, MVCFramework.Commons,
  DMVC.DTOs.Proveedor;

type
  [MVCPath('/')]
  TProveedorController = class(TMVCController)
  public
    [MVCPath('/proveedor/($nit)')]
    [MVCPath('/api/proveedor/($nit)')]
    [MVCHTTPMethod([httpGET])]
    function GetProveedor(const nit: String;
      const [MVCFromQueryString('anio', '')] AAnio: String): TProveedorDTO;
  end;

implementation

uses
  ProveedorRepository;

function TProveedorController.GetProveedor(const nit: String; const AAnio: String): TProveedorDTO;
var
  LInfo: TProveedorInfo;
begin
  LInfo := ProveedorRepository.ObtenerProveedorPorNit(nit, AAnio);
  Result := TProveedorDTO.Create;
  Result.Existe := LInfo.Existe;
  if LInfo.Existe then
    Result.Codigo := LInfo.Codigo;
end;

end.
