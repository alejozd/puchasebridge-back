# Fase 3 — Middlewares transversales (CORS, logger, licencia, estáticos/SPA, auth JWT) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Portar los 5 middlewares de Horse (CORS dinámico, logger HTTP, guard de licencia, archivos estáticos/SPA, auth) a `IMVCMiddleware` de DMVCFramework, agregándolos al servidor paralelo `PurchaseBridgeDMVC.exe` (puerto 9091), protegiendo los controllers ya migrados (`TEquivalenciaController`, `TProveedorController`) con auth real.

**Architecture:** Cada middleware Horse se traduce a una clase `TInterfacedObject, IMVCMiddleware` propia (patrón NexoPago), registrada en `dmvc/DMVC.WebModule.Main.pas` vía `FEngine.AddMiddleware(...)`. **Decisión de arquitectura (confirmada por el usuario, 2026-09-26): el login migra a JWT real** (`TMVCJWTAuthenticationMiddleware` + `IMVCAuthenticationHandler` propio), no se preserva el modelo de Horse (GUID plano en un `TDictionary` en memoria). El contrato de transporte no cambia para el frontend (`Authorization: Bearer <token>`), pero los tokens emitidos por Horse no van a servir contra el servidor DMVC — esto se documenta para la Fase 5, igual que los cambios de status HTTP de la Fase 2.

**Descubrimiento clave que resuelve el riesgo de auth anotado en el roadmap**: NexoPago decide qué rutas requieren sesión por **nombre completo de clase del controller** (`IMVCAuthenticationHandler.OnRequest` recibe `AControllerQualifiedClassName`), NO por prefijo de URL. Esto evita por completo el problema de que los controllers ya usan `[MVCPath('/')]` a nivel de clase — no hace falta enrutar por prefijo para proteger.

**Tech Stack:** Delphi (RAD Studio 23.0), DMVCFramework 3.4.3 Aluminium (`MVCFramework.Middleware.JWT`, `MVCFramework.JWT` — unidades vendorizadas, mismo `-U` de siempre), DUnitX. NO se usa `TMVCActiveRecordMiddleware` (PurchaseBridge no usa ActiveRecord — ver Fase 2 Architecture) — `OnAuthentication` consulta Helisa con FireDAC crudo, reusando `FirebirdConnection.GetHelisaQuery` (existente, sin cambios).

## Global Constraints

- No modificar ningún archivo Horse existente (`middleware/*.pas`, `services/AuthService.pas`, `services/LicenseService.pas`, `ServerBootstrap.pas`, etc.) — Horse sigue sirviendo en el puerto 9000 sin cambios hasta la Fase 5. `AuthService.pas`/`LicenseService.pas` se **leen** para entender el comportamiento a preservar, pero el nuevo auth handler DMVC es código nuevo que no las llama (usa su propia consulta FireDAC a Helisa; `LicenseService.TLicenciaService.SistemaBloqueado` SÍ se reutiliza tal cual, ver Task 2).
- **Auth = JWT real** (decisión del usuario): `TMVCJWTAuthenticationMiddleware` + `TPurchaseBridgeAuthHandler` (implementa `IMVCAuthenticationHandler`), deny-by-default vía `OnRequest` excepto `TPingController`. `OnAuthorization` siempre `True` para todo usuario autenticado (Horse no tiene permisos granulares, solo "autenticado o no" — no se inventa un sistema de roles/permisos que Horse no tenía).
- **CORS**: se preserva el comportamiento EXACTO de Horse (reflejo dinámico de `Origin`, no whitelist fija como NexoPago) — es un middleware de infraestructura, no una decisión de shape de respuesta ya cubierta por la decisión de la Fase 2; cambiarlo podría romper el frontend actual al momento del cutover sin que el usuario lo haya pedido.
- **Licencia**: se preserva el status 403 y las rutas excluidas (`/licencia*`, `/ping`) — no se cambia a 503 como NexoPago (eso sería inventar una decisión no pedida).
- **Estáticos/SPA**: se usa el patrón wrapper de NexoPago (`TMVCStaticFilesMiddleware` interno con `AStaticFilesPath='/'`, filtrando por prefijo ANTES de delegar) en vez de replicar el mecanismo de `EHorseCallbackInterrupted` de Horse — ese patrón no tiene equivalente directo en DMVC y el wrapper de NexoPago resuelve el mismo problema (servir en la raíz sin tragarse `/api`) de forma más simple y ya probada.
- Este repo NO tiene actualmente una carpeta `www/` real (verificado) — los tests de la Task 3 crean su propio fixture mínimo (`index.html` de prueba) en tiempo de test, no dependen del build real del frontend.
- Config nueva: agregar sección `[AUTH]` con clave `JWTSecret` a `bin\config.ini` (mismo archivo gitignored ya usado para `[BRIDGE]`/`[HELISA]` en las Fases 1-2). Se lee con `TIniFile` directo (mismo patrón que `HConfig.pas`), no se introduce `dotEnv` (eso es infraestructura de NexoPago, PurchaseBridge usa `config.ini`).
- Probar login exitoso end-to-end contra Helisa requeriría un usuario/clave real de la tabla `USUARIOS` — no disponible en este plan. Los tests automatizados cubren: (a) ruta protegida sin token → 401, (b) `/ping` sin token → 200 (sigue público), (c) login con usuario inexistente → 401 (sin necesitar datos reales, ver Task 4). El flujo completo login-exitoso→token-válido→acceso-a-ruta-protegida queda como **verificación manual** con credenciales reales del usuario (igual que Proveedor en la Fase 2 dejó `existe:true` como verificación manual).
- Orden final de registro en el WebModule (de afuera hacia adentro, ver Task 4 Step 4): `TPurchaseBridgeTraceMiddleware` → `TPurchaseBridgeCORSMiddleware` → `TPurchaseBridgeLicenseMiddleware` → `TPurchaseBridgeStaticAppMiddleware` → `TMVCJWTAuthenticationMiddleware`. Los controllers (`TPingController`, `TEquivalenciaController`, `TProveedorController`) se registran igual que antes.
- Compilador y rutas `-U`/`-I`: idénticas a las Fases 1-2 (ver roadmap). El servidor y los tests ya tenían `repositories`/`config`/`utils`/`database`/`services` en el `-U` — esta fase agrega `dmvc/Middleware` y `dmvc/Security`.
- Regla de nombres de unidad Delphi (conocida): nombre de unidad EXACTO al nombre de archivo, incluidos los puntos.
- Seguridad de credenciales: cualquier password/secreto usado en esta fase (JWT secret de prueba, credenciales de Helisa si se hace la verificación manual) va SOLO en `bin\config.ini` (gitignored) — nunca en código, nunca en commits, nunca repetido en reportes.

