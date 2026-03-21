unit XmlValidationController;

interface

procedure Registry;

implementation

uses
  Horse,
  System.JSON,
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Collections,
  XmlParserService,
  XmlPersistenceService,
  ValidationService;

function ParsedInvoiceToJSONObject(const AParsedInvoice: TParsedInvoice): TJSONObject;
var
  LProveedor, LTotales, LProducto: TJSONObject;
  LProductosArr: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  try
    LProveedor := TJSONObject.Create;
    LProveedor.AddPair('nit', AParsedInvoice.Provider.NIT);
    LProveedor.AddPair('nombre', AParsedInvoice.Provider.Nombre);
    LProveedor.AddPair('nombreLegal', AParsedInvoice.Provider.NombreLegal);
    LProveedor.AddPair('tipoIdentificacion', AParsedInvoice.Provider.TipoIdentificacion);
    LProveedor.AddPair('direccion', AParsedInvoice.Provider.Direccion);
    Result.AddPair('proveedor', LProveedor);

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
    Result.AddPair('productos', LProductosArr);

    LTotales := TJSONObject.Create;
    LTotales.AddPair('subtotal', TJSONNumber.Create(AParsedInvoice.Totals.Subtotal));
    LTotales.AddPair('taxExclusiveAmount', TJSONNumber.Create(AParsedInvoice.Totals.TaxExclusiveAmount));
    LTotales.AddPair('taxInclusiveAmount', TJSONNumber.Create(AParsedInvoice.Totals.TaxInclusiveAmount));
    LTotales.AddPair('impuestoTotal', TJSONNumber.Create(AParsedInvoice.Totals.ImpuestoTotal));
    LTotales.AddPair('total', TJSONNumber.Create(AParsedInvoice.Totals.Total));
    Result.AddPair('totales', LTotales);
  except
    on E: Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

function InternalValidateFile(const AFileName: string): TJSONObject;
var
  LPath, LFullFile, LXMLContent, LParsedJSONStr, LValidationResult: string;
  LParsedInvoice: TParsedInvoice;
  LResultJSON, LParsedObj: TJSONObject;
  LErroresArray, LEmptyProductos: TJSONArray;
  LVal: TJSONValue;
