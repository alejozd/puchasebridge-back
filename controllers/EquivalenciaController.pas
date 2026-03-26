unit EquivalenciaController;

interface

procedure Registry;

implementation

uses
  Horse,
  System.JSON,
  System.SysUtils,
  FireDAC.Comp.Client,
  EquivalenciaService;

procedure List(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LRefP, LUniP, LLimiteStr: string;
  LLimite: Integer;
  LQ: TFDQuery;
  LResponse: TJSONObject;
  LEquivalenciasArr: TJSONArray;
  LEquivalenciaObj: TJSONObject;
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    if not Req.Query.TryGetValue('referenciaP', LRefP) then LRefP := '';
    if not Req.Query.TryGetValue('unidadP', LUniP) then LUniP := '';

    if Req.Query.TryGetValue('limite', LLimiteStr) then
      LLimite := StrToIntDef(LLimiteStr, 50)
    else
      LLimite := 50;

    LQ := EquivalenciaService.ListarEquivalencias(LRefP, LUniP, LLimite);
    try
      LResponse := TJSONObject.Create;
      LEquivalenciasArr := TJSONArray.Create;

      while not LQ.Eof do
      begin
        LEquivalenciaObj := TJSONObject.Create;
        LEquivalenciaObj.AddPair('codigoH', TJSONNumber.Create(LQ.FieldByName('CODIGOH').AsInteger));
        LEquivalenciaObj.AddPair('subcodigoH', TJSONNumber.Create(LQ.FieldByName('SUBCODIGOH').AsInteger));
        LEquivalenciaObj.AddPair('nombreH', LQ.FieldByName('NOMBREH').AsString);
        LEquivalenciaObj.AddPair('referenciaH', LQ.FieldByName('REFERENCIAH').AsString);
        LEquivalenciaObj.AddPair('unidadH', LQ.FieldByName('UNIDADH').AsString);
        LEquivalenciaObj.AddPair('referenciaP', LQ.FieldByName('REFERENCIAP').AsString);
        LEquivalenciaObj.AddPair('unidadP', LQ.FieldByName('UNIDADP').AsString);
        LEquivalenciaObj.AddPair('factor', TJSONNumber.Create(LQ.FieldByName('FACTOR').AsFloat));

        LEquivalenciasArr.AddElement(LEquivalenciaObj);
        LQ.Next;
      end;

      LResponse.AddPair('equivalencias', LEquivalenciasArr);
      Res.Send(LResponse);
    finally
      LQ.Free;
    end;
  except
    on E: Exception do
    begin
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
    end;
  end;
end;

procedure Create(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LCodigoH, LSubCodigoH: Integer;
  LNombreH, LReferenciaH, LUnidadH: string;
  LReferenciaP, LUnidadP: string;
  LFactor: Double;
  LResponse: TJSONObject;
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    LBody := Req.Body<TJSONObject>;
    if not Assigned(LBody) then
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'JSON body is required');
      Res.Status(400).Send(LResponse);
      Exit;
    end;

    // Extracting and validating data
    if not LBody.TryGetValue('codigoH', LCodigoH) then
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'codigoH is required');
      Res.Status(400).Send(LResponse);
      Exit;
    end;

    if not LBody.TryGetValue('subCodigoH', LSubCodigoH) then
      LSubCodigoH := 0;

    if not LBody.TryGetValue('nombreH', LNombreH) then LNombreH := '';
    if not LBody.TryGetValue('referenciaH', LReferenciaH) then LReferenciaH := '';
    if not LBody.TryGetValue('unidadH', LUnidadH) then LUnidadH := '';
    if not LBody.TryGetValue('referenciaP', LReferenciaP) then LReferenciaP := '';
    if not LBody.TryGetValue('unidadP', LUnidadP) then LUnidadP := '';

    if LReferenciaP.Trim.IsEmpty then
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'referenciaP cannot be empty');
      Res.Status(400).Send(LResponse);
      Exit;
    end;

    if LUnidadP.Trim.IsEmpty then
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'unidadP cannot be empty');
      Res.Status(400).Send(LResponse);
      Exit;
    end;

    if not LBody.TryGetValue('factor', LFactor) or (LFactor <= 0) then
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'factor must be greater than 0');
      Res.Status(400).Send(LResponse);
      Exit;
    end;

    try
      EquivalenciaService.CrearEquivalencia(
        LCodigoH, LSubCodigoH, LNombreH, LReferenciaP, LUnidadP, LUnidadH, LReferenciaH, LFactor
      );

      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(True));
      LResponse.AddPair('message', 'Equivalencia creada correctamente');
      Res.Status(201).Send(LResponse);
    except
      on E: Exception do
      begin
        LResponse := TJSONObject.Create;
        LResponse.AddPair('success', TJSONBool.Create(False));

        if E.Message.Contains('Ya existe') then
        begin
          LResponse.AddPair('message', 'La equivalencia ya existe');
          Res.Status(409).Send(LResponse);
        end
        else
        begin
          LResponse.AddPair('message', E.Message);
          Res.Status(500).Send(LResponse);
        end;
      end;
    end;

  except
    on E: Exception do
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', E.Message);
      Res.Status(500).Send(LResponse);
    end;
  end;
end;

procedure Delete(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LRefP, LUniP: string;
  LSuccess: Boolean;
  LResponse: TJSONObject;
begin
  Res.ContentType('application/json; charset=utf-8');
  try
    if not Req.Query.TryGetValue('referenciaP', LRefP) or LRefP.Trim.IsEmpty then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'El parámetro "referenciaP" es obligatorio'));
      Exit;
    end;

    if not Req.Query.TryGetValue('unidadP', LUniP) or LUniP.Trim.IsEmpty then
    begin
      Res.Status(400).Send(TJSONObject.Create.AddPair('error', 'El parámetro "unidadP" es obligatorio'));
      Exit;
    end;

    LSuccess := EquivalenciaService.EliminarEquivalencia(LRefP, LUniP);

    LResponse := TJSONObject.Create;
    LResponse.AddPair('success', LSuccess);
    if LSuccess then
      LResponse.AddPair('message', 'Equivalencia eliminada correctamente')
    else
      LResponse.AddPair('message', 'No se encontró la equivalencia para eliminar');

    Res.Send(LResponse);
  except
    on E: Exception do
    begin
      Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
    end;
  end;
end;

procedure Registry;
begin
  THorse.Get('/equivalencias', List);
  THorse.Post('/equivalencia', Create);
  THorse.Delete('/equivalencia', Delete);
end;

end.
