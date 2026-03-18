unit HelisaController;

interface

procedure Registry;

implementation

uses
  Horse,
  System.JSON,
  System.SysUtils,
  ProductoRepository;

procedure GetProductos(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LFiltro, LAnio: string;
  LLimite: Integer;
  LQ: TFDQuery;
  LResponse: TJSONObject;
  LProductosArr: TJSONArray;
  LProductoObj: TJSONObject;
begin
  try
    if not Req.Query.TryGetValue('filtro', LFiltro) or LFiltro.Trim.IsEmpty then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'El parámetro "filtro" es obligatorio'));
      Exit;
    end;

    if LFiltro.Trim.Length < 3 then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'El filtro debe tener al menos 3 caracteres'));
      Exit;
    end;

    if not Req.Query.TryGetValue('limite', LLimite) then
      LLimite := 20;

    if not Req.Query.TryGetValue('anio', LAnio) then
      LAnio := '';

    LQ := ProductoRepository.BuscarProductos(LFiltro, LLimite, LAnio);
    try
      LResponse := TJSONObject.Create;
      LProductosArr := TJSONArray.Create;

      while not LQ.Eof do
      begin
        LProductoObj := TJSONObject.Create;
        LProductoObj.AddPair('codigo', TJSONNumber.Create(LQ.FieldByName('CODIGO').AsInteger));
        LProductoObj.AddPair('subcodigo', TJSONNumber.Create(LQ.FieldByName('SUBCODIGO').AsInteger));
        LProductoObj.AddPair('nombre', LQ.FieldByName('NOMBRE').AsString);
        LProductoObj.AddPair('referencia', LQ.FieldByName('REFERENCIA').AsString);
        LProductoObj.AddPair('unidad', LQ.FieldByName('UNIDAD').AsString);

        LProductosArr.AddElement(LProductoObj);
        LQ.Next;
      end;

      LResponse.AddPair('productos', LProductosArr);
      Res.Send(LResponse);
    finally
      // Manual cleanup of both Query and its Connection (since it has no owner)
      if Assigned(LQ.Connection) then
        LQ.Connection.Free;
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
  THorse.Get('/helisa/productos', GetProductos);
end;

end.
