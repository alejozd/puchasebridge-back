unit XmlValidationController;

interface

procedure Registry;

implementation

uses
  Horse,
  System.JSON,
  System.SysUtils,
  System.IOUtils,
  XmlParserService,
  ValidationService;

function ParsedInvoiceToJSONString(AParsedInvoice: TParsedInvoice): string;
var
  LJSON, LProveedor, LTotales, LProducto: TJSONObject;
  LProductosArr: TJSONArray;
  I: Integer;
begin
  LJSON := TJSONObject.Create;
  try
    LProveedor := TJSONObject.Create;
    LProveedor.AddPair('nit', AParsedInvoice.Provider.NIT);
    LProveedor.AddPair('nombre', AParsedInvoice.Provider.Nombre);
    LProveedor.AddPair('nombreLegal', AParsedInvoice.Provider.NombreLegal);
    LProveedor.AddPair('tipoIdentificacion', AParsedInvoice.Provider.TipoIdentificacion);
    LProveedor.AddPair('direccion', AParsedInvoice.Provider.Direccion);
    LJSON.AddPair('proveedor', LProveedor);

    LProductosArr := TJSONArray.Create;
    for I := 0 to Length(AParsedInvoice.Products) - 1 do
    begin
      LProducto := TJSONObject.Create;
      LProducto.AddPair('idLinea', AParsedInvoice.Products[I].IDLinea);
      LProducto.AddPair('descripcion', AParsedInvoice.Products[I].Descripcion);
      LProducto.AddPair('referencia', AParsedInvoice.Products[I].Referencia);
      LProducto.AddPair('referenciaEstandar', AParsedInvoice.Products[I].ReferenciaEstandar);
      LProducto.AddPair('cantidad', TJSONNumber.Create(AParsedInvoice.Products[I].Cantidad));
      LProducto.AddPair('unidad', AParsedInvoice.Products[I].Unidad);
      LProducto.AddPair('precioBase', TJSONNumber.Create(AParsedInvoice.Products[I].PrecioBase));
      LProducto.AddPair('valorUnitario', TJSONNumber.Create(AParsedInvoice.Products[I].ValorUnitario));
      LProducto.AddPair('valorTotal', TJSONNumber.Create(AParsedInvoice.Products[I].ValorTotal));
      LProducto.AddPair('impuesto', TJSONNumber.Create(AParsedInvoice.Products[I].Impuesto));
      LProducto.AddPair('porcentajeImpuesto', TJSONNumber.Create(AParsedInvoice.Products[I].ImpuestoPorcentaje));
      LProductosArr.Add(LProducto);
    end;
    LJSON.AddPair('productos', LProductosArr);

    LTotales := TJSONObject.Create;
    LTotales.AddPair('subtotal', TJSONNumber.Create(AParsedInvoice.Totals.Subtotal));
    LTotales.AddPair('taxExclusiveAmount', TJSONNumber.Create(AParsedInvoice.Totals.TaxExclusiveAmount));
    LTotales.AddPair('taxInclusiveAmount', TJSONNumber.Create(AParsedInvoice.Totals.TaxInclusiveAmount));
    LTotales.AddPair('impuestoTotal', TJSONNumber.Create(AParsedInvoice.Totals.ImpuestoTotal));
    LTotales.AddPair('total', TJSONNumber.Create(AParsedInvoice.Totals.Total));
    LJSON.AddPair('totales', LTotales);

    Result := LJSON.ToJSON;
  finally
    LJSON.Free;
  end;
end;

procedure Validate(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LFileName, LPath, LFullFile, LXMLContent, LParsedJSONStr, LValidationResult: string;
  LParsedInvoice: TParsedInvoice;
  LErrorResponse: TJSONObject;
begin
  try
    LBody := Req.Body<TJSONObject>;
    if (LBody = nil) or not LBody.TryGetValue('fileName', LFileName) then
    begin
      LErrorResponse := TJSONObject.Create;
      LErrorResponse.AddPair('success', TJSONBool.Create(False));
      LErrorResponse.AddPair('message', 'fileName is required in the body');
      Res.Status(400).Send(LErrorResponse);
      Exit;
    end;

    LFileName := TPath.GetFileName(LFileName);
    LPath := TPath.Combine('PurchaseBridge', 'Input');
    LFullFile := TPath.Combine(LPath, LFileName);

    if not TFile.Exists(LFullFile) then
    begin
      LErrorResponse := TJSONObject.Create;
      LErrorResponse.AddPair('success', TJSONBool.Create(False));
      LErrorResponse.AddPair('message', 'Archivo no encontrado');
      Res.Status(404).Send(LErrorResponse);
      Exit;
    end;

    try
      LXMLContent := TFile.ReadAllText(LFullFile, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        LErrorResponse := TJSONObject.Create;
        LErrorResponse.AddPair('success', TJSONBool.Create(False));
        LErrorResponse.AddPair('message', 'Error reading file: ' + E.Message);
        Res.Status(500).Send(LErrorResponse);
        Exit;
      end;
    end;

    try
      LParsedInvoice := TXmlParserService.Parse(LXMLContent);
      LParsedJSONStr := ParsedInvoiceToJSONString(LParsedInvoice);
    except
      on E: Exception do
      begin
        LErrorResponse := TJSONObject.Create;
        LErrorResponse.AddPair('success', TJSONBool.Create(False));
        LErrorResponse.AddPair('message', 'XML inválido o error en parseo: ' + E.Message);
        Res.Status(422).Send(LErrorResponse);
        Exit;
      end;
    end;

    try
      LValidationResult := ValidarDocumento(LParsedJSONStr);
      Res.Send<TJSONObject>(TJSONObject.ParseJSONValue(LValidationResult) as TJSONObject);
    except
      on E: Exception do
      begin
        LErrorResponse := TJSONObject.Create;
        LErrorResponse.AddPair('success', TJSONBool.Create(False));
        LErrorResponse.AddPair('message', 'Error en validación: ' + E.Message);
        Res.Status(500).Send(LErrorResponse);
      end;
    end;
  except
    on E: Exception do
    begin
      LErrorResponse := TJSONObject.Create;
      LErrorResponse.AddPair('success', TJSONBool.Create(False));
      LErrorResponse.AddPair('message', 'Unexpected error: ' + E.Message);
      Res.Status(500).Send(LErrorResponse);
    end;
  end;
end;

procedure Registry;
begin
  THorse.Post('/xml/validate', Validate);
end;

end.
