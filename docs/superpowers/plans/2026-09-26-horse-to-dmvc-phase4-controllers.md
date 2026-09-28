# Fase 4 — Controllers de alto riesgo/volumen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrar los 6 controllers Horse restantes (`HelisaController`, `LicenciaController`, `XmlValidationController`, `ImportController`, `DocumentosController`, `XmlController`) a DMVCFramework, protegidos por el auth JWT de la Fase 3, sin tocar Horse ni reescribir la lógica de negocio existente. `AuthController` (Horse) NO se migra como controller — su única ruta (`POST /auth/login`) ya está superada por `TMVCJWTAuthenticationMiddleware` desde la Fase 3.

**Nota importante de proceso (a pedido del usuario, 2026-09-26 — cuota semanal ajustada):** este plan tiene detalle TDD completo SOLO para la Task 1. Las Tasks 2-6 tienen objetivo/archivos/rutas definidos (roadmap-level), pero su detalle TDD completo (código exacto) se escribe justo antes de despachar cada una — no todo de una vez — para no gastar presupuesto explorando controllers que quizás no se alcancen a hacer esta semana. Cada task se commitea por separado y se pide aprobación explícita del usuario antes de pasar a la siguiente (no ejecución continua automática como en las Fases 1-3).

**Cuántas tareas: 6.**

**Architecture:** Mismo patrón de las Fases 1-3: cada controller DMVC llama DIRECTAMENTE a las unidades procedurales Horse existentes (`services/`, `repositories/`) sin DI/ActiveRecord nueva. Cada controller nuevo hereda automáticamente la protección JWT (deny-by-default vía `OnRequest` en `DMVC.Security.AuthHandler.pas`, ya implementado en la Fase 3) — no hace falta ningún cambio en el auth handler para que un controller nuevo quede protegido.

## Global Constraints

- No modificar ningún archivo Horse existente (`controllers/*.pas`, `services/*.pas`, `repositories/*.pas`, `ServerBootstrap.pas`, etc.).
- Todos los controllers nuevos quedan protegidos por JWT automáticamente (deny-by-default) — no se agrega ninguna excepción nueva a `OnRequest` en esta fase (a diferencia de `TPingController` en la Fase 3). Todos los tests de esta fase necesitan un token vía `DMVC.TestAuthHelper.ObtenerTokenDePrueba` (ya existe, Fase 3).
- **Seguridad de datos real (recordatorio de las Fases 2-3)**: `HelisaController`, `ImportController` y partes de `XmlController`/`DocumentosController` tocan la base REAL de Helisa (`heli00bd.hgw`) — cualquier test automatizado contra esas rutas debe ser de solo lectura o usar datos claramente ficticios, nunca escribir/mutar datos reales de negocio.
- `LicenciaController.Registrar`/`ActivarOnline` hacen llamadas de red reales a un servidor de licencias externo y MUTAN el estado real de licencia (`licencia.json`) — NO se automatizan esas dos rutas end-to-end (mismo criterio que el guard de licencia dormido de la Fase 3); solo se automatiza la validación de input (400 si falta el body) y `GetEstado` (de solo lectura, aunque internamente llama `ValidarLicencia` que sí pega a la red — evaluar caso por caso en la Task 2 si conviene mockear o dejar como verificación manual).
- Regla de nombres de unidad Delphi conocida (nombre de unidad EXACTO al nombre de archivo, incluidos los puntos).
- DCC32 resuelve rutas relativas `in` contra el CWD del compilador, no la carpeta del `.dpr` — `cd` a la carpeta correcta antes de compilar.
- Bajo el hosting `TIdHTTPWebBrokerBridge` de este proyecto, un middleware PROPIO que corta con `AHandled:=True` necesita `SendResponse` explícito (Fase 3) — esto NO aplica a controllers normales (que responden vía `Render`/`Result`, no vía middleware), solo es relevante si esta fase necesitara un middleware nuevo (no debería).
- Compilador y rutas `-U`/`-I`: acumuladas de las Fases 1-3 (`dmvc`, `dmvc/Controllers`, `dmvc/DTOs`, `dmvc/Middleware`, `dmvc/Security`, `services`, `database`, `config`, `utils`, `repositories`, más las fuentes de DMVCFramework/DUnitX ya conocidas) — cada Task nueva agrega la carpeta de sus propias unidades nuevas si aplica.
- El arnés de tests sigue siendo `tests/PurchaseBridge.Tests.dpr` — cada Task agrega sus unidades al `uses` existente.

---

### Task 1: HelisaController (2 rutas, solo lectura, sin service propio)

**Files:**
- Create: `dmvc/DTOs/DMVC.DTOs.Helisa.pas`
- Create: `dmvc/Controllers/DMVC.Controllers.HelisaController.pas`
- Modify: `dmvc/DMVC.WebModule.Main.pas` (registrar el controller)
- Create: `tests/DMVC/DMVC.HelisaControllerTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr`

**Interfaces:**
- Consumes: `FirebirdConnection.CrearConexionParticular('0')` y `FirebirdConnection.GetHelisaQuery` (existentes, sin cambios) para consultar Helisa directo (este controller NO tiene un `services/HelisaService.pas` propio — la lógica está inline en el Horse original, se preserva igual acá). `DMVC.TestAuthHelper.ObtenerTokenDePrueba` (Fase 3) para el token de los tests.
- Produces: nada que otras tasks consuman.

**Código Horse original preservado tal cual (controllers/HelisaController.pas)**:
- `GET /erp/productos` (+ `/api/erp/productos`): requiere query `search` (400 si falta/vacío). Consulta `INMAXXXX` en la BD de empresa (`CrearConexionParticular('0')`) filtrando por `NOMBRE LIKE`/`REFERENCIA LIKE` (case-insensitive vía `.ToUpper` + `%like%`), `FIRST 20`, y para cada resultado busca la sigla de unidad en `INTUXXXX` de la BD global (`GetHelisaQuery`). Responde array JSON con `codigo, subcodigo, nombre, referencia, unidad, unidadDefault`.
- `GET /erp/unidades` (+ `/api/erp/unidades`): sin params, `SELECT CODIGO, NOMBRE, SIGLA FROM INTUXXXX ORDER BY NOMBRE` contra `GetHelisaQuery`. Responde array JSON con `codigo, nombre, sigla`.

- [ ] **Step 1: Escribir los DTOs**

Crear `dmvc/DTOs/DMVC.DTOs.Helisa.pas`:

```pascal
unit DMVC.DTOs.Helisa;

interface

uses
  MVCFramework.Serializer.Commons;

type
  [MVCNameCase(ncCamelCase)]
  TProductoHelisaDTO = class
  private
    fCodigo: Integer;
    fSubcodigo: Integer;
    fNombre: String;
    fReferencia: String;
    fUnidad: Integer;
    fUnidadDefault: String;
  public
    property Codigo: Integer read fCodigo write fCodigo;
    property Subcodigo: Integer read fSubcodigo write fSubcodigo;
    property Nombre: String read fNombre write fNombre;
    property Referencia: String read fReferencia write fReferencia;
    property Unidad: Integer read fUnidad write fUnidad;
    property UnidadDefault: String read fUnidadDefault write fUnidadDefault;
  end;

  [MVCNameCase(ncCamelCase)]
  TUnidadHelisaDTO = class
  private
    fCodigo: String;
    fNombre: String;
    fSigla: String;
  public
    property Codigo: String read fCodigo write fCodigo;
    property Nombre: String read fNombre write fNombre;
    property Sigla: String read fSigla write fSigla;
  end;

implementation

end.
```

- [ ] **Step 2: Escribir el controller**

Crear `dmvc/Controllers/DMVC.Controllers.HelisaController.pas`:

```pascal
unit DMVC.Controllers.HelisaController;

interface

uses
  MVCFramework, MVCFramework.Commons,
  System.Generics.Collections,
  DMVC.DTOs.Helisa;

type
  [MVCPath('/')]
  THelisaController = class(TMVCController)
  public
    [MVCPath('/erp/productos')]
    [MVCPath('/api/erp/productos')]
    [MVCHTTPMethod([httpGET])]
    function GetProductos(const [MVCFromQueryString('search', '')] ASearch: String): TObjectList<TProductoHelisaDTO>;

    [MVCPath('/erp/unidades')]
    [MVCPath('/api/erp/unidades')]
    [MVCHTTPMethod([httpGET])]
    function GetUnidades: TObjectList<TUnidadHelisaDTO>;
  end;

implementation

uses
  System.SysUtils, FireDAC.Comp.Client, FirebirdConnection;

function THelisaController.GetProductos(const ASearch: String): TObjectList<TProductoHelisaDTO>;
var
  LQEmpresa, LQGlobal: TFDQuery;
  LItem: TProductoHelisaDTO;
  LSubcodigo: Integer;
begin
  if Trim(ASearch) = '' then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'El parámetro "search" es obligatorio');

  Result := TObjectList<TProductoHelisaDTO>.Create(True);
  try
    LQEmpresa := TFDQuery.Create(nil);
    try
      LQEmpresa.Connection := CrearConexionParticular('0');
      try
        LQEmpresa.SQL.Text :=
          'SELECT FIRST 20 CODIGO, SUBCODIGO, NOMBRE, REFERENCIA ' +
          'FROM INMAXXXX ' +
          'WHERE NOMBRE LIKE :FILTRO OR REFERENCIA LIKE :FILTRO ' +
          'ORDER BY NOMBRE';
        LQEmpresa.ParamByName('FILTRO').AsString := '%' + ASearch.ToUpper + '%';
        LQEmpresa.Open;

        LQGlobal := GetHelisaQuery;
        try
          LQGlobal.SQL.Text := 'SELECT SIGLA FROM INTUXXXX WHERE CODIGO = :SUBCODIGO';

          while not LQEmpresa.Eof do
          begin
            LSubcodigo := LQEmpresa.FieldByName('SUBCODIGO').AsInteger;

            LItem := TProductoHelisaDTO.Create;
            LItem.Codigo := LQEmpresa.FieldByName('CODIGO').AsInteger;
            LItem.Subcodigo := LSubcodigo;
            LItem.Nombre := LQEmpresa.FieldByName('NOMBRE').AsString;
            LItem.Referencia := LQEmpresa.FieldByName('REFERENCIA').AsString;
            LItem.Unidad := LSubcodigo;

            LQGlobal.Close;
            LQGlobal.ParamByName('SUBCODIGO').AsInteger := LSubcodigo;
            LQGlobal.Open;
            if not LQGlobal.IsEmpty then
              LItem.UnidadDefault := LQGlobal.FieldByName('SIGLA').AsString
            else
              LItem.UnidadDefault := '';

            Result.Add(LItem);
            LQEmpresa.Next;
          end;
        finally
          if Assigned(LQGlobal.Connection) then LQGlobal.Connection.Free;
          LQGlobal.Free;
        end;
      finally
        if Assigned(LQEmpresa.Connection) then LQEmpresa.Connection.Free;
      end;
    finally
      LQEmpresa.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function THelisaController.GetUnidades: TObjectList<TUnidadHelisaDTO>;
var
  LQ: TFDQuery;
  LItem: TUnidadHelisaDTO;
begin
  Result := TObjectList<TUnidadHelisaDTO>.Create(True);
  try
    LQ := GetHelisaQuery;
    try
      LQ.SQL.Text := 'SELECT CODIGO, NOMBRE, SIGLA FROM INTUXXXX ORDER BY NOMBRE';
      LQ.Open;
      while not LQ.Eof do
      begin
        LItem := TUnidadHelisaDTO.Create;
        LItem.Codigo := LQ.FieldByName('CODIGO').AsString;
        LItem.Nombre := LQ.FieldByName('NOMBRE').AsString;
        LItem.Sigla := LQ.FieldByName('SIGLA').AsString;
        Result.Add(LItem);
        LQ.Next;
      end;
    finally
      if Assigned(LQ.Connection) then LQ.Connection.Free;
      LQ.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
```

