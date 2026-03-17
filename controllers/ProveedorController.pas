unit ProveedorController;

interface

procedure Registry;

implementation

uses
  Horse,
  ProveedorRepository,
  System.JSON,
  System.SysUtils;

procedure GetProveedor(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Nit, Anio: string;
  Proveedor: TProveedorInfo;
  Obj: TJSONObject;
begin
  Nit := Req.Params['nit'];
  Anio := Req.Query['anio'];

  Proveedor := ObtenerProveedorPorNit(Nit, Anio);

  Obj := TJSONObject.Create;
  Obj.AddPair('existe', TJSONBool.Create(Proveedor.Existe));
  if Proveedor.Existe then
    Obj.AddPair('codigo', Proveedor.Codigo);

  Res.Send(Obj);
end;

procedure Registry;
begin
  THorse.Get('/proveedor/:nit', GetProveedor);
end;

end.
