unit ImportController;

interface

procedure Registry;

implementation

uses
  Horse,
  System.JSON,
  System.SysUtils,
  XMLFacturaService,
  ProveedorRepository,
  ProductoRepository;

procedure PostFacturaXML(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  XMLContent: string;
  Factura: TFacturaXML;
  ResponseJSON, ProveedorJSON, ProductoJSON: TJSONObject;
  ProductosArray: TJSONArray;
  I: Integer;
  Proveedor: TProveedorInfo;
  ExisteProductoVar: Boolean;
begin
  XMLContent := Req.Body;
  if XMLContent = '' then
  begin
    Res.Status(400).Send('Cuerpo XML vac' + #237 + 'o');
    Exit;
  end;

  try
    Factura := TXMLFacturaService.Parsear(XMLContent);

    ResponseJSON := TJSONObject.Create;

    // Validate Provider
    Proveedor := ObtenerProveedorPorNit(Factura.NitProveedor, Factura.Anio);
    ProveedorJSON := TJSONObject.Create;
    ProveedorJSON.AddPair('nit', Factura.NitProveedor);
    ProveedorJSON.AddPair('existe', TJSONBool.Create(Proveedor.Existe));
    if Proveedor.Existe then
      ProveedorJSON.AddPair('codigo', Proveedor.Codigo);
    ResponseJSON.AddPair('proveedor', ProveedorJSON);

    // Validate Products
    ProductosArray := TJSONArray.Create;
    for I := 0 to Length(Factura.Productos) - 1 do
    begin
      ExisteProductoVar := ExisteProducto(Factura.Productos[I].Referencia, Factura.Productos[I].Descripcion, Factura.Anio);

      ProductoJSON := TJSONObject.Create;
      ProductoJSON.AddPair('referencia', Factura.Productos[I].Referencia);
      ProductoJSON.AddPair('descripcion', Factura.Productos[I].Descripcion);
      ProductoJSON.AddPair('existe', TJSONBool.Create(ExisteProductoVar));
      ProductosArray.AddElement(ProductoJSON);
    end;
    ResponseJSON.AddPair('productos', ProductosArray);

    Res.Send(ResponseJSON);
  except
    on E: Exception do
      Res.Status(500).Send('Error procesando XML: ' + E.Message);
  end;
end;

procedure Registry;
begin
  THorse
    .Post('/factura/xml', PostFacturaXML);
end;

end.