---

### Task 1: CORS dinámico + logger HTTP

**Files:**
- Create: `dmvc/Middleware/DMVC.Middleware.CORS.pas`
- Create: `dmvc/Middleware/DMVC.Middleware.HttpLogger.pas`
- Modify: `dmvc/DMVC.WebModule.Main.pas` (registrar ambos middlewares)
- Create: `tests/DMVC/DMVC.CORSMiddlewareTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr` (agregar la unidad de test)

**Interfaces:**
- Consumes: `uLogger.Log` (unidad existente `utils/uLogger.pas`, sin cambios) — revisa su firma exacta antes de llamarla (`Log(const AMessage: string; ALevel: TLogLevel; const ACategory: string; ...)` según lo visto en Horse; si la firma no calza exactamente, usa `uLogger.LogInfo`/`LogError` que ya se usan en otras partes del repo con una firma más simple, y documenta cuál usaste).
- Produces: nada que otras tasks consuman directamente — Task 4 (auth) reutiliza el mismo patrón de clase `TInterfacedObject, IMVCMiddleware` establecido aquí, pero no depende de código de esta task.

- [ ] **Step 1: Escribir el middleware CORS**

Crear `dmvc/Middleware/DMVC.Middleware.CORS.pas`:

```pascal
unit DMVC.Middleware.CORS;

interface

uses
  MVCFramework;

type
  // Refleja el Origin recibido tal cual (sin whitelist) y responde 200 vacio
  // a los preflight OPTIONS. Preserva EXACTAMENTE el comportamiento de
  // CORSMiddleware.pas (Horse) -- no se cambia a un origen fijo como hace
  // NexoPago, porque eso podria romper el frontend actual sin que se haya
  // pedido ese cambio.
  TPurchaseBridgeCORSMiddleware = class(TInterfacedObject, IMVCMiddleware)
  protected
    procedure OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
    procedure OnBeforeControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      var AHandled: Boolean);
    procedure OnAfterControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      const AHandled: Boolean);
    procedure OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
  end;

implementation

uses
  System.SysUtils, MVCFramework.Commons;

{ TPurchaseBridgeCORSMiddleware }

procedure TPurchaseBridgeCORSMiddleware.OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
var
  LOrigin: string;
begin
  LOrigin := Trim(AContext.Request.Headers['Origin']);

  if not LOrigin.IsEmpty then
    AContext.Response.SetCustomHeader('Access-Control-Allow-Origin', LOrigin);

  AContext.Response.SetCustomHeader('Vary', 'Origin');
  AContext.Response.SetCustomHeader('Access-Control-Allow-Credentials', 'true');
  AContext.Response.SetCustomHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, Accept');
  AContext.Response.SetCustomHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');

  if AContext.Request.HTTPMethod = httpOPTIONS then
  begin
    AContext.Response.RawWebResponse.StatusCode := HTTP_STATUS.OK;
    AContext.Response.RawWebResponse.Content := '';
    AHandled := True;
  end;
end;

procedure TPurchaseBridgeCORSMiddleware.OnBeforeControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; var AHandled: Boolean);
begin
  // No-op.
end;

procedure TPurchaseBridgeCORSMiddleware.OnAfterControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; const AHandled: Boolean);
begin
  // No-op.
end;

procedure TPurchaseBridgeCORSMiddleware.OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
begin
  // No-op.
end;

end.
```

- [ ] **Step 2: Escribir el middleware de logger HTTP**

Crear `dmvc/Middleware/DMVC.Middleware.HttpLogger.pas`:

```pascal
unit DMVC.Middleware.HttpLogger;

interface

uses
  MVCFramework;

type
  // Mide la duracion desde OnBeforeRouting hasta OnAfterControllerAction y
  // loguea con el mismo filtro que uHttpLoggerMiddleware.pas (Horse): siempre
  // loguea errores (status >= 400), excluye assets/estaticos, siempre loguea
  // api/auth/licencia/ping.
  TPurchaseBridgeTraceMiddleware = class(TInterfacedObject, IMVCMiddleware)
  private const
    START_TICK_KEY = 'purchasebridge.trace.starttick';
    function ShouldLogRequest(const APath: string; AStatus: Integer): Boolean;
  protected
    procedure OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
    procedure OnBeforeControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      var AHandled: Boolean);
    procedure OnAfterControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      const AHandled: Boolean);
    procedure OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
  end;

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, uLogger;

{ TPurchaseBridgeTraceMiddleware }

function TPurchaseBridgeTraceMiddleware.ShouldLogRequest(const APath: string; AStatus: Integer): Boolean;
begin
  if AStatus >= 400 then
    Exit(True);

  if StartsText('/assets/', APath) or
     StartsText('/.well-known/', APath) or
     SameText(APath, '/favicon.ico') or
     SameText(APath, '/login') or
     StartsText('/app/', APath) then
    Exit(False);

  if StartsText('/api/', APath) or
     StartsText('/auth/', APath) or
     StartsText('/xml/', APath) or
     StartsText('/licencia/', APath) or
     SameText(APath, '/ping') then
    Exit(True);

  Result := True;
end;

procedure TPurchaseBridgeTraceMiddleware.OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
begin
  AContext.Data[START_TICK_KEY] := IntToStr(Int64(TThread.GetTickCount64));
end;

procedure TPurchaseBridgeTraceMiddleware.OnBeforeControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; var AHandled: Boolean);
begin
  // No-op.
end;

procedure TPurchaseBridgeTraceMiddleware.OnAfterControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; const AHandled: Boolean);
var
  LStartTickStr: string;
  LStartTick: Int64;
  LDuration: Int64;
  LPath: string;
  LStatus: Integer;
begin
  LPath := AContext.Request.RawWebRequest.PathInfo;
  LStatus := AContext.Response.StatusCode;

  if AContext.Data.TryGetValue(START_TICK_KEY, LStartTickStr) and TryStrToInt64(LStartTickStr, LStartTick) then
    LDuration := Int64(TThread.GetTickCount64) - LStartTick
  else
    LDuration := -1;

  if ShouldLogRequest(LPath, LStatus) then
    uLogger.LogInfo(Format('%s %s -> %d (%dms)',
      [AContext.Request.HTTPMethodAsString, LPath, LStatus, LDuration]), 'http');
end;

procedure TPurchaseBridgeTraceMiddleware.OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
begin
  // No-op.
end;

end.
```

