unit AuthService;

interface

uses
  System.JSON,
  System.SysUtils,
  Horse,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection,
  HConfig;

function Login(const AUsuario, AClave: string): TJSONObject;

implementation

function Login(const AUsuario, AClave: string): TJSONObject;
var
  LQUser, LQEmpresa: TFDQuery;
  LUserObj, LEmpresaObj: TJSONObject;
  LEmpresaCode: string;
begin
  Result := TJSONObject.Create;
  LQUser := GetHelisaQuery;
  try
    // 1. Validar Usuario en HELISABD.HGW.USUARIOS
    LQUser.SQL.Text := 'SELECT CODIGO, NOMBRE, CLAVE FROM USUARIOS WHERE NOMBRE = :NOMBRE';
    LQUser.ParamByName('NOMBRE').AsString := AUsuario;
    LQUser.Open;

    if LQUser.IsEmpty then
      raise EHorseException.Create(THTTPStatus.Unauthorized, 'Usuario no encontrado');

    if LQUser.FieldByName('CLAVE').AsString <> AClave then
      raise EHorseException.Create(THTTPStatus.Unauthorized, 'Clave incorrecta');

    LUserObj := TJSONObject.Create;
    LUserObj.AddPair('codigo', TJSONNumber.Create(LQUser.FieldByName('CODIGO').AsInteger));
    LUserObj.AddPair('nombre', LQUser.FieldByName('NOMBRE').AsString);
    Result.AddPair('usuario', LUserObj);

    // 2. Obtener Contexto de Empresa
    LEmpresaCode := THConfig.GetInstance.Config.Empresa;

    LQEmpresa := TFDQuery.Create(nil);
    try
      LQEmpresa.Connection := LQUser.Connection; // Reutilizar conexión a HELISABD
      LQEmpresa.SQL.Text :=
        'SELECT CODIGO, NOMBRE, IDENTIDAD, ANOACTUAL, TARIFA_RETE_CREE ' +
        'FROM DIRECTOR WHERE CODIGO = :CODIGO';
      LQEmpresa.ParamByName('CODIGO').AsString := LEmpresaCode;
      LQEmpresa.Open;

      if LQEmpresa.IsEmpty then
        raise Exception.Create('Configuración de empresa no válida en Helisa');

      LEmpresaObj := TJSONObject.Create;
      LEmpresaObj.AddPair('codigo', TJSONNumber.Create(LQEmpresa.FieldByName('CODIGO').AsInteger));
      LEmpresaObj.AddPair('nombre', LQEmpresa.FieldByName('NOMBRE').AsString);
      LEmpresaObj.AddPair('identidad', LQEmpresa.FieldByName('IDENTIDAD').AsString);
      LEmpresaObj.AddPair('anoActual', TJSONNumber.Create(LQEmpresa.FieldByName('ANOACTUAL').AsInteger));
      LEmpresaObj.AddPair('tarifaReteCree', TJSONNumber.Create(LQEmpresa.FieldByName('TARIFA_RETE_CREE').AsFloat));
      Result.AddPair('empresa', LEmpresaObj);
    finally
      LQEmpresa.Free;
    end;

    Result.AddPair('success', TJSONBool.Create(True));
    Result.AddPair('token', 'abc123'); // Token placeholder as requested
  finally
    // GetHelisaQuery returns a query with an unowned connection, cleanup handled by query destruction
    // unless the connection was explicitly created. FirebirdConnection.pas says GetHelisaQuery
    // creates a connection owned by the result query.
    LQUser.Free;
  end;
end;

end.
