unit DocumentosController;

interface

procedure Registry;

implementation

uses
  Horse,
  System.JSON,
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  XmlParserService,
  ValidationService,
  DocumentoService,
  EquivalenciaService,
  AuthService,
  AuthMiddleware,
  FireDAC.Comp.Client;

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

procedure Procesar(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LFilesArr: TJSONArray;
  LFileName, LPath, LProcessedPath, LXMLContent, LParsedJSONStr, LValidationResult: string;
  LParsedInvoice: TParsedInvoice;
  LValidationObj, LProcesadoObj, LErrorObj, LResponse, LParsedObj: TJSONObject;
  LProcesadosArr, LErroresArr: TJSONArray;
  LHeader: TDocumentoHeader;
  LDetalles: TArray<TDocumentoDetalle>;
  I, J: Integer;
  LValido, LRequiereHomologacion: Boolean;
  LEquivalencia: TFDQuery;
  LFactor: Double;
  LFilesValue, LValidoVal: TJSONValue;
  LDocumentoERP, LAnio: string;
  LSession: TSessionInfo;
begin
  Res.ContentType('application/json; charset=utf-8');
  LProcesadosArr := TJSONArray.Create;
  LErroresArr := TJSONArray.Create;
  LResponse := TJSONObject.Create;

  try
    LBody := Req.Body<TJSONObject>;
    if Assigned(LBody) then
    begin
      LFilesValue := LBody.GetValue('files');
      if (LFilesValue <> nil) and (LFilesValue is TJSONArray) then
      begin
        LFilesArr := LFilesValue as TJSONArray;
        for I := 0 to LFilesArr.Count - 1 do
        begin
          LFileName := TPath.GetFileName(LFilesArr.Items[I].Value);
          LPath := TPath.Combine('PurchaseBridge', 'Input');
          LProcessedPath := TPath.Combine('PurchaseBridge', 'Processed');

          if not TDirectory.Exists(LProcessedPath) then
            TDirectory.CreateDirectory(LProcessedPath);

          if not TFile.Exists(TPath.Combine(LPath, LFileName)) then
          begin
            LErrorObj := TJSONObject.Create;
            LErrorObj.AddPair('fileName', LFileName);
            LErrorObj.AddPair('error', 'Archivo no encontrado');
            LErroresArr.Add(LErrorObj);
            Continue;
          end;

          if DocumentoExiste(LFileName) then
          begin
            LErrorObj := TJSONObject.Create;
            LErrorObj.AddPair('fileName', LFileName);
            LErrorObj.AddPair('error', 'El documento ya fue procesado anteriormente');
            LErroresArr.Add(LErrorObj);
            Continue;
          end;

          try
            LXMLContent := TFile.ReadAllText(TPath.Combine(LPath, LFileName), TEncoding.UTF8);
            LParsedInvoice := TXmlParserService.Parse(LXMLContent);

            LParsedObj := ParsedInvoiceToJSONObject(LParsedInvoice);
            try
              LParsedJSONStr := LParsedObj.ToJSON;
            finally
              LParsedObj.Free;
            end;

            LValidationResult := ValidarDocumento(LParsedJSONStr);
            LValidationObj := TJSONObject.ParseJSONValue(LValidationResult) as TJSONObject;
            if not Assigned(LValidationObj) then
               raise Exception.Create('Error parseando resultado de validación');
            try
              LValido := False;
              LValidoVal := LValidationObj.GetValue('valido');
              if (LValidoVal <> nil) and (LValidoVal is TJSONBool) then
                LValido := (LValidoVal as TJSONBool).AsBoolean;

              LRequiereHomologacion := False;
              LValidoVal := LValidationObj.GetValue('requiereHomologacion');
              if (LValidoVal <> nil) and (LValidoVal is TJSONBool) then
                LRequiereHomologacion := (LValidoVal as TJSONBool).AsBoolean;

              if LValido and not LRequiereHomologacion then
              begin
                LAnio := FormatDateTime('yyyy', LParsedInvoice.FechaEmision);

                LSession := Req.Session<TSessionInfoObj>.Data;

                LHeader.Proveedor := LParsedInvoice.Provider.NIT;
                LHeader.CodigoTercero := LValidationObj.GetValue('codigoTercero').Value;
                LHeader.Fecha := LParsedInvoice.FechaEmision;
                LHeader.Total := LParsedInvoice.Totals.Total;
                LHeader.Estado := 'PROCESADO';
                LHeader.XMLFileName := LFileName;
                LHeader.NombreUsuario := LSession.Nombre;
                LHeader.CodigoUsuario := LSession.Codigo.ToString;
                LHeader.Anio := LAnio;

                SetLength(LDetalles, Length(LParsedInvoice.Products));
                for J := 0 to Length(LParsedInvoice.Products) - 1 do
                begin
                  LDetalles[J].CodigoProducto := LParsedInvoice.Products[J].Referencia;
                  LDetalles[J].Cantidad := LParsedInvoice.Products[J].Cantidad;
                  LDetalles[J].Precio := LParsedInvoice.Products[J].ValorUnitario;
                  LDetalles[J].TfIva := LParsedInvoice.Products[J].ImpuestoPorcentaje;
                  LDetalles[J].VrIva := LParsedInvoice.Products[J].Impuesto;
                  LDetalles[J].TfDescuento := LParsedInvoice.Products[J].DescuentoPorcentaje;
                  LDetalles[J].VrDescuento := LParsedInvoice.Products[J].Descuento;
                  LDetalles[J].VrIca := 0;
                  LDetalles[J].VrReteIca := 0;
                  LDetalles[J].VrReteIva := 0;
                  LDetalles[J].VrReteFuente := 0;
                  LDetalles[J].Total := LDetalles[J].Cantidad * LDetalles[J].Precio;

                  LEquivalencia := BuscarEquivalencia(LParsedInvoice.Products[J].Referencia, LParsedInvoice.Products[J].Unidad);
                  try
                    if not LEquivalencia.IsEmpty then
                    begin
                      LFactor := LEquivalencia.FieldByName('FACTOR').AsFloat;
                      if LFactor = 0 then LFactor := 1;
                      LDetalles[J].CodigoProducto := LEquivalencia.FieldByName('REFERENCIAH').AsString;
                      LDetalles[J].Cantidad := LDetalles[J].Cantidad * LFactor;
                      LDetalles[J].CodigoConcepto := LEquivalencia.FieldByName('CODIGOH').AsInteger;
                      LDetalles[J].Subcodigo := LEquivalencia.FieldByName('SUBCODIGOH').AsInteger;
                    end;
                  finally
                    LEquivalencia.Free;
                  end;

                  LDetalles[J].Total := LDetalles[J].Cantidad * LDetalles[J].Precio;
                end;

                try
                  LDocumentoERP := GuardarDocumento(LHeader, LDetalles);

                  TFile.Move(TPath.Combine(LPath, LFileName), TPath.Combine(LProcessedPath, LFileName));

                  LProcesadoObj := TJSONObject.Create;
                  LProcesadoObj.AddPair('fileName', LFileName);
                  LProcesadoObj.AddPair('status', 'OK');
                  LProcesadoObj.AddPair('documento', LDocumentoERP);
                  LProcesadosArr.Add(LProcesadoObj);
                except
                  on E: Exception do
                  begin
                    LErrorObj := TJSONObject.Create;
                    LErrorObj.AddPair('fileName', LFileName);
                    LErrorObj.AddPair('error', 'Error al guardar en BD: ' + E.Message);
                    LErroresArr.Add(LErrorObj);
                  end;
                end;
              end
              else
              begin
                LErrorObj := TJSONObject.Create;
                LErrorObj.AddPair('fileName', LFileName);
                if LRequiereHomologacion then
                  LErrorObj.AddPair('error', 'Requiere homologación de productos')
                else
                  LErrorObj.AddPair('error', 'Documento inválido para procesar');
                LErroresArr.Add(LErrorObj);
              end;
            finally
              LValidationObj.Free;
            end;

          except
            on E: Exception do
            begin
              LErrorObj := TJSONObject.Create;
              LErrorObj.AddPair('fileName', LFileName);
              LErrorObj.AddPair('error', 'Error procesando archivo: ' + E.Message);
              LErroresArr.Add(LErrorObj);
            end;
          end;
        end;
      end;
    end;

    LResponse.AddPair('procesados', LProcesadosArr);
    LResponse.AddPair('errores', LErroresArr);
    Res.Send<TJSONObject>(LResponse);

  except
    on E: Exception do
    begin
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', E.Message);
      Res.Status(500).Send(LResponse);
    end;
  end;
end;

procedure Registry;
begin
  THorse.Post('/documentos/procesar', Procesar);
end;

end.
