unit DMVC.Controllers.XmlValidationController;

interface

uses
  MVCFramework, MVCFramework.Commons;

type
  [MVCPath('/')]
  TXmlValidationController = class(TMVCController)
  public
    [MVCPath('/xml/validate')]
    [MVCPath('/api/xml/validate')]
    [MVCHTTPMethod([httpPOST])]
    procedure Validate;

    [MVCPath('/xml/validate/batch')]
    [MVCPath('/api/xml/validate/batch')]
    [MVCHTTPMethod([httpPOST])]
    procedure ValidateBatch;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Classes,
  XmlParserService, XmlPersistenceService, ValidationService, uPaths;

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
      LProducto.AddPair('unidadXML', AParsedInvoice.Products[I].Unidad);
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
    Result.Free;
    raise;
  end;
end;

function InternalValidateFile(const AFileName: string): TJSONObject;
var
  LPath, LFullFile, LXMLContent, LParsedJSONStr, LValidationResult: string;
  LParsedInvoice: TParsedInvoice;
  LParsedObj: TJSONObject;
  LErroresArray: TJSONArray;
  LVal: TJSONValue;
begin
  try
    LPath := GetInputPath;
    LFullFile := TPath.Combine(LPath, AFileName);

    if not TFile.Exists(LFullFile) then
    begin
      Result := TJSONObject.Create;
      Result.AddPair('fileName', AFileName);
      Result.AddPair('valido', TJSONBool.Create(False));
      Result.AddPair('requiereHomologacion', TJSONBool.Create(False));
      Result.AddPair('proveedorExiste', TJSONBool.Create(False));
      Result.AddPair('productos', TJSONArray.Create);
      LErroresArray := TJSONArray.Create;
      LErroresArray.Add('Archivo no encontrado');
      Result.AddPair('errores', LErroresArray);
      Exit;
    end;

    try
      LXMLContent := TFile.ReadAllText(LFullFile, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        Result := TJSONObject.Create;
        Result.AddPair('fileName', AFileName);
        Result.AddPair('valido', TJSONBool.Create(False));
        Result.AddPair('requiereHomologacion', TJSONBool.Create(False));
        Result.AddPair('proveedorExiste', TJSONBool.Create(False));
        Result.AddPair('productos', TJSONArray.Create);
        LErroresArray := TJSONArray.Create;
        LErroresArray.Add('Error al leer el archivo: ' + E.Message);
        Result.AddPair('errores', LErroresArray);
        Exit;
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
        Result := TJSONObject.Create;
        Result.AddPair('fileName', AFileName);
        Result.AddPair('valido', TJSONBool.Create(False));
        Result.AddPair('requiereHomologacion', TJSONBool.Create(False));
        Result.AddPair('proveedorExiste', TJSONBool.Create(False));
        Result.AddPair('productos', TJSONArray.Create);
        LErroresArray := TJSONArray.Create;
        LErroresArray.Add('XML inválido o error en parseo: ' + E.Message);
        Result.AddPair('errores', LErroresArray);
        Exit;
      end;
    end;

    try
      LValidationResult := ValidarDocumento(LParsedJSONStr);

      try
        UpsertXMLInvoice(AFileName, LParsedInvoice);
      except
        // Non-blocking error for staging
      end;

      LVal := TJSONObject.ParseJSONValue(LValidationResult);
      if LVal is TJSONObject then
      begin
        Result := LVal as TJSONObject;
        if Result.GetValue('fileName') = nil then
          Result.AddPair('fileName', AFileName);
      end
      else
      begin
        if Assigned(LVal) then LVal.Free;
        Result := TJSONObject.Create;
        Result.AddPair('fileName', AFileName);
        Result.AddPair('valido', TJSONBool.Create(False));
        Result.AddPair('requiereHomologacion', TJSONBool.Create(False));
        Result.AddPair('proveedorExiste', TJSONBool.Create(False));
        Result.AddPair('productos', TJSONArray.Create);
        LErroresArray := TJSONArray.Create;
        LErroresArray.Add('Error al procesar el resultado de validación');
        Result.AddPair('errores', LErroresArray);
      end;
    except
      on E: Exception do
      begin
        Result := TJSONObject.Create;
        Result.AddPair('fileName', AFileName);
        Result.AddPair('valido', TJSONBool.Create(False));
        Result.AddPair('requiereHomologacion', TJSONBool.Create(False));
        Result.AddPair('proveedorExiste', TJSONBool.Create(False));
        Result.AddPair('productos', TJSONArray.Create);
        LErroresArray := TJSONArray.Create;
        LErroresArray.Add('Error en validación: ' + E.Message);
        Result.AddPair('errores', LErroresArray);
      end;
    end;
  except
    on E: Exception do
    begin
      Result := TJSONObject.Create;
      Result.AddPair('fileName', AFileName);
      Result.AddPair('valido', TJSONBool.Create(False));
      Result.AddPair('requiereHomologacion', TJSONBool.Create(False));
      Result.AddPair('proveedorExiste', TJSONBool.Create(False));
      Result.AddPair('productos', TJSONArray.Create);
      LErroresArray := TJSONArray.Create;
      LErroresArray.Add('Error inesperado: ' + E.Message);
      Result.AddPair('errores', LErroresArray);
    end;
  end;
end;

procedure TXmlValidationController.Validate;
var
  LBody: TJSONObject;
  LFileName: string;
  LHasFileName: Boolean;
  LResultJSON: TJSONObject;
  LErroresArr: TJSONArray;
  LJsonStr: string;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  try
    LBody := TJSONObject.ParseJSONValue(Context.Request.Body) as TJSONObject;
    try
      LHasFileName := Assigned(LBody) and LBody.TryGetValue('fileName', LFileName);
    finally
      LBody.Free;
    end;

    if not LHasFileName then
    begin
      LResultJSON := TJSONObject.Create;
      try
        LResultJSON.AddPair('fileName', TJSONNull.Create);
        LResultJSON.AddPair('valido', TJSONBool.Create(False));
        LResultJSON.AddPair('requiereHomologacion', TJSONBool.Create(False));
        LErroresArr := TJSONArray.Create;
        LErroresArr.Add('fileName is required in the body');
        LResultJSON.AddPair('errores', LErroresArr);
        LJsonStr := LResultJSON.ToJSON;
        Render(HTTP_STATUS.BadRequest, LJsonStr);
      finally
        LResultJSON.Free;
      end;
      Exit;
    end;

    LFileName := TPath.GetFileName(LFileName);
    LResultJSON := InternalValidateFile(LFileName);
    try
      Render(LResultJSON.ToJSON);
    finally
      LResultJSON.Free;
    end;
  except
    on E: Exception do
    begin
      LResultJSON := TJSONObject.Create;
      try
        LResultJSON.AddPair('fileName', TJSONNull.Create);
        LResultJSON.AddPair('valido', TJSONBool.Create(False));
        LResultJSON.AddPair('requiereHomologacion', TJSONBool.Create(False));
        LErroresArr := TJSONArray.Create;
        LErroresArr.Add('Error inesperado: ' + E.Message);
        LResultJSON.AddPair('errores', LErroresArr);
        LJsonStr := LResultJSON.ToJSON;
        Render(HTTP_STATUS.InternalServerError, LJsonStr);
      finally
        LResultJSON.Free;
      end;
    end;
  end;
end;

procedure TXmlValidationController.ValidateBatch;
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
  ContentType := TMVCMediaType.APPLICATION_JSON;
  LFiles := TStringList.Create;
  try
    LBody := TJSONObject.ParseJSONValue(Context.Request.Body) as TJSONObject;
    try
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
    finally
      LBody.Free;
    end;

    if LFiles.Count = 0 then
    begin
      LPath := GetInputPath;
      if TDirectory.Exists(LPath) then
      begin
        for LFileName in TDirectory.GetFiles(LPath, '*.xml') do
          LFiles.Add(TPath.GetFileName(LFileName));
      end;
    end;

    LOutputJSON := TJSONObject.Create;
    try
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

      Render(LOutputJSON.ToJSON);
    finally
      LOutputJSON.Free;
    end;
  finally
    LFiles.Free;
  end;
end;

end.
