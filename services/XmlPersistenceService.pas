unit XmlPersistenceService;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Classes,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection,
  XmlParserService;

procedure UpsertXMLInvoice(const AFileName: string; const AParsedInvoice: TParsedInvoice);

implementation

procedure UpsertXMLInvoice(const AFileName: string; const AParsedInvoice: TParsedInvoice);
var
  Conn: TFDConnection;
  Q: TFDQuery;
  LFileID: Integer;
  I: Integer;
begin
  Conn := GetBridgeConnection;
  try
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Conn.StartTransaction;
      try
        // 1. Check if file exists
        Q.SQL.Text := 'SELECT ID FROM XML_FILES WHERE FILE_NAME = :FNAME';
        Q.ParamByName('FNAME').AsString := AFileName;
        Q.Open;

        if not Q.IsEmpty then
        begin
          LFileID := Q.FieldByName('ID').AsInteger;
          Q.Close;

          // Update existing header
          Q.SQL.Text :=
            'UPDATE XML_FILES SET ' +
            'PROVEEDOR_NIT = :NIT, ' +
            'PROVEEDOR_NOMBRE = :PROV, ' +
            'FECHA_DOCUMENTO = :FECHA, ' +
            'ESTADO = ''VALIDADO'', ' +
            'FECHA_VALIDACION = CURRENT_TIMESTAMP ' +
            'WHERE ID = :ID';
          Q.ParamByName('NIT').AsString := AParsedInvoice.Provider.NIT;
          Q.ParamByName('PROV').AsString := AParsedInvoice.Provider.Nombre;
          Q.ParamByName('FECHA').AsDate := AParsedInvoice.FechaEmision;
          Q.ParamByName('ID').AsInteger := LFileID;
          Q.ExecSQL;

          // Delete old products to refresh them
          Q.SQL.Text := 'DELETE FROM XML_PRODUCTOS WHERE XML_FILE_ID = :FILEID';
          Q.ParamByName('FILEID').AsInteger := LFileID;
          Q.ExecSQL;
        end
        else
        begin
          Q.Close;
          // Insert new header
          Q.SQL.Text :=
            'INSERT INTO XML_FILES (FILE_NAME, PROVEEDOR_NIT, PROVEEDOR_NOMBRE, FECHA_DOCUMENTO, ESTADO, FECHA_CARGA, FECHA_VALIDACION) ' +
            'VALUES (:FNAME, :NIT, :PROV, :FECHA, ''VALIDADO'', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING ID';
          Q.ParamByName('FNAME').AsString := AFileName;
          Q.ParamByName('NIT').AsString := AParsedInvoice.Provider.NIT;
          Q.ParamByName('PROV').AsString := AParsedInvoice.Provider.Nombre;
          Q.ParamByName('FECHA').AsDate := AParsedInvoice.FechaEmision;
          Q.Open;
          LFileID := Q.FieldByName('ID').AsInteger;
          Q.Close;
        end;

        // 2. Insert products - Using UNIDAD for XML_PRODUCTOS and UNIDADH for EQUIVALENCIA lookup
        Q.SQL.Text :=
          'INSERT INTO XML_PRODUCTOS (XML_FILE_ID, DESCRIPCION, REFERENCIA, REFERENCIA_STD, CANTIDAD, UNIDAD, VALOR_UNITARIO, VALOR_TOTAL, IMPUESTO, EQUIVALENCIA_ID) ' +
          'VALUES (:FILEID, :DESC, :REF, :REFSTD, :CANT, :UNI, :VUNI, :VTOT, :IMP, ' +
          '(SELECT FIRST 1 ID FROM EQUIVALENCIA WHERE REFERENCIAH = :REFX AND UNIDADH = :UNIX))';

        for I := 0 to Length(AParsedInvoice.Products) - 1 do
        begin
          Q.ParamByName('FILEID').AsInteger := LFileID;
          Q.ParamByName('DESC').AsString := Copy(AParsedInvoice.Products[I].Descripcion, 1, 255);
          Q.ParamByName('REF').AsString := AParsedInvoice.Products[I].Referencia;
          Q.ParamByName('REFSTD').AsString := AParsedInvoice.Products[I].ReferenciaEstandar;
          Q.ParamByName('CANT').AsFloat := AParsedInvoice.Products[I].Cantidad;
          Q.ParamByName('UNI').AsString := AParsedInvoice.Products[I].Unidad;
          Q.ParamByName('VUNI').AsFloat := AParsedInvoice.Products[I].ValorUnitario;
          Q.ParamByName('VTOT').AsFloat := AParsedInvoice.Products[I].ValorTotal;
          Q.ParamByName('IMP').AsFloat := AParsedInvoice.Products[I].Impuesto;

          // Parameters for the EQUIVALENCIA subquery (mapping XML ref/unit)
          Q.ParamByName('REFX').AsString := AParsedInvoice.Products[I].Referencia;
          Q.ParamByName('UNIX').AsString := AParsedInvoice.Products[I].Unidad;

          if not Q.ParamByName('REF').AsString.Trim.IsEmpty then
            Q.ExecSQL;
        end;

        Conn.Commit;
      except
        on E: Exception do
        begin
          Conn.Rollback;
          raise;
        end;
      end;
    finally
      Q.Free;
    end;
  finally
    Conn.Free;
  end;
end;

end.