**Verificar antes de compilar**: revisa `utils/uLogger.pas` para confirmar que `LogInfo(const AMessage: string; const ACategory: string)` es la firma real (2 argumentos) — si tiene una firma distinta (por ejemplo con un tercer parámetro de severidad), ajusta la llamada de arriba para que compile, sin cambiar `uLogger.pas`.

- [ ] **Step 3: Registrar ambos middlewares en el WebModule**

Modificar `dmvc/DMVC.WebModule.Main.pas`. Estado actual (Fase 2):

```pascal
uses
  DMVC.Controllers.PingController,
  DMVC.Controllers.EquivalenciaController,
  DMVC.Controllers.ProveedorController;

constructor TPurchaseBridgeDMVCWebModule.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEngine := TMVCEngine.Create(Self);
  FEngine.AddController(TPingController);
  FEngine.AddController(TEquivalenciaController);
  FEngine.AddController(TProveedorController);
end;
```

Cambiar a (los middlewares se agregan ANTES de los controllers — en DMVC el orden de `AddController` no importa para el ruteo, pero mantenlos juntos por claridad; el orden de `AddMiddleware` SÍ importa, ver Global Constraints):

```pascal
uses
  DMVC.Controllers.PingController,
  DMVC.Controllers.EquivalenciaController,
  DMVC.Controllers.ProveedorController,
  DMVC.Middleware.HttpLogger,
  DMVC.Middleware.CORS;

constructor TPurchaseBridgeDMVCWebModule.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEngine := TMVCEngine.Create(Self);
  FEngine.AddMiddleware(TPurchaseBridgeTraceMiddleware.Create);
  FEngine.AddMiddleware(TPurchaseBridgeCORSMiddleware.Create);
  FEngine.AddController(TPingController);
  FEngine.AddController(TEquivalenciaController);
  FEngine.AddController(TProveedorController);
end;
```

- [ ] **Step 4: Escribir el test que falla (RED)**

Crear `tests/DMVC/DMVC.CORSMiddlewareTests.pas`:

```pascal
unit DMVC.CORSMiddlewareTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TCORSMiddlewareTests = class
  private
    FServer: TTestServerProcess;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Get_ReflectsOriginHeader;

    [Test]
    procedure Options_ReturnsOkWithEmptyBody;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, IdHTTP;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TCORSMiddlewareTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
end;

procedure TCORSMiddlewareTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TCORSMiddlewareTests.Get_ReflectsOriginHeader;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Request.CustomHeaders.AddValue('Origin', 'http://example-test.local');
    LHttp.Get(Format('http://localhost:%d/ping', [TEST_PORT]));
    Assert.AreEqual('http://example-test.local', LHttp.Response.CustomHeaders.Values['Access-Control-Allow-Origin']);
    Assert.AreEqual('true', LHttp.Response.CustomHeaders.Values['Access-Control-Allow-Credentials']);
  finally
    LHttp.Free;
  end;
end;

procedure TCORSMiddlewareTests.Options_ReturnsOkWithEmptyBody;
var
  LHttp: TIdHTTP;
  LResponse: string;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LResponse := LHttp.Options(Format('http://localhost:%d/api/equivalencias', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    Assert.AreEqual('', LResponse);
  finally
    LHttp.Free;
  end;
end;

end.
```

Modificar `tests/PurchaseBridge.Tests.dpr`, agregando al `uses` (después de la última unidad de test de la Fase 2, `DMVC.ProveedorControllerTests in 'DMVC\DMVC.ProveedorControllerTests.pas'`):

```pascal
  DMVC.CORSMiddlewareTests in 'DMVC\DMVC.CORSMiddlewareTests.pas';
```
(mover el `;` final a esta línea).

Recompilar el runner de tests (cwd = carpeta `tests/`, ver nota de Global Constraints de la Fase 2 sobre resolución de rutas relativas de DCC32) y correrlo — ambos tests nuevos deben fallar: `Get_ReflectsOriginHeader` porque hoy `/ping` no devuelve ese header (o lo puede devolver como `Response.CustomHeaders` vacío), y `Options_ReturnsOkWithEmptyBody` porque hoy OPTIONS no está manejado especialmente. RED esperado.

- [ ] **Step 5: Compilar servidor y tests, confirmar GREEN**

Mismos comandos de compilación de las Fases 1-2 (cwd correcto en cada caso — ver nota de rutas relativas), agregando `dmvc/Middleware` al `-U` del servidor y del proyecto de tests.

Correr `PurchaseBridge.Tests.exe` — deben pasar TODOS los tests anteriores (8: sanity, ping, 3 de Equivalencia, 1 de Proveedor) más los 2 nuevos de CORS.

- [ ] **Step 6: Verificación manual**

Con el server corriendo: `curl -i -H "Origin: http://localhost:5173" http://localhost:9091/api/equivalencias` → confirma `Access-Control-Allow-Origin: http://localhost:5173` en la respuesta. `curl -i -X OPTIONS http://localhost:9091/api/equivalencia` → `200` con body vacío.

- [ ] **Step 7: Commit**

```bash
git add dmvc/Middleware/DMVC.Middleware.CORS.pas dmvc/Middleware/DMVC.Middleware.HttpLogger.pas dmvc/DMVC.WebModule.Main.pas tests/DMVC/DMVC.CORSMiddlewareTests.pas tests/PurchaseBridge.Tests.dpr
git commit -m "feat: migrate CORS and HTTP logger middlewares to DMVCFramework"
```

---

### Task 2: Guard de licencia

**Files:**
- Create: `dmvc/Middleware/DMVC.Middleware.License.pas`
- Modify: `dmvc/DMVC.WebModule.Main.pas` (registrar el middleware)
- Create: `tests/DMVC/DMVC.LicenseMiddlewareTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr`

**Interfaces:**
- Consumes: `LicenseService.TLicenciaService.SistemaBloqueado` (class property de solo lectura, unidad existente `services/LicenseService.pas`, sin cambios — recuerda que NO es una función, se lee sin paréntesis).
- Produces: nada que otras tasks consuman.

