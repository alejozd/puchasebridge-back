unit DMVC.Controllers.ImportController;

interface

uses
  MVCFramework, MVCFramework.Commons;

type
  [MVCPath('/')]
  TImportController = class(TMVCController)
  public
    [MVCPath('/factura/xml')]
    [MVCHTTPMethod([httpPOST])]
    procedure PostFacturaXML;
  end;

implementation

uses
  System.SysUtils, System.JSON,
  Xml.xmldom, Xml.adomxmldom,
  XMLFacturaService, ProveedorRepository, ProductoRepository, uLogger;

procedure TImportController.PostFacturaXML;
var
  LXMLContent: string;
  LFactura: TFacturaXML;
  LResponseJSON, LProveedorJSON, LProductoJSON: TJSONObject;
  LProductosArray: TJSONArray;
  I: Integer;
  LProveedor: TProveedorInfo;
  LExisteProducto: Boolean;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  try
    LXMLContent := Context.Request.Body;
    if LXMLContent = '' then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Cuerpo XML vacío');

    LFactura := TXMLFacturaService.Parsear(LXMLContent);

    LResponseJSON := TJSONObject.Create;
    try
      LProveedor := ObtenerProveedorPorNit(LFactura.NitProveedor, LFactura.Anio);
      LProveedorJSON := TJSONObject.Create;
      LProveedorJSON.AddPair('nit', LFactura.NitProveedor);
      LProveedorJSON.AddPair('existe', TJSONBool.Create(LProveedor.Existe));
      if LProveedor.Existe then
        LProveedorJSON.AddPair('codigo', LProveedor.Codigo);
      LResponseJSON.AddPair('proveedor', LProveedorJSON);

      LProductosArray := TJSONArray.Create;
      for I := 0 to Length(LFactura.Productos) - 1 do
      begin
        LExisteProducto := ExisteProducto(LFactura.Productos[I].Referencia, LFactura.Productos[I].Descripcion, LFactura.Anio);

        LProductoJSON := TJSONObject.Create;
        LProductoJSON.AddPair('referencia', LFactura.Productos[I].Referencia);
        LProductoJSON.AddPair('descripcion', LFactura.Productos[I].Descripcion);
        LProductoJSON.AddPair('existe', TJSONBool.Create(LExisteProducto));
        LProductosArray.AddElement(LProductoJSON);
      end;
      LResponseJSON.AddPair('productos', LProductosArray);

      Render(LResponseJSON.ToJSON);
    finally
      LResponseJSON.Free;
    end;
  except
    on E: EMVCException do
      raise;
    on E: Exception do
    begin
      uLogger.LogError(E.Message, 'error_response');
      raise EMVCException.Create(HTTP_STATUS.InternalServerError, 'Error interno del servidor: ' + E.Message);
    end;
  end;
end;

initialization
  // XMLFacturaService.Parsear usa Xml.XMLDoc.LoadXMLData, que sin un DOMVendor
  // por defecto explicito cae en MSXML (COM), no instalado en este entorno de
  // build/test ("Microsoft MSXML is not installed"). XmlValidationController
  // (Task 3) evita esto seteando el vendor por instancia en XmlParserService;
  // XMLFacturaService.pas es un archivo Horse que no se puede tocar (Global
  // Constraints), asi que se fuerza ADOM como vendor por defecto a nivel de
  // proceso desde este controller, que ya depende de XMLFacturaService.
  Xml.xmldom.DefaultDOMVendor := Xml.adomxmldom.sAdom4XmlVendor;

end.