Nota: el `try/except Result.Free; raise;` en ambos métodos replica el fix de seguridad-ante-excepción de la Fase 2 Task 1 (`TEquivalenciaController.GetEquivalencias`) — aplícalo desde el principio acá, no esperes a que una revisión lo pida de nuevo.

- [ ] **Step 3: Registrar el controller en el WebModule**

Modificar `dmvc/DMVC.WebModule.Main.pas`: agregar `DMVC.Controllers.HelisaController` al `uses` de `implementation` y `FEngine.AddController(THelisaController);` junto a los demás controllers (después de `TProveedorController`).

- [ ] **Step 4: Escribir los tests que fallan (RED)**

Crear `tests/DMVC/DMVC.HelisaControllerTests.pas` (sigue el patrón exacto de `DMVC.ProveedorControllerTests.pas`/`DMVC.EquivalenciaControllerTests.pas` de las Fases 2-3: `Setup`/`TearDown` con `TTestServerProcess`, token de `DMVC.TestAuthHelper.ObtenerTokenDePrueba` guardado en un campo `FToken`, enviado como `Authorization: Bearer <token>` en cada request):

```pascal
unit DMVC.HelisaControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  THelisaControllerTests = class
  private
    FServer: TTestServerProcess;
    FToken: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetProductos_WithoutSearch_Returns400;

    [Test]
    procedure GetProductos_WithSearch_ReturnsJsonArray;

    [Test]
    procedure GetUnidades_ReturnsJsonArray;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, IdHTTP, DMVC.TestAuthHelper;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure THelisaControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
  FToken := ObtenerTokenDePrueba(TEST_PORT);
end;

procedure THelisaControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure THelisaControllerTests.GetProductos_WithoutSearch_Returns400;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    try
      LHttp.Get(Format('http://localhost:%d/api/erp/productos', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 400');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(400, E.ErrorCode);
    end;
  finally
    LHttp.Free;
  end;
end;

procedure THelisaControllerTests.GetProductos_WithSearch_ReturnsJsonArray;
var
  LHttp: TIdHTTP;
  LBody: string;
  LJson: TJSONValue;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    // NIT/termino de busqueda ficticio a proposito: no se necesita que exista
    // de verdad, solo que la consulta ejecute y devuelva un array (vacio o no)
    // -- ver Global Constraints sobre no depender de datos reales de Helisa.
    LBody := LHttp.Get(Format('http://localhost:%d/api/erp/productos?search=__PHASE4TEST_NOEXISTE__', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LBody);
    try
      Assert.IsTrue(LJson is TJSONArray);
    finally
      LJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

procedure THelisaControllerTests.GetUnidades_ReturnsJsonArray;
var
  LHttp: TIdHTTP;
  LBody: string;
  LJson: TJSONValue;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LBody := LHttp.Get(Format('http://localhost:%d/api/erp/unidades', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LBody);
    try
      Assert.IsTrue(LJson is TJSONArray);
    finally
      LJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

end.
```

**Verificar antes de escribir**: revisa la firma exacta de `ObtenerTokenDePrueba` en `tests/DMVC/DMVC.TestAuthHelper.pas` (Fase 3) — el ejemplo de arriba asume `function ObtenerTokenDePrueba(APort: Integer): string`, ajusta si la firma real difiere.

Modificar `tests/PurchaseBridge.Tests.dpr`: agregar `DMVC.HelisaControllerTests in 'DMVC\DMVC.HelisaControllerTests.pas';` al final del `uses` (mover el `;`).

Recompilar (cwd = `tests/`) y correr — los 3 tests nuevos deben fallar (404, porque `/erp/productos`/`/erp/unidades` no existen todavía en el server compilado) — RED esperado.

- [ ] **Step 5: Compilar servidor y tests, confirmar GREEN**

Compilar el servidor (cwd = raíz del worktree) agregando `dmvc/DTOs` y `dmvc/Controllers` al `-U` si no están ya (deberían estarlo desde la Fase 2). Compilar tests (cwd = `tests/`). Correr la suite completa — deben pasar TODOS los tests anteriores (15 de las Fases 1-3) más los 3 nuevos de Helisa.

- [ ] **Step 6: Verificación manual**

Con el server corriendo y un token válido: `curl -H "Authorization: Bearer <token>" "http://localhost:9091/api/erp/productos?search=algo"` y `curl -H "Authorization: Bearer <token>" http://localhost:9091/api/erp/unidades` → ambos 200 con array JSON.

- [ ] **Step 7: Commit**

```bash
git add dmvc/DTOs/DMVC.DTOs.Helisa.pas dmvc/Controllers/DMVC.Controllers.HelisaController.pas dmvc/DMVC.WebModule.Main.pas tests/DMVC/DMVC.HelisaControllerTests.pas tests/PurchaseBridge.Tests.dpr
git commit -m "feat: migrate HelisaController to DMVCFramework"
```

**Después de este commit: PARAR y pedir aprobación del usuario antes de escribir el detalle de la Task 2 y continuar** (instrucción explícita del usuario para esta fase, ver nota de proceso arriba).

---

### Roadmap de las Tasks 2-6 (detalle TDD completo se escribe justo antes de cada una)

### Task 2: LicenciaController (4 rutas)

**Files:**
- Create: `dmvc/Controllers/DMVC.Controllers.LicenciaController.pas`
- Modify: `dmvc/DMVC.WebModule.Main.pas` (registrar el controller)
- Create: `tests/DMVC/DMVC.LicenciaControllerTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr`

**Interfaces:**
- Consumes: `services/LicenseService.pas` (`TLicenciaService.ValidarLicencia`, `.RegistrarLicencia`, `.ActivarOnline`, `.LicenciaActual`, sin cambios) y `config/HConfig.pas` (`THConfig.GetInstance.License`, sin cambios).
- No DTOs: el shape de respuesta es dinámico (campos condicionales: `expira` null/fecha, `dias_restantes` null/número, `mensaje_vencimiento`/`requiere_reactivacion`/`detalle` solo en ciertas ramas) — se preserva construyendo `TJSONObject` a mano igual que el Horse original, y se envía con `ContentType := TMVCMediaType.APPLICATION_JSON; Render(LResponse.ToJSON);` (patrón ya usado en `DMVC.Middleware.License.pas` de la Fase 3 para el content-type; `Render(string)` ya existe en `TMVCController`).

**Decisión de testing (importante, ver Global Constraints):** `GetEstado` llama `ValidarLicencia` y `ActivarOnline`/`Registrar` (tras pasar la validación de input) llaman a servicios que hacen peticiones de red reales y pueden mutar el archivo de licencia real — en el entorno de test de este worktree NO hay sección `[LICENCIA]` configurada (mismo hecho ya documentado en la Fase 3 para el guard de licencia dormido), así que ejecutar esas rutas de verdad en un test automatizado dañaría el estado real o fallaría de forma impredecible por falta de red/config. Por lo tanto, los tests automatizados de esta task se limitan a:
1. La validación de input de `Registrar` (falla ANTES de tocar la red, se puede probar con seguridad).
2. La protección JWT de las 4 rutas (falla en el middleware, ANTES de que el controller ejecute cualquier llamada de red — seguro de probar).

No se automatiza el camino feliz de `GetEstado`/`Registrar`/`ActivarOnline` contra la red real — queda para verificación manual (Step 6), igual que Fase 3 dejó dormido el guard de licencia.

- [ ] **Step 1: Escribir el controller**

Crear `dmvc/Controllers/DMVC.Controllers.LicenciaController.pas`:

```pascal
unit DMVC.Controllers.LicenciaController;

interface

uses
  MVCFramework, MVCFramework.Commons;

type
  [MVCPath('/')]
  TLicenciaController = class(TMVCController)
  public
    [MVCPath('/licencia/estado')]
    [MVCPath('/api/licencia/estado')]
    [MVCHTTPMethod([httpGET])]
    procedure GetEstado;

    [MVCPath('/licencia/registrar')]
    [MVCPath('/api/licencia/registrar')]
    [MVCPath('/licencia/activar')]
    [MVCPath('/api/licencia/activar')]
    [MVCHTTPMethod([httpPOST])]
    procedure Registrar;

    [MVCPath('/licencia/activar-online')]
    [MVCPath('/api/licencia/activar-online')]
    [MVCHTTPMethod([httpPOST])]
    procedure ActivarOnline;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.DateUtils,
  LicenseService, HConfig, uLogger;

procedure BuildEstadoFields(const AResponse: TJSONObject);
begin
  AResponse.AddPair('estado', TLicenciaService.LicenciaActual.Estado);

  if TLicenciaService.LicenciaActual.Mensaje = 'Licencia requiere reactivaci' + #243 + ' n' then
  begin
    AResponse.AddPair('expira', TJSONNull.Create);
    AResponse.AddPair('dias_restantes', TJSONNumber.Create(0));
    AResponse.AddPair('mensaje', TLicenciaService.LicenciaActual.Mensaje);
    AResponse.AddPair('detalle', 'Licencia activa sin expiraci' + #243 + 'n calculada');
    AResponse.AddPair('requiere_reactivacion', TJSONBool.Create(True));
  end
  else if TLicenciaService.LicenciaActual.EsPermanente then
  begin
    AResponse.AddPair('expira', TJSONNull.Create);
    AResponse.AddPair('dias_restantes', TJSONNull.Create);
    AResponse.AddPair('mensaje_vencimiento', 'Licencia permanente');
  end
  else
  begin
    AResponse.AddPair('expira', DateToISO8601(TLicenciaService.LicenciaActual.Expira));
    AResponse.AddPair('dias_restantes', TJSONNumber.Create(TLicenciaService.LicenciaActual.DiasRestantes));
  end;

  if TLicenciaService.LicenciaActual.TipoLicencia.Trim.IsEmpty then
    AResponse.AddPair('tipo_licencia', 'demo')
  else
    AResponse.AddPair('tipo_licencia', TLicenciaService.LicenciaActual.TipoLicencia);
end;

procedure TLicenciaController.GetEstado;
var
  LConfig: TLicensingConfig;
  LResponse: TJSONObject;
begin
  LConfig := THConfig.GetInstance.License;

  TLicenciaService.ValidarLicencia(LConfig.Nit, LConfig.InstalacionHash);

  if Assigned(TLicenciaService.LicenciaActual) then
  begin
    LResponse := TJSONObject.Create;
    try
      BuildEstadoFields(LResponse);
      LResponse.AddPair('instalacion_hash', LConfig.InstalacionHash);
      ContentType := TMVCMediaType.APPLICATION_JSON;
      Render(LResponse.ToJSON);
    finally
      LResponse.Free;
    end;
  end
  else
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'No se pudo obtener el estado de la licencia');
end;

procedure TLicenciaController.Registrar;
var
  LBody: TJSONObject;
  LCodigo: string;
  LConfig: TLicensingConfig;
  LSuccess: Boolean;
  LResponse: TJSONObject;
begin
  LBody := TJSONObject.ParseJSONValue(Context.Request.Body) as TJSONObject;
  try
    if not Assigned(LBody) or not LBody.TryGetValue('codigo', LCodigo) then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'C' + #243 + 'digo de registro no proporcionado');
  finally
    LBody.Free;
  end;

  LConfig := THConfig.GetInstance.License;
  Log('Intento de registro de licencia con c' + #243 + 'digo: ' + LCodigo, llInfo);

  LSuccess := TLicenciaService.RegistrarLicencia(LConfig.Nit, LConfig.InstalacionHash, LCodigo);

  LResponse := TJSONObject.Create;
  try
    if not LSuccess and Assigned(TLicenciaService.LicenciaActual) and
       (TLicenciaService.LicenciaActual.Mensaje = 'Licencia no v' + #225 + ' lida para este equipo') then
      LResponse.AddPair('error', TLicenciaService.LicenciaActual.Mensaje)
    else
    begin
      LResponse.AddPair('success', TJSONBool.Create(LSuccess));
      if LSuccess and Assigned(TLicenciaService.LicenciaActual) then
        LResponse.AddPair('mensaje', TLicenciaService.LicenciaActual.Mensaje)
      else
        LResponse.AddPair('mensaje', 'Error al registrar la licencia. Verifique el c' + #243 + 'digo o la conexi' + #243 + 'n.');
    end;

    ContentType := TMVCMediaType.APPLICATION_JSON;
    Render(LResponse.ToJSON);
  finally
    LResponse.Free;
  end;
end;

procedure TLicenciaController.ActivarOnline;
var
  LSuccess: Boolean;
  LResponse: TJSONObject;
begin
  Log('Intento de activacion online de licencia', llInfo);

  LSuccess := TLicenciaService.ActivarOnline;

  LResponse := TJSONObject.Create;
  try
    LResponse.AddPair('success', TJSONBool.Create(LSuccess));
    if LSuccess and Assigned(TLicenciaService.LicenciaActual) then
      BuildEstadoFields(LResponse)
    else
      LResponse.AddPair('mensaje', 'Error al activar la licencia online. Verifique su conexi' + #243 + 'n.');

    ContentType := TMVCMediaType.APPLICATION_JSON;
    Render(LResponse.ToJSON);
  finally
    LResponse.Free;
  end;
end;

end.
```

