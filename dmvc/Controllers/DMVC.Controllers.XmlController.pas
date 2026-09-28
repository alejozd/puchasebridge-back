unit DMVC.Controllers.XmlController;

interface

uses
  MVCFramework, MVCFramework.Commons;

type
  [MVCPath('/')]
  TXmlController = class(TMVCController)
  public
    [MVCPath('/xml/list')]
    [MVCPath('/api/xml/list')]
    [MVCPath('/xml/files')]
    [MVCPath('/api/xml/files')]
    [MVCHTTPMethod([httpGET])]
    procedure GetFiles;

    [MVCPath('/xml/files/($id)')]
    [MVCPath('/api/xml/files/($id)')]
    [MVCHTTPMethod([httpGET])]
    procedure GetFileById(const id: string);

    [MVCPath('/xml/parse')]
    [MVCPath('/api/xml/parse')]
    [MVCHTTPMethod([httpPOST])]
    procedure Parse;

    [MVCPath('/xml/productos/pendientes')]
    [MVCPath('/api/xml/productos/pendientes')]
    [MVCHTTPMethod([httpGET])]
    procedure GetProductosPendientes(const [MVCFromQueryString('fileName', '')] AFileName: String);

    [MVCPath('/xml/productos/documento')]
    [MVCPath('/api/xml/productos/documento')]
    [MVCHTTPMethod([httpGET])]
    procedure GetProductosDocumento(const [MVCFromQueryString('fileName', '')] AFileName: String);

    [MVCPath('/dashboard/metrics')]
    [MVCPath('/api/dashboard/metrics')]
    [MVCHTTPMethod([httpGET])]
    procedure GetDashboardMetrics;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Types,
  System.Generics.Collections, System.Generics.Defaults,
  FireDAC.Comp.Client, FirebirdConnection,
  XmlParserService, DianUnits, uPaths;

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
  if (LCode = '94') or (LCode = 'NIU') then
    Result := 'UND'
  else if LCode = 'KGM' then
    Result := 'KG'
  else if LCode = 'LTR' then
    Result := 'LT'
  else
    Result := AUnidadCodigo;
end;

function FindFileFullPath(const AFileName: string): string;
var
  LSearchPaths: TArray<string>;
  LPath, LCandidate: string;
begin
  Result := '';
  LSearchPaths := [GetInputPath, GetProcessedPath, GetOutputPath];
  for LPath in LSearchPaths do
  begin
    LCandidate := TPath.Combine(LPath, AFileName);
    if TFile.Exists(LCandidate) then
      Exit(LCandidate);
  end;
end;

function FindXmlFile(const AFileName: string): string;
var
  LInputPath, LProcessedPath: string;
begin
  Result := '';
  LInputPath := GetInputPath;
  LProcessedPath := GetProcessedPath;
  if TFile.Exists(TPath.Combine(LInputPath, AFileName)) then
    Exit(TPath.Combine(LInputPath, AFileName));
  if TFile.Exists(TPath.Combine(LProcessedPath, AFileName)) then
    Exit(TPath.Combine(LProcessedPath, AFileName));
end;

procedure TXmlController.GetFiles;
var
  Q: TFDQuery;
  LPath, LFile, LFileNameOnly, LPhysicalPath, LKey: string;
  LSearchPaths: TArray<string>;
  LFiles: TStringDynArray;
  LCombinedList: TList<TCombinedFileInfo>;
  LInfo: TCombinedFileInfo;
  LDBData: TDictionary<string, TCombinedFileInfo>;
  LJSONList: TJSONArray;
  LJSONObj: TJSONObject;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  LCombinedList := TList<TCombinedFileInfo>.Create;
  try
    LDBData := TDictionary<string, TCombinedFileInfo>.Create;
    try
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

      for LKey in LDBData.Keys do
      begin
        LInfo := LDBData.Items[LKey];
        LPhysicalPath := FindFileFullPath(LInfo.FileName);
        if not LPhysicalPath.IsEmpty then
        begin
          LInfo.Size := TFile.GetSize(LPhysicalPath);
          LInfo.LastModified := TFile.GetLastWriteTime(LPhysicalPath);
          LDBData.Items[LKey] := LInfo;
        end;
      end;

      LSearchPaths := [GetInputPath, GetProcessedPath, GetOutputPath];
      for LPath in LSearchPaths do
      begin
        if TDirectory.Exists(LPath) then
        begin
          LFiles := TDirectory.GetFiles(LPath, '*.xml');
          for LFile in LFiles do
          begin
            LFileNameOnly := TPath.GetFileName(LFile);
            if LDBData.TryGetValue(LFileNameOnly.ToLower, LInfo) then
            begin
              if (LInfo.Size <= 0) or (LInfo.LastModified <= 0) then
              begin
                LInfo.Size := TFile.GetSize(LFile);
                LInfo.LastModified := TFile.GetLastWriteTime(LFile);
                LDBData.Items[LFileNameOnly.ToLower] := LInfo;
              end;
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
      end;

      for LInfo in LDBData.Values do
        LCombinedList.Add(LInfo);

      LCombinedList.Sort(TComparer<TCombinedFileInfo>.Construct(
        function(const Left, Right: TCombinedFileInfo): Integer
        begin
          if Left.FechaCarga < Right.FechaCarga then Result := 1
          else if Left.FechaCarga > Right.FechaCarga then Result := -1
          else Result := 0;
        end));

      LJSONList := TJSONArray.Create;
      try
        for LInfo in LCombinedList do
        begin
          LJSONObj := TJSONObject.Create;
          LJSONObj.AddPair('id', TJSONNumber.Create(LInfo.ID));
          LJSONObj.AddPair('fileName', LInfo.FileName);
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
          if LInfo.LastModified > 0 then
            LJSONObj.AddPair('lastModified', FormatDateTime('yyyy-mm-dd HH:nn:ss', LInfo.LastModified))
          else
            LJSONObj.AddPair('lastModified', TJSONNull.Create);
          LJSONList.AddElement(LJSONObj);
        end;
        Render(LJSONList.ToJSON);
      finally
        LJSONList.Free;
      end;
    finally
      LDBData.Free;
    end;
  finally
    LCombinedList.Free;
  end;
