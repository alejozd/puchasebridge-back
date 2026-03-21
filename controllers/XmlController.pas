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
  ValidationService,
  FireDAC.Comp.Client,
  FirebirdConnection,
  AuthService,
  AuthMiddleware,
  DocumentoService,
  EquivalenciaService;

type
  TFileInfo = record
    FileName: string;
    Size: Int64;
    LastModified: TDateTime;
  end;

procedure ListFiles(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Q: TFDQuery;
  LJSONList: TJSONArray;
  LJSONObj: TJSONObject;
begin
  try
    Q := GetBridgeQuery;
    try
      Q.SQL.Text :=
        'SELECT ID, FILE_NAME, PROVEEDOR_NOMBRE, FECHA_DOCUMENTO, ESTADO, FECHA_CARGA ' +
        'FROM XML_FILES ORDER BY FECHA_CARGA DESC';
      Q.Open;

      LJSONList := TJSONArray.Create;
      while not Q.Eof do
      begin
        LJSONObj := TJSONObject.Create;
        LJSONObj.AddPair('id', TJSONNumber.Create(Q.FieldByName('ID').AsInteger));
        LJSONObj.AddPair('file_name', Q.FieldByName('FILE_NAME').AsString);
        LJSONObj.AddPair('proveedor_nombre', Q.FieldByName('PROVEEDOR_NOMBRE').AsString);
        if not Q.FieldByName('FECHA_DOCUMENTO').IsNull then
          LJSONObj.AddPair('fecha_documento', FormatDateTime('yyyy-mm-dd HH:nn:ss', Q.FieldByName('FECHA_DOCUMENTO').AsDateTime))
        else
          LJSONObj.AddPair('fecha_documento', TJSONNull.Create);
        LJSONObj.AddPair('estado', Q.FieldByName('ESTADO').AsString);
        LJSONObj.AddPair('fecha_carga', FormatDateTime('yyyy-mm-dd HH:nn:ss', Q.FieldByName('FECHA_CARGA').AsDateTime));
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
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
    end;
  end;
end;

procedure GetFile(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LId: Integer;
  Q, QProd: TFDQuery;
  LJSONObj, LFileObj, LProdObj: TJSONObject;
  LProdArr: TJSONArray;
begin
  try
    LId := StrToIntDef(Req.Params['id'], 0);
    if LId <= 0 then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'ID de archivo inválido'));
      Exit;
    end;

    Q := GetBridgeQuery;
    try
      Q.SQL.Text := 'SELECT * FROM XML_FILES WHERE ID = :ID';
      Q.ParamByName('ID').AsInteger := LId;
      Q.Open;

      if Q.IsEmpty then
      begin
        Res.Status(404).Send(TJSONObject.Create.AddPair('error', 'Archivo no encontrado'));
        Exit;
      end;

      LJSONObj := TJSONObject.Create;
      LFileObj := TJSONObject.Create;
      LFileObj.AddPair('id', TJSONNumber.Create(Q.FieldByName('ID').AsInteger));
      LFileObj.AddPair('file_name', Q.FieldByName('FILE_NAME').AsString);
      LFileObj.AddPair('proveedor_nit', Q.FieldByName('PROVEEDOR_NIT').AsString);
      LFileObj.AddPair('proveedor_nombre', Q.FieldByName('PROVEEDOR_NOMBRE').AsString);
      if not Q.FieldByName('FECHA_DOCUMENTO').IsNull then
        LFileObj.AddPair('fecha_documento', FormatDateTime('yyyy-mm-dd HH:nn:ss', Q.FieldByName('FECHA_DOCUMENTO').AsDateTime))
      else
        LFileObj.AddPair('fecha_documento', TJSONNull.Create);
      LFileObj.AddPair('estado', Q.FieldByName('ESTADO').AsString);
      LFileObj.AddPair('fecha_carga', FormatDateTime('yyyy-mm-dd HH:nn:ss', Q.FieldByName('FECHA_CARGA').AsDateTime));
      LJSONObj.AddPair('archivo', LFileObj);

      QProd := GetBridgeQuery;
      try
        QProd.SQL.Text := 'SELECT * FROM XML_PRODUCTOS WHERE XML_FILE_ID = :FILEID';
        QProd.ParamByName('FILEID').AsInteger := LId;
        QProd.Open;

        LProdArr := TJSONArray.Create;
        while not QProd.Eof do
        begin
          LProdObj := TJSONObject.Create;
          LProdObj.AddPair('id', TJSONNumber.Create(QProd.FieldByName('ID').AsInteger));
          LProdObj.AddPair('descripcion', QProd.FieldByName('DESCRIPCION').AsString);
          LProdObj.AddPair('referencia', QProd.FieldByName('REFERENCIA').AsString);
          LProdObj.AddPair('cantidad', TJSONNumber.Create(QProd.FieldByName('CANTIDAD').AsFloat));
          LProdObj.AddPair('unidad', QProd.FieldByName('UNIDAD').AsString);
          LProdObj.AddPair('valor_unitario', TJSONNumber.Create(QProd.FieldByName('VALOR_UNITARIO').AsFloat));
          LProdObj.AddPair('valor_total', TJSONNumber.Create(QProd.FieldByName('VALOR_TOTAL').AsFloat));
          if not QProd.FieldByName('EQUIVALENCIA_ID').IsNull then
            LProdObj.AddPair('equivalencia_id', TJSONNumber.Create(QProd.FieldByName('EQUIVALENCIA_ID').AsInteger))
          else
            LProdObj.AddPair('equivalencia_id', TJSONNull.Create);

          LProdArr.AddElement(LProdObj);
          QProd.Next;
        end;
        LJSONObj.AddPair('productos', LProdArr);
      finally
        QProd.Free;
      end;

      Res.Send(LJSONObj);
    finally
      Q.Free;
    end;
  except
    on E: Exception do
    begin
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
    end;
  end;
