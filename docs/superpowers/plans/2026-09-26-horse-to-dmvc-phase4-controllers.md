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

**Objetivo:** `GET /licencia/estado`, `POST /licencia/registrar` (+ alias `/licencia/activar`), `POST /licencia/activar-online` — todas usan `services/LicenseService.pas` (`TLicenciaService`, sin cambios). `GetEstado` llama `ValidarLicencia` (red real) — decidir si se testea automatizado o solo manual. `Registrar`/`ActivarOnline` mutan estado real de licencia — NO automatizar el flujo completo, solo validación de input (400 sin body/código).

**Archivos:** `dmvc/DTOs/DMVC.DTOs.Licencia.pas`, `dmvc/Controllers/DMVC.Controllers.LicenciaController.pas`, tests correspondientes.

### Task 3: XmlValidationController (2 rutas)

**Objetivo:** `POST /xml/validate` (body `{fileName}`, lee de `GetInputPath`), `POST /xml/validate/batch` (body `{files:[...]}` o todos los `.xml` de Input si no se especifica). Usa `XmlParserService`/`XmlPersistenceService`/`ValidationService`/`uPaths` (sin cambios). El response shape es un JSON armado a mano con muchos campos (`valido`, `requiereHomologacion`, `proveedorExiste`, `productos`, `errores`, etc.) — decidir si se modela como DTO completo o se preserva como JSON crudo vía `TJSONObject`/`IMVCResponse` dado lo dinámico del shape.

**Archivos:** `dmvc/Controllers/DMVC.Controllers.XmlValidationController.pas`, tests correspondientes.

### Task 4: ImportController (1 ruta)

**Objetivo:** `POST /factura/xml` (sin alias `/api`) — recibe XML crudo en el body, usa `XMLFacturaService.Parsear`, `ProveedorRepository.ObtenerProveedorPorNit` (Helisa real, solo lectura), `ProductoRepository.ExisteProducto`. Responde JSON con proveedor+productos y si existen.

**Archivos:** `dmvc/DTOs/DMVC.DTOs.Import.pas`, `dmvc/Controllers/DMVC.Controllers.ImportController.pas`, tests correspondientes.

### Task 5: DocumentosController (1 ruta) + endpoint /api/auth/me

**Objetivo:** `POST /documentos/procesar` — usa `Req.Session<TSessionInfoObj>.Data` en Horse (sesión GUID en memoria, ya obsoleta desde la Fase 3). En DMVC el equivalente es leer `Context.LoggedUser`/sus custom claims (`codigo`, `nombre`, seteados en `OnAuthentication` de `DMVC.Security.AuthHandler.pas`, Fase 3). Este task establece el patrón "leer usuario actual desde el JWT" y lo reusa para agregar `GET /api/auth/me` (controller nuevo o el mismo), reemplazando el payload de usuario/empresa que el login de Horse solía devolver (ver nota de la Fase 3 sobre el contrato de login cambiado).

**Archivos:** `dmvc/Controllers/DMVC.Controllers.DocumentosController.pas`, posiblemente `dmvc/Controllers/DMVC.Controllers.AuthController.pas` (solo `/me`), tests correspondientes.

### Task 6: XmlController (9 rutas — la más grande, 1176 líneas en Horse)

**Objetivo:** `GET /xml/list` y `/xml/files` (mismo handler), `POST /xml/upload` (binario, `horse-octet-stream` en Horse → `TMVCWebRequest`/body crudo en DMVC), `POST /xml/parse`, `GET /xml/files/:id`, `POST /xml/procesar` (batch JSON), `GET /xml/productos/pendientes`, `GET /xml/productos/documento`, `POST /xml/homologar`, `GET /dashboard/metrics`. Dado el tamaño, evaluar al llegar a esta task si conviene partirla en 2 (rutas de lectura vs. upload/escritura).

**Archivos:** `dmvc/DTOs/DMVC.DTOs.Xml.pas`, `dmvc/Controllers/DMVC.Controllers.XmlController.pas`, tests correspondientes.

---

## Self-Review (de la Task 1, la única con detalle completo por ahora)

**Cobertura:** Task 1 cubre las 2 rutas de `HelisaController` completas. Las Tasks 2-6 cubren las 12 rutas restantes del objetivo de la Fase 4 del roadmap (a nivel de objetivo, detalle TDD pendiente de escribirse task por task).

**Placeholders:** ninguno en la Task 1 (código completo). Las Tasks 2-6 son deliberadamente roadmap-level por la restricción de proceso explícita del usuario — no son placeholders de un plan que debería tener detalle ahora, son la siguiente fase del mismo patrón incremental ya usado a nivel de fases completas (Fases 1-5), aplicado esta vez a nivel de tasks dentro de una fase.

## Próximo paso

Ejecutar Task 1 (subagent-driven-development: implementer → review → fix si aplica → commit). Al terminar Task 1, PARAR y pedir aprobación explícita antes de escribir el detalle completo de la Task 2.
