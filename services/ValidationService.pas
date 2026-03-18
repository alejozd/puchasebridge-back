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
  LInputJSON := TJSONObject.ParseJSONValue(AJsonParse) as TJSONObject;
  if not Assigned(LInputJSON) then
  begin
    Result := '{"error": "JSON de entrada inválido"}';
    Exit;
  end;

  LOutputJSON := TJSONObject.Create;
  LResultProductosArray := TJSONArray.Create;
  LErroresArray := TJSONArray.Create;

  try
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
        LErroresArray.Add('Proveedor no existe en Helisa');

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
          LResultItemJSON.AddPair('existeEquivalencia', LValido);
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

      LOutputJSON.AddPair('valido', LValido);
      LOutputJSON.AddPair('requiereHomologacion', LRequiereHomologacion);
      LOutputJSON.AddPair('proveedorExiste', LProveedorExiste);
      LOutputJSON.AddPair('productos', LResultProductosArray);
      LOutputJSON.AddPair('errores', LErroresArray);

      Result := LOutputJSON.ToJSON;
    except
      on E: Exception do
      begin
        LResultProductosArray.Free;
        LErroresArray.Free;
        Result := '{"error": "Error durante la validación: ' + E.Message + '"}';
      end;
    end;
  finally
    LInputJSON.Free;
    LOutputJSON.Free;
  end;
end;

end.
