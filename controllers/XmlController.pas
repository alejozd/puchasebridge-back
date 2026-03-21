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
  XmlProcessingService,
  ValidationService,
  FireDAC.Comp.Client,
  FirebirdConnection,
  AuthService,
  AuthMiddleware,
  DocumentoService,
  EquivalenciaService,
  ProveedorRepository;

type
  TFileInfo = record
    FileName: string;
    Size: Int64;
    LastModified: TDateTime;
  end;

procedure ListFiles(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LResult: TJSONArray;
begin
  try
    LResult := TXmlPersistenceService.ListFiles;
    Res.Send(LResult);
  except
    on E: Exception do
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
  end;
end;

procedure GetFile(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LId: Integer;
  LDetail: TJSONObject;
begin
  try
    LId := StrToIntDef(Req.Params['id'], 0);
    if LId <= 0 then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'ID de archivo inválido'));
      Exit;
    end;

    LDetail := TXmlPersistenceService.GetFileDetail(LId);
    if Assigned(LDetail) then
      Res.Send(LDetail)
    else
      Res.Status(404).Send(TJSONObject.Create.AddPair('error', 'Archivo no encontrado'));
  except
    on E: Exception do
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
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
          if Left.LastModified < Right.LastModified then Result := 1
          else if Left.LastModified > Right.LastModified then Result := -1
          else Result := 0;
        end));

      LJSONList := TJSONArray.Create;
      for LFileInfo in LFileInfoList do
      begin
        LJSONObj := TJSONObject.Create;
        LJSONObj.AddPair('fileName', LFileInfo.FileName);
        LJSONObj.AddPair('size', TJSONNumber.Create(LFileInfo.Size));
        LJSONObj.AddPair('lastModified', FormatDateTime('yyyy-mm-dd HH:nn:ss', LFileInfo.LastModified));
        LJSONList.AddElement(LJSONObj);
      end;
      Res.Send(LJSONList);
    finally
      LFileInfoList.Free;
    end;
  except
    on E: Exception do
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
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
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'No file uploaded with field name "file"'));
      Exit;
    end;

    LFileName := LFile.FileName;
    if not SameText(ExtractFileExt(LFileName), '.xml') then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'The file must have a .xml extension'));
      Exit;
    end;

    LPath := TPath.Combine('PurchaseBridge', 'Input');
    if not TDirectory.Exists(LPath) then TDirectory.CreateDirectory(LPath);
    LFullFile := TPath.Combine(LPath, LFileName);

    LFile.Stream.Position := 0;
    LFileStream := TFileStream.Create(LFullFile, fmCreate);
    try
      LFileStream.CopyFrom(LFile.Stream, LFile.Stream.Size);
    finally
      LFileStream.Free;
    end;

    LResponse := TJSONObject.Create;
    LResponse.AddPair('success', True);
    LResponse.AddPair('message', 'XML uploaded successfully');
    LResponse.AddPair('fileName', LFileName);
    LResponse.AddPair('path', LFullFile.Replace('\', '/'));
    Res.Send(LResponse);
  except
    on E: Exception do
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
  end;
end;

procedure GetPendingProducts(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LResult: TJSONArray;
begin
  try
    LResult := TXmlPersistenceService.ListPendingProducts;
    Res.Send(LResult);
  except
    on E: Exception do
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
  end;
end;

procedure ProcesarXml(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LIdsArr: TJSONArray;
  LSessionObj: TSessionInfoObj;
  LResult: TJSONObject;
begin
  try
    LBody := Req.Body<TJSONObject>;
    if not Assigned(LBody) or not (LBody.GetValue('ids') is TJSONArray) then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'Lista de IDs es requerida'));
      Exit;
    end;

    LIdsArr := LBody.GetValue('ids') as TJSONArray;
    LSessionObj := Req.Session<TSessionInfoObj>;
    if not Assigned(LSessionObj) then
    begin
      Res.Status(401).Send(TJSONObject.Create.AddPair('error', 'Sesión no válida'));
      Exit;
    end;

    LResult := TXmlProcessingService.ProcesarBatch(LIdsArr, LSessionObj.Data);
    Res.Send(LResult);
  except
    on E: Exception do
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
  end;
end;

procedure Validate(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LFileName, LPath, LFullFile: string;
  LId: Integer;
  LXMLContent: string;
  LParsedInvoice: TParsedInvoice;
  LResponse: TJSONObject;
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
      LFileName := TPath.GetFileName(LFileName)
    else if LBody.TryGetValue('id', LId) then
      LFileName := TXmlPersistenceService.GetFileNameById(LId);

    if LFileName = '' then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'fileName o id válido es requerido'));
      Exit;
    end;

    LPath := TPath.Combine('PurchaseBridge', 'Input');
    LFullFile := TPath.Combine(LPath, LFileName);

    if not TFile.Exists(LFullFile) then
    begin
      Res.Status(404).Send(TJSONObject.Create.AddPair('error', 'Archivo no encontrado físicamente: ' + LFileName));
      Exit;
    end;

    LXMLContent := TFile.ReadAllText(LFullFile, TEncoding.UTF8);
    LParsedInvoice := TXmlParserService.Parse(LXMLContent);

    LId := TXmlPersistenceService.SaveXmlHeader(LFileName, LParsedInvoice);
    TXmlPersistenceService.SaveXmlProducts(LId, LParsedInvoice.Products);

    LResponse := TJSONObject.Create;
    LResponse.AddPair('success', True);
    LResponse.AddPair('id', LId);
    LResponse.AddPair('errores', TJSONArray.Create);
    LResponse.AddPair('advertencias', TJSONArray.Create);
    Res.Send(LResponse);
  except
    on E: Exception do
      Res.Status(500).Send(TJSONObject.Create.AddPair('success', False).AddPair('error', E.Message));
  end;
end;

procedure Parse(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LFileName, LPath, LFullFile, LXMLContent: string;
  LParsedInvoice: TParsedInvoice;
  LResponse, LProveedorObj, LTotalesObj, LProductoObj: TJSONObject;
  LProductosArr: TJSONArray;
  I: Integer;
begin
  try
    LBody := Req.Body<TJSONObject>;
    if (LBody = nil) or not LBody.TryGetValue('fileName', LFileName) then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'fileName is required'));
      Exit;
    end;

    LFileName := TPath.GetFileName(LFileName);
    LPath := TPath.Combine('PurchaseBridge', 'Input');
    LFullFile := TPath.Combine(LPath, LFileName);

    if not TFile.Exists(LFullFile) then
    begin
      Res.Status(404).Send(TJSONObject.Create.AddPair('error', 'Archivo no encontrado'));
      Exit;
    end;

    LXMLContent := TFile.ReadAllText(LFullFile, TEncoding.UTF8);
    LParsedInvoice := TXmlParserService.Parse(LXMLContent);

    LResponse := TJSONObject.Create;
    try
      LResponse.AddPair('success', True);
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
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
  end;
end;

procedure Registry;
begin
  THorse.Get('/xml/list', List);
  THorse.Post('/xml/upload', Upload);
  THorse.Post('/xml/parse', Parse);

  THorse.Get('/xml/files', ListFiles);
  THorse.Get('/xml/files/:id', GetFile);
  THorse.Get('/xml/productos/pendientes', GetPendingProducts);
  THorse.Post('/xml/validate', Validate);
  THorse.Post('/xml/procesar', ProcesarXml);
end;

end.
