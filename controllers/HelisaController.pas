unit HelisaController;

interface

procedure Registry;

implementation

uses
  Horse,
  System.JSON,
  System.SysUtils,
  FireDAC.Comp.Client,
  FirebirdConnection;

procedure GetProductos(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LFiltro: string;
  LQ: TFDQuery;
  LProductoObj: TJSONObject;
  LProductosArr: TJSONArray;
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    if not Req.Query.TryGetValue('search', LFiltro) or LFiltro.Trim.IsEmpty then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'El parámetro "search" es obligatorio'));
      Exit;
    end;

    LQ := GetHelisaQuery;
    try
      LQ.Connection.Free;
      LQ.Connection := CrearConexionParticular('0');

      // Consultar HELI00BD.HGW y tabla INMAXXXX con JOIN a unidades
      LQ.SQL.Text :=
        'SELECT FIRST 20 I.CODIGO, I.SUBCODIGO, I.NOMBRE, I.REFERENCIA, U.SIGLA AS UNIDAD_DEFAULT ' +
        'FROM INMAXXXX I ' +
        'LEFT JOIN INTUXXXX U ON I.SUBCODIGO = U.CODIGO ' +
        'WHERE I.NOMBRE LIKE :FILTRO OR I.REFERENCIA LIKE :FILTRO ' +
        'ORDER BY I.NOMBRE';

      LQ.ParamByName('FILTRO').AsString := '%' + LFiltro.ToUpper + '%';
      LQ.Open;

      LProductosArr := TJSONArray.Create;
      while not LQ.Eof do
      begin
        LProductoObj := TJSONObject.Create;
        LProductoObj.AddPair('codigo', TJSONNumber.Create(LQ.FieldByName('CODIGO').AsInteger));
        LProductoObj.AddPair('subcodigo', TJSONNumber.Create(LQ.FieldByName('SUBCODIGO').AsInteger));
        LProductoObj.AddPair('nombre', LQ.FieldByName('NOMBRE').AsString);
        LProductoObj.AddPair('referencia', LQ.FieldByName('REFERENCIA').AsString);
        // Relationship: INTUXXXX.CODIGO = INMAXXXX.SUBCODIGO
        LProductoObj.AddPair('unidad', TJSONNumber.Create(LQ.FieldByName('SUBCODIGO').AsInteger));
        LProductoObj.AddPair('unidadDefault', LQ.FieldByName('UNIDAD_DEFAULT').AsString);

        LProductosArr.AddElement(LProductoObj);
        LQ.Next;
      end;

      Res.Send(LProductosArr);
    finally
      if Assigned(LQ.Connection) then LQ.Connection.Free;
      LQ.Free;
    end;
  except
    on E: Exception do
    begin
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
    end;
  end;
end;

procedure GetUnidades(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LQ: TFDQuery;
  LUnidadesArr: TJSONArray;
  LUnidadObj: TJSONObject;
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    // Consultar HELISABD.HGW y tabla INTUXXXX
    LQ := GetHelisaQuery;
    try
      LQ.SQL.Text := 'SELECT CODIGO, NOMBRE, SIGLA FROM INTUXXXX ORDER BY NOMBRE';
      LQ.Open;

      LUnidadesArr := TJSONArray.Create;
      while not LQ.Eof do
      begin
        LUnidadObj := TJSONObject.Create;
        LUnidadObj.AddPair('codigo', LQ.FieldByName('CODIGO').AsString);
        LUnidadObj.AddPair('nombre', LQ.FieldByName('NOMBRE').AsString);
        LUnidadObj.AddPair('sigla', LQ.FieldByName('SIGLA').AsString);

        LUnidadesArr.AddElement(LUnidadObj);
        LQ.Next;
      end;
      Res.Send(LUnidadesArr);
    finally
      if Assigned(LQ.Connection) then LQ.Connection.Free;
      LQ.Free;
    end;
  except
    on E: Exception do
    begin
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
    end;
  end;
end;

procedure Registry;
begin
  THorse.Get('/erp/productos', GetProductos);
  THorse.Get('/erp/unidades', GetUnidades);
end;

end.