**Nota de comportamiento a preservar tal cual**: excluye rutas que CONTENGAN `/licencia` (no solo empiecen, `Contains`) y rutas que EMPIECEN con `/ping`. Responde 403 (NO 503 como NexoPago) con el shape `{"ok": false, "mensaje": "Sistema bloqueado por licencia expirada"}` — mismo shape que Horse, para no inventar una tercera convención de error además de la ya decidida en la Fase 2 (`EMVCException` para los controllers) — este es un middleware, no pasa por `EMVCException`.

- [ ] **Step 1: Escribir el middleware**

Crear `dmvc/Middleware/DMVC.Middleware.License.pas`:

```pascal
unit DMVC.Middleware.License;

interface

uses
  MVCFramework;

type
  TPurchaseBridgeLicenseMiddleware = class(TInterfacedObject, IMVCMiddleware)
  protected
    procedure OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
    procedure OnBeforeControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      var AHandled: Boolean);
    procedure OnAfterControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      const AHandled: Boolean);
    procedure OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
  end;

implementation

uses
  System.SysUtils, System.JSON, MVCFramework.Commons, LicenseService;

{ TPurchaseBridgeLicenseMiddleware }

procedure TPurchaseBridgeLicenseMiddleware.OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
var
  LPath: string;
  LJson: TJSONObject;
begin
  LPath := AContext.Request.RawWebRequest.PathInfo;

  if LPath.Contains('/licencia') or LPath.StartsWith('/ping') then
    Exit;

  if not TLicenciaService.SistemaBloqueado then
    Exit;

  LJson := TJSONObject.Create;
  try
    LJson.AddPair('ok', TJSONBool.Create(False));
    LJson.AddPair('mensaje', 'Sistema bloqueado por licencia expirada');
    AContext.Response.RawWebResponse.StatusCode := 403;
    AContext.Response.RawWebResponse.ContentType := TMVCMediaType.APPLICATION_JSON + '; charset=utf-8';
    AContext.Response.RawWebResponse.Content := LJson.ToJSON;
    // CRITICO (descubierto empiricamente en la Task 1 de esta fase, ver
    // DMVC.Middleware.CORS.pas): bajo el hosting TIdHTTPWebBrokerBridge de
    // este proyecto, TMVCEngine.InternalExecuteAction.Result NUNCA se vuelve
    // True solo porque un middleware puso AHandled:=True en OnBeforeRouting
    // -- eso deja que TWebRequestHandler.HandleRequest omita el envio de la
    // respuesta por completo (status/headers/body quedan descartados en
    // silencio), sin importar si el body esta vacio o no. Hay que llamar
    // SendResponse explicitamente ANTES de marcar AHandled, igual que hace
    // TMVCEngine.OnBeforeDispatch en su propio manejo de excepciones.
    AContext.Response.RawWebResponse.SendResponse;
  finally
    LJson.Free;
  end;
  AHandled := True;
end;

procedure TPurchaseBridgeLicenseMiddleware.OnBeforeControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; var AHandled: Boolean);
begin
  // No-op.
end;

procedure TPurchaseBridgeLicenseMiddleware.OnAfterControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; const AHandled: Boolean);
begin
  // No-op.
end;

procedure TPurchaseBridgeLicenseMiddleware.OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
begin
  // No-op.
end;

end.
```

- [ ] **Step 2: Registrar en el WebModule**

Agregar a `dmvc/DMVC.WebModule.Main.pas` (después de CORS, antes de los controllers):

```pascal
uses
  ...,
  DMVC.Middleware.License;

constructor TPurchaseBridgeDMVCWebModule.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEngine := TMVCEngine.Create(Self);
  FEngine.AddMiddleware(TPurchaseBridgeTraceMiddleware.Create);
  FEngine.AddMiddleware(TPurchaseBridgeCORSMiddleware.Create);
  FEngine.AddMiddleware(TPurchaseBridgeLicenseMiddleware.Create);
  FEngine.AddController(TPingController);
  FEngine.AddController(TEquivalenciaController);
  FEngine.AddController(TProveedorController);
end;
```

- [ ] **Step 3: Test (RED primero)**

Dado que `TLicenciaService.SistemaBloqueado` depende de un archivo `licencia.json` local (ver `LicenseService.pas`, `GetLicenseFilePath`) cuyo estado no controlamos fácilmente en un test automatizado sin invocar toda la lógica de activación/validación (fuera de alcance de esta fase), el test automatizado de esta task NO simula el bloqueo — verifica el camino **no bloqueado** (el caso normal) y que `/ping`/`/licencia*` nunca se bloquean por diseño, incluso leyendo el código:

Crear `tests/DMVC/DMVC.LicenseMiddlewareTests.pas`:

```pascal
unit DMVC.LicenseMiddlewareTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TLicenseMiddlewareTests = class
  private
    FServer: TTestServerProcess;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Ping_NeverBlockedByLicense;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, IdHTTP;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TLicenseMiddlewareTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
end;

procedure TLicenseMiddlewareTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TLicenseMiddlewareTests.Ping_NeverBlockedByLicense;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Get(Format('http://localhost:%d/ping', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode, '/ping nunca debe ser bloqueado por el guard de licencia');
  finally
    LHttp.Free;
  end;
end;

end.
```

Modificar `tests/PurchaseBridge.Tests.dpr`: agregar `DMVC.LicenseMiddlewareTests in 'DMVC\DMVC.LicenseMiddlewareTests.pas';` al final del `uses` (mover el `;`).

Recompilar y correr — antes de registrar el middleware (Step 2 aún no aplicado si sigues TDD estricto) este test en realidad YA PASA porque `/ping` siempre respondió 200 (no hay RED real aquí, es un test de regresión). **Esto es aceptable para esta task**: documenta explícitamente en tu reporte que este test no tuvo un RED significativo (a diferencia de las tasks anteriores) porque no hay forma segura de simular `SistemaBloqueado=True` sin manipular el archivo de licencia real — prioriza que el middleware se registre correctamente y no rompa nada, verificado por este test de regresión más la verificación manual del Step 5.

- [ ] **Step 4: Compilar, confirmar GREEN, y verificación manual del bloqueo**

Compilar servidor+tests con `dmvc/Middleware` ya en el `-U`. Correr la suite completa — deben pasar todos.

