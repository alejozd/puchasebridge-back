unit XmlProcessingService;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection,
  AuthService,
  DocumentoService,
  XmlPersistenceService,
  ProveedorRepository;

type
  TXmlProcessingService = class
  public
    class function ProcesarBatch(AIds: TJSONArray; ASession: TSessionInfo): TJSONObject;
  end;

implementation

{ TXmlProcessingService }

class function TXmlProcessingService.ProcesarBatch(AIds: TJSONArray; ASession: TSessionInfo): TJSONObject;
var
  LProcesadosArr, LErroresArr: TJSONArray;
  I, J: Integer;
  LId: Integer;
  Q, QProd: TFDQuery;
  LHeader: TDocumentoHeader;
  LDetalles: TArray<TDocumentoDetalle>;
  LAnio, LDocumentoERP: string;
  LFactor: Double;
  LCanProcess: Boolean;
  LProvInfo: TProveedorInfo;
  LErrorObj, LProcesadoObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  LProcesadosArr := TJSONArray.Create;
  LErroresArr := TJSONArray.Create;
  Result.AddPair('procesados', LProcesadosArr);
  Result.AddPair('errores', LErroresArr);

  for I := 0 to AIds.Count - 1 do
  begin
    LId := StrToIntDef(AIds.Items[I].Value, 0);
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
          LErrorObj.AddPair('id', LId);
          LErrorObj.AddPair('error', 'Archivo no encontrado');
          LErroresArr.Add(LErrorObj);
          Continue;
        end;

        if Q.FieldByName('ESTADO').AsString = 'PROCESADO' then
        begin
          LErrorObj := TJSONObject.Create;
          LErrorObj.AddPair('id', LId);
          LErrorObj.AddPair('error', 'El archivo ya fue procesado');
          LErroresArr.Add(LErrorObj);
          Continue;
        end;

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
          LErrorObj.AddPair('id', LId);
          LErrorObj.AddPair('error', 'Existen productos sin homologación');
          LErroresArr.Add(LErrorObj);
          Continue;
        end;

        LAnio := FormatDateTime('yyyy', Q.FieldByName('FECHA_DOCUMENTO').AsDateTime);
        LProvInfo := ObtenerProveedorPorNit(Q.FieldByName('PROVEEDOR_NIT').AsString, LAnio);

        if not LProvInfo.Existe then
        begin
          LErrorObj := TJSONObject.Create;
          LErrorObj.AddPair('id', LId);
          LErrorObj.AddPair('error', 'Proveedor no existe en el ERP para el año ' + LAnio);
          LErroresArr.Add(LErrorObj);
          Continue;
        end;

        LHeader.Proveedor := Q.FieldByName('PROVEEDOR_NIT').AsString;
        LHeader.CodigoTercero := LProvInfo.Codigo;
        LHeader.Fecha := Q.FieldByName('FECHA_DOCUMENTO').AsDateTime;
        LHeader.Estado := 'PROCESADO';
        LHeader.XMLFileName := Q.FieldByName('FILE_NAME').AsString;
        LHeader.NombreUsuario := ASession.Nombre;
        LHeader.CodigoUsuario := ASession.Codigo.ToString;
        LHeader.Anio := LAnio;

        QProd := GetBridgeQuery;
        try
          QProd.SQL.Text :=
            'SELECT P.*, E.CODIGOH, E.SUBCODIGOH, E.REFERENCIAH, E.FACTOR ' +
            'FROM XML_PRODUCTOS P JOIN EQUIVALENCIA E ON P.EQUIVALENCIA_ID = E.ID ' +
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
            LDetalles[J].TfIva := 0; LDetalles[J].VrIva := 0; LDetalles[J].TfDescuento := 0; LDetalles[J].VrDescuento := 0;
            LDetalles[J].VrIca := 0; LDetalles[J].VrReteIca := 0; LDetalles[J].VrReteIva := 0; LDetalles[J].VrReteFuente := 0;
            Inc(J);
            QProd.Next;
          end;
        finally
          QProd.Free;
        end;

        LDocumentoERP := GuardarDocumento(LHeader, LDetalles);
        TXmlPersistenceService.UpdateFileStatus(LId, 'PROCESADO');

        LProcesadoObj := TJSONObject.Create;
        LProcesadoObj.AddPair('id', LId);
        LProcesadoObj.AddPair('documento', LDocumentoERP);
        LProcesadosArr.Add(LProcesadoObj);
      finally
        Q.Free;
      end;
    except
      on E: Exception do
      begin
        LErrorObj := TJSONObject.Create;
        LErrorObj.AddPair('id', LId);
        LErrorObj.AddPair('error', E.Message);
        LErroresArr.Add(LErrorObj);
      end;
    end;
  end;
end;

end.