end;

procedure TXmlController.GetFileById(const id: string);
var
  Q: TFDQuery;
  LFileID: Integer;
  LResponse, LProductObj: TJSONObject;
  LProductsArr: TJSONArray;
  LUnidadCodigo: string;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  LFileID := StrToIntDef(id, 0);
  if LFileID = 0 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'ID inválido');

  Q := GetBridgeQuery;
  try
    Q.SQL.Text := 'SELECT * FROM XML_FILES WHERE ID = :ID';
    Q.ParamByName('ID').AsInteger := LFileID;
    Q.Open;

    if Q.IsEmpty then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Archivo no encontrado');

    LResponse := TJSONObject.Create;
    try
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
        LProductObj.AddPair('unidad', ResolveUnidadSigla(LUnidadCodigo));
        LProductObj.AddPair('unidadDescripcion', TDianUnits.GetUnitName(LUnidadCodigo));
        LProductObj.AddPair('valorUnitario', TJSONNumber.Create(Q.FieldByName('VALOR_UNITARIO').AsFloat));
        LProductObj.AddPair('valorTotal', TJSONNumber.Create(Q.FieldByName('VALOR_TOTAL').AsFloat));
        LProductObj.AddPair('impuesto', TJSONNumber.Create(Q.FieldByName('IMPUESTO').AsFloat));
        if not Q.FieldByName('EQUIVALENCIA_ID').IsNull then
        begin
          LProductObj.AddPair('equivalenciaId', TJSONNumber.Create(Q.FieldByName('EQUIVALENCIA_ID').AsInteger));
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

      Render(LResponse.ToJSON);
    finally
      LResponse.Free;
    end;
  finally
    Q.Free;
  end;
end;

procedure TXmlController.Parse;
var
  LBody: TJSONObject;
  LFileName, LFullFile, LXMLContent: string;
  LParsedInvoice: TParsedInvoice;
  LResponse, LProveedorObj, LTotalesObj, LProductoObj: TJSONObject;
  LProductosArr: TJSONArray;
  I: Integer;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  LBody := TJSONObject.ParseJSONValue(Context.Request.Body) as TJSONObject;
  try
    if (LBody = nil) or not LBody.TryGetValue('fileName', LFileName) then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'fileName is required in the body');
  finally
    LBody.Free;
  end;

  LFileName := TPath.GetFileName(LFileName);
  LFullFile := FindXmlFile(LFileName);
  if LFullFile.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Archivo no encontrado');

  try
    LXMLContent := TFile.ReadAllText(LFullFile, TEncoding.UTF8);
  except
    on E: Exception do
      raise EMVCException.Create(HTTP_STATUS.InternalServerError, 'Error reading file: ' + E.Message);
  end;

  try
    LParsedInvoice := TXmlParserService.Parse(LXMLContent);
  except
    on E: Exception do
      raise EMVCException.Create(HTTP_STATUS.UnprocessableEntity, 'XML inválido');
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
    LTotalesObj.AddPair('retencion', TJSONNumber.Create(LParsedInvoice.Totals.RetencionTotal));
    LTotalesObj.AddPair('total', TJSONNumber.Create(LParsedInvoice.Totals.Total));
    LResponse.AddPair('totales', LTotalesObj);

    Render(LResponse.ToJSON);
  finally
    LResponse.Free;
  end;
end;

procedure TXmlController.GetProductosPendientes(const AFileName: String);
var
  Q: TFDQuery;
  LJSONList: TJSONArray;
  LJSONObj: TJSONObject;
  LFileID: Integer;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  if AFileName.Trim.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'fileName is required');

  Q := GetBridgeQuery;
  try
    Q.SQL.Text := 'SELECT ID FROM XML_FILES WHERE FILE_NAME = :FNAME';
    Q.ParamByName('FNAME').AsString := AFileName;
    Q.Open;

    if Q.IsEmpty then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'File not found in staging');

    LFileID := Q.FieldByName('ID').AsInteger;
    Q.Close;

    Q.SQL.Text :=
      'SELECT REFERENCIA AS REFERENCIAXML, DESCRIPCION AS NOMBREPRODUCTO, UNIDAD AS UNIDADXML ' +
      'FROM XML_PRODUCTOS ' +
      'WHERE XML_FILE_ID = :FILEID AND EQUIVALENCIA_ID IS NULL';
    Q.ParamByName('FILEID').AsInteger := LFileID;
    Q.Open;

    LJSONList := TJSONArray.Create;
    try
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
      Render(LJSONList.ToJSON);
    finally
      LJSONList.Free;
    end;
  finally
    Q.Free;
  end;
