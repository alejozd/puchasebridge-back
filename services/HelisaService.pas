unit HelisaService;

interface

uses
  System.SysUtils,
  System.Classes,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection,
  HelisaUtils;

type
  THEHeaderOC = record
    Documento: string;
    Fecha: TDateTime;
    CodigoTercero: string;
    NombreUsuario: string;
    CodigoUsuario: string;
    Anio: string;
  end;

  THEDetalleOC = record
    Consecutivo: Integer;
    Clase: Integer;
    CodigoConcepto: Integer;
    Subcodigo: Integer;
    Cantidad: Double;
    ValorUnitario: Double;
    ValorTotal: Double;
    TfIva: Double;
    VrIva: Double;
    TfDescuento: Double;
    VrDescuento: Double;
    VrIca: Double;
    VrReteIca: Double;
    VrReteIva: Double;
    VrReteFuente: Double;
  end;

function InsertarOrdenCompra(AHeader: THEHeaderOC; ADetalles: TArray<THEDetalleOC>): string;
function ObtenerSiglaUnidad(AConn: TFDConnection; ACodigo: string): string;

implementation

function InsertarOrdenCompra(AHeader: THEHeaderOC; ADetalles: TArray<THEDetalleOC>): string;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  LDocumento, LTipo: string;
  LConsecutivo: Integer;
  I: Integer;
  LAnioSuffix: string;
  LDocuTable, LOcmaTable, LOctrTable: string;
  LArtBruto, LSerBruto: Double;
  LArtIvaExento, LSerIvaExento: Double;
  LArtIvaGravado, LSerIvaGravado: Double;
  LArtDesc, LSerDesc: Double;
  LArtIva, LSerIva: Double;
  LArtIca, LSerIca: Double;
  LTotalReteIca, LTotalReteIva, LTotalReteFuente: Double;
