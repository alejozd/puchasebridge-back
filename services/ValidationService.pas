unit ValidationService;

interface

uses
  System.JSON,
  System.SysUtils,
  ProveedorRepository,
  EquivalenciaService;

function ValidarDocumento(AJsonParse: string): string;

implementation

function ValidarDocumento(AJsonParse: string): string;
var
  LInputJSON, LOutputJSON: TJSONObject;
  LProveedorJSON, LItemJSON, LResultItemJSON: TJSONObject;
  LProductosArray, LResultProductosArray, LErroresArray: TJSONArray;
  LNIT, LReferencia, LUnidad: string;
  LProveedorInfo: TProveedorInfo;
  LProveedorExiste, LTodosProductosExisten, LAlgunProductoNoExiste: Boolean;
  LValido, LRequiereHomologacion: Boolean;
  I: Integer;
begin
  LOutputJSON := TJSONObject.Create;
  LResultProductosArray := TJSONArray.Create;
  LErroresArray := TJSONArray.Create;

  // Add child objects to parent immediately to ensure single cleanup point
  LOutputJSON.AddPair('productos', LResultProductosArray);
  LOutputJSON.AddPair('errores', LErroresArray);

  LInputJSON := nil;

  try
    LInputJSON := TJSONObject.ParseJSONValue(AJsonParse) as TJSONObject;
    if not Assigned(LInputJSON) then
    begin
      LErroresArray.Add('JSON de entrada inválido');
      LOutputJSON.AddPair('valido', TJSONBool.Create(False));
      LOutputJSON.AddPair('requiereHomologacion', TJSONBool.Create(False));
      LOutputJSON.AddPair('proveedorExiste', TJSONBool.Create(False));
      Result := LOutputJSON.ToJSON;
      Exit;
    end;

    try
      // A. Validar proveedor
      LProveedorExiste := False;
      LProveedorJSON := LInputJSON.GetValue('proveedor') as TJSONObject;
      if Assigned(LProveedorJSON) then
      begin
        LNIT := LProveedorJSON.GetValue('nit').Value;
        LProveedorInfo := ObtenerProveedorPorNit(LNIT, '');
        LProveedorExiste := LProveedorInfo.Existe;
      end;

      if not LProveedorExiste then
        LErroresArray.Add('Proveedor no existe en Helisa')
      else
        LOutputJSON.AddPair('codigoTercero', LProveedorInfo.Codigo);

      // B. Validar productos
      LTodosProductosExisten := True;
      LAlgunProductoNoExiste := False;
      LProductosArray := LInputJSON.GetValue('productos') as TJSONArray;

      if Assigned(LProductosArray) then
      begin
        for I := 0 to LProductosArray.Count - 1 do
        begin
          LItemJSON := LProductosArray.Items[I] as TJSONObject;
          LReferencia := LItemJSON.GetValue('referencia').Value;
          LUnidad := LItemJSON.GetValue('unidad').Value;

          if LReferencia.Trim.IsEmpty or LUnidad.Trim.IsEmpty then
            LValido := False
          else
            LValido := ExisteEquivalencia(LReferencia, LUnidad);

          if not LValido then
          begin
            LTodosProductosExisten := False;
            LAlgunProductoNoExiste := True;
            LErroresArray.Add(Format('Producto %s con unidad %s no tiene equivalencia', [LReferencia, LUnidad]));
          end;

          LResultItemJSON := TJSONObject.Create;
          LResultItemJSON.AddPair('referencia', LReferencia);
          LResultItemJSON.AddPair('unidad', LUnidad);
          LResultItemJSON.AddPair('existeEquivalencia', TJSONBool.Create(LValido));
          LResultProductosArray.Add(LResultItemJSON);
        end;
      end;

      // C. Clasificación del documento (Reglas 4.1 - 4.4)
      LValido := False;
      LRequiereHomologacion := False;

      if LProveedorExiste then
      begin
        if LTodosProductosExisten then
        begin
          // 4.1 Proveedor existe + todos productos existen -> VALIDO
          LValido := True;
        end
        else if LAlgunProductoNoExiste then
        begin
          // 4.3 Proveedor existe + algún producto NO existe -> VALIDO (requiere homologación)
          LValido := True;
          LRequiereHomologacion := True;
        end;
      end
      else
      begin
        // 4.2 Proveedor NO existe + productos existen -> INVALIDO
        // 4.4 Proveedor NO existe + algún producto NO existe -> INVALIDO
        LValido := False;
      end;

      LOutputJSON.AddPair('valido', TJSONBool.Create(LValido));
      LOutputJSON.AddPair('requiereHomologacion', TJSONBool.Create(LRequiereHomologacion));
      LOutputJSON.AddPair('proveedorExiste', TJSONBool.Create(LProveedorExiste));

      Result := LOutputJSON.ToJSON;
    except
      on E: Exception do
      begin
        LErroresArray.Add('Error durante la validación: ' + E.Message);
        // Ensure standard fields are present even on inner exception
        if LOutputJSON.GetValue('valido') = nil then LOutputJSON.AddPair('valido', TJSONBool.Create(False));
        if LOutputJSON.GetValue('requiereHomologacion') = nil then LOutputJSON.AddPair('requiereHomologacion', TJSONBool.Create(False));
        if LOutputJSON.GetValue('proveedorExiste') = nil then LOutputJSON.AddPair('proveedorExiste', TJSONBool.Create(False));
        Result := LOutputJSON.ToJSON;
      end;
    end;
  finally
    if Assigned(LInputJSON) then
      LInputJSON.Free;
    LOutputJSON.Free;
  end;
end;

end.
