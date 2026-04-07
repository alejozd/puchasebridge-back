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
  ProductoRepository,
  ErrorResponseUtils;

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
  try
    XMLContent := Req.Body;
    if XMLContent = '' then
    begin
      SendErrorResponse(Res, 400, 'Cuerpo XML vacío');
      Exit;
    end;

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
    begin
      LogError(E.Message);
      SendErrorResponse(Res, 500, 'Error interno del servidor', E.Message);
    end;
  end;
end;

procedure Registry;
begin
  THorse.Post('/api/factura/xml', PostFacturaXML);
end;

end.