**ADVERTENCIA (hallazgo de review, corregido):** los literales `'Licencia requiere reactivaci' + #243 + ' n'` y `'Licencia no v' + #225 + ' lida para este equipo'` de arriba llevan un ESPACIO antes de la última letra — parece un error tipográfico pero NO lo es: es el valor EXACTO que `services/LicenseService.pas` asigna en runtime (confirmado leyendo el archivo, líneas con `FLicenciaActual.Mensaje :=`). Si se “corrige” quitando el espacio, la comparación de igualdad de string deja de coincidir nunca y esas ramas de negocio (reactivación requerida / equipo no autorizado) quedan muertas en silencio, sin que ningún test lo detecte a menos que se pruebe contra un estado de licencia real con ese mensaje exacto. Copiar estos literales carácter por carácter, sin “limpiarlos”.

Notas de fidelidad con el Horse original:
- `GetEstado`/`ActivarOnline` comparten exactamente la misma lógica condicional de campos (`BuildEstadoFields`, extraída como función libre en la sección `implementation` para no duplicar el bloque de 20 líneas dos veces — esto es refactor MECÁNICO sin cambio de comportamiento, no una abstracción nueva de diseño).
- `Registrar` valida el body ANTES de tocar `LicenseService` — igual que el original — por eso el test de 400 es seguro de automatizar.
- Errores ahora se señalizan con `raise EMVCException.Create(...)` (convención DMVC ya usada en Fases 2-3) en vez de `Res.Status(...).Send(...)` (convención Horse).
- `Context.Request.Body` (string) reemplaza `Req.Body<TJSONObject>` de Horse — verificar el nombre exacto de la propiedad en `MVCFramework.pas` (`TWebContext.Request.Body`) antes de compilar; si el nombre real difiere, usar el que corresponda (mismo patrón ya usado en controllers de Fase 2 si alguno parsea JSON crudo).

- [ ] **Step 2: Registrar el controller en el WebModule**

Modificar `dmvc/DMVC.WebModule.Main.pas`: agregar `DMVC.Controllers.LicenciaController` al `uses` y `FEngine.AddController(TLicenciaController);` después de `THelisaController`.

- [ ] **Step 3: Escribir los tests (RED → GREEN)**

Crear `tests/DMVC/DMVC.LicenciaControllerTests.pas` (mismo patrón `TTestServerProcess` + `ObtenerTokenDePrueba` de la Task 1):

```pascal
unit DMVC.LicenciaControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TLicenciaControllerTests = class
  private
    FServer: TTestServerProcess;
    FToken: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Registrar_WithoutCodigo_Returns400;

    [Test]
    procedure GetEstado_WithoutToken_Returns401;

    [Test]
    procedure Registrar_WithoutToken_Returns401;

    [Test]
    procedure ActivarOnline_WithoutToken_Returns401;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, IdHTTP, IdGlobal, DMVC.TestAuthHelper;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TLicenciaControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
  FToken := ObtenerTokenDePrueba(TEST_PORT);
end;

procedure TLicenciaControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TLicenciaControllerTests.Registrar_WithoutCodigo_Returns400;
var
  LHttp: TIdHTTP;
  LBytes: TIdBytes;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/json';
    LBytes := IndyTextEncoding_UTF8.GetBytes('{}');
    try
      LHttp.Post(Format('http://localhost:%d/api/licencia/registrar', [TEST_PORT]), TIdMemoryStream.Create);
      Assert.Fail('Se esperaba una excepcion HTTP 400');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(400, E.ErrorCode);
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TLicenciaControllerTests.GetEstado_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    try
      LHttp.Get(Format('http://localhost:%d/api/licencia/estado', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 401');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(401, E.ErrorCode);
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TLicenciaControllerTests.Registrar_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
  LResponse: TStringStream;
  LRequest: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{"codigo":"X"}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.ContentType := 'application/json';
    try
      LHttp.Post(Format('http://localhost:%d/api/licencia/registrar', [TEST_PORT]), LRequest, LResponse);
      Assert.Fail('Se esperaba una excepcion HTTP 401');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(401, E.ErrorCode);
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TLicenciaControllerTests.ActivarOnline_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
  LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LResponse := TStringStream.Create;
  try
    try
      LHttp.Post(Format('http://localhost:%d/api/licencia/activar-online', [TEST_PORT]), TStream(nil), LResponse);
      Assert.Fail('Se esperaba una excepcion HTTP 401');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(401, E.ErrorCode);
    end;
  finally
    LResponse.Free;
    LHttp.Free;
  end;
end;

end.
```

**Antes de escribir el código final, quien implemente debe:**
1. Revisar `tests/DMVC/DMVC.EquivalenciaControllerTests.pas` o `DMVC.ProveedorControllerTests.pas` (Fase 2/3) para copiar el patrón EXACTO de cómo se hace un POST con body JSON vía `TIdHTTP` en este proyecto (el snippet de `Registrar_WithoutCodigo_Returns400`/`Registrar_WithoutToken_Returns401` de arriba es ilustrativo del INTENTO, no necesariamente sintácticamente perfecto para `TIdHTTP.Post` — unificar con el helper/patrón que ya exista, en vez de introducir uno nuevo).
2. Verificar la firma real de `ObtenerTokenDePrueba`.

Modificar `tests/PurchaseBridge.Tests.dpr`: agregar `DMVC.LicenciaControllerTests in 'DMVC\DMVC.LicenciaControllerTests.pas';`.

Compilar servidor + tests (mismas rutas `-U` que la Task 1, sin carpetas nuevas ya que no hay DTOs nuevos). Correr la suite completa — deben pasar los 18 anteriores + 4 nuevos = 22.

- [ ] **Step 4: Verificación manual (camino feliz, NO automatizado)**

Con el server corriendo y un token válido:
- `curl -H "Authorization: Bearer <token>" http://localhost:9091/api/licencia/estado` → observar respuesta (puede fallar por falta de `[LICENCIA]` en `config.ini` de este entorno — está bien, documentar el resultado observado tal cual, igual que se documentó el guard dormido en la Fase 3).
- NO ejecutar `registrar`/`activar-online` con datos reales a menos que el usuario lo pida explícitamente (mutan estado real de licencia).

- [ ] **Step 5: Commit**

```bash
git add dmvc/Controllers/DMVC.Controllers.LicenciaController.pas dmvc/DMVC.WebModule.Main.pas tests/DMVC/DMVC.LicenciaControllerTests.pas tests/PurchaseBridge.Tests.dpr
git commit -m "feat: migrate LicenciaController to DMVCFramework"
```

**Después de este commit: PARAR y pedir aprobación del usuario antes de escribir el detalle de la Task 3.**

### Task 3: XmlValidationController (2 rutas)

**Files:**
- Create: `dmvc/Controllers/DMVC.Controllers.XmlValidationController.pas`
- Modify: `dmvc/DMVC.WebModule.Main.pas` (registrar el controller)
- Create: `tests/DMVC/DMVC.XmlValidationControllerTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr`

**Interfaces:**
- Consumes: `services/XmlParserService.pas` (`TXmlParserService.Parse`, `TParsedInvoice`), `services/XmlPersistenceService.pas` (`UpsertXMLInvoice`), `services/ValidationService.pas` (`ValidarDocumento`), `utils/uPaths.pas` (`GetInputPath`) — todos sin cambios.
- Sin DTOs: mismo criterio que la Task 2 — el shape de respuesta es dinámico (`valido`/`requiereHomologacion`/`proveedorExiste`/`productos`/`errores` varían según la rama), se preserva construyendo `TJSONObject` a mano y enviando con `ContentType := TMVCMediaType.APPLICATION_JSON;` + `Render(...)`.

**Decisión de testing (mismo criterio de seguridad que la Task 2):** `InternalValidateFile` (función compartida por ambas rutas) NUNCA lanza excepción — atrapa todo internamente y siempre devuelve HTTP 200 con el resultado embebido en el JSON (`valido:true/false`). El único caso de error HTTP real (400) es la validación de `fileName` faltante en `Validate`, que ocurre ANTES de tocar el filesystem — segura de automatizar. Para cubrir el resto del comportamiento SIN depender de archivos XML reales ni escribir en las tablas de staging reales (`UpsertXMLInvoice` sí persiste si el parseo tiene éxito), los tests usan nombres de archivo que DETERMINÍSTICAMENTE no existen en el disco — eso dispara la rama "Archivo no encontrado" (la primera guarda de `InternalValidateFile`, antes de leer/parsear/persistir nada), que es 100% determinística y no requiere red ni DB. No se prueba el camino feliz completo (XML real parseado + persistido) en esta task — igual que Fase 3 dejó dormido el guard de licencia y la Task 2 dejó sin automatizar el camino de red real.

- [ ] **Step 1: Escribir el controller**

Crear `dmvc/Controllers/DMVC.Controllers.XmlValidationController.pas`:

