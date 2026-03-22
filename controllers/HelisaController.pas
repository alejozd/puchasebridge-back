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
  LQEmpresa, LQGlobal: TFDQuery;
  LProductoObj: TJSONObject;
  LProductosArr: TJSONArray;
  LSubcodigo: Integer;
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    if not Req.Query.TryGetValue('search', LFiltro) or LFiltro.Trim.IsEmpty then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'El parámetro "search" es obligatorio'));
      Exit;
    end;

    // 1. Consultar productos en la base de datos de la empresa (heli00bd.hgw)
    LQEmpresa := TFDQuery.Create(nil);
    try
      LQEmpresa.Connection := CrearConexionParticular('0');
      try
        LQEmpresa.SQL.Text :=
          'SELECT FIRST 20 CODIGO, SUBCODIGO, NOMBRE, REFERENCIA ' +
          'FROM INMAXXXX ' +
          'WHERE NOMBRE LIKE :FILTRO OR REFERENCIA LIKE :FILTRO ' +
          'ORDER BY NOMBRE';

        LQEmpresa.ParamByName('FILTRO').AsString := '%' + LFiltro.ToUpper + '%';
        LQEmpresa.Open;

        LProductosArr := TJSONArray.Create;

        // 2. Para cada producto, buscar su sigla de unidad en la base de datos global (helisabd.hgw)
        LQGlobal := GetHelisaQuery;
        try
          LQGlobal.SQL.Text := 'SELECT SIGLA FROM INTUXXXX WHERE CODIGO = :SUBCODIGO';

          while not LQEmpresa.Eof do
          begin
            LSubcodigo := LQEmpresa.FieldByName('SUBCODIGO').AsInteger;

            LProductoObj := TJSONObject.Create;
            LProductoObj.AddPair('codigo', TJSONNumber.Create(LQEmpresa.FieldByName('CODIGO').AsInteger));
            LProductoObj.AddPair('subcodigo', TJSONNumber.Create(LSubcodigo));
            LProductoObj.AddPair('nombre', LQEmpresa.FieldByName('NOMBRE').AsString);
            LProductoObj.AddPair('referencia', LQEmpresa.FieldByName('REFERENCIA').AsString);
            LProductoObj.AddPair('unidad', TJSONNumber.Create(LSubcodigo));

            // Buscar sigla
            LQGlobal.Close;
            LQGlobal.ParamByName('SUBCODIGO').AsInteger := LSubcodigo;
            LQGlobal.Open;

            if not LQGlobal.IsEmpty then
              LProductoObj.AddPair('unidadDefault', LQGlobal.FieldByName('SIGLA').AsString)
            else
              LProductoObj.AddPair('unidadDefault', '');

            LProductosArr.AddElement(LProductoObj);
            LQEmpresa.Next;
          end;
        finally
          if Assigned(LQGlobal.Connection) then LQGlobal.Connection.Free;
          LQGlobal.Free;
        end;

        Res.Send(LProductosArr);
      finally
        if Assigned(LQEmpresa.Connection) then LQEmpresa.Connection.Free;
      end;
    finally
      LQEmpresa.Free;
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
