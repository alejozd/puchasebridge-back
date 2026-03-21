unit XmlPersistenceService;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection,
  XmlParserService;

type
  TXmlPersistenceService = class
  public
    class function SaveXmlHeader(const AFileName: string; const AParsedInvoice: TParsedInvoice): Integer;
    class procedure SaveXmlProducts(AXmlFileId: Integer; const AProducts: TArray<TProductInfo>);
    class function GetXmlFileId(const AFileName: string): Integer;
    class function GetFileNameById(AId: Integer): string;
    class function ListFiles: TJSONArray;
    class function GetFileDetail(AId: Integer): TJSONObject;
    class function ListPendingProducts: TJSONArray;
    class procedure UpdateFileStatus(AId: Integer; const AStatus: string);
  end;

implementation

{ TXmlPersistenceService }

class function TXmlPersistenceService.GetXmlFileId(const AFileName: string): Integer;
var
  Q: TFDQuery;
begin
  Result := 0;
  Q := GetBridgeQuery;
  try
    Q.SQL.Text := 'SELECT ID FROM XML_FILES WHERE FILE_NAME = :FNAME';
    Q.ParamByName('FNAME').AsString := AFileName;
    Q.Open;
    if not Q.IsEmpty then
      Result := Q.FieldByName('ID').AsInteger;
  finally
    Q.Free;
  end;
end;

class function TXmlPersistenceService.GetFileNameById(AId: Integer): string;
var
  Q: TFDQuery;
begin
  Result := '';
  Q := GetBridgeQuery;
  try
    Q.SQL.Text := 'SELECT FILE_NAME FROM XML_FILES WHERE ID = :ID';
    Q.ParamByName('ID').AsInteger := AId;
    Q.Open;
    if not Q.IsEmpty then
      Result := Q.FieldByName('FILE_NAME').AsString;
  finally
    Q.Free;
  end;
end;

class function TXmlPersistenceService.SaveXmlHeader(const AFileName: string; const AParsedInvoice: TParsedInvoice): Integer;
var
  Q: TFDQuery;
  LId: Integer;
begin
  LId := GetXmlFileId(AFileName);
  Q := GetBridgeQuery;
  try
    if LId > 0 then
    begin
      Q.SQL.Text :=
        'UPDATE XML_FILES SET PROVEEDOR_NIT = :NIT, PROVEEDOR_NOMBRE = :NOMBRE, ' +
        'FECHA_DOCUMENTO = :FECHA, ESTADO = ''VALIDADO'' WHERE ID = :ID';
      Q.ParamByName('ID').AsInteger := LId;
      Result := LId;
    end
    else
    begin
      Q.SQL.Text :=
        'INSERT INTO XML_FILES (FILE_NAME, PROVEEDOR_NIT, PROVEEDOR_NOMBRE, FECHA_DOCUMENTO, ESTADO) ' +
        'VALUES (:FNAME, :NIT, :NOMBRE, :FECHA, ''VALIDADO'') RETURNING ID';
      Q.ParamByName('FNAME').AsString := AFileName;
    end;

    Q.ParamByName('NIT').AsString := AParsedInvoice.Provider.NIT;
    Q.ParamByName('NOMBRE').AsString := AParsedInvoice.Provider.Nombre;
    Q.ParamByName('FECHA').AsDateTime := AParsedInvoice.FechaEmision;

    if LId > 0 then
      Q.ExecSQL
    else
    begin
      Q.Open;
      Result := Q.FieldByName('ID').AsInteger;
    end;
  finally
    Q.Free;
  end;
end;

class procedure TXmlPersistenceService.SaveXmlProducts(AXmlFileId: Integer; const AProducts: TArray<TProductInfo>);
var
  Q, QEquiv: TFDQuery;
  I: Integer;
  LEquivId: Integer;
begin
  Q := GetBridgeQuery;
  QEquiv := GetBridgeQuery;
  try
    Q.SQL.Text := 'DELETE FROM XML_PRODUCTOS WHERE XML_FILE_ID = :FILEID';
    Q.ParamByName('FILEID').AsInteger := AXmlFileId;
    Q.ExecSQL;

    Q.SQL.Text :=
      'INSERT INTO XML_PRODUCTOS (XML_FILE_ID, DESCRIPCION, REFERENCIA, CANTIDAD, UNIDAD, ' +
      'VALOR_UNITARIO, VALOR_TOTAL, EQUIVALENCIA_ID) ' +
      'VALUES (:FILEID, :DESC, :REF, :CANT, :UNI, :PREC, :TOTAL, :EQUIVID)';

    QEquiv.SQL.Text := 'SELECT ID FROM EQUIVALENCIA WHERE REFERENCIAP = :REF AND UNIDADP = :UNI';

    for I := 0 to Length(AProducts) - 1 do
    begin
      LEquivId := 0;
      QEquiv.Close;
      QEquiv.ParamByName('REF').AsString := AProducts[I].Referencia;
      QEquiv.ParamByName('UNI').AsString := AProducts[I].Unidad;
      QEquiv.Open;
      if not QEquiv.IsEmpty then
        LEquivId := QEquiv.FieldByName('ID').AsInteger;

      Q.ParamByName('FILEID').AsInteger := AXmlFileId;
      Q.ParamByName('DESC').AsString := AProducts[I].Descripcion;
      Q.ParamByName('REF').AsString := AProducts[I].Referencia;
      Q.ParamByName('CANT').AsFloat := AProducts[I].Cantidad;
      Q.ParamByName('UNI').AsString := AProducts[I].Unidad;
      Q.ParamByName('PREC').AsFloat := AProducts[I].ValorUnitario;
      Q.ParamByName('TOTAL').AsFloat := AProducts[I].ValorTotal;

      if LEquivId > 0 then
        Q.ParamByName('EQUIVID').AsInteger := LEquivId
      else
        Q.ParamByName('EQUIVID').Clear;

      Q.ExecSQL;
    end;
  finally
    QEquiv.Free;
    Q.Free;
  end;