```pascal
unit DMVC.Controllers.XmlValidationController;

interface

uses
  MVCFramework, MVCFramework.Commons;

type
  [MVCPath('/')]
  TXmlValidationController = class(TMVCController)
  public
    [MVCPath('/xml/validate')]
    [MVCPath('/api/xml/validate')]
    [MVCHTTPMethod([httpPOST])]
    procedure Validate;

    [MVCPath('/xml/validate/batch')]
    [MVCPath('/api/xml/validate/batch')]
    [MVCHTTPMethod([httpPOST])]
    procedure ValidateBatch;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Classes,
  XmlParserService, XmlPersistenceService, ValidationService, uPaths;

function ParsedInvoiceToJSONObject(const AParsedInvoice: TParsedInvoice): TJSONObject;
var
  LProveedor, LTotales, LProducto: TJSONObject;
  LProductosArr: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  try
    LProveedor := TJSONObject.Create;
    LProveedor.AddPair('nit', AParsedInvoice.Provider.NIT);
    LProveedor.AddPair('nombre', AParsedInvoice.Provider.Nombre);
    LProveedor.AddPair('nombreLegal', AParsedInvoice.Provider.NombreLegal);
    LProveedor.AddPair('tipoIdentificacion', AParsedInvoice.Provider.TipoIdentificacion);
    LProveedor.AddPair('direccion', AParsedInvoice.Provider.Direccion);
    Result.AddPair('proveedor', LProveedor);

    LProductosArr := TJSONArray.Create;
    for I := 0 to Length(AParsedInvoice.Products) - 1 do
    begin
      LProducto := TJSONObject.Create;
      LProducto.AddPair('idLinea', AParsedInvoice.Products[I].IDLinea);
      LProducto.AddPair('descripcion', AParsedInvoice.Products[I].Descripcion);
      LProducto.AddPair('referencia', AParsedInvoice.Products[I].Referencia);
      LProducto.AddPair('referenciaEstandar', AParsedInvoice.Products[I].ReferenciaEstandar);
      LProducto.AddPair('cantidad', TJSONNumber.Create(AParsedInvoice.Products[I].Cantidad));
      LProducto.AddPair('unidadXML', AParsedInvoice.Products[I].Unidad);
      LProducto.AddPair('precioBase', TJSONNumber.Create(AParsedInvoice.Products[I].PrecioBase));
      LProducto.AddPair('valorUnitario', TJSONNumber.Create(AParsedInvoice.Products[I].ValorUnitario));
      LProducto.AddPair('valorTotal', TJSONNumber.Create(AParsedInvoice.Products[I].ValorTotal));
      LProducto.AddPair('impuesto', TJSONNumber.Create(AParsedInvoice.Products[I].Impuesto));
      LProducto.AddPair('porcentajeImpuesto', TJSONNumber.Create(AParsedInvoice.Products[I].ImpuestoPorcentaje));
      LProductosArr.Add(LProducto);
    end;
    Result.AddPair('productos', LProductosArr);

    LTotales := TJSONObject.Create;
    LTotales.AddPair('subtotal', TJSONNumber.Create(AParsedInvoice.Totals.Subtotal));
    LTotales.AddPair('taxExclusiveAmount', TJSONNumber.Create(AParsedInvoice.Totals.TaxExclusiveAmount));
    LTotales.AddPair('taxInclusiveAmount', TJSONNumber.Create(AParsedInvoice.Totals.TaxInclusiveAmount));
    LTotales.AddPair('impuestoTotal', TJSONNumber.Create(AParsedInvoice.Totals.ImpuestoTotal));
    LTotales.AddPair('total', TJSONNumber.Create(AParsedInvoice.Totals.Total));
    Result.AddPair('totales', LTotales);
  except
    Result.Free;
    raise;
  end;
end;

function InternalValidateFile(const AFileName: string): TJSONObject;
var
  LPath, LFullFile, LXMLContent, LParsedJSONStr, LValidationResult: string;
  LParsedInvoice: TParsedInvoice;
  LParsedObj: TJSONObject;
  LErroresArray: TJSONArray;
  LVal: TJSONValue;
begin
  try
    LPath := GetInputPath;
    LFullFile := TPath.Combine(LPath, AFileName);

    if not TFile.Exists(LFullFile) then
    begin
      Result := TJSONObject.Create;
      Result.AddPair('fileName', AFileName);
      Result.AddPair('valido', TJSONBool.Create(False));
      Result.AddPair('requiereHomologacion', TJSONBool.Create(False));
      Result.AddPair('proveedorExiste', TJSONBool.Create(False));
      Result.AddPair('productos', TJSONArray.Create);
      LErroresArray := TJSONArray.Create;
      LErroresArray.Add('Archivo no encontrado');
      Result.AddPair('errores', LErroresArray);
      Exit;
    end;

    try
      LXMLContent := TFile.ReadAllText(LFullFile, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        Result := TJSONObject.Create;
        Result.AddPair('fileName', AFileName);
        Result.AddPair('valido', TJSONBool.Create(False));
        Result.AddPair('requiereHomologacion', TJSONBool.Create(False));
        Result.AddPair('proveedorExiste', TJSONBool.Create(False));
        Result.AddPair('productos', TJSONArray.Create);
        LErroresArray := TJSONArray.Create;
        LErroresArray.Add('Error al leer el archivo: ' + E.Message);
        Result.AddPair('errores', LErroresArray);
        Exit;
      end;
    end;

    try
      LParsedInvoice := TXmlParserService.Parse(LXMLContent);
      LParsedObj := ParsedInvoiceToJSONObject(LParsedInvoice);
      try
        LParsedJSONStr := LParsedObj.ToJSON;
      finally
        LParsedObj.Free;
      end;
    except
      on E: Exception do
      begin
        Result := TJSONObject.Create;
        Result.AddPair('fileName', AFileName);
        Result.AddPair('valido', TJSONBool.Create(False));
        Result.AddPair('requiereHomologacion', TJSONBool.Create(False));
        Result.AddPair('proveedorExiste', TJSONBool.Create(False));
        Result.AddPair('productos', TJSONArray.Create);
        LErroresArray := TJSONArray.Create;
        LErroresArray.Add('XML inválido o error en parseo: ' + E.Message);
        Result.AddPair('errores', LErroresArray);
        Exit;
      end;
    end;

    try
      LValidationResult := ValidarDocumento(LParsedJSONStr);

      try
        UpsertXMLInvoice(AFileName, LParsedInvoice);
      except
        // Non-blocking error for staging
      end;

      LVal := TJSONObject.ParseJSONValue(LValidationResult);
      if LVal is TJSONObject then
      begin
        Result := LVal as TJSONObject;
        if Result.GetValue('fileName') = nil then
          Result.AddPair('fileName', AFileName);
      end
      else
      begin
        if Assigned(LVal) then LVal.Free;
        Result := TJSONObject.Create;
        Result.AddPair('fileName', AFileName);
        Result.AddPair('valido', TJSONBool.Create(False));
        Result.AddPair('requiereHomologacion', TJSONBool.Create(False));
        Result.AddPair('proveedorExiste', TJSONBool.Create(False));
        Result.AddPair('productos', TJSONArray.Create);
        LErroresArray := TJSONArray.Create;
        LErroresArray.Add('Error al procesar el resultado de validación');
        Result.AddPair('errores', LErroresArray);
      end;
    except
      on E: Exception do
      begin
        Result := TJSONObject.Create;
        Result.AddPair('fileName', AFileName);
        Result.AddPair('valido', TJSONBool.Create(False));
        Result.AddPair('requiereHomologacion', TJSONBool.Create(False));
        Result.AddPair('proveedorExiste', TJSONBool.Create(False));
        Result.AddPair('productos', TJSONArray.Create);
        LErroresArray := TJSONArray.Create;
        LErroresArray.Add('Error en validación: ' + E.Message);
        Result.AddPair('errores', LErroresArray);
      end;
    end;
  except
    on E: Exception do
    begin
      Result := TJSONObject.Create;
      Result.AddPair('fileName', AFileName);
      Result.AddPair('valido', TJSONBool.Create(False));
      Result.AddPair('requiereHomologacion', TJSONBool.Create(False));
      Result.AddPair('proveedorExiste', TJSONBool.Create(False));
      Result.AddPair('productos', TJSONArray.Create);
      LErroresArray := TJSONArray.Create;
      LErroresArray.Add('Error inesperado: ' + E.Message);
      Result.AddPair('errores', LErroresArray);
    end;
  end;
end;

procedure TXmlValidationController.Validate;
var
  LBody: TJSONObject;
  LFileName: string;
  LHasFileName: Boolean;
  LResultJSON: TJSONObject;
  LErroresArr: TJSONArray;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  try
    LBody := TJSONObject.ParseJSONValue(Context.Request.Body) as TJSONObject;
    try
      LHasFileName := Assigned(LBody) and LBody.TryGetValue('fileName', LFileName);
    finally
      LBody.Free;
    end;

    if not LHasFileName then
    begin
      LResultJSON := TJSONObject.Create;
      try
        LResultJSON.AddPair('fileName', TJSONNull.Create);
        LResultJSON.AddPair('valido', TJSONBool.Create(False));
        LResultJSON.AddPair('requiereHomologacion', TJSONBool.Create(False));
        LErroresArr := TJSONArray.Create;
        LErroresArr.Add('fileName is required in the body');
        LResultJSON.AddPair('errores', LErroresArr);
        Render(HTTP_STATUS.BadRequest, LResultJSON.ToJSON);
      finally
        LResultJSON.Free;
      end;
      Exit;
    end;

    LFileName := TPath.GetFileName(LFileName);
    LResultJSON := InternalValidateFile(LFileName);
    try
      Render(LResultJSON.ToJSON);
    finally
      LResultJSON.Free;
    end;
  except
    on E: Exception do
    begin
      LResultJSON := TJSONObject.Create;
      try
        LResultJSON.AddPair('fileName', TJSONNull.Create);
        LResultJSON.AddPair('valido', TJSONBool.Create(False));
        LResultJSON.AddPair('requiereHomologacion', TJSONBool.Create(False));
        LErroresArr := TJSONArray.Create;
        LErroresArr.Add('Error inesperado: ' + E.Message);
        LResultJSON.AddPair('errores', LErroresArr);
        Render(HTTP_STATUS.InternalServerError, LResultJSON.ToJSON);
      finally
        LResultJSON.Free;
      end;
    end;
  end;
end;

procedure TXmlValidationController.ValidateBatch;
var
  LBody: TJSONObject;
  LFilesArr: TJSONArray;
  LFiles: TStringList;
  LFileName, LPath: string;
  LOutputJSON, LSummary: TJSONObject;
  LDocumentsArr: TJSONArray;
  LResultDoc: TJSONObject;
  LValido: Boolean;
  LTotal, LValidos, LConErrores: Integer;
  I: Integer;
  LFilesValue: TJSONValue;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  LFiles := TStringList.Create;
  try
    LBody := TJSONObject.ParseJSONValue(Context.Request.Body) as TJSONObject;
    try
      if Assigned(LBody) then
      begin
        LFilesValue := LBody.GetValue('files');
        if (LFilesValue <> nil) and (LFilesValue is TJSONArray) then
        begin
          LFilesArr := LFilesValue as TJSONArray;
          for I := 0 to LFilesArr.Count - 1 do
            LFiles.Add(TPath.GetFileName(LFilesArr.Items[I].Value));
        end;
      end;
    finally
      LBody.Free;
    end;

    if LFiles.Count = 0 then
    begin
      LPath := GetInputPath;
      if TDirectory.Exists(LPath) then
      begin
        for LFileName in TDirectory.GetFiles(LPath, '*.xml') do
          LFiles.Add(TPath.GetFileName(LFileName));
      end;
    end;

    LOutputJSON := TJSONObject.Create;
    try
      LDocumentsArr := TJSONArray.Create;
      LTotal := LFiles.Count;
      LValidos := 0;
      LConErrores := 0;

      for I := 0 to LFiles.Count - 1 do
      begin
        LResultDoc := InternalValidateFile(LFiles[I]);

        LValido := False;
        if (LResultDoc.GetValue('valido') <> nil) and (LResultDoc.GetValue('valido') is TJSONBool) then
          LValido := (LResultDoc.GetValue('valido') as TJSONBool).AsBoolean;

        if LValido then
          Inc(LValidos)
        else
          Inc(LConErrores);

        LDocumentsArr.Add(LResultDoc);
      end;

      LOutputJSON.AddPair('documentos', LDocumentsArr);

      LSummary := TJSONObject.Create;
      LSummary.AddPair('total', TJSONNumber.Create(LTotal));
      LSummary.AddPair('validos', TJSONNumber.Create(LValidos));
      LSummary.AddPair('conErrores', TJSONNumber.Create(LConErrores));
      LOutputJSON.AddPair('resumen', LSummary);

      Render(LOutputJSON.ToJSON);
    finally
      LOutputJSON.Free;
    end;
  finally
    LFiles.Free;
  end;
end;

end.
```