begin
  LAnioSuffix := AHeader.Anio;
  LDocuTable := 'DOCU' + LAnioSuffix;
  LOcmaTable := 'OCMA' + LAnioSuffix;
  LOctrTable := 'OCTR' + LAnioSuffix;

  Conn := GetHelisaConnection;
  try
    Conn.StartTransaction;
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := Conn;

        // 1. Obtener consecutivo de DOCUXXXX
        Q.SQL.Text := Format('SELECT FIRST 1 TIPO, CONSECUTIVO FROM %s WHERE MODULO = 10 AND CLASE = 31', [LDocuTable]);
        Q.Open;
        if Q.IsEmpty then
          raise Exception.Create('No se encontró configuración de Orden de Compra en DOCUXXXX');

        LTipo := Q.FieldByName('TIPO').AsString;
        LConsecutivo := Q.FieldByName('CONSECUTIVO').AsInteger;
        Q.Close;

        LDocumento := FormatDocumentNumber(LTipo, LConsecutivo);

        // 2. Insertar Detalle (OCTRXXXX)
        Q.SQL.Text := Format(
          'INSERT INTO %s (' +
          '  DOCUMENTO, CONSECUTIVO, CLASE, CODIGO_BODEGA, CODIGO_CONCEPTO, SUBCODIGO, ' +
          '  LISTAPRECIO, CANTIDAD, UNIDADES_DEVUELTAS, VR_UNITARIO, VR_TOTAL, VR_VPN, VR_ING_GASTO, ' +
          '  TF_IVA, VR_IVA, TF_CONSUMO, VR_CONSUMO, TF_GASOLINA, VR_GASOLINA, TF_BOLSA, VR_BOLSA, ' +
          '  TF_CARBONO, VR_CARBONO, TF_CANNABIS, VR_CANNABIS, TF_DESCUENTO, VR_DESCUENTO, ' +
          '  TF_ICA, VR_ICA, TF_RETEICA, VR_RETEICA, TF_RETEIVA, VR_RETEIVA, VR_RETE_CREE, ' +
          '  VR_AUTORETE_CREE, TF_RETEHORTIFRUT, VR_RETEHORTIFRUT, TF_RETEBOLSAAGRO, VR_RETEBOLSAAGRO, ' +
          '  HACE_PARTE_COSTO, HACE_PARTE_COSTO_NIIF, DISPERSION, VR_RETEFUENTE' +
          ') VALUES (' +
          '  :DOC, :CONS, :CLASE, 1, :CONC, :SUB, ' +
          '  0, :CANT, 0, :VUNIT, :VTOTAL, 0, 0, ' +
          '  :TIVA, :VIVA, 0, 0, 0, 0, 0, 0, ' +
          '  0, 0, 0, 0, :TDESC, :VDESC, ' +
          '  0, :VICA, 0, :VRETEICA, 0, :VRETEIVA, 0, ' +
          '  0, 0, 0, 0, 0, ' +
          '  ''N'', ''N'', ''N'', :VRETEF' +
          ')', [LOctrTable]);

        for I := 0 to Length(ADetalles) - 1 do
        begin
          Q.ParamByName('DOC').AsString := LDocumento;
          Q.ParamByName('CONS').AsInteger := I + 1;
          Q.ParamByName('CLASE').AsInteger := ADetalles[I].Clase;
          Q.ParamByName('CONC').AsInteger := ADetalles[I].CodigoConcepto;
          Q.ParamByName('SUB').AsInteger := ADetalles[I].Subcodigo;
          Q.ParamByName('CANT').AsFloat := ADetalles[I].Cantidad;
          Q.ParamByName('VUNIT').AsFloat := ADetalles[I].ValorUnitario;
          Q.ParamByName('VTOTAL').AsFloat := ADetalles[I].ValorTotal;
          Q.ParamByName('TIVA').AsFloat := ADetalles[I].TfIva;
          Q.ParamByName('VIVA').AsFloat := ADetalles[I].VrIva;
          Q.ParamByName('TDESC').AsFloat := ADetalles[I].TfDescuento;
          Q.ParamByName('VDESC').AsFloat := ADetalles[I].VrDescuento;
          Q.ParamByName('VICA').AsFloat := ADetalles[I].VrIca;
          Q.ParamByName('VRETEICA').AsFloat := ADetalles[I].VrReteIca;
          Q.ParamByName('VRETEIVA').AsFloat := ADetalles[I].VrReteIva;
          Q.ParamByName('VRETEF').AsFloat := ADetalles[I].VrReteFuente;
          Q.ExecSQL;
        end;

        // 3. Calcular Totales desde OCTRXXXX
        Q.SQL.Text := Format(
          'SELECT ' +
          '  SUM(CASE WHEN CLASE = 1 THEN VR_TOTAL ELSE 0 END) AS ART_BRUTO, ' +
          '  SUM(CASE WHEN CLASE = 2 THEN VR_TOTAL ELSE 0 END) AS SER_BRUTO, ' +
          '  SUM(CASE WHEN CLASE = 1 AND TF_IVA = 0 THEN VR_TOTAL ELSE 0 END) AS ART_IVA_EXENTO, ' +
          '  SUM(CASE WHEN CLASE = 2 AND TF_IVA = 0 THEN VR_TOTAL ELSE 0 END) AS SER_IVA_EXENTO, ' +
          '  SUM(CASE WHEN CLASE = 1 AND TF_IVA > 0 THEN VR_TOTAL ELSE 0 END) AS ART_IVA_GRAVADO, ' +
          '  SUM(CASE WHEN CLASE = 2 AND TF_IVA > 0 THEN VR_TOTAL ELSE 0 END) AS SER_IVA_GRAVADO, ' +
          '  SUM(CASE WHEN CLASE = 1 THEN VR_DESCUENTO ELSE 0 END) AS ART_DESC, ' +
          '  SUM(CASE WHEN CLASE = 2 THEN VR_DESCUENTO ELSE 0 END) AS SER_DESC, ' +
          '  SUM(CASE WHEN CLASE = 1 THEN VR_IVA ELSE 0 END) AS ART_IVA, ' +
          '  SUM(CASE WHEN CLASE = 2 THEN VR_IVA ELSE 0 END) AS SER_IVA, ' +
          '  SUM(CASE WHEN CLASE = 1 THEN VR_ICA ELSE 0 END) AS ART_ICA, ' +
          '  SUM(CASE WHEN CLASE = 2 THEN VR_ICA ELSE 0 END) AS SER_ICA, ' +
          '  SUM(VR_RETEICA) AS TOTAL_RETEICA, ' +
          '  SUM(VR_RETEIVA) AS TOTAL_RETEIVA, ' +
          '  SUM(VR_RETEFUENTE) AS TOTAL_RETEFUENTE ' +
          'FROM %s WHERE DOCUMENTO = :DOC', [LOctrTable]);
        Q.ParamByName('DOC').AsString := LDocumento;
        Q.Open;

        LArtBruto := Q.FieldByName('ART_BRUTO').AsFloat;
        LSerBruto := Q.FieldByName('SER_BRUTO').AsFloat;
        LArtIvaExento := Q.FieldByName('ART_IVA_EXENTO').AsFloat;
        LSerIvaExento := Q.FieldByName('SER_IVA_EXENTO').AsFloat;
        LArtIvaGravado := Q.FieldByName('ART_IVA_GRAVADO').AsFloat;
        LSerIvaGravado := Q.FieldByName('SER_IVA_GRAVADO').AsFloat;
        LArtDesc := Q.FieldByName('ART_DESC').AsFloat;
        LSerDesc := Q.FieldByName('SER_DESC').AsFloat;
        LArtIva := Q.FieldByName('ART_IVA').AsFloat;
        LSerIva := Q.FieldByName('SER_IVA').AsFloat;
        LArtIca := Q.FieldByName('ART_ICA').AsFloat;
        LSerIca := Q.FieldByName('SER_ICA').AsFloat;
        LTotalReteIca := Q.FieldByName('TOTAL_RETEICA').AsFloat;
        LTotalReteIva := Q.FieldByName('TOTAL_RETEIVA').AsFloat;
        LTotalReteFuente := Q.FieldByName('TOTAL_RETEFUENTE').AsFloat;
        Q.Close;

        // 4. Insertar Encabezado (OCMAXXXX)
        Q.SQL.Text := Format(
          'INSERT INTO %s (' +
          '  DOCUMENTO, FECHA, CODIGO_TERCERO, CLASE_FAC, ESTADO_DOCUMENTO, ' +
          '  ART_TOTAL_BRUTO, SER_TOTAL_BRUTO, ART_TOTAL_IVA_EXENTO, SER_TOTAL_IVA_EXENTO, ' +
          '  ART_TOTAL_IVA_GRAVADO, SER_TOTAL_IVA_GRAVADO, ART_TOTAL_DESCUENTO, SER_TOTAL_DESCUENTO, ' +
          '  ART_TOTAL_DESCUENTO_ADICIONAL, SER_TOTAL_DESCUENTO_ADICIONAL, ART_TOTAL_IVA, SER_TOTAL_IVA, ' +
          '  ART_TOTAL_CONSUMO, SER_TOTAL_CONSUMO, ART_TOTAL_GASOLINA, SER_TOTAL_GASOLINA, ' +
          '  ART_TOTAL_BOLSA, SER_TOTAL_BOLSA, ART_TOTAL_CARBONO, SER_TOTAL_CARBONO, ' +
          '  ART_TOTAL_CANNABIS, SER_TOTAL_CANNABIS, ART_TOTAL_ICA, SER_TOTAL_ICA, ' +
          '  TOTAL_RETEICA, TOTAL_RETEIVA, TOTAL_RETEFUENTE, TOTAL_AUTORETENCION, ' +
          '  TOTAL_RETE_CREE, TOTAL_AUTORETE_CREE, TOTAL_RETEHORTIF, TOTAL_BOLSAAGRO, ' +
          '  TASA_CAMBIO, NOMBRE_PANTALLA, NOMBRE_USUARIO, CODIGO_USUARIO, FECHA_SISTEMA' +
          ') VALUES (' +
          '  :DOC, :FECHA, :TERCERO, 1, 1, ' +
          '  :ART_BRUTO, :SER_BRUTO, :ART_IVA_EX, :SER_IVA_EX, ' +
          '  :ART_IVA_GR, :SER_IVA_GR, :ART_DESC, :SER_DESC, ' +
          '  0, 0, :ART_IVA, :SER_IVA, ' +
          '  0, 0, 0, 0, ' +
          '  0, 0, 0, 0, ' +
          '  0, 0, :ART_ICA, :SER_ICA, ' +
          '  :RETEICA, :RETEIVA, :RETEF, 0, ' +
          '  0, 0, 0, 0, ' +
          '  1, ''PURCHASE'', :USER, :USER_COD, CURRENT_TIMESTAMP' +
          ')', [LOcmaTable]);

        Q.ParamByName('DOC').AsString := LDocumento;
        Q.ParamByName('FECHA').AsInteger := DateToHeDate(AHeader.Fecha);
        Q.ParamByName('TERCERO').AsString := AHeader.CodigoTercero;
        Q.ParamByName('ART_BRUTO').AsFloat := LArtBruto;
        Q.ParamByName('SER_BRUTO').AsFloat := LSerBruto;
        Q.ParamByName('ART_IVA_EX').AsFloat := LArtIvaExento;
        Q.ParamByName('SER_IVA_EX').AsFloat := LSerIvaExento;
        Q.ParamByName('ART_IVA_GR').AsFloat := LArtIvaGravado;
        Q.ParamByName('SER_IVA_GR').AsFloat := LSerIvaGravado;
        Q.ParamByName('ART_DESC').AsFloat := LArtDesc;
        Q.ParamByName('SER_DESC').AsFloat := LSerDesc;
        Q.ParamByName('ART_IVA').AsFloat := LArtIva;
        Q.ParamByName('SER_IVA').AsFloat := LSerIva;
        Q.ParamByName('ART_ICA').AsFloat := LArtIca;
        Q.ParamByName('SER_ICA').AsFloat := LSerIca;
        Q.ParamByName('RETEICA').AsFloat := LTotalReteIca;
        Q.ParamByName('RETEIVA').AsFloat := LTotalReteIva;
        Q.ParamByName('RETEF').AsFloat := LTotalReteFuente;
        Q.ParamByName('USER').AsString := AHeader.NombreUsuario;
        Q.ParamByName('USER_COD').AsString := AHeader.CodigoUsuario;
        Q.ExecSQL;

        // 5. Incrementar consecutivo en DOCUXXXX
        Q.SQL.Text := Format('UPDATE %s SET CONSECUTIVO = CONSECUTIVO + 1 WHERE MODULO = 10 AND CLASE = 31', [LDocuTable]);
        Q.ExecSQL;

        Conn.Commit;
        Result := LDocumento;
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

function ObtenerSiglaUnidad(AConn: TFDConnection; ACodigo: string): string;
var
  Qry: TFDQuery;
begin
  Result := '';
  if not Assigned(AConn) then Exit;

  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := AConn;
    Qry.SQL.Text := 'SELECT SIGLA FROM INTUXXXX WHERE CODIGO = :CODIGO';
    Qry.ParamByName('CODIGO').AsString := ACodigo;
    Qry.Open;

    if not Qry.IsEmpty then
      Result := Qry.FieldByName('SIGLA').AsString;
  finally
    Qry.Free;
  end;
end;

end.
