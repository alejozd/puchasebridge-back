unit XmlController;

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
  System.Generics.Defaults,
  System.Types,
  Web.HTTPApp,
  Web.ReqFiles,
  XmlParserService,
  XmlPersistenceService,
  FireDAC.Comp.Client,
  FirebirdConnection,
  EquivalenciaService,
  DianUnits;

type
  TCombinedFileInfo = record
    ID: Integer;
    FileName: string;
    Size: Int64;
    ProveedorNit: string;
    Proveedor: string;
    FechaDocumento: TDateTime;
    Estado: string;
    FechaCarga: TDateTime;
    LastModified: TDateTime;
  end;

procedure Upload(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LFile: TAbstractWebRequestFile;
  LPath, LFileName, LFullFile: string;
  LResponse: TJSONObject;
  I: Integer;
  LFound: Boolean;
  LFileStream: TFileStream;
begin
  Res.ContentType('application/json; charset=utf-8');
  LFound := False;
  LFile := nil;

  try
    for I := 0 to Req.RawWebRequest.Files.Count - 1 do
    begin
      if SameText(Req.RawWebRequest.Files[I].FieldName, 'file') then
      begin
        LFile := Req.RawWebRequest.Files[I];
        LFound := True;
        Break;
      end;
    end;

    if not LFound then
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'No file uploaded with field name "file"');
      Res.Status(400).Send(LResponse);
      Exit;
    end;

    LFileName := LFile.FileName;
    if not SameText(ExtractFileExt(LFileName), '.xml') then
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'The file must have a .xml extension');
      Res.Status(400).Send(LResponse);
      Exit;
    end;

    LPath := TPath.Combine('PurchaseBridge', 'Input');
    if not TDirectory.Exists(LPath) then
      TDirectory.CreateDirectory(LPath);

    LFullFile := TPath.Combine(LPath, LFileName);

    LFile.Stream.Position := 0;
    LFileStream := TFileStream.Create(LFullFile, fmCreate);
    try
      LFileStream.CopyFrom(LFile.Stream, LFile.Stream.Size);
    finally
      LFileStream.Free;
    end;

    LResponse := TJSONObject.Create;
    LResponse.AddPair('success', TJSONBool.Create(True));
    LResponse.AddPair('message', 'XML uploaded successfully');
    LResponse.AddPair('fileName', LFileName);
    LResponse.AddPair('path', LFullFile.Replace('\', '/'));
    Res.Send(LResponse);
  except
    on E: Exception do
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'Error saving file: ' + E.Message);
      Res.Status(500).Send(LResponse);
    end;
  end;
end;

procedure Parse(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LFileName, LPath, LFullFile: string;
  LXMLContent: string;
  LParsedInvoice: TParsedInvoice;
  LResponse: TJSONObject;
  LProveedorObj: TJSONObject;
  LTotalesObj: TJSONObject;
  LProductosArr: TJSONArray;
  LProductoObj: TJSONObject;
  I: Integer;
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    LBody := Req.Body<TJSONObject>;
    if (LBody = nil) or not LBody.TryGetValue('fileName', LFileName) then
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'fileName is required in the body');
      Res.Status(400).Send(LResponse);
      Exit;
    end;

    LFileName := TPath.GetFileName(LFileName);
    LPath := TPath.Combine('PurchaseBridge', 'Input');
    LFullFile := TPath.Combine(LPath, LFileName);

    if not TFile.Exists(LFullFile) then
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'Archivo no encontrado');
      Res.Status(404).Send(LResponse);
      Exit;
    end;

    try
      LXMLContent := TFile.ReadAllText(LFullFile, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        LResponse := TJSONObject.Create;
        LResponse.AddPair('success', TJSONBool.Create(False));
        LResponse.AddPair('message', 'Error reading file: ' + E.Message);
        Res.Status(500).Send(LResponse);
        Exit;
      end;
    end;

    try
      LParsedInvoice := TXmlParserService.Parse(LXMLContent);
    except
      on E: Exception do
      begin
        LResponse := TJSONObject.Create;
        LResponse.AddPair('success', TJSONBool.Create(False));
        LResponse.AddPair('message', 'XML inválido');
        Res.Status(422).Send(LResponse);
        Exit;
      end;
    end;

    LResponse := TJSONObject.Create;
    try
      LResponse.AddPair('success', TJSONBool.Create(True));

      LProveedorObj := TJSONObject.Create;
      LProveedorObj.AddPair('nit', LParsedInvoice.Provider.NIT);
      LProveedorObj.AddPair('nombre', LParsedInvoice.Provider.Nombre);
      LProveedorObj.AddPair('nombreLegal', LParsedInvoice.Provider.NombreLegal);
      LProveedorObj.AddPair('tipoIdentificacion', LParsedInvoice.Provider.TipoIdentificacion);
      LProveedorObj.AddPair('direccion', LParsedInvoice.Provider.Direccion);
      LResponse.AddPair('proveedor', LProveedorObj);

      LProductosArr := TJSONArray.Create;
      for I := 0 to Length(LParsedInvoice.Products) - 1 do
      begin
        LProductoObj := TJSONObject.Create;
        LProductoObj.AddPair('idLinea', LParsedInvoice.Products[I].IDLinea);
        LProductoObj.AddPair('descripcion', LParsedInvoice.Products[I].Descripcion);
        LProductoObj.AddPair('referencia', LParsedInvoice.Products[I].Referencia);
        LProductoObj.AddPair('referenciaEstandar', LParsedInvoice.Products[I].ReferenciaEstandar);
        LProductoObj.AddPair('cantidad', TJSONNumber.Create(LParsedInvoice.Products[I].Cantidad));
        LProductoObj.AddPair('unidad', LParsedInvoice.Products[I].Unidad);
        LProductoObj.AddPair('precioBase', TJSONNumber.Create(LParsedInvoice.Products[I].PrecioBase));
        LProductoObj.AddPair('valorUnitario', TJSONNumber.Create(LParsedInvoice.Products[I].ValorUnitario));
        LProductoObj.AddPair('valorTotal', TJSONNumber.Create(LParsedInvoice.Products[I].ValorTotal));
        LProductoObj.AddPair('impuesto', TJSONNumber.Create(LParsedInvoice.Products[I].Impuesto));
        LProductoObj.AddPair('porcentajeImpuesto', TJSONNumber.Create(LParsedInvoice.Products[I].ImpuestoPorcentaje));
        LProductosArr.AddElement(LProductoObj);
      end;
      LResponse.AddPair('productos', LProductosArr);

      LTotalesObj := TJSONObject.Create;
      LTotalesObj.AddPair('subtotal', TJSONNumber.Create(LParsedInvoice.Totals.Subtotal));
      LTotalesObj.AddPair('taxExclusiveAmount', TJSONNumber.Create(LParsedInvoice.Totals.TaxExclusiveAmount));
      LTotalesObj.AddPair('taxInclusiveAmount', TJSONNumber.Create(LParsedInvoice.Totals.TaxInclusiveAmount));
      LTotalesObj.AddPair('impuestoTotal', TJSONNumber.Create(LParsedInvoice.Totals.ImpuestoTotal));
      LTotalesObj.AddPair('total', TJSONNumber.Create(LParsedInvoice.Totals.Total));
      LResponse.AddPair('totales', LTotalesObj);

      Res.Send(LResponse);
    except
      LResponse.Free;
      raise;
    end;
  except
    on E: Exception do
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'Unexpected error: ' + E.Message);
      Res.Status(500).Send(LResponse);
    end;
  end;
