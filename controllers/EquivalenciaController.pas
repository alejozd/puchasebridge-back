unit EquivalenciaController;

interface

procedure Registry;

implementation

uses
  Horse,
  System.JSON,
  System.SysUtils,
  EquivalenciaService;

procedure Create(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LCodigoH, LSubCodigoH: Integer;
  LNombreH, LReferenciaH, LUnidadH: string;
  LReferenciaP, LUnidadP: string;
  LFactor: Double;
  LResponse: TJSONObject;
begin
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
        LCodigoH, LSubCodigoH, LNombreH, LReferenciaH, LUnidadH, LUnidadP, LReferenciaP, LFactor
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

procedure Registry;
begin
  THorse.Post('/equivalencia', Create);
end;

end.