begin
  try
    LPath := TPath.Combine('PurchaseBridge', 'Input');
    LFullFile := TPath.Combine(LPath, AFileName);

    if not TFile.Exists(LFullFile) then
    begin
      LResultJSON := TJSONObject.Create;
      LResultJSON.AddPair('fileName', AFileName);
      LResultJSON.AddPair('valido', TJSONBool.Create(False));
      LResultJSON.AddPair('requiereHomologacion', TJSONBool.Create(False));
      LResultJSON.AddPair('proveedorExiste', TJSONBool.Create(False));
      LResultJSON.AddPair('productos', TJSONArray.Create);
      LErroresArray := TJSONArray.Create;
      LErroresArray.Add('Archivo no encontrado');
      LResultJSON.AddPair('errores', LErroresArray);
      Exit(LResultJSON);
    end;

    try
      LXMLContent := TFile.ReadAllText(LFullFile, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        LResultJSON := TJSONObject.Create;
        LResultJSON.AddPair('fileName', AFileName);
        LResultJSON.AddPair('valido', TJSONBool.Create(False));
        LResultJSON.AddPair('requiereHomologacion', TJSONBool.Create(False));
        LResultJSON.AddPair('proveedorExiste', TJSONBool.Create(False));
        LResultJSON.AddPair('productos', TJSONArray.Create);
        LErroresArray := TJSONArray.Create;
        LErroresArray.Add('Error al leer el archivo: ' + E.Message);
        LResultJSON.AddPair('errores', LErroresArray);
        Exit(LResultJSON);
      end;
    end;

    try
      LParsedInvoice := TXmlParserService.Parse(LXMLContent);
      LParsedObj := ParsedInvoiceToJSONObject(LParsedInvoice);
      try
        LParsedJSONStr := LParsedObj.ToJSON;
      finally
        LParsedObj.Free;
      end;
    except
      on E: Exception do
      begin
        LResultJSON := TJSONObject.Create;
        LResultJSON.AddPair('fileName', AFileName);
        LResultJSON.AddPair('valido', TJSONBool.Create(False));
        LResultJSON.AddPair('requiereHomologacion', TJSONBool.Create(False));
        LResultJSON.AddPair('proveedorExiste', TJSONBool.Create(False));
        LResultJSON.AddPair('productos', TJSONArray.Create);
        LErroresArray := TJSONArray.Create;
        LErroresArray.Add('XML inválido o error en parseo: ' + E.Message);
        LResultJSON.AddPair('errores', LErroresArray);
        Exit(LResultJSON);
      end;
    end;

    try
      LValidationResult := ValidarDocumento(LParsedJSONStr);

      // Persist the XML data into staging tables
      UpsertXMLInvoice(AFileName, LParsedInvoice);

      LVal := TJSONObject.ParseJSONValue(LValidationResult);
      if LVal is TJSONObject then
      begin
        LResultJSON := LVal as TJSONObject;
        LResultJSON.AddPair('fileName', AFileName);
      end
      else
      begin
        if Assigned(LVal) then LVal.Free;
        LResultJSON := TJSONObject.Create;
        LResultJSON.AddPair('fileName', AFileName);
        LResultJSON.AddPair('valido', TJSONBool.Create(False));
        LResultJSON.AddPair('requiereHomologacion', TJSONBool.Create(False));
        LResultJSON.AddPair('proveedorExiste', TJSONBool.Create(False));
        LResultJSON.AddPair('productos', TJSONArray.Create);
        LErroresArray := TJSONArray.Create;
        LErroresArray.Add('Error al procesar el resultado de validación');
        LResultJSON.AddPair('errores', LErroresArray);
      end;
      Result := LResultJSON;
    except
      on E: Exception do
      begin
        LResultJSON := TJSONObject.Create;
        LResultJSON.AddPair('fileName', AFileName);
        LResultJSON.AddPair('valido', TJSONBool.Create(False));
        LResultJSON.AddPair('requiereHomologacion', TJSONBool.Create(False));
        LResultJSON.AddPair('proveedorExiste', TJSONBool.Create(False));
        LResultJSON.AddPair('productos', TJSONArray.Create);
        LErroresArray := TJSONArray.Create;
        LErroresArray.Add('Error en validación: ' + E.Message);
        LResultJSON.AddPair('errores', LErroresArray);
        Result := LResultJSON;
      end;
    end;
  except
    on E: Exception do
    begin
      LResultJSON := TJSONObject.Create;
      LResultJSON.AddPair('fileName', AFileName);
      LResultJSON.AddPair('valido', TJSONBool.Create(False));
      LResultJSON.AddPair('requiereHomologacion', TJSONBool.Create(False));
      LResultJSON.AddPair('proveedorExiste', TJSONBool.Create(False));
      LResultJSON.AddPair('productos', TJSONArray.Create);
      LErroresArray := TJSONArray.Create;
      LErroresArray.Add('Error inesperado: ' + E.Message);
      LResultJSON.AddPair('errores', LErroresArray);
      Result := LResultJSON;
    end;
  end;
end;

procedure Validate(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LFileName: string;
  LResultJSON: TJSONObject;
begin
  LBody := Req.Body<TJSONObject>;
  if (LBody = nil) or not LBody.TryGetValue('fileName', LFileName) then
  begin
    LResultJSON := TJSONObject.Create;
    LResultJSON.AddPair('success', TJSONBool.Create(False));
    LResultJSON.AddPair('message', 'fileName is required in the body');
    Res.Status(400).Send(LResultJSON);
    Exit;
  end;

  LFileName := TPath.GetFileName(LFileName);
  LResultJSON := InternalValidateFile(LFileName);

  Res.Send<TJSONObject>(LResultJSON);
end;

procedure ValidateBatch(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LFilesArr: TJSONArray;
  LFiles: TStringList;
  LFileName, LPath: string;
  LOutputJSON, LSummary: TJSONObject;
  LDocumentsArr: TJSONArray;
  LResultDoc: TJSONObject;
  LValido: Boolean;
  LTotal, LValidos, LConErrores: Integer;
  I: Integer;
  LFilesValue: TJSONValue;
begin
  LFiles := TStringList.Create;
  try
    LBody := Req.Body<TJSONObject>;
    if Assigned(LBody) then
    begin
      LFilesValue := LBody.GetValue('files');
      if (LFilesValue <> nil) and (LFilesValue is TJSONArray) then
      begin
        LFilesArr := LFilesValue as TJSONArray;
        for I := 0 to LFilesArr.Count - 1 do
          LFiles.Add(TPath.GetFileName(LFilesArr.Items[I].Value));
      end;
    end;

    if LFiles.Count = 0 then
    begin
      // Take all XML files from Input folder
      LPath := TPath.Combine('PurchaseBridge', 'Input');
      if TDirectory.Exists(LPath) then
      begin
        for LFileName in TDirectory.GetFiles(LPath, '*.xml') do
          LFiles.Add(TPath.GetFileName(LFileName));
      end;
    end;

    LOutputJSON := TJSONObject.Create;
    LDocumentsArr := TJSONArray.Create;
    LTotal := LFiles.Count;
    LValidos := 0;
    LConErrores := 0;

    for I := 0 to LFiles.Count - 1 do
    begin
      LResultDoc := InternalValidateFile(LFiles[I]);

      LValido := False;
      if (LResultDoc.GetValue('valido') <> nil) and (LResultDoc.GetValue('valido') is TJSONBool) then
        LValido := (LResultDoc.GetValue('valido') as TJSONBool).AsBoolean;

      if LValido then
        Inc(LValidos)
      else
        Inc(LConErrores);

      LDocumentsArr.Add(LResultDoc);
    end;

    LOutputJSON.AddPair('documentos', LDocumentsArr);

    LSummary := TJSONObject.Create;
    LSummary.AddPair('total', TJSONNumber.Create(LTotal));
    LSummary.AddPair('validos', TJSONNumber.Create(LValidos));
    LSummary.AddPair('conErrores', TJSONNumber.Create(LConErrores));
    LOutputJSON.AddPair('resumen', LSummary);

    Res.Send<TJSONObject>(LOutputJSON);
  finally
    LFiles.Free;
  end;
end;

procedure Registry;
begin
  THorse.Post('/xml/validate', Validate);
  THorse.Post('/xml/validate/batch', ValidateBatch);
end;

end.