Notas de fidelidad con el Horse original:
- `ParsedInvoiceToJSONObject`/`InternalValidateFile` son copia EXACTA de la lógica de negocio del Horse original (`controllers/XmlValidationController.pas`), solo cambia el contenedor (funciones libres en `implementation` en vez de funciones de unidad Horse) — respetar cada literal de string y cada nombre de campo JSON tal cual (recordar la advertencia de la Task 2 sobre nunca "limpiar" literales copiados de Horse; en esta task no hay literales con espacios sospechosos conocidos, pero aplica el mismo principio general de copiar carácter por carácter).
- `Res.Status(400).Send(...)` / `Res.Send<TJSONObject>(...)` de Horse se reemplazan por `Render(HTTP_STATUS.BadRequest, json.ToJSON)` / `Render(json.ToJSON)` de DMVC — confirmar que el overload `Render(const AStatusCode: Integer; const AContent: string)` existe en esta versión de `TMVCController` (ya listado en `MVCFramework.pas` de este framework) antes de compilar.
- `UpsertXMLInvoice` solo se alcanza a llamar cuando el parseo XML tiene éxito — los tests de esta task usan nombres de archivo inexistentes, por lo que NUNCA llegan a esa línea (verificado leyendo el flujo: el `Exit` de "Archivo no encontrado" ocurre antes).

- [ ] **Step 2: Registrar el controller en el WebModule**

Modificar `dmvc/DMVC.WebModule.Main.pas`: agregar `DMVC.Controllers.XmlValidationController` al `uses` y `FEngine.AddController(TXmlValidationController);` después de `TLicenciaController`.

- [ ] **Step 3: Escribir los tests (RED → GREEN)**

Crear `tests/DMVC/DMVC.XmlValidationControllerTests.pas` (mismo patrón `TTestServerProcess` + `ObtenerTokenDePrueba` + `TStringStream` request/response de la Task 2):

```pascal
unit DMVC.XmlValidationControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TXmlValidationControllerTests = class
  private
    FServer: TTestServerProcess;
    FToken: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Validate_WithoutFileName_Returns400;

    [Test]
    procedure Validate_WithNonexistentFile_ReturnsValidoFalse;

    [Test]
    procedure ValidateBatch_WithNonexistentFiles_ReturnsSummary;

    [Test]
    procedure Validate_WithoutToken_Returns401;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Classes, IdHTTP, DMVC.TestAuthHelper;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TXmlValidationControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
  FToken := ObtenerTokenDePrueba(TEST_PORT);
end;

procedure TXmlValidationControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TXmlValidationControllerTests.Validate_WithoutFileName_Returns400;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/json';
    try
      LHttp.Post(Format('http://localhost:%d/api/xml/validate', [TEST_PORT]), LRequest, LResponse);
      Assert.Fail('Se esperaba una excepcion HTTP 400');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(400, E.ErrorCode);
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TXmlValidationControllerTests.Validate_WithNonexistentFile_ReturnsValidoFalse;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
  LJson: TJSONObject;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{"fileName":"__phase4_no_existe__.xml"}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/json';
    LHttp.Post(Format('http://localhost:%d/api/xml/validate', [TEST_PORT]), LRequest, LResponse);
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LResponse.DataString) as TJSONObject;
    try
      Assert.IsNotNull(LJson);
      Assert.IsFalse((LJson.GetValue('valido') as TJSONBool).AsBoolean);
    finally
      LJson.Free;
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TXmlValidationControllerTests.ValidateBatch_WithNonexistentFiles_ReturnsSummary;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
  LJson, LResumen: TJSONObject;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{"files":["__a__.xml","__b__.xml"]}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/json';
    LHttp.Post(Format('http://localhost:%d/api/xml/validate/batch', [TEST_PORT]), LRequest, LResponse);
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LResponse.DataString) as TJSONObject;
    try
      LResumen := LJson.GetValue('resumen') as TJSONObject;
      Assert.AreEqual(2, (LResumen.GetValue('total') as TJSONNumber).AsInt);
      Assert.AreEqual(0, (LResumen.GetValue('validos') as TJSONNumber).AsInt);
      Assert.AreEqual(2, (LResumen.GetValue('conErrores') as TJSONNumber).AsInt);
    finally
      LJson.Free;
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TXmlValidationControllerTests.Validate_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('{"fileName":"x.xml"}', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.ContentType := 'application/json';
    try
      LHttp.Post(Format('http://localhost:%d/api/xml/validate', [TEST_PORT]), LRequest, LResponse);
      Assert.Fail('Se esperaba una excepcion HTTP 401');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(401, E.ErrorCode);
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

end.
```

Modificar `tests/PurchaseBridge.Tests.dpr`: agregar `DMVC.XmlValidationControllerTests in 'DMVC\DMVC.XmlValidationControllerTests.pas';`.

Compilar servidor + tests. Correr la suite completa — deben pasar los 22 anteriores + 4 nuevos = 26.

- [ ] **Step 4: Verificación manual (opcional)**

Con el server corriendo y un token válido, probar `POST /api/xml/validate` con un `fileName` que exista de verdad en la carpeta `Input` configurada (si el usuario tiene uno de prueba disponible) para confirmar el camino feliz completo — NO obligatorio si no hay un XML de prueba a mano; los tests automatizados ya cubren el contrato de la ruta.

- [ ] **Step 5: Commit**

```bash
git add dmvc/Controllers/DMVC.Controllers.XmlValidationController.pas dmvc/DMVC.WebModule.Main.pas tests/DMVC/DMVC.XmlValidationControllerTests.pas tests/PurchaseBridge.Tests.dpr
git commit -m "feat: migrate XmlValidationController to DMVCFramework"
```

**Después de este commit: PARAR y pedir aprobación del usuario antes de escribir el detalle de la Task 4.**

### Task 4: ImportController (1 ruta)

**Files:**
- Create: `dmvc/Controllers/DMVC.Controllers.ImportController.pas`
- Modify: `dmvc/DMVC.WebModule.Main.pas`
- Create: `tests/DMVC/DMVC.ImportControllerTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr`

**Interfaces:**
- Consumes: `services/XMLFacturaService.pas` (`TXMLFacturaService.Parsear`, `TFacturaXML`, `TProductoXML`), `repositories/ProveedorRepository.pas` (`ObtenerProveedorPorNit`, `TProveedorInfo`), `repositories/ProductoRepository.pas` (`ExisteProducto`), `utils/uLogger.pas` (`LogError`) — todos sin cambios. NO se usa `utils/ErrorResponseUtils.pas` (depende de `THorseResponse`, es Horse-specific) — se reemplaza por el mismo patrón `raise EMVCException.Create(status, mensaje)` ya usado en Tasks 1-2 (normalización de shape de error `{success,message,detail}` → shape estándar de DMVC, ya aceptada desde la Fase 3).
- Sin DTOs: el shape de respuesta (`proveedor`/`productos`) es simple pero con un campo condicional (`codigo` solo si `existe`) — se preserva igual que Horse con `TJSONObject` a mano.
- Sin alias `/api` (a diferencia de casi todas las demás rutas de este proyecto) — el Horse original solo registra `/factura/xml`, sin duplicado. Preservar tal cual, no agregar el alias.

**Decisión de testing:** a diferencia de `LicenciaController` (Task 2), esta ruta SÍ es segura de probar en su camino feliz completo: `ObtenerProveedorPorNit`/`ExisteProducto` son consultas de solo lectura contra la Helisa real (mismo patrón ya usado y aceptado en la Fase 2 para `ProveedorController`) — usando un NIT y una referencia de producto claramente ficticios (`'000000000-TEST'` — mismo NIT ficticio ya usado en la Fase 2, y una referencia con un sufijo `__PHASE4TEST__` que no debería existir), el test ejercita el parseo XML real + las dos consultas reales sin depender de que existan datos reales ni escribir nada.

- [ ] **Step 1: Escribir el controller**

Crear `dmvc/Controllers/DMVC.Controllers.ImportController.pas`:

```pascal
unit DMVC.Controllers.ImportController;

interface

uses
  MVCFramework, MVCFramework.Commons;

type
  [MVCPath('/')]
  TImportController = class(TMVCController)
  public
    [MVCPath('/factura/xml')]
    [MVCHTTPMethod([httpPOST])]
    procedure PostFacturaXML;
  end;

implementation

uses
  System.SysUtils, System.JSON,
  XMLFacturaService, ProveedorRepository, ProductoRepository, uLogger;

procedure TImportController.PostFacturaXML;
var
  LXMLContent: string;
  LFactura: TFacturaXML;
  LResponseJSON, LProveedorJSON, LProductoJSON: TJSONObject;
  LProductosArray: TJSONArray;
  I: Integer;
  LProveedor: TProveedorInfo;
  LExisteProducto: Boolean;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  try
    LXMLContent := Context.Request.Body;
    if LXMLContent = '' then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Cuerpo XML vacío');

    LFactura := TXMLFacturaService.Parsear(LXMLContent);

    LResponseJSON := TJSONObject.Create;
    try
      LProveedor := ObtenerProveedorPorNit(LFactura.NitProveedor, LFactura.Anio);
      LProveedorJSON := TJSONObject.Create;
      LProveedorJSON.AddPair('nit', LFactura.NitProveedor);
      LProveedorJSON.AddPair('existe', TJSONBool.Create(LProveedor.Existe));
      if LProveedor.Existe then
        LProveedorJSON.AddPair('codigo', LProveedor.Codigo);
      LResponseJSON.AddPair('proveedor', LProveedorJSON);

      LProductosArray := TJSONArray.Create;
      for I := 0 to Length(LFactura.Productos) - 1 do
      begin
        LExisteProducto := ExisteProducto(LFactura.Productos[I].Referencia, LFactura.Productos[I].Descripcion, LFactura.Anio);

        LProductoJSON := TJSONObject.Create;
        LProductoJSON.AddPair('referencia', LFactura.Productos[I].Referencia);
        LProductoJSON.AddPair('descripcion', LFactura.Productos[I].Descripcion);
        LProductoJSON.AddPair('existe', TJSONBool.Create(LExisteProducto));
        LProductosArray.AddElement(LProductoJSON);
      end;
      LResponseJSON.AddPair('productos', LProductosArray);

      Render(LResponseJSON.ToJSON);
    finally
      LResponseJSON.Free;
    end;
  except
    on E: EMVCException do
      raise;
    on E: Exception do
    begin
      uLogger.LogError(E.Message, 'error_response');
      raise EMVCException.Create(HTTP_STATUS.InternalServerError, 'Error interno del servidor: ' + E.Message);
    end;
  end;
end;

end.
```