Verificación manual del bloqueo (no automatizable de forma segura): si tienes forma de forzar `SistemaBloqueado=True` en un entorno de prueba (por ejemplo, apuntando `GetLicenseFilePath` a un `licencia.json` de prueba corrupto/vencido), verifica manualmente que `curl http://localhost:9091/api/equivalencias` responde 403 con el JSON `{"ok":false,"mensaje":"..."}`, y que `curl http://localhost:9091/ping` sigue respondiendo 200. Si no tienes forma segura de hacer esta prueba sin afectar tu licencia real, sáltala y documenta por qué.

- [ ] **Step 5: Commit**

```bash
git add dmvc/Middleware/DMVC.Middleware.License.pas dmvc/DMVC.WebModule.Main.pas tests/DMVC/DMVC.LicenseMiddlewareTests.pas tests/PurchaseBridge.Tests.dpr
git commit -m "feat: migrate license guard middleware to DMVCFramework"
```

---

### Task 3: Archivos estáticos / fallback SPA

**Files:**
- Create: `dmvc/Middleware/DMVC.Middleware.StaticApp.pas`
- Modify: `dmvc/DMVC.WebModule.Main.pas` (registrar el middleware)
- Create: `tests/DMVC/DMVC.StaticAppMiddlewareTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr`

**Interfaces:**
- Consumes: `MVCFramework.Middleware.StaticFiles.TMVCStaticFilesMiddleware` (vendorizada, `-U` ya cubierto por el path de `sources` de DMVCFramework).
- Produces: nada que otras tasks consuman.

**Patrón (de NexoPago, adaptado)**: envolver `TMVCStaticFilesMiddleware('/', <carpeta>, 'index.html', True)` con un wrapper que en `OnBeforeRouting` excluye por prefijo (`/api`, `/auth`, `/licencia`, o exacto `/ping` — el set completo de `IsExcludedPath` de Horse) ANTES de delegar al middleware interno. Si no excluyes, `AStaticFilesPath='/'` matchea CUALQUIER ruta (toda ruta HTTP empieza con `/`) y el fallback SPA se comería `/api/equivalencias` devolviendo `index.html` con 200 en vez de dejarlo llegar a los controllers.

**ADVERTENCIA de la Task 1 de esta fase (verificar, no asumir)**: se descubrió empíricamente que bajo el hosting `TIdHTTPWebBrokerBridge` de este proyecto, un middleware que corta la cadena con `AHandled:=True` en `OnBeforeRouting` puede no enviar la respuesta en absoluto (`TMVCEngine.InternalExecuteAction.Result` no se vuelve `True` solo por eso) salvo que llame `SendResponse` explícitamente — ver el fix real en `DMVC.Middleware.CORS.pas` (commit de la Task 1) y el equivalente aplicado en `DMVC.Middleware.License.pas` (Task 2). `TMVCStaticFilesMiddleware` es código de framework, probablemente ya maneja esto correctamente (por algo NexoPago lo usa en producción sin este problema), pero **verifícalo con un test real antes de asumirlo** — si al servir un archivo estático o el fallback SPA la respuesta se pierde/queda vacía, aplica el mismo patrón (`SendResponse` + `ContentStream` si el body queda vacío) en el wrapper `TPurchaseBridgeStaticAppMiddleware`, no en el middleware de stock.

- [ ] **Step 1: Escribir el middleware**

Crear `dmvc/Middleware/DMVC.Middleware.StaticApp.pas`:

```pascal
unit DMVC.Middleware.StaticApp;

interface

uses
  System.SysUtils,
  MVCFramework,
  MVCFramework.Middleware.StaticFiles;

type
  TPurchaseBridgeStaticAppMiddleware = class(TInterfacedObject, IMVCMiddleware)
  private
    fInnerStatic: IMVCMiddleware;
    function IsExcludedPath(const APath: string): Boolean;
  protected
    procedure OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
    procedure OnBeforeControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      var AHandled: Boolean);
    procedure OnAfterControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      const AHandled: Boolean);
    procedure OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
  public
    constructor Create(const ADocumentRoot: string);
  end;

implementation

{ TPurchaseBridgeStaticAppMiddleware }

constructor TPurchaseBridgeStaticAppMiddleware.Create(const ADocumentRoot: string);
begin
  inherited Create;
  fInnerStatic := TMVCStaticFilesMiddleware.Create('/', ADocumentRoot, 'index.html', True);
end;

function TPurchaseBridgeStaticAppMiddleware.IsExcludedPath(const APath: string): Boolean;
var
  LPath: string;
begin
  LPath := APath.ToLower;
  Result := LPath.StartsWith('/api') or
            LPath.StartsWith('/auth') or
            LPath.StartsWith('/licencia') or
            (LPath = '/ping');
end;

procedure TPurchaseBridgeStaticAppMiddleware.OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
begin
  if IsExcludedPath(AContext.Request.PathInfo) then
  begin
    AHandled := False;
    Exit;
  end;
  fInnerStatic.OnBeforeRouting(AContext, AHandled);
end;

procedure TPurchaseBridgeStaticAppMiddleware.OnBeforeControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; var AHandled: Boolean);
begin
  // No-op: toda la logica corre en OnBeforeRouting, igual que el middleware de stock.
end;

procedure TPurchaseBridgeStaticAppMiddleware.OnAfterControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName: string; const AActionName: string; const AHandled: Boolean);
begin
  // No-op.
end;

procedure TPurchaseBridgeStaticAppMiddleware.OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
begin
  // No-op.
end;

end.
```

- [ ] **Step 2: Test que falla (RED)**

Crear `tests/DMVC/DMVC.StaticAppMiddlewareTests.pas` — este test crea su propio fixture (`www_test/index.html`) porque este repo no tiene una carpeta `www/` real todavía:

```pascal
unit DMVC.StaticAppMiddlewareTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TStaticAppMiddlewareTests = class
  private
    FServer: TTestServerProcess;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure ApiRoute_NotSwallowedByStaticMiddleware;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, IdHTTP;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TStaticAppMiddlewareTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
end;

procedure TStaticAppMiddlewareTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TStaticAppMiddlewareTests.ApiRoute_NotSwallowedByStaticMiddleware;
var
  LHttp: TIdHTTP;
  LBody: string;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    // Si el middleware de estaticos se "comiera" esta ruta, devolveria 200
    // con el contenido de index.html en vez de dejarla llegar al controller.
    LBody := LHttp.Get(Format('http://localhost:%d/api/equivalencias', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    Assert.IsFalse(LBody.Contains('<html'), 'La ruta /api no debe ser interceptada por el middleware de estaticos');
  finally
    LHttp.Free;
  end;
end;

end.
```