end;

procedure TXmlController.GetProductosDocumento(const AFileName: String);
var
  Q: TFDQuery;
  LResponse: TJSONObject;
  LProductsArr: TJSONArray;
  LProductObj: TJSONObject;
  LFileID: Integer;
  LTotalProductos, LTotalPendientes, LTotalHomologados: Integer;
  LUnidadErp: string;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  if AFileName.Trim.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'fileName is required');

  Q := GetBridgeQuery;
  try
    Q.SQL.Text := 'SELECT ID FROM XML_FILES WHERE FILE_NAME = :FNAME';
    Q.ParamByName('FNAME').AsString := AFileName;
    Q.Open;

    if Q.IsEmpty then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'File not found in staging');

    LFileID := Q.FieldByName('ID').AsInteger;
    Q.Close;

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
    try
      LResponse.AddPair('totalProductos', TJSONNumber.Create(LTotalProductos));
      LResponse.AddPair('totalPendientes', TJSONNumber.Create(LTotalPendientes));
      LResponse.AddPair('totalHomologados', TJSONNumber.Create(LTotalHomologados));
      LResponse.AddPair('productos', LProductsArr);
      Render(LResponse.ToJSON);
    finally
      LResponse.Free;
    end;
  finally
    Q.Free;
  end;
end;

procedure TXmlController.GetDashboardMetrics;
var
  Q: TFDQuery;
  LResponse: TJSONObject;
  LTotal, LCargados, LPendientes, LListos, LProcesados, LErrores: Integer;
  LProcesadosHoy, LErroresHoy: Integer;
  LEstado: string;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  LCargados := 0; LPendientes := 0; LListos := 0; LProcesados := 0; LErrores := 0;

  Q := GetBridgeQuery;
  try
    Q.SQL.Text := 'SELECT COUNT(*) AS TOTAL FROM XML_FILES';
    Q.Open;
    LTotal := Q.FieldByName('TOTAL').AsInteger;
    Q.Close;

    Q.SQL.Text := 'SELECT ESTADO, COUNT(*) AS TOTAL FROM XML_FILES GROUP BY ESTADO';
    Q.Open;
    while not Q.Eof do
    begin
      LEstado := UpperCase(Q.FieldByName('ESTADO').AsString.Trim);
      if LEstado = 'CARGADO' then LCargados := Q.FieldByName('TOTAL').AsInteger
      else if LEstado = 'PENDIENTE' then LPendientes := Q.FieldByName('TOTAL').AsInteger
      else if LEstado = 'VALIDADO' then LListos := Q.FieldByName('TOTAL').AsInteger
      else if LEstado = 'PROCESADO' then LProcesados := Q.FieldByName('TOTAL').AsInteger
      else if LEstado = 'ERROR' then LErrores := Q.FieldByName('TOTAL').AsInteger;
      Q.Next;
    end;
    Q.Close;

    Q.SQL.Text :=
      'SELECT COUNT(*) AS TOTAL FROM XML_FILES ' +
      'WHERE ESTADO = ''PROCESADO'' AND CAST(COALESCE(FECHA_PROCESO, FECHA_CARGA) AS DATE) = CURRENT_DATE';
    Q.Open;
    LProcesadosHoy := Q.FieldByName('TOTAL').AsInteger;
    Q.Close;

    Q.SQL.Text :=
      'SELECT COUNT(*) AS TOTAL FROM XML_FILES ' +
      'WHERE ESTADO = ''ERROR'' AND CAST(COALESCE(FECHA_PROCESO, FECHA_CARGA) AS DATE) = CURRENT_DATE';
    Q.Open;
    LErroresHoy := Q.FieldByName('TOTAL').AsInteger;
    Q.Close;

    LResponse := TJSONObject.Create;
    try
      LResponse.AddPair('total', TJSONNumber.Create(LTotal));
      LResponse.AddPair('cargados', TJSONNumber.Create(LCargados));
      LResponse.AddPair('pendientes', TJSONNumber.Create(LPendientes));
      LResponse.AddPair('listos', TJSONNumber.Create(LListos));
      LResponse.AddPair('procesados', TJSONNumber.Create(LProcesados));
      LResponse.AddPair('errores', TJSONNumber.Create(LErrores));
      LResponse.AddPair('procesadosHoy', TJSONNumber.Create(LProcesadosHoy));
      LResponse.AddPair('erroresHoy', TJSONNumber.Create(LErroresHoy));
      Render(LResponse.ToJSON);
    finally
      LResponse.Free;
    end;
  finally
    Q.Free;
  end;
end;

end.