Notas:
- `on E: EMVCException do raise;` re-lanza sin envolver — así el 400 de "Cuerpo XML vacío" no cae en la rama genérica de 500.
- El único `Render(LResponseJSON.ToJSON)` es de un solo argumento (sin `StatusCode`), así que NO aplica la gotcha de resolución de overloads encontrada en la Task 3 (`Render(Integer, X.ToJSON)`) — solo aplica si se agrega un `Render(statusCode, ...)` en algún punto; si el compilador da `E2250` en algún `Render`, aplicar el mismo fix (asignar `.ToJSON` a una variable local `string` antes de pasarla).

- [ ] **Step 2: Registrar el controller en el WebModule**

Modificar `dmvc/DMVC.WebModule.Main.pas`: agregar `DMVC.Controllers.ImportController` al `uses` y `FEngine.AddController(TImportController);` después de `TXmlValidationController`.

- [ ] **Step 3: Escribir los tests (RED → GREEN)**

Crear `tests/DMVC/DMVC.ImportControllerTests.pas`. Usar un XML de factura UBL mínimo pero válido para que `TXMLFacturaService.Parsear` no lance excepción — el parser busca literalmente los nodos `cac:AccountingSupplierParty` → `cac:Party` → `cac:PartyTaxScheme` → `cbc:CompanyID` (NIT), `cbc:IssueDate` (año), y cada `cac:InvoiceLine` → `cac:Item` → `cbc:Description` + `cac:SellersItemIdentification` → `cbc:ID` (por producto). Declarar los namespaces `cac`/`cbc` en el XML de prueba para evitar un error de "prefijo no declarado" al cargarlo con `LoadXMLData`:

```pascal
unit DMVC.ImportControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TImportControllerTests = class
  private
    FServer: TTestServerProcess;
    FToken: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure PostFacturaXML_WithEmptyBody_Returns400;

    [Test]
    procedure PostFacturaXML_WithValidXML_ReturnsProveedorYProductos;

    [Test]
    procedure PostFacturaXML_WithoutToken_Returns401;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Classes, IdHTTP, DMVC.TestAuthHelper;

const
  TEST_PORT = 9091;
  TEST_XML =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<Invoice xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" ' +
    'xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">' +
    '<cbc:IssueDate>2024-05-22</cbc:IssueDate>' +
    '<cac:AccountingSupplierParty>' +
    '<cac:Party>' +
    '<cac:PartyTaxScheme>' +
    '<cbc:CompanyID>000000000-TEST</cbc:CompanyID>' +
    '</cac:PartyTaxScheme>' +
    '</cac:Party>' +
    '</cac:AccountingSupplierParty>' +
    '<cac:InvoiceLine>' +
    '<cac:Item>' +
    '<cbc:Description>Producto de prueba Fase 4</cbc:Description>' +
    '<cac:SellersItemIdentification>' +
    '<cbc:ID>__PHASE4TEST_REF__</cbc:ID>' +
    '</cac:SellersItemIdentification>' +
    '</cac:Item>' +
    '</cac:InvoiceLine>' +
    '</Invoice>';

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TImportControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
  FToken := ObtenerTokenDePrueba(TEST_PORT);
end;

procedure TImportControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TImportControllerTests.PostFacturaXML_WithEmptyBody_Returns400;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create('', TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/xml';
    try
      LHttp.Post(Format('http://localhost:%d/factura/xml', [TEST_PORT]), LRequest, LResponse);
      Assert.Fail('Se esperaba una excepcion HTTP 400');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(400, E.ErrorCode);
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TImportControllerTests.PostFacturaXML_WithValidXML_ReturnsProveedorYProductos;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
  LJson: TJSONObject;
  LProveedor: TJSONObject;
  LProductos: TJSONArray;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create(TEST_XML, TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FToken);
    LHttp.Request.ContentType := 'application/xml';
    LHttp.Post(Format('http://localhost:%d/factura/xml', [TEST_PORT]), LRequest, LResponse);
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LResponse.DataString) as TJSONObject;
    try
      Assert.IsNotNull(LJson);
      LProveedor := LJson.GetValue('proveedor') as TJSONObject;
      Assert.AreEqual('000000000-TEST', LProveedor.GetValue('nit').Value);
      Assert.IsFalse((LProveedor.GetValue('existe') as TJSONBool).AsBoolean);
      LProductos := LJson.GetValue('productos') as TJSONArray;
      Assert.AreEqual(1, LProductos.Count);
      Assert.IsFalse(((LProductos.Items[0] as TJSONObject).GetValue('existe') as TJSONBool).AsBoolean);
    finally
      LJson.Free;
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

procedure TImportControllerTests.PostFacturaXML_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
  LRequest, LResponse: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  LRequest := TStringStream.Create(TEST_XML, TEncoding.UTF8);
  LResponse := TStringStream.Create;
  try
    LHttp.Request.ContentType := 'application/xml';
    try
      LHttp.Post(Format('http://localhost:%d/factura/xml', [TEST_PORT]), LRequest, LResponse);
      Assert.Fail('Se esperaba una excepcion HTTP 401');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(401, E.ErrorCode);
    end;
  finally
    LRequest.Free;
    LResponse.Free;
    LHttp.Free;
  end;
end;

end.
```

**Antes de dar por bueno el test 2, quien implemente debe verificar empíricamente que `TEST_XML` es parseado sin excepción por `TXmlFacturaService.Parsear`** (correrlo una vez y confirmar 200, no asumir que el XML de arriba es perfecto a la primera — si `Parsear` lanza una excepción por algún nodo faltante/mal formado, ajustar el XML de prueba, NO el código del controller ni del servicio).

Modificar `tests/PurchaseBridge.Tests.dpr`: agregar `DMVC.ImportControllerTests in 'DMVC\DMVC.ImportControllerTests.pas';`.

Compilar servidor + tests. Correr la suite completa — deben pasar los 26 anteriores + 3 nuevos = 29.

- [ ] **Step 4: Commit**

```bash
git add dmvc/Controllers/DMVC.Controllers.ImportController.pas dmvc/DMVC.WebModule.Main.pas tests/DMVC/DMVC.ImportControllerTests.pas tests/PurchaseBridge.Tests.dpr
git commit -m "feat: migrate ImportController to DMVCFramework"
```

Sin gate de aprobación después de esta task — el usuario autorizó continuar con las tareas restantes (4, 5, 6) sin pausas intermedias; seguir directo a escribir el detalle de la Task 5.

### Task 5: DocumentosController (1 ruta) + endpoint /api/auth/me

**Files:**
- Create: `dmvc/Controllers/DMVC.Controllers.DocumentosController.pas`
- Create: `dmvc/Controllers/DMVC.Controllers.AuthController.pas` (solo `GET /api/auth/me`)
- Modify: `dmvc/DMVC.WebModule.Main.pas`
- Create: `tests/DMVC/DMVC.DocumentosControllerTests.pas`
- Create: `tests/DMVC/DMVC.AuthMeTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr`

**Interfaces:**
- Consumes (sin cambios): `services/XmlParserService.pas` (`TXmlParserService.Parse`, `TParsedInvoice`), `services/ValidationService.pas` (`ValidarDocumentoDesdeXML`), `services/DocumentoService.pas` (`TDocumentoHeader`, `TDocumentoDetalle`, `GuardarDocumento`, `DocumentoExiste`), `services/EquivalenciaService.pas` (`BuscarEquivalencia(AReferenciaH, AUnidadH): TFDQuery` overload de 2 argumentos), `utils/uPaths.pas` (`GetInputPath`, `GetProcessedPath`).
- **Reemplazo de sesión Horse → JWT claims (confirmado leyendo el framework, no adivinado):** `Req.Session<TSessionInfoObj>.Data` (GUID-sesión en memoria de Horse) se reemplaza por `Context.LoggedUser.CustomData['codigo']` / `Context.LoggedUser.CustomData['nombre']`. Verificado en `MVCFramework.Middleware.JWT.pas` (líneas ~403/463/602-607): los pares que `OnAuthentication` escribe en `ASessionData` (ya hoy `'codigo'`/`'nombre'`, ver `DMVC.Security.AuthHandler.pas` de la Fase 3) se guardan como custom claims del JWT en el login, y el middleware los reconstruye automáticamente en `Context.LoggedUser.CustomData` en CADA request subsecuente que traiga ese token — no hace falta ningún cambio en el auth handler existente para que esto funcione.
- Sin DTOs: mismo criterio que Tasks 2-4, respuesta dinámica vía `TJSONObject` a mano.

**Decisión de testing (mismo criterio de riesgo que Tasks 2 y 3, aplicado aquí con MÁS cuidado porque el riesgo es mayor):** `GuardarDocumento` escribe un documento contable REAL en el ERP Helisa y `TFile.Move` mueve un archivo real de `Input` a `Processed` — ambos son efectos de escritura reales e irreversibles fácilmente, más sensibles que cualquier otra ruta migrada hasta ahora en esta fase. Los tests automatizados de esta task se limitan ESTRICTAMENTE a las ramas que ocurren ANTES de tocar `GuardarDocumento`/`TFile.Move`/`DocumentoExiste`-con-datos-reales:
1. `files` vacío o ausente en el body → 200 con `procesados:[]`, `errores:[]` (el `for` nunca ejecuta, cero I/O).
2. Un nombre de archivo que NO existe en el disco → entrada en `errores` con `"Archivo no encontrado"` (primera guarda de la ruta, antes de leer/parsear/persistir nada).
3. Protección JWT (401 sin token) en ambas rutas nuevas (`/documentos/procesar` y `/api/auth/me`).
4. `/api/auth/me` con token válido → 200 con `codigo`/`nombre` presentes y no vacíos (esto SÍ es 100% seguro de probar: es una simple lectura de los claims del JWT ya emitido, sin tocar ninguna base de datos).

NO se automatiza: el camino feliz completo de `Procesar` (XML real parseado + `BuscarEquivalencia` + `GuardarDocumento` + `TFile.Move`) ni el caso "documento ya procesado" (`DocumentoExiste=True`, que requeriría un XML real ya guardado). Verificación manual únicamente, y solo si el usuario lo pide explícitamente con un XML de prueba real — igual criterio que `LicenciaController.Registrar`/`ActivarOnline` en la Task 2.

- [ ] **Step 1: Escribir el controller de auth/me**

Crear `dmvc/Controllers/DMVC.Controllers.AuthController.pas`:

```pascal
unit DMVC.Controllers.AuthController;

interface

uses
  MVCFramework, MVCFramework.Commons;

type
  [MVCPath('/')]
  TAuthController = class(TMVCController)
  public
    [MVCPath('/api/auth/me')]
    [MVCHTTPMethod([httpGET])]
    procedure GetMe;
  end;

implementation

uses
  System.JSON;

procedure TAuthController.GetMe;
var
  LResponse: TJSONObject;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  LResponse := TJSONObject.Create;
  try
    LResponse.AddPair('codigo', Context.LoggedUser.CustomData['codigo']);
    LResponse.AddPair('nombre', Context.LoggedUser.CustomData['nombre']);
    Render(LResponse.ToJSON);
  finally
    LResponse.Free;
  end;
end;

end.
```