Modificar `tests/PurchaseBridge.Tests.dpr`: agregar `DMVC.StaticAppMiddlewareTests in 'DMVC\DMVC.StaticAppMiddlewareTests.pas';` (mover `;`).

Este test en realidad ya pasa ANTES de agregar el middleware (porque hoy no hay middleware de estáticos en absoluto que pueda interceptar `/api`), igual que el caso de la Task 2 — el RED real que importa verificar es el escenario opuesto: agrega temporalmente el middleware con `AStaticFilesPath='/'` SIN el filtro de exclusión (comenta el `if IsExcludedPath...Exit` del Step 1) y confirma que EN ESE CASO el test SÍ falla (la ruta `/api/equivalencias` empieza a devolver el `index.html` de fallback) — esto prueba que el filtro de exclusión es lo que realmente hace el trabajo. Documenta este experimento en tu reporte, luego restaura el filtro antes de continuar.

- [ ] **Step 3: Registrar en el WebModule**

Agregar a `dmvc/DMVC.WebModule.Main.pas`, DESPUÉS de License y ANTES de nada relacionado a auth (Task 4). Necesitas una carpeta de documentos reales o de prueba — usa `'www'` resuelto relativo al ejecutable, igual que Horse (`ResolvePathFromBase('www')`), pero como esa carpeta no existe aún en este repo, créala vacía (o con un `index.html` placeholder) para que el middleware no falle al arrancar:

```pascal
uses
  ...,
  DMVC.Middleware.StaticApp;

constructor TPurchaseBridgeDMVCWebModule.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEngine := TMVCEngine.Create(Self);
  FEngine.AddMiddleware(TPurchaseBridgeTraceMiddleware.Create);
  FEngine.AddMiddleware(TPurchaseBridgeCORSMiddleware.Create);
  FEngine.AddMiddleware(TPurchaseBridgeLicenseMiddleware.Create);
  FEngine.AddMiddleware(TPurchaseBridgeStaticAppMiddleware.Create(
    ExtractFilePath(ParamStr(0)) + 'www'));
  FEngine.AddController(TPingController);
  FEngine.AddController(TEquivalenciaController);
  FEngine.AddController(TProveedorController);
end;
```

Agrega `System.SysUtils` al `uses` de `implementation` si no está ya (para `ExtractFilePath`/`ParamStr`).

Crea la carpeta `bin\www\` con un `index.html` mínimo (`<html><body>PurchaseBridge DMVC placeholder</body></html>`) para que el middleware tenga algo que servir — este archivo NO se commitea (es un placeholder de desarrollo, no el build real del frontend; si `bin/` ya está gitignored por las Fases 1-2, esto queda cubierto automáticamente).

- [ ] **Step 4: Compilar, confirmar GREEN**

Compilar servidor+tests. Correr la suite — todos los tests anteriores más `ApiRoute_NotSwallowedByStaticMiddleware` deben pasar.

- [ ] **Step 5: Verificación manual**

`curl http://localhost:9091/` → debe servir el `index.html` placeholder. `curl http://localhost:9091/ruta-inventada-cualquiera` → debe servir el mismo `index.html` (fallback SPA). `curl http://localhost:9091/api/equivalencias` → debe seguir devolviendo el array JSON de siempre, NO el HTML.

- [ ] **Step 6: Commit**

```bash
git add dmvc/Middleware/DMVC.Middleware.StaticApp.pas dmvc/DMVC.WebModule.Main.pas tests/DMVC/DMVC.StaticAppMiddlewareTests.pas tests/PurchaseBridge.Tests.dpr
git commit -m "feat: migrate static files/SPA fallback middleware to DMVCFramework"
```

---

### Task 4: Auth JWT (protege Equivalencia y Proveedor)

**Files:**
- Create: `dmvc/Security/DMVC.Security.JWTClaims.pas`
- Create: `dmvc/Security/DMVC.Security.AuthHandler.pas`
- Modify: `dmvc/DMVC.WebModule.Main.pas` (registrar `TMVCJWTAuthenticationMiddleware`)
- Create: `tests/DMVC/DMVC.AuthTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr`

**Interfaces:**
- Consumes: `FirebirdConnection.GetHelisaQuery: TFDQuery` (unidad existente `database/FirebirdConnection.pas`, sin cambios) para consultar `USUARIOS` en `OnAuthentication`. `HConfig`/`uPaths.GetConfigPath` (existentes) para leer `[AUTH] JWTSecret` de `config.ini`.
- Produces: nada que otras tasks de esta fase consuman — es la última task.

**Nota heredada de la Task 1 (SendResponse)**: `TMVCJWTAuthenticationMiddleware` es código de framework (igual que `TMVCStaticFilesMiddleware`), así que probablemente ya maneja correctamente el envío de sus respuestas 401 bajo este hosting — no deberías necesitar tocar nada al respecto aquí. Si el test `GetEquivalencias_WithoutToken_Returns401` (Step 5) falla de forma rara (conexión se cierra sin excepción `EIdHTTPProtocolException`, o el body queda vacío en vez de traer el mensaje de error del framework), revisa si aplica el mismo problema de `SendResponse`/`ContentStream` documentado en `DMVC.Middleware.CORS.pas` (Task 1) y `DMVC.Middleware.License.pas` (Task 2).

**IMPORTANTE — decisión de arquitectura ya tomada, no la reconsideres**: auth = JWT real (no el modelo de GUID en memoria de Horse). `OnAuthorization` siempre `True` para cualquier usuario autenticado (Horse no tiene permisos granulares). `OnRequest` deniega por defecto salvo `TPingController` (nombre completo de clase, patrón NexoPago) — esto es lo que resuelve el riesgo de auth anotado en el roadmap, no hace falta enrutar por prefijo de URL.

- [ ] **Step 1: Config del secreto JWT**

Agregar a `bin\config.ini` (y `tests\bin\config.ini`) una sección nueva:
```ini
[AUTH]
JWTSecret=<un valor largo y aleatorio solo para este entorno de pruebas>
```
Genera un valor random de al menos 32 caracteres tú mismo (no hace falta pedírselo al usuario, es un secreto de firma HMAC para el entorno de pruebas local, no una credencial externa) — por ejemplo con `TGuid.NewGuid.ToString + TGuid.NewGuid.ToString` en un script auxiliar de una sola vez, o cualquier generador de strings aleatorios. Verifica con `git status` que `config.ini` sigue sin trackearse.

