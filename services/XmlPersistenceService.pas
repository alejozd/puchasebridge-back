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
  LExiste: Boolean;
  LEquivalenciaID: Integer;
  LPendientes: Integer;
  LErrorMsg: string;
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
            'MENSAJE_ERROR = NULL, ' +
            'FECHA_VALIDACION = CURRENT_TIMESTAMP ' +
            'WHERE ID = :ID';
          Q.ParamByName('NIT').AsString := AParsedInvoice.Provider.NIT;
          Q.ParamByName('PROV').AsString := AParsedInvoice.Provider.Nombre;
          Q.ParamByName('FECHA').AsDate := AParsedInvoice.FechaEmision;
          Q.ParamByName('ID').AsInteger := LFileID;
          Q.ExecSQL;

          // Delete ONLY non-homologated products to preserve equivalences
          Q.SQL.Text :=
            'DELETE FROM XML_PRODUCTOS ' +
            'WHERE XML_FILE_ID = :FILEID ' +
            'AND EQUIVALENCIA_ID IS NULL';
          Q.ParamByName('FILEID').AsInteger := LFileID;
          Q.ExecSQL;
        end
        else
        begin
          Q.Close;
          // Insert new header
          Q.SQL.Text :=
            'INSERT INTO XML_FILES (FILE_NAME, PROVEEDOR_NIT, PROVEEDOR_NOMBRE, FECHA_DOCUMENTO, ESTADO, MENSAJE_ERROR, FECHA_CARGA, FECHA_VALIDACION) ' +
            'VALUES (:FNAME, :NIT, :PROV, :FECHA, ''VALIDADO'', NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING ID';
          Q.ParamByName('FNAME').AsString := AFileName;
          Q.ParamByName('NIT').AsString := AParsedInvoice.Provider.NIT;
          Q.ParamByName('PROV').AsString := AParsedInvoice.Provider.Nombre;
          Q.ParamByName('FECHA').AsDate := AParsedInvoice.FechaEmision;
          Q.Open;
          LFileID := Q.FieldByName('ID').AsInteger;
          Q.Close;
        end;

        for I := 0 to Length(AParsedInvoice.Products) - 1 do
        begin
          try
            // 1. Verificar si ya existe el producto
            Q.Close;
            Q.SQL.Text :=
              'SELECT 1 FROM XML_PRODUCTOS ' +
              'WHERE XML_FILE_ID = :FILEID ' +
              'AND REFERENCIA = :REF ' +
              'AND UNIDAD = :UNI';

            Q.ParamByName('FILEID').AsInteger := LFileID;
            Q.ParamByName('REF').AsString := AParsedInvoice.Products[I].Referencia;
            Q.ParamByName('UNI').AsString := AParsedInvoice.Products[I].Unidad;

            Q.Open;
            LExiste := not Q.IsEmpty;
            Q.Close;

            // 2. Si NO existe, lo insertas
            if not LExiste then
            begin
              // Se resuelve la equivalencia una sola vez para evitar duplicar subconsultas.
              Q.SQL.Text :=
                'SELECT FIRST 1 ID AS EID FROM EQUIVALENCIA ' +
                'WHERE REFERENCIAH = :REFX AND UNIDADH = :UNIX';
              Q.ParamByName('REFX').AsString := AParsedInvoice.Products[I].Referencia;
              Q.ParamByName('UNIX').AsString := AParsedInvoice.Products[I].Unidad;
              Q.Open;
              if not Q.IsEmpty then
                LEquivalenciaID := Q.FieldByName('EID').AsInteger
              else
                LEquivalenciaID := 0;
              Q.Close;

              Q.SQL.Text :=
                'INSERT INTO XML_PRODUCTOS (XML_FILE_ID, DESCRIPCION, REFERENCIA, REFERENCIA_STD, CANTIDAD, UNIDAD, VALOR_UNITARIO, VALOR_TOTAL, IMPUESTO, EQUIVALENCIA_ID, ESTADO_VALIDACION, MENSAJE_VALIDACION) ' +
                'VALUES (:FILEID, :DESC, :REF, :REFSTD, :CANT, :UNI, :VUNI, :VTOT, :IMP, :EID, :ESTADO, NULL)';

              Q.ParamByName('FILEID').AsInteger := LFileID;
              Q.ParamByName('DESC').AsString := Copy(AParsedInvoice.Products[I].Descripcion, 1, 255);
              Q.ParamByName('REF').AsString := AParsedInvoice.Products[I].Referencia;
              Q.ParamByName('REFSTD').AsString := AParsedInvoice.Products[I].ReferenciaEstandar;
              Q.ParamByName('CANT').AsFloat := AParsedInvoice.Products[I].Cantidad;
              Q.ParamByName('UNI').AsString := AParsedInvoice.Products[I].Unidad;
              Q.ParamByName('VUNI').AsFloat := AParsedInvoice.Products[I].ValorUnitario;
              Q.ParamByName('VTOT').AsFloat := AParsedInvoice.Products[I].ValorTotal;
              Q.ParamByName('IMP').AsFloat := AParsedInvoice.Products[I].Impuesto;
              if LEquivalenciaID > 0 then
                Q.ParamByName('EID').AsInteger := LEquivalenciaID
              else
                Q.ParamByName('EID').Clear;

              // Traza por producto: pendiente si no tiene equivalencia, homologado en caso contrario.
              if LEquivalenciaID > 0 then
                Q.ParamByName('ESTADO').AsString := 'HOMOLOGADO'
              else
                Q.ParamByName('ESTADO').AsString := 'PENDIENTE';

              if not Q.ParamByName('REF').AsString.Trim.IsEmpty then
                Q.ExecSQL;
            end;
          except
            on E: Exception do
            begin
              // Validación opcional por producto: se persiste error sin romper todo el lote.
              LErrorMsg := Copy(E.Message, 1, 500);
              Q.Close;
              Q.SQL.Text :=
                'UPDATE XML_PRODUCTOS SET ESTADO_VALIDACION = ''ERROR'', MENSAJE_VALIDACION = :MSG ' +
                'WHERE XML_FILE_ID = :FILEID AND REFERENCIA = :REF AND UNIDAD = :UNI';
              Q.ParamByName('MSG').AsString := LErrorMsg;
              Q.ParamByName('FILEID').AsInteger := LFileID;
              Q.ParamByName('REF').AsString := AParsedInvoice.Products[I].Referencia;
              Q.ParamByName('UNI').AsString := AParsedInvoice.Products[I].Unidad;
              Q.ExecSQL;
              raise;
            end;
          end;
        end;

        // Estado final del archivo según productos pendientes de homologación.
        Q.Close;
        Q.SQL.Text :=
          'SELECT COUNT(*) AS TOTAL FROM XML_PRODUCTOS ' +
          'WHERE XML_FILE_ID = :FILEID AND EQUIVALENCIA_ID IS NULL';
        Q.ParamByName('FILEID').AsInteger := LFileID;
        Q.Open;
        LPendientes := Q.FieldByName('TOTAL').AsInteger;
        Q.Close;

        if LPendientes > 0 then
        begin
          Q.SQL.Text :=
            'UPDATE XML_FILES SET ESTADO = ''PENDIENTE'', MENSAJE_ERROR = NULL WHERE ID = :ID';
          Q.ParamByName('ID').AsInteger := LFileID;
          Q.ExecSQL;
        end
        else
        begin
          Q.SQL.Text :=
            'UPDATE XML_FILES SET ESTADO = ''LISTO'', MENSAJE_ERROR = NULL WHERE ID = :ID';
          Q.ParamByName('ID').AsInteger := LFileID;
          Q.ExecSQL;
        end;

        Conn.Commit;
      except
        on E: Exception do
        begin
          Conn.Rollback;

          // Persistencia de error del parse/proceso en XML_FILES.
          Q.Connection := Conn;
          Q.SQL.Text :=
            'UPDATE XML_FILES SET ESTADO = ''ERROR'', MENSAJE_ERROR = :MSG WHERE FILE_NAME = :FNAME';
          Q.ParamByName('MSG').AsString := Copy(E.Message, 1, 500);
          Q.ParamByName('FNAME').AsString := AFileName;
          Q.ExecSQL;

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