end;

procedure List(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LPath: string;
  LFiles: TStringDynArray;
  LFile: string;
  LJSONList: TJSONArray;
  LJSONObj: TJSONObject;
  LFileInfoList: TList<TFileInfo>;
  LFileInfo: TFileInfo;
begin
  try
    LPath := TPath.Combine('PurchaseBridge', 'Input');
    if not TDirectory.Exists(LPath) then
    begin
      Res.Send(TJSONArray.Create);
      Exit;
    end;

    LFiles := TDirectory.GetFiles(LPath, '*.xml');

    LFileInfoList := TList<TFileInfo>.Create;
    try
      for LFile in LFiles do
      begin
        LFileInfo.FileName := TPath.GetFileName(LFile);
        LFileInfo.Size := TFile.GetSize(LFile);
        LFileInfo.LastModified := TFile.GetLastWriteTime(LFile);
        LFileInfoList.Add(LFileInfo);
      end;

      LFileInfoList.Sort(TComparer<TFileInfo>.Construct(
        function(const Left, Right: TFileInfo): Integer
        begin
          if Left.LastModified < Right.LastModified then
            Result := 1
          else if Left.LastModified > Right.LastModified then
            Result := -1
          else
            Result := 0;
        end));

      LJSONList := TJSONArray.Create;
      try
        for LFileInfo in LFileInfoList do
        begin
          LJSONObj := TJSONObject.Create;
          LJSONObj.AddPair('fileName', LFileInfo.FileName);
          LJSONObj.AddPair('size', TJSONNumber.Create(LFileInfo.Size));
          LJSONObj.AddPair('lastModified', FormatDateTime('yyyy-mm-dd HH:nn:ss', LFileInfo.LastModified));
          LJSONList.AddElement(LJSONObj);
        end;
        Res.Send(LJSONList);
      except
        LJSONList.Free;
        raise;
      end;
    finally
      LFileInfoList.Free;
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

procedure Upload(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LFile: TAbstractWebRequestFile;
  LPath, LFileName, LFullFile: string;
  LResponse: TJSONObject;
  I: Integer;
  LFound: Boolean;
  LFileStream: TFileStream;
begin
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

procedure GetPendingProducts(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Q: TFDQuery;
  LJSONList: TJSONArray;
  LJSONObj: TJSONObject;
begin
  try
    Q := GetBridgeQuery;
    try
      Q.SQL.Text :=
        'SELECT P.*, F.FILE_NAME, F.PROVEEDOR_NOMBRE ' +
        'FROM XML_PRODUCTOS P ' +
        'JOIN XML_FILES F ON P.XML_FILE_ID = F.ID ' +
        'WHERE P.EQUIVALENCIA_ID IS NULL';
      Q.Open;

      LJSONList := TJSONArray.Create;
      while not Q.Eof do
      begin
        LJSONObj := TJSONObject.Create;
        LJSONObj.AddPair('id', TJSONNumber.Create(Q.FieldByName('ID').AsInteger));
        LJSONObj.AddPair('xml_file_id', TJSONNumber.Create(Q.FieldByName('XML_FILE_ID').AsInteger));
        LJSONObj.AddPair('file_name', Q.FieldByName('FILE_NAME').AsString);
        LJSONObj.AddPair('proveedor_nombre', Q.FieldByName('PROVEEDOR_NOMBRE').AsString);
        LJSONObj.AddPair('descripcion', Q.FieldByName('DESCRIPCION').AsString);
        LJSONObj.AddPair('referencia', Q.FieldByName('REFERENCIA').AsString);
        LJSONObj.AddPair('cantidad', TJSONNumber.Create(Q.FieldByName('CANTIDAD').AsFloat));
        LJSONObj.AddPair('unidad', Q.FieldByName('UNIDAD').AsString);
        LJSONObj.AddPair('valor_unitario', TJSONNumber.Create(Q.FieldByName('VALOR_UNITARIO').AsFloat));
        LJSONObj.AddPair('valor_total', TJSONNumber.Create(Q.FieldByName('VALOR_TOTAL').AsFloat));
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
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
    end;
  end;
end;

procedure ProcesarXml(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LIdsArr: TJSONArray;
  LId: Integer;
  Q, QProd: TFDQuery;
  LHeader: TDocumentoHeader;
  LDetalles: TArray<TDocumentoDetalle>;
  LResponse, LProcesadoObj, LErrorObj: TJSONObject;
  LProcesadosArr, LErroresArr: TJSONArray;
  I, J: Integer;
  LAnio, LDocumentoERP: string;
  LSession: TSessionInfo;
  LEquivQ: TFDQuery;
  LFactor: Double;
  LCanProcess: Boolean;
begin
  LProcesadosArr := TJSONArray.Create;
  LErroresArr := TJSONArray.Create;
  LResponse := TJSONObject.Create;

  try
    LBody := Req.Body<TJSONObject>;
    if not Assigned(LBody) or not (LBody.GetValue('ids') is TJSONArray) then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'Lista de IDs es requerida'));
      Exit;
    end;

    LIdsArr := LBody.GetValue('ids') as TJSONArray;
    LSession := Req.Session<TSessionInfoObj>.Data;

    for I := 0 to LIdsArr.Count - 1 do
    begin
      LId := StrToIntDef(LIdsArr.Items[I].Value, 0);
      if LId <= 0 then Continue;

      try
        Q := GetBridgeQuery;
        try
          Q.SQL.Text := 'SELECT * FROM XML_FILES WHERE ID = :ID';
          Q.ParamByName('ID').AsInteger := LId;
          Q.Open;

          if Q.IsEmpty then
          begin
            LErrorObj := TJSONObject.Create;
            LErrorObj.AddPair('id', TJSONNumber.Create(LId));
            LErrorObj.AddPair('error', 'Archivo no encontrado');
            LErroresArr.Add(LErrorObj);
            Continue;
          end;

          if Q.FieldByName('ESTADO').AsString = 'PROCESADO' then
          begin
            LErrorObj := TJSONObject.Create;
            LErrorObj.AddPair('id', TJSONNumber.Create(LId));
            LErrorObj.AddPair('error', 'El archivo ya fue procesado');
            LErroresArr.Add(LErrorObj);
            Continue;
          end;

          // Check if all products have equivalency
          QProd := GetBridgeQuery;
          try
            QProd.SQL.Text := 'SELECT COUNT(*) as TOTAL FROM XML_PRODUCTOS WHERE XML_FILE_ID = :FILEID AND EQUIVALENCIA_ID IS NULL';
            QProd.ParamByName('FILEID').AsInteger := LId;
            QProd.Open;
            LCanProcess := QProd.FieldByName('TOTAL').AsInteger = 0;
          finally
            QProd.Free;
          end;

          if not LCanProcess then
          begin
            LErrorObj := TJSONObject.Create;
            LErrorObj.AddPair('id', TJSONNumber.Create(LId));
            LErrorObj.AddPair('error', 'Existen productos sin homologación');
            LErroresArr.Add(LErrorObj);
            Continue;
          end;

          // Prepare data for Helisa
          LAnio := FormatDateTime('yyyy', Q.FieldByName('FECHA_DOCUMENTO').AsDateTime);
          LHeader.Proveedor := Q.FieldByName('PROVEEDOR_NIT').AsString;
          LHeader.Fecha := Q.FieldByName('FECHA_DOCUMENTO').AsDateTime;
          LHeader.Estado := 'PROCESADO';
          LHeader.XMLFileName := Q.FieldByName('FILE_NAME').AsString;
          LHeader.NombreUsuario := LSession.Nombre;
          LHeader.CodigoUsuario := LSession.Codigo.ToString;
          LHeader.Anio := LAnio;

          // Obtain CodigoTercero
          LHeader.CodigoTercero := ObtenerProveedorPorNit(LHeader.Proveedor, LAnio).Codigo;

          QProd := GetBridgeQuery;
          try
            QProd.SQL.Text :=
              'SELECT P.*, E.CODIGOH, E.SUBCODIGOH, E.REFERENCIAH, E.FACTOR ' +
              'FROM XML_PRODUCTOS P ' +
              'JOIN EQUIVALENCIA E ON P.EQUIVALENCIA_ID = E.ID ' +
              'WHERE P.XML_FILE_ID = :FILEID';
            QProd.ParamByName('FILEID').AsInteger := LId;
            QProd.Open;

            SetLength(LDetalles, QProd.RecordCount);
            J := 0;
            while not QProd.Eof do
            begin
              LFactor := QProd.FieldByName('FACTOR').AsFloat;
              if LFactor <= 0 then LFactor := 1;

              LDetalles[J].CodigoProducto := QProd.FieldByName('REFERENCIAH').AsString;
              LDetalles[J].CodigoConcepto := QProd.FieldByName('CODIGOH').AsInteger;
              LDetalles[J].Subcodigo := QProd.FieldByName('SUBCODIGOH').AsInteger;
              LDetalles[J].Cantidad := QProd.FieldByName('CANTIDAD').AsFloat * LFactor;
              LDetalles[J].Precio := QProd.FieldByName('VALOR_UNITARIO').AsFloat;
              LDetalles[J].Total := LDetalles[J].Cantidad * LDetalles[J].Precio;

              // Defaults for required fields in Helisa
              LDetalles[J].TfIva := 0;
              LDetalles[J].VrIva := 0;
              LDetalles[J].TfDescuento := 0;
              LDetalles[J].VrDescuento := 0;
              LDetalles[J].VrIca := 0;
              LDetalles[J].VrReteIca := 0;
              LDetalles[J].VrReteIva := 0;
              LDetalles[J].VrReteFuente := 0;

              Inc(J);
              QProd.Next;
            end;
          finally
            QProd.Free;
          end;

          // Insert into Helisa
          LDocumentoERP := GuardarDocumento(LHeader, LDetalles);

          // Update Status
          QProd := GetBridgeQuery;
          try
            QProd.SQL.Text := 'UPDATE XML_FILES SET ESTADO = ''PROCESADO'' WHERE ID = :ID';
            QProd.ParamByName('ID').AsInteger := LId;
            QProd.ExecSQL;
          finally
            QProd.Free;
          end;

          LProcesadoObj := TJSONObject.Create;
          LProcesadoObj.AddPair('id', TJSONNumber.Create(LId));
          LProcesadoObj.AddPair('documento', LDocumentoERP);
          LProcesadosArr.Add(LProcesadoObj);

        finally
          Q.Free;
        end;
      except
        on E: Exception do
        begin
          LErrorObj := TJSONObject.Create;
          LErrorObj.AddPair('id', TJSONNumber.Create(LId));
          LErrorObj.AddPair('error', E.Message);
          LErroresArr.Add(LErrorObj);
        end;
      end;
    end;

    LResponse.AddPair('procesados', LProcesadosArr);
    LResponse.AddPair('errores', LErroresArr);
    Res.Send(LResponse);

  except
    on E: Exception do
    begin
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
    end;
  end;
end;

procedure Validate(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LFileName, LIdStr, LPath, LFullFile: string;
  LXMLContent: string;
  LParsedInvoice: TParsedInvoice;
  LResponse: TJSONObject;
  LFileId: Integer;
begin
  try
    LBody := Req.Body<TJSONObject>;
    if (LBody = nil) then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'Cuerpo JSON requerido'));
      Exit;
    end;

    LFileName := '';
    if LBody.TryGetValue('fileName', LFileName) then
    begin
      LFileName := TPath.GetFileName(LFileName);
    end
    else if LBody.TryGetValue('id', LIdStr) then
    begin
      // If ID is provided, we might need to look up the filename in the DB
      // For now, let's assume fileName is preferred or we implement the lookup
    end;

    if LFileName = '' then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'fileName es requerido'));
      Exit;
    end;

    LPath := TPath.Combine('PurchaseBridge', 'Input');
    LFullFile := TPath.Combine(LPath, LFileName);

    if not TFile.Exists(LFullFile) then
    begin
      Res.Status(404).Send(TJSONObject.Create.AddPair('error', 'Archivo no encontrado físicamente'));
      Exit;
    end;

    LXMLContent := TFile.ReadAllText(LFullFile, TEncoding.UTF8);
    LParsedInvoice := TXmlParserService.Parse(LXMLContent);

    // Save/Update in DB
    LFileId := TXmlPersistenceService.SaveXmlHeader(LFileName, LParsedInvoice);
    TXmlPersistenceService.SaveXmlProducts(LFileId, LParsedInvoice.Products);

    LResponse := TJSONObject.Create;
    LResponse.AddPair('success', TJSONBool.Create(True));
    LResponse.AddPair('id', TJSONNumber.Create(LFileId));
    LResponse.AddPair('errores', TJSONArray.Create);
    LResponse.AddPair('advertencias', TJSONArray.Create);

    Res.Send(LResponse);

  except
    on E: Exception do
    begin
      Res.Status(500).Send(TJSONObject.Create.AddPair('success', TJSONBool.Create(False))
        .AddPair('error', E.Message));
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

procedure Registry;
begin
  THorse.Get('/xml/list', List);
  THorse.Get('/xml/files', ListFiles);
  THorse.Get('/xml/files/:id', GetFile);
  THorse.Get('/xml/productos/pendientes', GetPendingProducts);
  THorse.Post('/xml/upload', Upload);
  THorse.Post('/xml/parse', Parse);
  THorse.Post('/xml/validate', Validate);
  THorse.Post('/xml/procesar', ProcesarXml);
end;

end.