- [ ] **Step 2: Escribir el setup de claims JWT**

Crear `dmvc/Security/DMVC.Security.JWTClaims.pas`:

```pascal
unit DMVC.Security.JWTClaims;

interface

uses
  MVCFramework.JWT;

procedure SetupPurchaseBridgeJWTClaims(const JWT: TJWT);

implementation

uses
  System.SysUtils;

procedure SetupPurchaseBridgeJWTClaims(const JWT: TJWT);
begin
  JWT.Claims.Issuer := 'PurchaseBridge';
  JWT.Claims.IssuedAt := Now;
  JWT.Claims.NotBefore := Now - EncodeTime(0, 1, 0, 0); // 1 min de tolerancia hacia atras
  JWT.Claims.ExpirationTime := Now + EncodeTime(8, 0, 0, 0); // sesion de 8 horas
end;

end.
```

- [ ] **Step 3: Escribir el auth handler**

Crear `dmvc/Security/DMVC.Security.AuthHandler.pas`:

```pascal
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
  System.SysUtils, FireDAC.Comp.Client, FirebirdConnection;

{ TPurchaseBridgeAuthHandler }

procedure TPurchaseBridgeAuthHandler.OnRequest(const AContext: TWebContext;
  const AControllerQualifiedClassName, AActionName: string; var AAuthenticationRequired: Boolean);
begin
  // Deny-by-default: unica excepcion es el health-check publico, igual que
  // Horse (/ping esta explicitamente excluido de Auth). Ver
  // dmvc/Controllers/DMVC.Controllers.PingController.pas para el nombre
  // completo de clase (unit DMVC.Controllers.PingController, clase
  // TPingController) -- ajusta el string abajo si el nombre completo real
  // (incluyendo namespace) difiere al compilar.
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
  LQuery := FirebirdConnection.GetHelisaQuery;
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
```

**Verificar antes de compilar**: el nombre completo de clase que `OnRequest` recibe (`AControllerQualifiedClassName`) puede o no incluir el nombre de la unidad, dependiendo de la versión de DMVCFramework — compila, agrega un log temporal (`uLogger.LogInfo('Controller: ' + AControllerQualifiedClassName, 'auth-debug')`) en `OnRequest`, haz una petición a `/ping`, revisa el log para confirmar el string exacto, ajusta la comparación, y quita el log temporal antes de commitear.

- [ ] **Step 4: Registrar el middleware JWT**

Modificar `dmvc/DMVC.WebModule.Main.pas` — agregar el `uses` y la última línea de `AddMiddleware` (JWT va AL FINAL, después de estáticos, protegiendo solo lo que efectivamente llega a un controller):

```pascal
uses
  System.SysUtils, System.Classes, System.IniFiles, Web.HTTPApp,
  MVCFramework, MVCFramework.JWT, MVCFramework.Middleware.JWT,
  uPaths;

// ... (declaraciones existentes)

implementation

uses
  DMVC.Controllers.PingController,
  DMVC.Controllers.EquivalenciaController,
  DMVC.Controllers.ProveedorController,
  DMVC.Middleware.HttpLogger,
  DMVC.Middleware.CORS,
  DMVC.Middleware.License,
  DMVC.Middleware.StaticApp,
  DMVC.Security.JWTClaims,
  DMVC.Security.AuthHandler;

function GetJWTSecret: string;
var
  LIni: TIniFile;
begin
  LIni := TIniFile.Create(uPaths.GetConfigPath);
  try
    Result := LIni.ReadString('AUTH', 'JWTSecret', '');
  finally
    LIni.Free;
  end;
end;

constructor TPurchaseBridgeDMVCWebModule.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEngine := TMVCEngine.Create(Self);
  FEngine.AddMiddleware(TPurchaseBridgeTraceMiddleware.Create);
  FEngine.AddMiddleware(TPurchaseBridgeCORSMiddleware.Create);
  FEngine.AddMiddleware(TPurchaseBridgeLicenseMiddleware.Create);
  FEngine.AddMiddleware(TPurchaseBridgeStaticAppMiddleware.Create(
    ExtractFilePath(ParamStr(0)) + 'www'));
  FEngine.AddMiddleware(TMVCJWTAuthenticationMiddleware.Create(
    TPurchaseBridgeAuthHandler.Create,
    SetupPurchaseBridgeJWTClaims,
    GetJWTSecret,
    '/api/auth/login',
    [TJWTCheckableClaim.ExpirationTime, TJWTCheckableClaim.NotBefore, TJWTCheckableClaim.IssuedAt],
    30));
  FEngine.AddController(TPingController);
  FEngine.AddController(TEquivalenciaController);
  FEngine.AddController(TProveedorController);
end;
```

Nota: `/api/auth/login` no tiene controller — `TMVCJWTAuthenticationMiddleware` lo intercepta directamente en su propio `OnBeforeRouting`, invoca `OnAuthentication`, y si `AIsValid=True` genera y devuelve el JWT él mismo (esto es un comportamiento del framework, no código a escribir). El body esperado del POST a `/api/auth/login` es `{"username": "...", "password": "..."}` (nombres de campo del framework, no configurables sin sobreescribir más lógica — documenta esto para el frontend en la Fase 5, es distinto del `{"usuario":"...","clave":"..."}` que espera Horse hoy).

- [ ] **Step 5: Tests que fallan (RED)**

Crear `tests/DMVC/DMVC.AuthTests.pas`:

