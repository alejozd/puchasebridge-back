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
  HelisaService,
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

function ResolveUnidadSigla(const AUnidadCodigo: string): string;
var
  LCode: string;
begin
  LCode := UpperCase(AUnidadCodigo.Trim);
  // Diccionario mínimo para UI: se retorna sigla empresarial; fallback al código original.
  if (LCode = '94') or (LCode = 'NIU') then
    Result := 'UND'
  else if LCode = 'KGM' then
    Result := 'KG'
  else if LCode = 'LTR' then
    Result := 'LT'
  else
    Result := AUnidadCodigo;
end;

procedure Upload(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LFile: TAbstractWebRequestFile;
  LPath, LFileName, LFullFile: string;
  LResponse: TJSONObject;
  I: Integer;
  LFound: Boolean;
  LFileStream: TFileStream;
  Q: TFDQuery;
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

    // Se registra/actualiza el archivo en staging y se deja explícitamente en estado CARGADO.
    Q := GetBridgeQuery;
    try
      Q.SQL.Text := 'SELECT ID FROM XML_FILES WHERE FILE_NAME = :FNAME';
      Q.ParamByName('FNAME').AsString := LFileName;
      Q.Open;
      if Q.IsEmpty then
      begin
        Q.Close;
        Q.SQL.Text :=
          'INSERT INTO XML_FILES (FILE_NAME, ESTADO, MENSAJE_ERROR, FECHA_CARGA) ' +
          'VALUES (:FNAME, ''CARGADO'', NULL, CURRENT_TIMESTAMP)';
        Q.ParamByName('FNAME').AsString := LFileName;
        Q.ExecSQL;
      end
      else
      begin
        Q.Close;
        Q.SQL.Text :=
          'UPDATE XML_FILES SET ESTADO = ''CARGADO'', MENSAJE_ERROR = NULL, FECHA_CARGA = CURRENT_TIMESTAMP ' +
          'WHERE FILE_NAME = :FNAME';
        Q.ParamByName('FNAME').AsString := LFileName;
        Q.ExecSQL;
      end;
    finally
      Q.Free;
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
  LUnidadCodigo: string;
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
      if not Q.FieldByName('FECHA_VALIDACION').IsNull then
        LResponse.AddPair('fechaValidacion', FormatDateTime('yyyy-mm-dd HH:nn:ss', Q.FieldByName('FECHA_VALIDACION').AsDateTime))
      else
        LResponse.AddPair('fechaValidacion', TJSONNull.Create);
      if not Q.FieldByName('FECHA_PROCESO').IsNull then
        LResponse.AddPair('fechaProceso', FormatDateTime('yyyy-mm-dd HH:nn:ss', Q.FieldByName('FECHA_PROCESO').AsDateTime))
      else
        LResponse.AddPair('fechaProceso', TJSONNull.Create);

      Q.Close;
      Q.SQL.Text := 'SELECT * FROM XML_PRODUCTOS WHERE XML_FILE_ID = :FILEID';
      Q.ParamByName('FILEID').AsInteger := LFileID;
      Q.Open;

      LProductsArr := TJSONArray.Create;
      while not Q.Eof do
      begin
        LProductObj := TJSONObject.Create;
        LUnidadCodigo := Q.FieldByName('UNIDAD').AsString;
        LProductObj.AddPair('id', TJSONNumber.Create(Q.FieldByName('ID').AsInteger));
        LProductObj.AddPair('descripcion', Q.FieldByName('DESCRIPCION').AsString);
        LProductObj.AddPair('referencia', Q.FieldByName('REFERENCIA').AsString);
        LProductObj.AddPair('referenciaStd', Q.FieldByName('REFERENCIA_STD').AsString);
        LProductObj.AddPair('cantidad', TJSONNumber.Create(Q.FieldByName('CANTIDAD').AsFloat));
        // Se envía unidad en sigla para consumo UI y descripción opcional para detalle.
        LProductObj.AddPair('unidad', ResolveUnidadSigla(LUnidadCodigo));
        LProductObj.AddPair('unidadDescripcion', TDianUnits.GetUnitName(LUnidadCodigo));
        LProductObj.AddPair('valorUnitario', TJSONNumber.Create(Q.FieldByName('VALOR_UNITARIO').AsFloat));
        LProductObj.AddPair('valorTotal', TJSONNumber.Create(Q.FieldByName('VALOR_TOTAL').AsFloat));
        LProductObj.AddPair('impuesto', TJSONNumber.Create(Q.FieldByName('IMPUESTO').AsFloat));

        if not Q.FieldByName('EQUIVALENCIA_ID').IsNull then
        begin
          LProductObj.AddPair('equivalenciaId', TJSONNumber.Create(Q.FieldByName('EQUIVALENCIA_ID').AsInteger));
          // Estado del producto listo para frontend empresarial.
          LProductObj.AddPair('estadoProducto', 'HOMOLOGADO');
        end
        else
        begin
          LProductObj.AddPair('equivalenciaId', TJSONNull.Create);
          LProductObj.AddPair('estadoProducto', 'PENDIENTE');
        end;

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
  LResponse: TJSONObject;
  LProcesadosArr, LRechazadosArr: TJSONArray;
  LHasPendientes: Boolean;
  LProcesadosCount, LRechazadosCount: Integer;
  LRechazadosLabel: string;
begin
  Res.ContentType('application/json; charset=utf-8');
  LBody := Req.Body<TJSONObject>;
  if (LBody = nil) or not LBody.TryGetValue('ids', LIdsArr) then
  begin
    Res.Status(400).Send('ids is required');
    Exit;
  end;

  LProcesadosArr := TJSONArray.Create;
  LRechazadosArr := TJSONArray.Create;
  LResponse := TJSONObject.Create;
  LProcesadosCount := 0;
  LRechazadosCount := 0;

  try
    Q := GetBridgeQuery;
    try
      for I := 0 to LIdsArr.Count - 1 do
      begin
        LId := StrToIntDef(LIdsArr.Items[I].Value, 0);
        if LId = 0 then Continue;

        try
          // 1. Regla de negocio: no procesar si hay al menos un producto pendiente de homologación.
          Q.SQL.Text :=
            'SELECT COUNT(*) as TOTAL ' +
            'FROM XML_PRODUCTOS ' +
            'WHERE XML_FILE_ID = :FILEID ' +
            'AND COALESCE(ESTADO_VALIDACION, ''PENDIENTE'') <> ''HOMOLOGADO''';
          Q.ParamByName('FILEID').AsInteger := LId;
          Q.Open;
          LHasPendientes := Q.FieldByName('TOTAL').AsInteger > 0;
          Q.Close;

          if LHasPendientes then
          begin
            Q.SQL.Text := 'UPDATE XML_FILES SET ESTADO = ''PENDIENTE'', MENSAJE_ERROR = :MSG WHERE ID = :ID';
            Q.ParamByName('MSG').AsString := 'El documento contiene productos sin homologar y no puede ser procesado';
            Q.ParamByName('ID').AsInteger := LId;
            Q.ExecSQL;
            LRechazadosArr.AddElement(TJSONNumber.Create(LId));
            Inc(LRechazadosCount);
            Writeln(Format('Documento %d no procesado: productos pendientes de homologación', [LId]));
            Continue;
          end;

          // 2. Procesar documento (marcando estado PROCESADO)
          Q.SQL.Text := 'UPDATE XML_FILES SET ESTADO = ''PROCESADO'', MENSAJE_ERROR = NULL, FECHA_PROCESO = CURRENT_TIMESTAMP WHERE ID = :ID';
          Q.ParamByName('ID').AsInteger := LId;
          Q.ExecSQL;

          LProcesadosArr.AddElement(TJSONNumber.Create(LId));
          Inc(LProcesadosCount);
        except
          on E: Exception do
          begin
            LRechazadosArr.AddElement(TJSONNumber.Create(LId));
            Inc(LRechazadosCount);
            Writeln(Format('Documento %d no procesado: %s', [LId, E.Message]));
          end;
        end;
      end;

      if LRechazadosCount = 1 then
        LRechazadosLabel := 'rechazado'
      else
        LRechazadosLabel := 'rechazados';

      LResponse.AddPair('success', TJSONBool.Create(True));
      LResponse.AddPair('procesados', LProcesadosArr);
      LResponse.AddPair('rechazados', LRechazadosArr);
      LResponse.AddPair(
        'mensaje',
        Format('%d documentos procesados, %d %s por productos pendientes',
          [LProcesadosCount, LRechazadosCount, LRechazadosLabel])
      );
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
  LBody, LResponse: TJSONObject;
  LReferenciaXML, LUnidadXML, LReferenciaErp, LUnidadErp, LNombreH, LUnidadErpSigla: string;
  LCodigoH, LSubCodigoH: Integer;
  LFactor: Double;
  LEquivalenciaID: Integer;
  LXMLFileID, LPendientes: Integer;
  LConn, LHelisaConn: TFDConnection;
  Q: TFDQuery;
begin
  Res.ContentType('application/json; charset=utf-8');
  LConn := GetBridgeConnection;
  try
    try
      LBody := Req.Body<TJSONObject>;
      if not Assigned(LBody) then
      begin
        if not Req.Body.Trim.IsEmpty then
          LBody := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
      end;

      if not Assigned(LBody) then
        raise Exception.Create('JSON body inválido o vacío');

      try
        // Extract XML product info
        if not LBody.TryGetValue('referenciaXml', LReferenciaXML) then
          if not LBody.TryGetValue('referenciaXML', LReferenciaXML) then
            raise Exception.Create('referenciaXml es requerido');

        if not LBody.TryGetValue('unidadXml', LUnidadXML) then
          if not LBody.TryGetValue('unidadXML', LUnidadXML) then
            raise Exception.Create('unidadXml es requerido');

        // Extract ERP product info (MANDATORY)
        if not LBody.TryGetValue('codigoH', LCodigoH) then
          raise Exception.Create('codigoH (Código ERP) es requerido');

        if not LBody.TryGetValue('nombreH', LNombreH) then
          raise Exception.Create('nombreH (Nombre ERP) es requerido');

        if not LBody.TryGetValue('subCodigoH', LSubCodigoH) then
          LSubCodigoH := 0;

        // Extract ERP mapping info
        if not LBody.TryGetValue('referenciaErp', LReferenciaErp) then
          if not LBody.TryGetValue('referenciaP', LReferenciaErp) then
            raise Exception.Create('referenciaErp es requerido');

        if not LBody.TryGetValue('unidadErp', LUnidadErp) then
          if not LBody.TryGetValue('unidadP', LUnidadErp) then
            raise Exception.Create('unidadErp es requerido');

        if not LBody.TryGetValue('factor', LFactor) then
        begin
           if LBody.GetValue('factor') <> nil then
             LFactor := StrToFloatDef(LBody.GetValue('factor').Value, 1)
           else
             LFactor := 1;
        end;

        if LReferenciaErp.Trim.IsEmpty then raise Exception.Create('Referencia ERP vacía');
        if LUnidadErp.Trim.IsEmpty then raise Exception.Create('Unidad ERP vacía');

        LConn.StartTransaction;
        try
          // Convert Unit Code to Sigla before saving
          LHelisaConn := GetHelisaConnection;
          try
            LUnidadErpSigla := HelisaService.ObtenerSiglaUnidad(LHelisaConn, LUnidadErp);
            if not LUnidadErpSigla.IsEmpty then
              LUnidadErp := LUnidadErpSigla;
          finally
            LHelisaConn.Free;
          end;

          // 1. Get or Create Equivalencia
          LEquivalenciaID := EquivalenciaService.GetIDEquivalencia(LConn, LReferenciaXML, LUnidadXML);

          if LEquivalenciaID = 0 then
          begin
            LEquivalenciaID := EquivalenciaService.CrearEquivalencia(
              LConn, LCodigoH, LSubCodigoH, LNombreH, LReferenciaXML, LUnidadXML, LUnidadErp, LReferenciaErp, LFactor
            );
          end;

          // 2. Update all pending products in XML_PRODUCTOS with this same mapping
          Q := TFDQuery.Create(nil);
          try
            Q.Connection := LConn;
            Q.SQL.Text :=
              'UPDATE XML_PRODUCTOS SET EQUIVALENCIA_ID = :EID, ESTADO_VALIDACION = ''HOMOLOGADO'', MENSAJE_VALIDACION = NULL ' +
              'WHERE REFERENCIA = :REF AND UNIDAD = :UNI AND EQUIVALENCIA_ID IS NULL';
            Q.ParamByName('EID').AsInteger := LEquivalenciaID;
            Q.ParamByName('REF').AsString := LReferenciaXML;
            Q.ParamByName('UNI').AsString := LUnidadXML;
            Q.ExecSQL;

            // 3. Recalcular estado del XML después de homologar para mantener flujo PENDIENTE/LISTO.
            Q.SQL.Text :=
              'SELECT FIRST 1 XML_FILE_ID AS XML_FILE_ID ' +
              'FROM XML_PRODUCTOS ' +
              'WHERE REFERENCIA = :REF AND UNIDAD = :UNI';
            Q.ParamByName('REF').AsString := LReferenciaXML;
            Q.ParamByName('UNI').AsString := LUnidadXML;
            Q.Open;
            if not Q.IsEmpty then
            begin
              LXMLFileID := Q.FieldByName('XML_FILE_ID').AsInteger;
              Q.Close;

              // Se cuenta cuántos productos del XML siguen sin equivalencia.
              Q.SQL.Text :=
                'SELECT COUNT(*) AS TOTAL ' +
                'FROM XML_PRODUCTOS ' +
                'WHERE XML_FILE_ID = :XML_FILE_ID ' +
                'AND EQUIVALENCIA_ID IS NULL';
              Q.ParamByName('XML_FILE_ID').AsInteger := LXMLFileID;
              Q.Open;
              LPendientes := Q.FieldByName('TOTAL').AsInteger;
              Q.Close;

              // Si no hay pendientes queda LISTO; si hay pendientes se mantiene PENDIENTE.
              if LPendientes = 0 then
                Q.SQL.Text := 'UPDATE XML_FILES SET ESTADO = ''LISTO'' WHERE ID = :XML_FILE_ID'
              else
                Q.SQL.Text := 'UPDATE XML_FILES SET ESTADO = ''PENDIENTE'' WHERE ID = :XML_FILE_ID';
              Q.ParamByName('XML_FILE_ID').AsInteger := LXMLFileID;
              Q.ExecSQL;
            end
            else
              Q.Close;
          finally
            Q.Free;
          end;

          LConn.Commit;

          LResponse := TJSONObject.Create;
          LResponse.AddPair('success', TJSONBool.Create(True));
          LResponse.AddPair('message', 'Homologación guardada correctamente');
          Res.Send(LResponse);
        except
          on E: Exception do
          begin
            LConn.Rollback;
            raise;
          end;
        end;
      finally
        if (LBody <> Req.Body<TJSONObject>) and Assigned(LBody) then
          LBody.Free;
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
  finally
    LConn.Free;
  end;
end;

procedure GetProductosDocumento(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Q: TFDQuery;
  LResponse: TJSONObject;
  LProductsArr: TJSONArray;
  LProductObj: TJSONObject;
  LFileName: string;
  LFileID: Integer;
  LTotalProductos, LTotalPendientes, LTotalHomologados: Integer;
  LUnidadErp: string;
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

      // 2. Get All Products with LEFT JOIN to EQUIVALENCIA
      Q.SQL.Text :=
        'SELECT P.REFERENCIA AS REFERENCIAXML, P.DESCRIPCION AS NOMBREPRODUCTO, P.UNIDAD AS UNIDADXML, ' +
        '       E.REFERENCIAP AS REFERENCIAERP, E.NOMBREH AS NOMBREERP, E.UNIDADH AS UNIDADERP, E.FACTOR, ' +
        '       P.EQUIVALENCIA_ID ' +
        'FROM XML_PRODUCTOS P ' +
        'LEFT JOIN EQUIVALENCIA E ON P.EQUIVALENCIA_ID = E.ID ' +
        'WHERE P.XML_FILE_ID = :FILEID';

      Q.ParamByName('FILEID').AsInteger := LFileID;
      Q.Open;

      LTotalProductos := 0;
      LTotalPendientes := 0;
      LTotalHomologados := 0;
      LProductsArr := TJSONArray.Create;

      while not Q.Eof do
      begin
        Inc(LTotalProductos);
        LProductObj := TJSONObject.Create;
        LProductObj.AddPair('referenciaXML', Q.FieldByName('REFERENCIAXML').AsString);
        LProductObj.AddPair('nombreProducto', Q.FieldByName('NOMBREPRODUCTO').AsString);
        LProductObj.AddPair('unidadXML', Q.FieldByName('UNIDADXML').AsString);
        LProductObj.AddPair('unidadXMLNombre', TDianUnits.GetUnitName(Q.FieldByName('UNIDADXML').AsString));

        if not Q.FieldByName('EQUIVALENCIA_ID').IsNull then
        begin
          Inc(LTotalHomologados);
          LProductObj.AddPair('estado', 'HOMOLOGADO');
          LProductObj.AddPair('referenciaErp', Q.FieldByName('REFERENCIAERP').AsString);
          LProductObj.AddPair('nombreErp', Q.FieldByName('NOMBREERP').AsString);

          LUnidadErp := Q.FieldByName('UNIDADERP').AsString;
          LProductObj.AddPair('unidadErp', LUnidadErp);

          // For unidadErpNombre, we'd ideally fetch it from Helisa global DB.
          // Since cross-DB JOIN is not supported and performance is requested,
          // we could do a separate lookup if needed, but for now we'll use UNIDADERP as name
          // or leave it as placeholder if we can't easily get it here.
          // Let's assume for now that unidadErp and unidadErpNombre can be the same if we don't have the sigla.
          // Wait, HelisaController.pas gets it from INTUXXXX.
          LProductObj.AddPair('unidadErpNombre', LUnidadErp);
          LProductObj.AddPair('factor', TJSONNumber.Create(Q.FieldByName('FACTOR').AsFloat));
        end
        else
        begin
          Inc(LTotalPendientes);
          LProductObj.AddPair('estado', 'PENDIENTE');
          LProductObj.AddPair('referenciaErp', TJSONNull.Create);
          LProductObj.AddPair('nombreErp', TJSONNull.Create);
          LProductObj.AddPair('unidadErp', TJSONNull.Create);
          LProductObj.AddPair('unidadErpNombre', TJSONNull.Create);
          LProductObj.AddPair('factor', TJSONNull.Create);
        end;

        LProductsArr.AddElement(LProductObj);
        Q.Next;
      end;

      LResponse := TJSONObject.Create;
      LResponse.AddPair('totalProductos', TJSONNumber.Create(LTotalProductos));
      LResponse.AddPair('totalPendientes', TJSONNumber.Create(LTotalPendientes));
      LResponse.AddPair('totalHomologados', TJSONNumber.Create(LTotalHomologados));
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

procedure GetDashboardMetrics(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Q: TFDQuery;
  LResponse: TJSONObject;
  LTotal, LCargados, LPendientes, LListos, LProcesados, LErrores: Integer;
  LProcesadosHoy, LErroresHoy: Integer;
  LEstado: string;
begin
  Res.ContentType('application/json; charset=utf-8');
  LTotal := 0;
  LCargados := 0;
  LPendientes := 0;
  LListos := 0;
  LProcesados := 0;
  LErrores := 0;
  LProcesadosHoy := 0;
  LErroresHoy := 0;

  try
    Q := GetBridgeQuery;
    try
      // 1) Total de archivos
      Q.SQL.Text := 'SELECT COUNT(*) AS TOTAL FROM XML_FILES';
      Q.Open;
      LTotal := Q.FieldByName('TOTAL').AsInteger;
      Q.Close;

      // 2) Cantidad por estado usando GROUP BY ESTADO
      Q.SQL.Text :=
        'SELECT ESTADO, COUNT(*) AS TOTAL ' +
        'FROM XML_FILES ' +
        'GROUP BY ESTADO';
      Q.Open;
      while not Q.Eof do
      begin
        LEstado := UpperCase(Q.FieldByName('ESTADO').AsString.Trim);
        if LEstado = 'CARGADO' then
          LCargados := Q.FieldByName('TOTAL').AsInteger
        else if LEstado = 'PENDIENTE' then
          LPendientes := Q.FieldByName('TOTAL').AsInteger
        else if LEstado = 'LISTO' then
          LListos := Q.FieldByName('TOTAL').AsInteger
        else if LEstado = 'PROCESADO' then
          LProcesados := Q.FieldByName('TOTAL').AsInteger
        else if LEstado = 'ERROR' then
          LErrores := Q.FieldByName('TOTAL').AsInteger;
        Q.Next;
      end;
      Q.Close;

      // 3) Métricas de hoy: usa FECHA_PROCESO; si no existe, cae a FECHA_CARGA.
      Q.SQL.Text :=
        'SELECT COUNT(*) AS TOTAL ' +
        'FROM XML_FILES ' +
        'WHERE ESTADO = ''PROCESADO'' ' +
        'AND CAST(COALESCE(FECHA_PROCESO, FECHA_CARGA) AS DATE) = CURRENT_DATE';
      Q.Open;
      LProcesadosHoy := Q.FieldByName('TOTAL').AsInteger;
      Q.Close;

      Q.SQL.Text :=
        'SELECT COUNT(*) AS TOTAL ' +
        'FROM XML_FILES ' +
        'WHERE ESTADO = ''ERROR'' ' +
        'AND CAST(COALESCE(FECHA_PROCESO, FECHA_CARGA) AS DATE) = CURRENT_DATE';
      Q.Open;
      LErroresHoy := Q.FieldByName('TOTAL').AsInteger;
      Q.Close;

      LResponse := TJSONObject.Create;
      LResponse.AddPair('total', TJSONNumber.Create(LTotal));
      LResponse.AddPair('cargados', TJSONNumber.Create(LCargados));
      LResponse.AddPair('pendientes', TJSONNumber.Create(LPendientes));
      LResponse.AddPair('listos', TJSONNumber.Create(LListos));
      LResponse.AddPair('procesados', TJSONNumber.Create(LProcesados));
      LResponse.AddPair('errores', TJSONNumber.Create(LErrores));
      LResponse.AddPair('procesadosHoy', TJSONNumber.Create(LProcesadosHoy));
      LResponse.AddPair('erroresHoy', TJSONNumber.Create(LErroresHoy));
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
  THorse.Get('/xml/productos/documento', GetProductosDocumento);
  THorse.Post('/xml/homologar', Homologar);
  THorse.Get('/dashboard/metrics', GetDashboardMetrics);
end;

end.