- [ ] **Step 2: Escribir el controller de documentos**

Crear `dmvc/Controllers/DMVC.Controllers.DocumentosController.pas`:

```pascal
unit DMVC.Controllers.DocumentosController;

interface

uses
  MVCFramework, MVCFramework.Commons;

type
  [MVCPath('/')]
  TDocumentosController = class(TMVCController)
  public
    [MVCPath('/documentos/procesar')]
    [MVCPath('/api/documentos/procesar')]
    [MVCHTTPMethod([httpPOST])]
    procedure Procesar;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Classes,
  FireDAC.Comp.Client,
  XmlParserService, ValidationService, DocumentoService, EquivalenciaService, uPaths;

function ParsedInvoiceToJSONObject(const AParsedInvoice: TParsedInvoice): TJSONObject;
var
  LProveedor, LTotales, LProducto: TJSONObject;
  LProductosArr: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  try
    LProveedor := TJSONObject.Create;
    LProveedor.AddPair('nit', AParsedInvoice.Provider.NIT);
    LProveedor.AddPair('nombre', AParsedInvoice.Provider.Nombre);
    LProveedor.AddPair('nombreLegal', AParsedInvoice.Provider.NombreLegal);
    LProveedor.AddPair('tipoIdentificacion', AParsedInvoice.Provider.TipoIdentificacion);
    LProveedor.AddPair('direccion', AParsedInvoice.Provider.Direccion);
    Result.AddPair('proveedor', LProveedor);

    LProductosArr := TJSONArray.Create;
    for I := 0 to Length(AParsedInvoice.Products) - 1 do
    begin
      LProducto := TJSONObject.Create;
      LProducto.AddPair('idLinea', AParsedInvoice.Products[I].IDLinea);
      LProducto.AddPair('descripcion', AParsedInvoice.Products[I].Descripcion);
      LProducto.AddPair('referencia', AParsedInvoice.Products[I].Referencia);
      LProducto.AddPair('referenciaEstandar', AParsedInvoice.Products[I].ReferenciaEstandar);
      LProducto.AddPair('cantidad', TJSONNumber.Create(AParsedInvoice.Products[I].Cantidad));
      LProducto.AddPair('unidad', AParsedInvoice.Products[I].Unidad);
      LProducto.AddPair('precioBase', TJSONNumber.Create(AParsedInvoice.Products[I].PrecioBase));
      LProducto.AddPair('valorUnitario', TJSONNumber.Create(AParsedInvoice.Products[I].ValorUnitario));
      LProducto.AddPair('valorTotal', TJSONNumber.Create(AParsedInvoice.Products[I].ValorTotal));
      LProducto.AddPair('impuesto', TJSONNumber.Create(AParsedInvoice.Products[I].Impuesto));
      LProducto.AddPair('porcentajeImpuesto', TJSONNumber.Create(AParsedInvoice.Products[I].ImpuestoPorcentaje));
      LProductosArr.Add(LProducto);
    end;
    Result.AddPair('productos', LProductosArr);

    LTotales := TJSONObject.Create;
    LTotales.AddPair('subtotal', TJSONNumber.Create(AParsedInvoice.Totals.Subtotal));
    LTotales.AddPair('taxExclusiveAmount', TJSONNumber.Create(AParsedInvoice.Totals.TaxExclusiveAmount));
    LTotales.AddPair('taxInclusiveAmount', TJSONNumber.Create(AParsedInvoice.Totals.TaxInclusiveAmount));
    LTotales.AddPair('impuestoTotal', TJSONNumber.Create(AParsedInvoice.Totals.ImpuestoTotal));
    LTotales.AddPair('total', TJSONNumber.Create(AParsedInvoice.Totals.Total));
    Result.AddPair('totales', LTotales);
  except
    Result.Free;
    raise;
  end;
end;

procedure TDocumentosController.Procesar;
var
  LBody: TJSONObject;
  LFilesArr: TJSONArray;
  LFileName, LPath, LProcessedPath, LXMLContent, LParsedJSONStr, LValidationResult: string;
  LParsedInvoice: TParsedInvoice;
  LValidationObj, LProcesadoObj, LErrorObj, LResponse, LParsedObj: TJSONObject;
  LProcesadosArr, LErroresArr: TJSONArray;
  LHeader: TDocumentoHeader;
  LDetalles: TArray<TDocumentoDetalle>;
  I, J: Integer;
  LValido, LRequiereHomologacion: Boolean;
  LEquivalencia: TFDQuery;
  LFactor: Double;
  LFilesValue, LValidoVal: TJSONValue;
  LDocumentoERP, LAnio, LCodigoUsuario, LNombreUsuario: string;
begin
  ContentType := TMVCMediaType.APPLICATION_JSON;
  LProcesadosArr := TJSONArray.Create;
  LErroresArr := TJSONArray.Create;
  try
    LBody := TJSONObject.ParseJSONValue(Context.Request.Body) as TJSONObject;
    try
      if Assigned(LBody) then
      begin
        LFilesValue := LBody.GetValue('files');
        if (LFilesValue <> nil) and (LFilesValue is TJSONArray) then
        begin
          LFilesArr := LFilesValue as TJSONArray;
          for I := 0 to LFilesArr.Count - 1 do
          begin
            LFileName := TPath.GetFileName(LFilesArr.Items[I].Value);
            LPath := GetInputPath;
            LProcessedPath := GetProcessedPath;

            if not TDirectory.Exists(LProcessedPath) then
              TDirectory.CreateDirectory(LProcessedPath);

            if not TFile.Exists(TPath.Combine(LPath, LFileName)) then
            begin
              LErrorObj := TJSONObject.Create;
              LErrorObj.AddPair('fileName', LFileName);
              LErrorObj.AddPair('error', 'Archivo no encontrado');
              LErroresArr.Add(LErrorObj);
              Continue;
            end;

            if DocumentoExiste(LFileName) then
            begin
              LErrorObj := TJSONObject.Create;
              LErrorObj.AddPair('fileName', LFileName);
              LErrorObj.AddPair('error', 'El documento ya fue procesado anteriormente');
              LErroresArr.Add(LErrorObj);
              Continue;
            end;

            try
              LXMLContent := TFile.ReadAllText(TPath.Combine(LPath, LFileName), TEncoding.UTF8);
              LParsedInvoice := TXmlParserService.Parse(LXMLContent);

              LParsedObj := ParsedInvoiceToJSONObject(LParsedInvoice);
              try
                LParsedJSONStr := LParsedObj.ToJSON;
              finally
                LParsedObj.Free;
              end;

              LValidationResult := ValidarDocumentoDesdeXML(LParsedJSONStr);
              LValidationObj := TJSONObject.ParseJSONValue(LValidationResult) as TJSONObject;
              if not Assigned(LValidationObj) then
                 raise Exception.Create('Error parseando resultado de validación');
              try
                LValido := False;
                LValidoVal := LValidationObj.GetValue('valido');
                if (LValidoVal <> nil) and (LValidoVal is TJSONBool) then
                  LValido := (LValidoVal as TJSONBool).AsBoolean;

                LRequiereHomologacion := False;
                LValidoVal := LValidationObj.GetValue('requiereHomologacion');
                if (LValidoVal <> nil) and (LValidoVal is TJSONBool) then
                  LRequiereHomologacion := (LValidoVal as TJSONBool).AsBoolean;

                if LValido and not LRequiereHomologacion then
                begin
                  LAnio := FormatDateTime('yyyy', LParsedInvoice.FechaEmision);

                  LCodigoUsuario := Context.LoggedUser.CustomData['codigo'];
                  LNombreUsuario := Context.LoggedUser.CustomData['nombre'];

                  LHeader.Proveedor := LParsedInvoice.Provider.NIT;
                  LHeader.CodigoTercero := LValidationObj.GetValue('codigoTercero').Value;
                  LHeader.Fecha := LParsedInvoice.FechaEmision;
                  LHeader.Total := LParsedInvoice.Totals.Total;
                  LHeader.Estado := 'PROCESADO';
                  LHeader.XMLFileName := LFileName;
                  LHeader.NombreUsuario := LNombreUsuario;
                  LHeader.CodigoUsuario := LCodigoUsuario;
                  LHeader.Anio := LAnio;

                  SetLength(LDetalles, Length(LParsedInvoice.Products));
                  for J := 0 to Length(LParsedInvoice.Products) - 1 do
                  begin
                    LDetalles[J].CodigoProducto := LParsedInvoice.Products[J].Referencia;
                    LDetalles[J].Cantidad := LParsedInvoice.Products[J].Cantidad;
                    LDetalles[J].Precio := LParsedInvoice.Products[J].ValorUnitario;
                    LDetalles[J].TfIva := LParsedInvoice.Products[J].ImpuestoPorcentaje;
                    LDetalles[J].VrIva := LParsedInvoice.Products[J].Impuesto;
                    LDetalles[J].TfDescuento := LParsedInvoice.Products[J].DescuentoPorcentaje;
                    LDetalles[J].VrDescuento := LParsedInvoice.Products[J].Descuento;
                    LDetalles[J].VrIca := 0;
                    LDetalles[J].VrReteIca := 0;
                    LDetalles[J].VrReteIva := 0;
                    LDetalles[J].VrReteFuente := 0;
                    LDetalles[J].Total := LDetalles[J].Cantidad * LDetalles[J].Precio;

                    LEquivalencia := BuscarEquivalencia(LParsedInvoice.Products[J].Referencia, LParsedInvoice.Products[J].Unidad);
                    try
                      if LEquivalencia.IsEmpty then
                      begin
                        raise Exception.Create(
                          Format('No existe equivalencia para la referencia "%s" con unidad "%s"',
                            [LParsedInvoice.Products[J].Referencia, LParsedInvoice.Products[J].Unidad])
                        );
                      end;

                      LFactor := LEquivalencia.FieldByName('FACTOR').AsFloat;
                      if LFactor = 0 then LFactor := 1;

                      LDetalles[J].Texto := LEquivalencia.FieldByName('NOMBREH').AsString + ' (' + LEquivalencia.FieldByName('REFERENCIAH').AsString + ')';
                      LDetalles[J].CodigoProducto := LEquivalencia.FieldByName('REFERENCIAH').AsString;
                      LDetalles[J].Cantidad := LDetalles[J].Cantidad * LFactor;
                      LDetalles[J].CodigoConcepto := LEquivalencia.FieldByName('CODIGOH').AsInteger;
                      LDetalles[J].Subcodigo := LEquivalencia.FieldByName('SUBCODIGOH').AsInteger;
                    finally
                      LEquivalencia.Free;
                    end;

                    LDetalles[J].Total := LDetalles[J].Cantidad * LDetalles[J].Precio;
                  end;

                  try
                    LDocumentoERP := GuardarDocumento(LHeader, LDetalles);

                    TFile.Move(TPath.Combine(LPath, LFileName), TPath.Combine(LProcessedPath, LFileName));

                    LProcesadoObj := TJSONObject.Create;
                    LProcesadoObj.AddPair('fileName', LFileName);
                    LProcesadoObj.AddPair('status', 'OK');
                    LProcesadoObj.AddPair('documento', LDocumentoERP);
                    LProcesadosArr.Add(LProcesadoObj);
                  except
                    on E: Exception do
                    begin
                      LErrorObj := TJSONObject.Create;
                      LErrorObj.AddPair('fileName', LFileName);
                      LErrorObj.AddPair('error', 'Error al guardar en BD: ' + E.Message);
                      LErroresArr.Add(LErrorObj);
                    end;
                  end;
                end
                else
                begin
                  LErrorObj := TJSONObject.Create;
                  LErrorObj.AddPair('fileName', LFileName);
                  if LRequiereHomologacion then
                    LErrorObj.AddPair('error', 'Requiere homologación de productos')
                  else
                    LErrorObj.AddPair('error', 'Documento inválido para procesar');
                  LErroresArr.Add(LErrorObj);
                end;
              finally
                LValidationObj.Free;
              end;

            except
              on E: Exception do
              begin
                LErrorObj := TJSONObject.Create;
                LErrorObj.AddPair('fileName', LFileName);
                LErrorObj.AddPair('error', E.Message);
                LErroresArr.Add(LErrorObj);
              end;
            end;
          end;
        end;
      end;
    finally
      LBody.Free;
    end;

    LResponse := TJSONObject.Create;
    try
      LResponse.AddPair('procesados', LProcesadosArr);
      LProcesadosArr := nil; // ownership transferido a LResponse (inmediato, evita doble-free si el AddPair de errores fallara)
      LResponse.AddPair('errores', LErroresArr);
      LErroresArr := nil; // ownership transferido a LResponse
      Render(LResponse.ToJSON);
    finally
      LResponse.Free;
    end;
  except
    on E: Exception do
    begin
      LProcesadosArr.Free; // no-op si ya es nil (ownership ya transferido)
      LErroresArr.Free;
      raise EMVCException.Create(HTTP_STATUS.InternalServerError, 'Error interno: ' + E.Message);
    end;
  end;
end;

end.
```

