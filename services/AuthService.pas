unit AuthService;

interface

uses
  System.JSON,
  System.SysUtils,
  System.Generics.Collections,
  System.SyncObjs,
  Horse,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection,
  HConfig;

type
  TSessionInfo = record
    Codigo: Integer;
    Nombre: string;
  end;

  TSessionInfoObj = class
  public
    Data: TSessionInfo;
    constructor Create(AData: TSessionInfo);
  end;

function Login(const AUsuario, AClave: string): TJSONObject;
function ValidateToken(const AToken: string): TSessionInfo;

implementation

var
  Sessions: TDictionary<string, TSessionInfo>;
  SessionLock: TCriticalSection;

constructor TSessionInfoObj.Create(AData: TSessionInfo);
begin
  Data := AData;
end;

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
      raise EHorseException.New.Status(THTTPStatus.Unauthorized).Error('Usuario no encontrado');

    if LQUser.FieldByName('CLAVE').AsString <> AClave then
      raise EHorseException.New.Status(THTTPStatus.Unauthorized).Error('Clave incorrecta');

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

    // Generar Token
    var LToken := TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '');
    var LSession: TSessionInfo;
    LSession.Codigo := LQUser.FieldByName('CODIGO').AsInteger;
    LSession.Nombre := LQUser.FieldByName('NOMBRE').AsString;

    SessionLock.Enter;
    try
      Sessions.AddOrSetValue(LToken, LSession);
    finally
      SessionLock.Leave;
    end;

    Result.AddPair('token', LToken);
  finally
    // GetHelisaQuery returns a query with an unowned connection, cleanup handled by query destruction
    // unless the connection was explicitly created. FirebirdConnection.pas says GetHelisaQuery
    // creates a connection owned by the result query.
    LQUser.Free;
  end;
end;

function ValidateToken(const AToken: string): TSessionInfo;
begin
  SessionLock.Enter;
  try
    if not Sessions.TryGetValue(AToken, Result) then
      raise EHorseException.New.Status(THTTPStatus.Unauthorized).Error('Token inválido');
  finally
    SessionLock.Leave;
  end;
end;

initialization
  Sessions := TDictionary<string, TSessionInfo>.Create;
  SessionLock := TCriticalSection.Create;

finalization
  Sessions.Free;
  SessionLock.Free;

end.