end;

procedure GetFileById(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Q: TFDQuery;
  LFileID: Integer;
  LResponse, LProductObj: TJSONObject;
  LProductsArr: TJSONArray;
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    LFileID := StrToIntDef(Req.Params['id'], 0);
    if LFileID = 0 then
    begin
      Res.Status(400).Send('ID inválido');
      Exit;
    end;

    Q := GetBridgeQuery;
    try
      Q.SQL.Text := 'SELECT * FROM XML_FILES WHERE ID = :ID';
      Q.ParamByName('ID').AsInteger := LFileID;
      Q.Open;

      if Q.IsEmpty then
      begin
        Res.Status(404).Send('Archivo no encontrado');
        Exit;
      end;

      LResponse := TJSONObject.Create;
      LResponse.AddPair('id', TJSONNumber.Create(Q.FieldByName('ID').AsInteger));
      LResponse.AddPair('fileName', Q.FieldByName('FILE_NAME').AsString);
      LResponse.AddPair('proveedorNit', Q.FieldByName('PROVEEDOR_NIT').AsString);
      if Q.FieldByName('PROVEEDOR_NOMBRE').AsString.Trim.IsEmpty then
      begin
        LResponse.AddPair('proveedor', 'Sin proveedor');
        LResponse.AddPair('proveedorNombre', 'Sin proveedor');
      end
      else
      begin
        LResponse.AddPair('proveedor', Q.FieldByName('PROVEEDOR_NOMBRE').AsString);
        LResponse.AddPair('proveedorNombre', Q.FieldByName('PROVEEDOR_NOMBRE').AsString);
      end;
      LResponse.AddPair('fechaDocumento', FormatDateTime('yyyy-mm-dd', Q.FieldByName('FECHA_DOCUMENTO').AsDateTime));
      LResponse.AddPair('estado', Q.FieldByName('ESTADO').AsString);
      LResponse.AddPair('fechaCarga', FormatDateTime('yyyy-mm-dd HH:nn:ss', Q.FieldByName('FECHA_CARGA').AsDateTime));

      Q.Close;
      Q.SQL.Text := 'SELECT * FROM XML_PRODUCTOS WHERE XML_FILE_ID = :FILEID';
      Q.ParamByName('FILEID').AsInteger := LFileID;
      Q.Open;

      LProductsArr := TJSONArray.Create;
      while not Q.Eof do
      begin
        LProductObj := TJSONObject.Create;
        LProductObj.AddPair('id', TJSONNumber.Create(Q.FieldByName('ID').AsInteger));
        LProductObj.AddPair('descripcion', Q.FieldByName('DESCRIPCION').AsString);
        LProductObj.AddPair('referencia', Q.FieldByName('REFERENCIA').AsString);
        LProductObj.AddPair('referenciaStd', Q.FieldByName('REFERENCIA_STD').AsString);
        LProductObj.AddPair('cantidad', TJSONNumber.Create(Q.FieldByName('CANTIDAD').AsFloat));
        LProductObj.AddPair('unidad', Q.FieldByName('UNIDAD').AsString);
        LProductObj.AddPair('valorUnitario', TJSONNumber.Create(Q.FieldByName('VALOR_UNITARIO').AsFloat));
        LProductObj.AddPair('valorTotal', TJSONNumber.Create(Q.FieldByName('VALOR_TOTAL').AsFloat));
        LProductObj.AddPair('impuesto', TJSONNumber.Create(Q.FieldByName('IMPUESTO').AsFloat));

        if not Q.FieldByName('EQUIVALENCIA_ID').IsNull then
          LProductObj.AddPair('equivalenciaId', TJSONNumber.Create(Q.FieldByName('EQUIVALENCIA_ID').AsInteger))
        else
          LProductObj.AddPair('equivalenciaId', TJSONNull.Create);

        LProductsArr.AddElement(LProductObj);
        Q.Next;
      end;
      LResponse.AddPair('productos', LProductsArr);

      Res.Send(LResponse);
    finally
      Q.Free;
    end;
  except
    on E: Exception do
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', E.Message);
      Res.Status(500).Send(LResponse);
    end;
  end;
end;

procedure ProcesarBatch(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Q: TFDQuery;
  LBody: TJSONObject;
  LIdsArr: TJSONArray;
  LId: Integer;
  I: Integer;
  LResponse, LProcesadoObj, LErrorObj: TJSONObject;
  LProcesadosArr, LErroresArr: TJSONArray;
  LHasPendientes: Boolean;
begin
  Res.ContentType('application/json; charset=utf-8');
  LBody := Req.Body<TJSONObject>;
  if (LBody = nil) or not LBody.TryGetValue('ids', LIdsArr) then
  begin
    Res.Status(400).Send('ids is required');
    Exit;
  end;

  LProcesadosArr := TJSONArray.Create;
  LErroresArr := TJSONArray.Create;
  LResponse := TJSONObject.Create;

  try
    Q := GetBridgeQuery;
    try
      for I := 0 to LIdsArr.Count - 1 do
      begin
        LId := StrToIntDef(LIdsArr.Items[I].Value, 0);
        if LId = 0 then Continue;

        // 1. Check if all products have equivalencies
        Q.SQL.Text := 'SELECT COUNT(*) as TOTAL FROM XML_PRODUCTOS WHERE XML_FILE_ID = :FILEID AND EQUIVALENCIA_ID IS NULL';
        Q.ParamByName('FILEID').AsInteger := LId;
        Q.Open;
        LHasPendientes := Q.FieldByName('TOTAL').AsInteger > 0;
        Q.Close;

        if LHasPendientes then
        begin
          LErrorObj := TJSONObject.Create;
          LErrorObj.AddPair('id', TJSONNumber.Create(LId));
          LErrorObj.AddPair('error', 'Tiene productos sin equivalencia');
          LErroresArr.AddElement(LErrorObj);
        end
        else
        begin
          // 2. Simulate processing (setting state to PROCESADO)
          Q.SQL.Text := 'UPDATE XML_FILES SET ESTADO = ''PROCESADO'', FECHA_PROCESO = CURRENT_TIMESTAMP WHERE ID = :ID';
          Q.ParamByName('ID').AsInteger := LId;
          Q.ExecSQL;

          LProcesadoObj := TJSONObject.Create;
          LProcesadoObj.AddPair('id', TJSONNumber.Create(LId));
          LProcesadoObj.AddPair('status', 'OK');
          LProcesadosArr.AddElement(LProcesadoObj);
        end;
      end;

      LResponse.AddPair('procesados', LProcesadosArr);
      LResponse.AddPair('errores', LErroresArr);
      Res.Send(LResponse);
    finally
      Q.Free;
    end;
  except
    on E: Exception do
    begin
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', E.Message);
      Res.Status(500).Send(LResponse);
    end;
  end;
end;

procedure GetProductosPendientes(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Q: TFDQuery;
  LJSONList: TJSONArray;
  LJSONObj: TJSONObject;
  LFileName: string;
  LFileID: Integer;
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    if not Req.Query.TryGetValue('fileName', LFileName) or LFileName.Trim.IsEmpty then
    begin
      Res.Status(400).Send('fileName is required');
      Exit;
    end;

    Q := GetBridgeQuery;
    try
      // 1. Get File ID
      Q.SQL.Text := 'SELECT ID FROM XML_FILES WHERE FILE_NAME = :FNAME';
      Q.ParamByName('FNAME').AsString := LFileName;
      Q.Open;

      if Q.IsEmpty then
      begin
        Res.Status(404).Send('File not found in staging');
        Exit;
      end;

      LFileID := Q.FieldByName('ID').AsInteger;
      Q.Close;

      // 2. Get Pending Products with exact aliases for frontend consistency
      Q.SQL.Text :=
        'SELECT REFERENCIA AS REFERENCIAXML, DESCRIPCION AS NOMBREPRODUCTO, UNIDAD AS UNIDADXML ' +
        'FROM XML_PRODUCTOS ' +
        'WHERE XML_FILE_ID = :FILEID AND EQUIVALENCIA_ID IS NULL';

      Q.ParamByName('FILEID').AsInteger := LFileID;
      Q.Open;

      LJSONList := TJSONArray.Create;
      while not Q.Eof do
      begin
        LJSONObj := TJSONObject.Create;
        LJSONObj.AddPair('referenciaXML', Q.FieldByName('REFERENCIAXML').AsString);
        LJSONObj.AddPair('nombreProducto', Q.FieldByName('NOMBREPRODUCTO').AsString);
        LJSONObj.AddPair('unidadXML', Q.FieldByName('UNIDADXML').AsString);
        LJSONObj.AddPair('unidadXMLNombre', TDianUnits.GetUnitName(Q.FieldByName('UNIDADXML').AsString));
        LJSONObj.AddPair('estado', 'pendiente');
        LJSONList.AddElement(LJSONObj);
        Q.Next;
      end;
      Res.Send(LJSONList);
    finally
      Q.Free;
    end;
  except
    on E: Exception do
    begin
      LJSONObj := TJSONObject.Create;
      LJSONObj.AddPair('success', TJSONBool.Create(False));
      LJSONObj.AddPair('message', E.Message);
      Res.Status(500).Send(LJSONObj);
    end;
  end;
end;

procedure GetFiles(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Q: TFDQuery;
  LPath, LFile, LFileNameOnly: string;
  LFiles: TStringDynArray;
  LCombinedList: TList<TCombinedFileInfo>;
  LInfo: TCombinedFileInfo;
  LDBData: TDictionary<string, TCombinedFileInfo>;
  LJSONList: TJSONArray;
  LJSONObj: TJSONObject;
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    LCombinedList := TList<TCombinedFileInfo>.Create;
    try
      LDBData := TDictionary<string, TCombinedFileInfo>.Create;
      try
      // 1. Get database records
      Q := GetBridgeQuery;
      try
        Q.SQL.Text := 'SELECT * FROM XML_FILES';
        Q.Open;
        while not Q.Eof do
        begin
          LInfo := Default(TCombinedFileInfo);
          LInfo.ID := Q.FieldByName('ID').AsInteger;
          LInfo.FileName := Q.FieldByName('FILE_NAME').AsString;
          LInfo.ProveedorNit := Q.FieldByName('PROVEEDOR_NIT').AsString;
          LInfo.Proveedor := Q.FieldByName('PROVEEDOR_NOMBRE').AsString;
          if LInfo.Proveedor.Trim.IsEmpty then LInfo.Proveedor := 'Sin proveedor';
          LInfo.FechaDocumento := Q.FieldByName('FECHA_DOCUMENTO').AsDateTime;
          LInfo.Estado := Q.FieldByName('ESTADO').AsString;
          LInfo.FechaCarga := Q.FieldByName('FECHA_CARGA').AsDateTime;
          LDBData.AddOrSetValue(LInfo.FileName.ToLower, LInfo);
          Q.Next;
        end;
      finally
        Q.Free;
      end;

      // 2. Scan physical files and merge/add
      LPath := TPath.Combine('PurchaseBridge', 'Input');
      if TDirectory.Exists(LPath) then
      begin
        LFiles := TDirectory.GetFiles(LPath, '*.xml');
        for LFile in LFiles do
        begin
          LFileNameOnly := TPath.GetFileName(LFile);
          if LDBData.TryGetValue(LFileNameOnly.ToLower, LInfo) then
          begin
            LInfo.Size := TFile.GetSize(LFile);
            LInfo.LastModified := TFile.GetLastWriteTime(LFile);
            LDBData.Items[LFileNameOnly.ToLower] := LInfo;
          end
          else
          begin
            LInfo := Default(TCombinedFileInfo);
            LInfo.ID := 0;
            LInfo.FileName := LFileNameOnly;
            LInfo.Size := TFile.GetSize(LFile);
            LInfo.LastModified := TFile.GetLastWriteTime(LFile);
            LInfo.ProveedorNit := '';
            LInfo.Proveedor := 'Sin procesar';
            LInfo.FechaDocumento := 0;
            LInfo.Estado := 'CARGADO';
            LInfo.FechaCarga := LInfo.LastModified;
            LDBData.Add(LFileNameOnly.ToLower, LInfo);
          end;
        end;
      end;

      for LInfo in LDBData.Values do
        LCombinedList.Add(LInfo);

      // 3. Sort by FechaCarga desc
      LCombinedList.Sort(TComparer<TCombinedFileInfo>.Construct(
        function(const Left, Right: TCombinedFileInfo): Integer
        begin
          if Left.FechaCarga < Right.FechaCarga then Result := 1
          else if Left.FechaCarga > Right.FechaCarga then Result := -1
          else Result := 0;
        end));

      // 4. Construct JSON
      LJSONList := TJSONArray.Create;
      for LInfo in LCombinedList do
      begin
        LJSONObj := TJSONObject.Create;
        LJSONObj.AddPair('id', TJSONNumber.Create(LInfo.ID));
        LJSONObj.AddPair('fileName', LInfo.FileName);

        // Final implementation of Size fallback
        if LInfo.Size > 0 then
          LJSONObj.AddPair('size', TJSONNumber.Create(LInfo.Size))
        else
          LJSONObj.AddPair('size', TJSONNumber.Create(0));

        LJSONObj.AddPair('proveedorNit', LInfo.ProveedorNit);
        LJSONObj.AddPair('proveedor', LInfo.Proveedor);
        LJSONObj.AddPair('proveedorNombre', LInfo.Proveedor);
        if LInfo.FechaDocumento > 0 then
          LJSONObj.AddPair('fechaDocumento', FormatDateTime('yyyy-mm-dd', LInfo.FechaDocumento))
        else
          LJSONObj.AddPair('fechaDocumento', TJSONNull.Create);
        LJSONObj.AddPair('estado', LInfo.Estado);
        LJSONObj.AddPair('fechaCarga', FormatDateTime('yyyy-mm-dd HH:nn:ss', LInfo.FechaCarga));
        LJSONObj.AddPair('lastModified', FormatDateTime('yyyy-mm-dd HH:nn:ss', LInfo.LastModified));
        LJSONList.AddElement(LJSONObj);
      end;
      Res.Send(LJSONList);
      finally
        LDBData.Free;
      end;
    finally
      LCombinedList.Free;
    end;
  except
    on E: Exception do
    begin
      LJSONObj := TJSONObject.Create;
      LJSONObj.AddPair('success', TJSONBool.Create(False));
      LJSONObj.AddPair('message', E.Message);
      Res.Status(500).Send(LJSONObj);
    end;
  end;
end;

procedure Homologar(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LJSON: TJSONObject;
  LReferenciaXML, LUnidadXML, LReferenciaErp, LUnidadErp: string;
  LFactor: Double;
  LResponse: TJSONObject;
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    try
      if Req.Body.Trim.IsEmpty then
        raise Exception.Create('Request body vacío');

      LJSON := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
      try
        if not Assigned(LJSON) then
          raise Exception.Create('JSON inválido');

        // Validar campos obligatorios
        if LJSON.GetValue('referenciaXml') = nil then
          raise Exception.Create('referenciaXml requerido');
        if LJSON.GetValue('unidadXml') = nil then
          raise Exception.Create('unidadXml requerido');
        if LJSON.GetValue('referenciaErp') = nil then
          raise Exception.Create('referenciaErp requerido');
        if LJSON.GetValue('unidadErp') = nil then
          raise Exception.Create('unidadErp requerido');
        if LJSON.GetValue('factor') = nil then
          raise Exception.Create('factor requerido');

        // Asignación segura
        LReferenciaXML := LJSON.GetValue('referenciaXml').Value;
        LUnidadXML := LJSON.GetValue('unidadXml').Value;
        LReferenciaErp := LJSON.GetValue('referenciaErp').Value;
        LUnidadErp := LJSON.GetValue('unidadErp').Value;

        if LJSON.GetValue('factor') is TJSONNumber then
          LFactor := (LJSON.GetValue('factor') as TJSONNumber).AsDouble
        else
          LFactor := StrToFloatDef(LJSON.GetValue('factor').Value, 0);

        // Validar antes de usar
        if LReferenciaErp.Trim = '' then
          raise Exception.Create('Referencia ERP vacía');
        if LUnidadErp.Trim = '' then
          raise Exception.Create('Unidad ERP vacía');

        // Pasamos los valores del XML a REFERENCIAH/UNIDADH para que coincida con la lógica de búsqueda
        // y los valores del ERP a REFERENCIAP/UNIDADP.
        EquivalenciaService.CrearEquivalencia(
          0, 0, '', LReferenciaXML, LUnidadXML, LUnidadErp, LReferenciaErp, LFactor
        );

        LResponse := TJSONObject.Create;
        LResponse.AddPair('success', TJSONBool.Create(True));
        LResponse.AddPair('message', 'Homologación guardada correctamente');
        Res.Send(LResponse);
      finally
        if Assigned(LJSON) then LJSON.Free;
      end;
    except
      on E: Exception do
      begin
        LResponse := TJSONObject.Create;
        LResponse.AddPair('success', TJSONBool.Create(False));
        LResponse.AddPair('mensaje', E.Message);
        Res.Status(500).Send(LResponse);
      end;
    end;
  except
    on E: Exception do
    begin
      Res.Status(500).Send(E.Message);
    end;
  end;
end;

procedure Registry;
begin
  // /xml/list is deprecated, use /xml/files
  THorse.Get('/xml/list', GetFiles);
  THorse.Post('/xml/upload', Upload);
  THorse.Post('/xml/parse', Parse);
  THorse.Get('/xml/files', GetFiles);
  THorse.Get('/xml/files/:id', GetFileById);
  THorse.Post('/xml/procesar', ProcesarBatch);
  THorse.Get('/xml/productos/pendientes', GetProductosPendientes);
  THorse.Post('/xml/homologar', Homologar);
end;

end.