Notas de fidelidad y cambios deliberados:
- `LSession := Req.Session<TSessionInfoObj>.Data; ... LSession.Nombre; ... LSession.Codigo.ToString;` → `Context.LoggedUser.CustomData['nombre']` / `Context.LoggedUser.CustomData['codigo']` (ver justificación arriba). `CustomData['codigo']` ya es `string` (así se guardó en `ASessionData.AddOrSetValue('codigo', LQuery.FieldByName('CODIGO').AsString)` en la Fase 3) — NO hace falta `.ToString`, a diferencia del original que convertía un `Integer`.
- El leak preexistente de Horse (si la request completa falla ANTES de construir `LResponse`, `LProcesadosArr`/`LErroresArr` quedaban sin liberar) se corrige de forma mecánica con el patrón `:= nil` tras la transferencia de ownership + `.Free` (no-op sobre `nil`) en el `except` — mismo espíritu que el fix `try/except Result.Free; raise;` ya aplicado en Tasks 1 y 3, no es una reescritura de la lógica de negocio.
- El resto de la lógica de negocio (parseo, validación, cálculo de equivalencias, construcción de `TDocumentoHeader`/`TDocumentoDetalle`) es copia EXACTA del Horse original, literal por literal.

- [ ] **Step 3: Registrar ambos controllers en el WebModule**

Modificar `dmvc/DMVC.WebModule.Main.pas`: agregar `DMVC.Controllers.DocumentosController` y `DMVC.Controllers.AuthController` al `uses`, y `FEngine.AddController(TDocumentosController);` + `FEngine.AddController(TAuthController);` después de `TImportController`.

- [ ] **Step 4: Escribir los tests (RED → GREEN)**

Crear `tests/DMVC/DMVC.AuthMeTests.pas` (2 tests: `GetMe_WithValidToken_ReturnsCodigoYNombre`, `GetMe_WithoutToken_Returns401`) y `tests/DMVC/DMVC.DocumentosControllerTests.pas` (3 tests: `Procesar_WithEmptyFiles_ReturnsEmptyArrays`, `Procesar_WithNonexistentFile_ReturnsArchivoNoEncontrado`, `Procesar_WithoutToken_Returns401`), mismo patrón `TTestServerProcess` + `ObtenerTokenDePrueba` + `TIdHTTP`/`TStringStream` de las tasks anteriores. Para `GetMe_WithValidToken_...`, NO asumir el valor exacto de `codigo`/`nombre` (son datos reales de Helisa) — solo verificar que ambos campos existen y no están vacíos.

Modificar `tests/PurchaseBridge.Tests.dpr`: agregar ambas unidades nuevas al `uses`.

Compilar servidor + tests. Correr la suite completa — deben pasar los 29 anteriores (tras la Task 4) + 5 nuevos = 34.

- [ ] **Step 5: Commit**

```bash
git add dmvc/Controllers/DMVC.Controllers.DocumentosController.pas dmvc/Controllers/DMVC.Controllers.AuthController.pas dmvc/DMVC.WebModule.Main.pas tests/DMVC/DMVC.DocumentosControllerTests.pas tests/DMVC/DMVC.AuthMeTests.pas tests/PurchaseBridge.Tests.dpr
git commit -m "feat: migrate DocumentosController to DMVCFramework, add /api/auth/me"
```

Sin gate de aprobación — seguir directo a escribir el detalle de la Task 6.

**Archivos:** `dmvc/Controllers/DMVC.Controllers.DocumentosController.pas`, `dmvc/Controllers/DMVC.Controllers.AuthController.pas`, tests correspondientes.

### Task 6: XmlController (9 rutas — la más grande, 1176 líneas en Horse)

**Decisión (tomada tras leer el archivo completo, 2026-09-28): se divide en dos sub-tareas**, 6a y 6b, por tamaño/riesgo — el detalle TDD completo de cada una se escribe justo antes de despacharla (mismo criterio just-in-time del resto de esta fase), no ambas de una vez. Comparten el mismo `dmvc/Controllers/DMVC.Controllers.XmlController.pas` (un solo controller con las 9 acciones, igual que el Horse original agrupa todo en una unidad) — 6a agrega las acciones de solo lectura primero, 6b agrega las de escritura al mismo archivo después.

**Hallazgo importante de la lectura completa:** a diferencia de `LicenciaController`/`DocumentosController` (que tocan sistemas EXTERNOS reales — servidor de licencias, ERP Helisa), las 3 rutas de escritura de `XmlController` (`Upload`, `ProcesarBatch`, `Homologar`) escriben en la base **BRIDGE local** (`purchasebridge.fdb`), que es la base de pruebas descartable de este proyecto (mismo criterio ya usado en la Fase 2 para crear/borrar registros de Equivalencia) — el único toque a Helisa real en todo el controller es una lectura de sigla de unidad en `Homologar` (`HelisaService.ObtenerSiglaUnidad`, solo lectura). Esto significa que 6b SÍ puede automatizar su camino feliz completo con limpieza posterior (patrón `finally` + DELETE crudo, como en la Fase 2), a diferencia de Tasks 2 y 5 de esta fase.

#### Task 6a: XmlController — rutas de solo lectura (6 handlers, 7 registros de ruta)

**Objetivo:** `GET /xml/list` + `/xml/files` (mismo handler `GetFiles`, alias — Horse marca `/xml/list` como deprecado en un comentario, preservar igual), `GET /xml/files/:id` (`GetFileById`, path param), `POST /xml/parse` (`Parse` — lee un archivo YA existente en Input/Processed y lo parsea, sin escribir nada), `GET /xml/productos/pendientes` (`GetProductosPendientes`), `GET /xml/productos/documento` (`GetProductosDocumento`), `GET /dashboard/metrics` (`GetDashboardMetrics`). Todas consultan `GetBridgeQuery` (BRIDGE local) y opcionalmente `TDianUnits.GetUnitName`/`ResolveUnidadSigla` (tablas/diccionario locales, sin red). Ninguna escribe nada — se puede automatizar el camino feliz completo sembrando filas de prueba en BRIDGE dentro del propio test (mismo patrón ya usado en la Fase 2).

**Archivos:** Create `dmvc/Controllers/DMVC.Controllers.XmlController.pas` (arranca con estas 6 acciones), modify `dmvc/DMVC.WebModule.Main.pas`, create `tests/DMVC/DMVC.XmlControllerReadTests.pas`, modify `tests/PurchaseBridge.Tests.dpr`.

#### Task 6b: XmlController — rutas de escritura (3 handlers, 6 registros de ruta)

**Objetivo:** `POST /xml/upload` (`Upload` — recibe un archivo `multipart/form-data` con campo `file`, lo guarda en `GetInputPath` y hace upsert en `XML_FILES` de BRIDGE), `POST /xml/procesar` (`ProcesarBatch` — recibe `{ids:[...]}`, transacción por ID sobre BRIDGE), `POST /xml/homologar` (`Homologar` — recibe mapeo XML→ERP, crea/reutiliza una `Equivalencia` en BRIDGE vía `EquivalenciaService.GetIDEquivalencia`/`CrearEquivalencia`, actualiza `XML_PRODUCTOS`/`XML_FILES`, con UNA lectura real a Helisa vía `HelisaService.ObtenerSiglaUnidad` para convertir código de unidad a sigla). Se agregan al MISMO `dmvc/Controllers/DMVC.Controllers.XmlController.pas` de la Task 6a.

**Punto a verificar empíricamente antes de escribir el detalle completo (no asumir):** cómo `Upload` recibe el archivo multipart en DMVCFramework — el Horse original usa `Req.RawWebRequest.Files` (WebBroker `TAbstractWebRequestFile`, vía el módulo `horse-octet-stream`/WebBroker subyacente). Dado que este proyecto hostea DMVC sobre el mismo `TIdHTTPWebBrokerBridge`+`TWebModule` (confirmado en `PurchaseBridgeDMVC.dpr`, Fases 1-3), es razonable esperar que `Context.Request.RawWebRequest.Files` esté igualmente disponible en un controller DMVC (mismo `TWebRequest` subyacente) — pero esto debe confirmarse leyendo `MVCFramework.pas` (`TMVCWebRequest`/`RawWebRequest`) y/o probándolo antes de dar el código por bueno, no asumirlo por analogía.

**Archivos:** Modify `dmvc/Controllers/DMVC.Controllers.XmlController.pas` (agregar las 3 acciones), modify `dmvc/DMVC.WebModule.Main.pas` (ya registrado desde 6a, no requiere segundo `AddController`), create `tests/DMVC/DMVC.XmlControllerWriteTests.pas`, modify `tests/PurchaseBridge.Tests.dpr`.

**Archivos (ambas sub-tareas):** `dmvc/Controllers/DMVC.Controllers.XmlController.pas`, tests correspondientes.

---

## Self-Review (de la Task 1, la única con detalle completo por ahora)

**Cobertura:** Task 1 cubre las 2 rutas de `HelisaController` completas. Las Tasks 2-6 cubren las 12 rutas restantes del objetivo de la Fase 4 del roadmap (a nivel de objetivo, detalle TDD pendiente de escribirse task por task).

**Placeholders:** ninguno en la Task 1 (código completo). Las Tasks 2-6 son deliberadamente roadmap-level por la restricción de proceso explícita del usuario — no son placeholders de un plan que debería tener detalle ahora, son la siguiente fase del mismo patrón incremental ya usado a nivel de fases completas (Fases 1-5), aplicado esta vez a nivel de tasks dentro de una fase.

## Próximo paso

Ejecutar Task 1 (subagent-driven-development: implementer → review → fix si aplica → commit). Al terminar Task 1, PARAR y pedir aprobación explícita antes de escribir el detalle completo de la Task 2.
