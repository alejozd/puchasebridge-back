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
  EquivalenciaService;

type
  TFileInfo = record
    FileName: string;
    Size: Int64;
    LastModified: TDateTime;
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
  Res.ContentType('application/json; charset=utf-8');
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
      LResponse.AddPair('proveedorNombre', Q.FieldByName('PROVEEDOR_NOMBRE').AsString);
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
        LProductObj.AddPair('unidadXML', Q.FieldByName('UNIDADH').AsString);
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
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    Q := GetBridgeQuery;
    try
      Q.SQL.Text :=
        'SELECT P.*, F.FILE_NAME FROM XML_PRODUCTOS P ' +
        'JOIN XML_FILES F ON P.XML_FILE_ID = F.ID ' +
        'WHERE P.EQUIVALENCIA_ID IS NULL ' +
        'ORDER BY F.FECHA_CARGA DESC';
      Q.Open;

      LJSONList := TJSONArray.Create;
      while not Q.Eof do
      begin
        if Q.FieldByName('REFERENCIA').AsString.Trim.IsEmpty or
           Q.FieldByName('DESCRIPCION').AsString.Trim.IsEmpty or
           Q.FieldByName('UNIDADH').AsString.Trim.IsEmpty then
        begin
          Q.Next;
          Continue;
        end;

        LJSONObj := TJSONObject.Create;
        LJSONObj.AddPair('fileName', Q.FieldByName('FILE_NAME').AsString);
        LJSONObj.AddPair('nombreXML', Q.FieldByName('DESCRIPCION').AsString);
        LJSONObj.AddPair('referenciaXML', Q.FieldByName('REFERENCIA').AsString);
        LJSONObj.AddPair('referenciaStd', Q.FieldByName('REFERENCIA_STD').AsString);
        LJSONObj.AddPair('cantidad', TJSONNumber.Create(Q.FieldByName('CANTIDAD').AsFloat));
        LJSONObj.AddPair('unidadXML', Q.FieldByName('UNIDADH').AsString);
        LJSONObj.AddPair('valorUnitario', TJSONNumber.Create(Q.FieldByName('VALOR_UNITARIO').AsFloat));
        LJSONObj.AddPair('valorTotal', TJSONNumber.Create(Q.FieldByName('VALOR_TOTAL').AsFloat));
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
  LJSONList: TJSONArray;
  LJSONObj: TJSONObject;
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    Q := GetBridgeQuery;
    try
      Q.SQL.Text := 'SELECT * FROM XML_FILES ORDER BY FECHA_CARGA DESC';
      Q.Open;

      LJSONList := TJSONArray.Create;
      while not Q.Eof do
      begin
        LJSONObj := TJSONObject.Create;
        LJSONObj.AddPair('id', TJSONNumber.Create(Q.FieldByName('ID').AsInteger));
        LJSONObj.AddPair('fileName', Q.FieldByName('FILE_NAME').AsString);
        LJSONObj.AddPair('proveedorNit', Q.FieldByName('PROVEEDOR_NIT').AsString);
        LJSONObj.AddPair('proveedorNombre', Q.FieldByName('PROVEEDOR_NOMBRE').AsString);
        LJSONObj.AddPair('fechaDocumento', FormatDateTime('yyyy-mm-dd', Q.FieldByName('FECHA_DOCUMENTO').AsDateTime));
        LJSONObj.AddPair('estado', Q.FieldByName('ESTADO').AsString);
        LJSONObj.AddPair('fechaCarga', FormatDateTime('yyyy-mm-dd HH:nn:ss', Q.FieldByName('FECHA_CARGA').AsDateTime));
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

procedure Homologar(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LReferenciaXML, LUnidadXML, LReferenciaP, LUnidadP: string;
  LFactor: Double;
  LResponse: TJSONObject;
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    LBody := Req.Body<TJSONObject>;
    if (LBody = nil) then
    begin
      Res.Status(400).Send('Body is required');
      Exit;
    end;

    LReferenciaXML := LBody.GetValue('referenciaXML').Value;
    LUnidadXML := LBody.GetValue('unidadXML').Value;
    LReferenciaP := LBody.GetValue('referenciaP').Value;
    LUnidadP := LBody.GetValue('unidadP').Value;
    LFactor := (LBody.GetValue('factor') as TJSONNumber).AsDouble;

    if LReferenciaXML.Trim.IsEmpty or LUnidadXML.Trim.IsEmpty or
       LReferenciaP.Trim.IsEmpty or LUnidadP.Trim.IsEmpty then
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'Todos los campos son obligatorios');
      Res.Status(400).Send(LResponse);
      Exit;
    end;

    try
      // REFERENCIAH -> referencia XML (referenciaXML)
      // UNIDADH -> unidad XML (unidadXML)
      // REFERENCIAP -> referencia ERP (referenciaP)
      // UNIDADP -> código unidad ERP (unidadP)
      EquivalenciaService.CrearEquivalencia(
        0, 0, '', LReferenciaP, LUnidadP, LUnidadXML, LReferenciaXML, LFactor
      );

      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(True));
      LResponse.AddPair('message', 'Homologación guardada correctamente');
      Res.Send(LResponse);
    except
      on E: Exception do
      begin
        LResponse := TJSONObject.Create;
        LResponse.AddPair('success', TJSONBool.Create(False));
        LResponse.AddPair('message', 'Error al guardar homologación: ' + E.Message);
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
  THorse.Get('/xml/list', List);
  THorse.Post('/xml/upload', Upload);
  THorse.Post('/xml/parse', Parse);
  THorse.Get('/xml/files', GetFiles);
  THorse.Get('/xml/files/:id', GetFileById);
  THorse.Post('/xml/procesar', ProcesarBatch);
  THorse.Get('/xml/productos/pendientes', GetProductosPendientes);
  THorse.Post('/xml/homologar', Homologar);
end;

end.
