unit DocumentoService;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Classes,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection,
  XmlParserService;

type
  TDocumentoHeader = record
    Proveedor: string;
    Fecha: TDateTime;
    Total: Double;
    Estado: string;
    XMLFileName: string;
  end;

  TDocumentoDetalle = record
    CodigoProducto: string;
    Cantidad: Double;
    Precio: Double;
    Total: Double;
  end;

function GuardarDocumento(AHeader: TDocumentoHeader; ADetalles: TArray<TDocumentoDetalle>): Integer;
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

function GuardarDocumento(AHeader: TDocumentoHeader; ADetalles: TArray<TDocumentoDetalle>): Integer;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  LDocumentoID: Integer;
  I: Integer;
begin
  Conn := GetBridgeConnection;
  try
    Conn.StartTransaction;
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := Conn;

        // Insert Header
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

        // Insert Details
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

        Conn.Commit;
        Result := LDocumentoID;
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
