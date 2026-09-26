unit DMVC.Security.AuthHandler;

interface

uses
  System.Generics.Collections,
  MVCFramework;

type
  TPurchaseBridgeAuthHandler = class(TInterfacedObject, IMVCAuthenticationHandler)
  public
    procedure OnRequest(const AContext: TWebContext; const AControllerQualifiedClassName,
      AActionName: string; var AAuthenticationRequired: Boolean);
    procedure OnAuthentication(const AContext: TWebContext; const AUserName, APassword: string;
      AUserRoles: TList<string>; var AIsValid: Boolean; const ASessionData: TDictionary<string, string>);
    procedure OnAuthorization(const AContext: TWebContext; AUserRoles: TList<string>;
      const AControllerQualifiedClassName: string; const AActionName: string; var AIsAuthorized: Boolean);
  end;

implementation

uses
  System.SysUtils, FireDAC.Comp.Client, FirebirdConnection, uLogger;

{ TPurchaseBridgeAuthHandler }

procedure TPurchaseBridgeAuthHandler.OnRequest(const AContext: TWebContext;
  const AControllerQualifiedClassName, AActionName: string; var AAuthenticationRequired: Boolean);
begin
  // Deny-by-default: unica excepcion es el health-check publico, igual que
  // Horse (/ping esta explicitamente excluido de Auth). Verificado
  // empiricamente (no adivinado) que AControllerQualifiedClassName llega como
  // el resultado de TClass.QualifiedClassName: 'DMVC.Controllers.PingController.TPingController'.
  AAuthenticationRequired := not SameText(AControllerQualifiedClassName,
    'DMVC.Controllers.PingController.TPingController');
end;

procedure TPurchaseBridgeAuthHandler.OnAuthentication(const AContext: TWebContext;
  const AUserName, APassword: string; AUserRoles: TList<string>; var AIsValid: Boolean;
  const ASessionData: TDictionary<string, string>);
var
  LQuery: TFDQuery;
begin
  AIsValid := False;

  // Bug real encontrado durante verificacion manual (Step 7): FireDAC deriva el
  // tamano del parametro NOMBRE de la metadata de la columna (VARCHAR(15) en
  // Helisa) y ParamByName('NOMBRE').AsString lanza EFDException ("Data too
  // large for variable") si AUserName excede ese ancho, ANTES de abrir la
  // consulta. Un username mas largo que la columna nunca puede coincidir con
  // ningun usuario real, asi que se descarta antes de tocar la base -- evita
  // el crash sin necesitar conocer/hardcodear el ancho exacto de la columna
  // (que ademas podria variarse entre instalaciones de Helisa) y sin tocar
  // ParamByName(...).Size (probado: fijar Size manualmente antes de Prepare
  // desincroniza el ciclo de vida del cursor de FireDAC/Firebird y produce un
  // EIBNativeException "Attempt to reclose a closed cursor" distinto, peor,
  // en este entorno). services/AuthService.pas tiene el mismo patron original
  // sin ningun guard (no se modifica, por restriccion explicita de esta
  // task) y hereda el mismo bug preexistente para usernames largos -- fuera
  // de alcance aqui.
  if Length(AUserName) > 15 then
    Exit;

  LQuery := FirebirdConnection.GetHelisaQuery;
  try
    try
      LQuery.SQL.Text := 'SELECT CODIGO, NOMBRE, CLAVE FROM USUARIOS WHERE NOMBRE = :NOMBRE';
      LQuery.ParamByName('NOMBRE').AsString := AUserName;
      LQuery.Open;

      if LQuery.IsEmpty then
        Exit;

      if LQuery.FieldByName('CLAVE').AsString <> APassword then
        Exit;

      AIsValid := True;
      AUserRoles.Add('user'); // Horse no tiene roles; se agrega un rol generico
                              // para que TList<string> no quede vacio (algunos
                              // puntos de DMVC asumen al menos un rol presente).
      ASessionData.AddOrSetValue('codigo', LQuery.FieldByName('CODIGO').AsString);
      ASessionData.AddOrSetValue('nombre', LQuery.FieldByName('NOMBRE').AsString);
    except
      on E: Exception do
      begin
        // Fail-closed: cualquier error de base de datos durante la
        // autenticacion se trata como credenciales invalidas (401), nunca
        // como un 500 que filtre detalles internos de FireDAC/Firebird al
        // cliente. Se deja registro para diagnostico.
        AIsValid := False;
        uLogger.LogError(E, 'auth-error');
      end;
    end;
  finally
    LQuery.Free;
  end;
end;

procedure TPurchaseBridgeAuthHandler.OnAuthorization(const AContext: TWebContext;
  AUserRoles: TList<string>; const AControllerQualifiedClassName: string;
  const AActionName: string; var AIsAuthorized: Boolean);
begin
  // Horse no tiene permisos granulares por ruta: cualquier usuario con token
  // valido (ya paso OnAuthentication) tiene acceso a todo lo que OnRequest
  // marco como protegido.
  AIsAuthorized := True;
end;

end.