```pascal
unit DMVC.AuthTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TAuthTests = class
  private
    FServer: TTestServerProcess;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetEquivalencias_WithoutToken_Returns401;

    [Test]
    procedure Ping_WithoutToken_StillReturns200;

    [Test]
    procedure Login_WithNonexistentUser_Returns401;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, IdHTTP, IdException;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TAuthTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
end;

procedure TAuthTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TAuthTests.GetEquivalencias_WithoutToken_Returns401;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    try
      LHttp.Get(Format('http://localhost:%d/api/equivalencias', [TEST_PORT]));
      Assert.Fail('Se esperaba una excepcion HTTP 401');
    except
      on E: EIdHTTPProtocolException do
        Assert.AreEqual(401, E.ErrorCode, 'Debe responder 401 sin token');
    end;
  finally
    LHttp.Free;
  end;
end;

procedure TAuthTests.Ping_WithoutToken_StillReturns200;
var
  LHttp: TIdHTTP;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.Get(Format('http://localhost:%d/ping', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode, '/ping debe seguir siendo publico');
  finally
    LHttp.Free;
  end;
end;

procedure TAuthTests.Login_WithNonexistentUser_Returns401;
var
  LHttp: TIdHTTP;
  LBodyJson: TJSONObject;
  LPostBody: TStringStream;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LBodyJson := TJSONObject.Create;
    try
      LBodyJson.AddPair('username', '__usuario_inexistente_phase3_test__');
      LBodyJson.AddPair('password', 'cualquier-clave');
      LPostBody := TStringStream.Create(LBodyJson.ToJSON, TEncoding.UTF8);
      try
        LHttp.Request.ContentType := 'application/json';
        try
          LHttp.Post(Format('http://localhost:%d/api/auth/login', [TEST_PORT]), LPostBody);
          Assert.Fail('Se esperaba una excepcion HTTP 401 para un usuario inexistente');
        except
          on E: EIdHTTPProtocolException do
            Assert.AreEqual(401, E.ErrorCode, 'Login con usuario inexistente debe responder 401');
        end;
      finally
        LPostBody.Free;
      end;
    finally
      LBodyJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

end.
```

Modificar `tests/PurchaseBridge.Tests.dpr`: agregar `DMVC.AuthTests in 'DMVC\DMVC.AuthTests.pas';` (mover `;`).

Recompilar y correr ANTES de implementar el Step 3/4 completos — `GetEquivalencias_WithoutToken_Returns401` y `Login_WithNonexistentUser_Returns401` deben fallar (hoy `/api/equivalencias` responde 200 sin token, y `/api/auth/login` ni siquiera existe como ruta) — RED esperado. `Ping_WithoutToken_StillReturns200` ya pasa (no hay RED real ahí, es regresión, igual que en la Task 2).

- [ ] **Step 6: Compilar, confirmar GREEN**

Con el auth handler y el middleware JWT ya implementados (Steps 1-4), recompilar servidor+tests (agrega `dmvc/Security` al `-U` de ambos) y correr la suite completa — los 3 tests de esta task deben pasar, junto con TODOS los anteriores (Equivalencia/Proveedor deben seguir pasando: sus propios tests no envían token, así que si ahora requieren 401, esos tests de las Fases 2 EMPEZARÁN A FALLAR salvo que los actualices).

**Acción requerida sobre los tests de la Fase 2**: `DMVC.EquivalenciaControllerTests.pas` y `DMVC.ProveedorControllerTests.pas` van a necesitar enviar un header `Authorization: Bearer <token>` válido ahora que esos controllers quedan protegidos por defecto. Opciones, en orden de preferencia:
1. Agregar un helper compartido (`tests/DMVC/DMVC.TestAuthHelper.pas`) con una función `ObtenerTokenDePrueba: string` que haga login contra Helisa con credenciales reales de prueba SI están disponibles vía una variable de entorno o sección de `config.ini` (p.ej. `[AUTH_TEST] Username=...`/`Password=...`) — si no están configuradas, los tests de Equivalencia/Proveedor que dependen de auth deben marcarse `[Ignore]` con un mensaje claro en vez de fallar en rojo permanentemente.
2. Si no hay credenciales reales de prueba disponibles y prefieres no bloquear esta task por eso, pregúntale al usuario ahora (no asumas) si puede darte un usuario/clave de prueba de Helisa para los tests automatizados, o si prefiere dejar los tests de Equivalencia/Proveedor como `[Ignore]` documentado hasta que los tenga.

No dejes tests en rojo de forma permanente sin decisión explícita del usuario — este es exactamente el tipo de bloqueo que en las Fases 1-2 se resolvió preguntando, no adivinando.

- [ ] **Step 7: Verificación manual (login exitoso, flujo completo)**

Si tienes credenciales reales de un usuario de Helisa a mano: `curl -X POST http://localhost:9091/api/auth/login -H "Content-Type: application/json" -d "{\"username\":\"<usuario_real>\",\"password\":\"<clave_real>\"}"` → debe responder 200 con un JWT. Luego `curl -H "Authorization: Bearer <token>" http://localhost:9091/api/equivalencias` → debe responder 200 con el array JSON (antes daba 401 sin el header). Si no tienes credenciales a mano, documenta esta verificación como pendiente para cuando el usuario las tenga.

- [ ] **Step 8: Commit**

```bash
git add dmvc/Security tests/DMVC/DMVC.AuthTests.pas tests/PurchaseBridge.Tests.dpr dmvc/DMVC.WebModule.Main.pas
git commit -m "feat: add JWT authentication to DMVCFramework server, protecting Equivalencia and Proveedor"
```

---

## Self-Review

**Cobertura:** Task 1 cubre CORS + logger. Task 2 cubre el guard de licencia. Task 3 cubre estáticos/SPA. Task 4 cubre auth JWT + protección de los controllers existentes. Los 5 middlewares del objetivo de la Fase 2 del roadmap quedan cubiertos.

**Placeholders:** ninguno de omisión. Dos notas explícitas de "esto no tiene un RED real" (Tasks 2 y 3) están justificadas y documentadas, no son placeholders sino limitaciones reales de qué se puede probar de forma segura sin manipular datos de licencia real o sin un build real del frontend.

**Decisión abierta explícita para el ejecutor**: Task 4 Step 6 tiene una decisión que requiere al usuario (credenciales de prueba para Equivalencia/Proveedor vs. marcar esos tests `[Ignore]`) — no la resuelvas adivinando, sigue el patrón ya establecido en esta migración de preguntar cuando haga falta un dato que solo el usuario tiene.

**Consistencia de tipos:** `TPurchaseBridgeCORSMiddleware`/`TPurchaseBridgeLicenseMiddleware`/`TPurchaseBridgeStaticAppMiddleware`/`TPurchaseBridgeTraceMiddleware` siguen el mismo patrón de clase (`TInterfacedObject, IMVCMiddleware`, 4 métodos) en las 4 tasks. `TPurchaseBridgeAuthHandler` implementa `IMVCAuthenticationHandler` con la firma exacta de DMVCFramework 3.4.3 (verificada contra `MVCFramework.pas` del framework vendorizado).

## Próximo paso

Cuando esta fase esté mergeada y verificada, se redacta el plan detallado de la Fase 4 (controllers de alto riesgo/volumen: Auth, Helisa, Documentos, Import, Xml, XmlValidation, Licencia), reusando el patrón de auth ya establecido aquí para proteger esos controllers desde el principio.
