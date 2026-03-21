unit XmlPersistenceService;

interface

uses
  System.SysUtils,
  System.Classes,
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
  Q: TFDQuery;
  I: Integer;
  LEquivQ: TFDQuery;
  LEquivId: Integer;
begin
  Q := GetBridgeQuery;
  try
    // Delete existing products for this file to refresh
    Q.SQL.Text := 'DELETE FROM XML_PRODUCTOS WHERE XML_FILE_ID = :FILEID';
    Q.ParamByName('FILEID').AsInteger := AXmlFileId;
    Q.ExecSQL;

    Q.SQL.Text :=
      'INSERT INTO XML_PRODUCTOS (XML_FILE_ID, DESCRIPCION, REFERENCIA, CANTIDAD, UNIDAD, ' +
      'VALOR_UNITARIO, VALOR_TOTAL, EQUIVALENCIA_ID) ' +
      'VALUES (:FILEID, :DESC, :REF, :CANT, :UNI, :PREC, :TOTAL, :EQUIVID)';

    for I := 0 to Length(AProducts) - 1 do
    begin
      LEquivId := 0;
      LEquivQ := GetBridgeQuery;
      try
        LEquivQ.SQL.Text := 'SELECT ID FROM EQUIVALENCIA WHERE REFERENCIAP = :REF AND UNIDADP = :UNI';
        LEquivQ.ParamByName('REF').AsString := AProducts[I].Referencia;
        LEquivQ.ParamByName('UNI').AsString := AProducts[I].Unidad;
        LEquivQ.Open;
        if not LEquivQ.IsEmpty then
          LEquivId := LEquivQ.FieldByName('ID').AsInteger;
      finally
        LEquivQ.Free;
      end;

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
    Q.Free;
  end;
end;

end.
