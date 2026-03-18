unit DocumentoService;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Classes,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection,
  XmlParserService,
  HelisaService;

type
  TDocumentoHeader = record
    Proveedor: string;
    CodigoTercero: string;
    Fecha: TDateTime;
    Total: Double;
    Estado: string;
    XMLFileName: string;
    NombreUsuario: string;
    CodigoUsuario: string;
    Anio: string;
  end;

  TDocumentoDetalle = record
    CodigoProducto: string;
    CodigoConcepto: Integer;
    Subcodigo: Integer;
    Cantidad: Double;
    Precio: Double;
    Total: Double;
    TfIva: Double;
    VrIva: Double;
    TfDescuento: Double;
    VrDescuento: Double;
    VrIca: Double;
    VrReteIca: Double;
    VrReteIva: Double;
    VrReteFuente: Double;
  end;

function GuardarDocumento(AHeader: TDocumentoHeader; ADetalles: TArray<TDocumentoDetalle>): string;
function DocumentoExiste(const AXMLFileName: string): Boolean;

implementation

function DocumentoExiste(const AXMLFileName: string): Boolean;
var
  Q: TFDQuery;
begin
  Q := GetBridgeQuery;
  try
    Q.SQL.Text := 'SELECT ID FROM DOCUMENTO WHERE XML_FILENAME = :FNAME';
    Q.ParamByName('FNAME').AsString := AXMLFileName;
    Q.Open;
    Result := not Q.IsEmpty;
  finally
    Q.Free;
  end;
end;

function GuardarDocumento(AHeader: TDocumentoHeader; ADetalles: TArray<TDocumentoDetalle>): string;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  LDocumentoID: Integer;
  LDocumentoERP: string;
  LHEHeader: THEHeaderOC;
  LHEDetalles: TArray<THEDetalleOC>;
  I: Integer;
begin
  // 1. Persistir en PurchaseBridge (Documento original y trazabilidad)
  Conn := GetBridgeConnection;
  try
    Conn.StartTransaction;
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := Conn;

        Q.SQL.Text :=
          'INSERT INTO DOCUMENTO (PROVEEDOR, FECHA, TOTAL, ESTADO, XML_FILENAME) ' +
          'VALUES (:PROV, :FECHA, :TOTAL, :ESTADO, :FNAME) RETURNING ID';

        Q.ParamByName('PROV').AsString := AHeader.Proveedor;
        Q.ParamByName('FECHA').AsDateTime := AHeader.Fecha;
        Q.ParamByName('TOTAL').AsFloat := AHeader.Total;
        Q.ParamByName('ESTADO').AsString := AHeader.Estado;
        Q.ParamByName('FNAME').AsString := AHeader.XMLFileName;

        Q.Open;
        LDocumentoID := Q.FieldByName('ID').AsInteger;
        Q.Close;

        Q.SQL.Text :=
          'INSERT INTO DOCUMENTO_DETALLE (DOCUMENTO_ID, CODIGO_PRODUCTO, CANTIDAD, PRECIO, TOTAL) ' +
          'VALUES (:DOCID, :COD, :CANT, :PREC, :TOTAL)';

        for I := 0 to Length(ADetalles) - 1 do
        begin
          Q.ParamByName('DOCID').AsInteger := LDocumentoID;
          Q.ParamByName('COD').AsString := ADetalles[I].CodigoProducto;
          Q.ParamByName('CANT').AsFloat := ADetalles[I].Cantidad;
          Q.ParamByName('PREC').AsFloat := ADetalles[I].Precio;
          Q.ParamByName('TOTAL').AsFloat := ADetalles[I].Total;
          Q.ExecSQL;
        end;

        // 2. Persistir en Helisa ERP
        LHEHeader.Fecha := AHeader.Fecha;
        LHEHeader.CodigoTercero := AHeader.CodigoTercero;
        LHEHeader.NombreUsuario := AHeader.NombreUsuario;
        LHEHeader.CodigoUsuario := AHeader.CodigoUsuario;
        LHEHeader.Anio := AHeader.Anio;

        SetLength(LHEDetalles, Length(ADetalles));
        for I := 0 to Length(ADetalles) - 1 do
        begin
          LHEDetalles[I].Clase := 1;
          LHEDetalles[I].CodigoConcepto := ADetalles[I].CodigoConcepto;
          LHEDetalles[I].Subcodigo := ADetalles[I].Subcodigo;
          LHEDetalles[I].Cantidad := ADetalles[I].Cantidad;
          LHEDetalles[I].ValorUnitario := ADetalles[I].Precio;
          LHEDetalles[I].ValorTotal := ADetalles[I].Total;
          LHEDetalles[I].TfIva := ADetalles[I].TfIva;
          LHEDetalles[I].VrIva := ADetalles[I].VrIva;
          LHEDetalles[I].TfDescuento := ADetalles[I].TfDescuento;
          LHEDetalles[I].VrDescuento := ADetalles[I].VrDescuento;
          LHEDetalles[I].VrIca := ADetalles[I].VrIca;
          LHEDetalles[I].VrReteIca := ADetalles[I].VrReteIca;
          LHEDetalles[I].VrReteIva := ADetalles[I].VrReteIva;
          LHEDetalles[I].VrReteFuente := ADetalles[I].VrReteFuente;
        end;

        LDocumentoERP := HelisaService.InsertarOrdenCompra(LHEHeader, LHEDetalles);

        // Actualizar con el numero de documento de Helisa
        Q.SQL.Text := 'UPDATE DOCUMENTO SET ESTADO = :ESTADO WHERE ID = :ID';
        Q.ParamByName('ESTADO').AsString := LDocumentoERP;
        Q.ParamByName('ID').AsInteger := LDocumentoID;
        Q.ExecSQL;

        Conn.Commit;
        Result := LDocumentoERP;
      finally
        Q.Free;
      end;
    except
      on E: Exception do
      begin
        Conn.Rollback;
        raise;
      end;
    end;
  finally
    Conn.Free;
  end;
end;

end.