end;

class function TXmlPersistenceService.ListFiles: TJSONArray;
var
  Q: TFDQuery;
  LObj: TJSONObject;
begin
  Result := TJSONArray.Create;
  Q := GetBridgeQuery;
  try
    Q.SQL.Text := 'SELECT ID, FILE_NAME, PROVEEDOR_NOMBRE, FECHA_DOCUMENTO, ESTADO, FECHA_CARGA FROM XML_FILES ORDER BY FECHA_CARGA DESC';
    Q.Open;
    while not Q.Eof do
    begin
      LObj := TJSONObject.Create;
      LObj.AddPair('id', TJSONNumber.Create(Q.FieldByName('ID').AsInteger));
      LObj.AddPair('file_name', Q.FieldByName('FILE_NAME').AsString);
      LObj.AddPair('proveedor_nombre', Q.FieldByName('PROVEEDOR_NOMBRE').AsString);
      if not Q.FieldByName('FECHA_DOCUMENTO').IsNull then
        LObj.AddPair('fecha_documento', FormatDateTime('yyyy-mm-dd HH:nn:ss', Q.FieldByName('FECHA_DOCUMENTO').AsDateTime))
      else
        LObj.AddPair('fecha_documento', TJSONNull.Create);
      LObj.AddPair('estado', Q.FieldByName('ESTADO').AsString);
      LObj.AddPair('fecha_carga', FormatDateTime('yyyy-mm-dd HH:nn:ss', Q.FieldByName('FECHA_CARGA').AsDateTime));
      Result.AddElement(LObj);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

class function TXmlPersistenceService.GetFileDetail(AId: Integer): TJSONObject;
var
  Q, QProd: TFDQuery;
  LFileObj, LProdObj: TJSONObject;
  LProdArr: TJSONArray;
begin
  Result := nil;
  Q := GetBridgeQuery;
  try
    Q.SQL.Text := 'SELECT * FROM XML_FILES WHERE ID = :ID';
    Q.ParamByName('ID').AsInteger := AId;
    Q.Open;

    if Q.IsEmpty then Exit;

    Result := TJSONObject.Create;
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
    Result.AddPair('archivo', LFileObj);

    QProd := GetBridgeQuery;
    try
      QProd.SQL.Text := 'SELECT * FROM XML_PRODUCTOS WHERE XML_FILE_ID = :FILEID';
      QProd.ParamByName('FILEID').AsInteger := AId;
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
      Result.AddPair('productos', LProdArr);
    finally
      QProd.Free;
    end;
  finally
    Q.Free;
  end;
end;

class function TXmlPersistenceService.ListPendingProducts: TJSONArray;
var
  Q: TFDQuery;
  LObj: TJSONObject;
begin
  Result := TJSONArray.Create;
  Q := GetBridgeQuery;
  try
    Q.SQL.Text :=
      'SELECT P.*, F.FILE_NAME, F.PROVEEDOR_NOMBRE FROM XML_PRODUCTOS P ' +
      'JOIN XML_FILES F ON P.XML_FILE_ID = F.ID WHERE P.EQUIVALENCIA_ID IS NULL';
    Q.Open;
    while not Q.Eof do
    begin
      LObj := TJSONObject.Create;
      LObj.AddPair('id', TJSONNumber.Create(Q.FieldByName('ID').AsInteger));
      LObj.AddPair('xml_file_id', TJSONNumber.Create(Q.FieldByName('XML_FILE_ID').AsInteger));
      LObj.AddPair('file_name', Q.FieldByName('FILE_NAME').AsString);
      LObj.AddPair('proveedor_nombre', Q.FieldByName('PROVEEDOR_NOMBRE').AsString);
      LObj.AddPair('descripcion', Q.FieldByName('DESCRIPCION').AsString);
      LObj.AddPair('referencia', Q.FieldByName('REFERENCIA').AsString);
      LObj.AddPair('cantidad', TJSONNumber.Create(Q.FieldByName('CANTIDAD').AsFloat));
      LObj.AddPair('unidad', Q.FieldByName('UNIDAD').AsString);
      LObj.AddPair('valor_unitario', TJSONNumber.Create(Q.FieldByName('VALOR_UNITARIO').AsFloat));
      LObj.AddPair('valor_total', TJSONNumber.Create(Q.FieldByName('VALOR_TOTAL').AsFloat));
      Result.AddElement(LObj);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

class procedure TXmlPersistenceService.UpdateFileStatus(AId: Integer; const AStatus: string);
var
  Q: TFDQuery;
begin
  Q := GetBridgeQuery;
  try
    Q.SQL.Text := 'UPDATE XML_FILES SET ESTADO = :STATUS WHERE ID = :ID';
    Q.ParamByName('STATUS').AsString := AStatus;
    Q.ParamByName('ID').AsInteger := AId;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

end.
