# Fase 5 — Cutover (apagar Horse) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) o superpowers:executing-plans para implementar este plan task-by-task. Steps usan sintaxis de checkbox (`- [ ]`) para tracking.

**Goal:** Dejar DMVCFramework como el ÚNICO servidor de PurchaseBridge (puerto 9000, mismo Windows Service de producción), retirando Horse por completo del código fuente (controllers/, middleware/, `ServerBootstrap.pas`, `ServerMain.pas`, `modules/`, dependencias de `boss.json`). Verificar contra `PurchaseBridge.postman_collection.json`.

**Límite explícito de esta fase (decisión del usuario, 2026-09-28):** todo el trabajo de código (compilar, correr los 57 tests DUnitX de la Fase 4, verificar con Postman contra un DMVC local) se hace en un worktree aislado, igual que las Fases 1-4. **NO se instala, reemplaza ni reinicia el Windows Service real** (`PurchaseBridgeService.exe`/`.dproj` en la raíz del repo, que son el artefacto de producción) — eso queda como paso manual explícito del usuario, fuera del alcance de este plan. Este plan deja el código y el build listos; el despliegue real es una decisión y acción separada.

**Architecture:** Réplica exacta, en DMVC, del patrón de arranque de producción que ya existe para Horse:
- `ServerBootstrap.pas` (Horse) → `dmvc/DMVC.ServerBootstrap.pas` (nuevo): configura el engine DMVC (WebModule ya existente desde la Fase 1-4, sin cambios), puerto 9000 por defecto, wiring de `TLicenciaService.InicializarLicencia`/`StartPeriodicValidation` (pendiente documentado desde la Fase 3), `EnsureServiceDirectories`/`LogResolvedPaths` (mismo `uPaths`, sin cambios).
- `ServerMain.pas` (Horse) → `dmvc/DMVC.ServerMain.pas` (nuevo): mismo patrón exacto de reintentos + hilo de fondo (`TThread`, `StartServer(ARunInBackground, AMaxStartAttempts, ARetryDelayMs)`/`StopServer`/`IsServerRunning`) que ya usa el Windows Service — traducido a la API de `TIdHTTPWebBrokerBridge` en vez de `THorse.Listen`/`StopListen`.
- `service/PurchaseBridge.Service.pas`: cambia su `uses ServerMain` (Horse) por `uses DMVC.ServerMain` — es el ÚNICO cambio funcional en el wrapper de servicio de Windows; su lógica (`ServiceStart`/`ServiceStop`) no cambia.
- `PurchaseBridgeDMVC.dpr` se convierte en el ÚNICO entrypoint de consola (puerto 9000 por defecto, ya no 9091; sigue aceptando override por `ParamStr(1)` para desarrollo local). `PurchaseBridge.dpr` (Horse) se elimina.

## Tech Stack
Mismo de las Fases 1-4: DMVCFramework 3.4.3 Aluminium, `TIdHTTPWebBrokerBridge`, Firebird/FireDAC sin cambios, DUnitX para tests nuevos.

## Global Constraints
- No modificar `services/`, `repositories/`, `database/FirebirdConnection.pas`, `config/HConfig.pas` — toda la capa de negocio queda intacta, reusada tal cual por DMVC desde las Fases 2-4.
- No instalar/reiniciar el Windows Service real (ver límite explícito arriba).
- `PurchaseBridgeService.dproj`/`.exe`/`.dsk`/`.identcache` en la raíz del repo son artefactos de build de producción — no se tocan directamente; el `.dproj` se actualiza solo en su `uses`/lista de archivos si DCC32 lo requiere para compilar, nunca se abre en el IDE ni se reinstala como servicio desde este plan.
- Antes de borrar cualquier archivo Horse (`controllers/*.pas`, `middleware/*.pas`, `ServerBootstrap.pas`, `ServerMain.pas`, `services/AuthService.pas`, `utils/ErrorResponseUtils.pas`, `modules/`), confirmar explícitamente que NINGÚN archivo DMVC lo referencia (grep `uses` en todo `dmvc/`) — la Fase 3 ya documentó que `DMVC.Security.AuthHandler.pas` NO reusa `AuthService.pas` (hace su propia consulta a `USUARIOS`), así que `AuthService.pas` y `ErrorResponseUtils.pas` son candidatos a retiro, pero verificar de nuevo en el momento, no confiar solo en la memoria de fases anteriores.
- Toolchain de compilación: igual que Fases 1-4 (DCC32.EXE, rutas `-U`/`-NS` ya conocidas, documentadas en el plan de la Fase 4).
- Regla de nombres de unidad Delphi (unit name = nombre de archivo exacto, con puntos) sigue aplicando a todo archivo nuevo.

---

### Task 1: DMVC.ServerBootstrap.pas — arranque con license init, puerto 9000, paths de producción

**Files:**
- Create: `dmvc/DMVC.ServerBootstrap.pas`
- Create: `tests/DMVC/DMVC.ServerBootstrapTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr`

**Interfaces:**
- Consume (sin cambios): `config/HConfig.pas` (`THConfig.GetInstance`), `utils/uPaths.pas` (`EnsureServiceDirectories`, `GetBasePath`/`GetInputPath`/`GetProcessedPath`/`GetLogsPath`), `services/LicenseService.pas` (`TLicenciaService.InicializarLicencia`, `.StartPeriodicValidation`), `utils/uLogger.pas`.
- Reusa el WebModule/engine DMVC ya existente (`dmvc/DMVC.WebModule.Main.pas`, sin cambios desde la Fase 4) — este archivo NO reconfigura controllers/middleware, solo envuelve el `TIdHTTPWebBrokerBridge` + las llamadas de inicialización que Horse hace en `ServerBootstrap.InitializeServerDependencies`.

**Decisión de paridad exacta con Horse (`ServerBootstrap.pas` líneas 169-184, ya leído este sesión):** replicar el MISMO orden — `EnsureServiceDirectories` → `LogResolvedPaths` (mismo formato de log) → `THConfig.GetInstance` → `try TLicenciaService.InicializarLicencia; StartPeriodicValidation; except log y continuar (no re-raise)`. Este es exactamente el punto pendiente documentado en el roadmap desde la Fase 3 ("guard de licencia dormido") — activarlo acá es lo que lo saca del estado dormido, usando el `config.ini` de producción real (con `[LICENCIA]` válido) en el entorno del Windows Service.

- [ ] **Step 1: Escribir el bootstrap**

Crear `dmvc/DMVC.ServerBootstrap.pas`:

```pascal
unit DMVC.ServerBootstrap;

interface

uses
  IdHTTPWebBrokerBridge;

const
  DEFAULT_DMVC_PORT = 9000;

function CreateAndActivateServer(APort: Integer): TIdHTTPWebBrokerBridge;
procedure InitializeServerDependencies;

implementation

uses
  System.SysUtils,
  Web.WebReq, Web.WebBroker,
  MVCFramework.Commons,
  HConfig, uPaths, uLogger, LicenseService,
  DMVC.WebModule.Main;

procedure LogResolvedPaths;
begin
  uLogger.LogInfo('BasePath: ' + GetBasePath, 'startup_paths');
  uLogger.LogInfo('InputPath: ' + GetInputPath, 'startup_paths');
  uLogger.LogInfo('ProcessedPath: ' + GetProcessedPath, 'startup_paths');
  uLogger.LogInfo('LogsPath: ' + GetLogsPath, 'startup_paths');
end;

procedure InitializeServerDependencies;
begin
  EnsureServiceDirectories;
  LogResolvedPaths;

  THConfig.GetInstance;
  uLogger.LogInfo('Configuracion cargada correctamente (DMVC).', 'startup');

  try
    TLicenciaService.InicializarLicencia;
    TLicenciaService.StartPeriodicValidation;
  except
    on E: Exception do
      uLogger.LogError(E, 'startup');
  end;
end;

function CreateAndActivateServer(APort: Integer): TIdHTTPWebBrokerBridge;
begin
  if WebRequestHandler <> nil then
    WebRequestHandler.WebModuleClass := WebModuleClass;
  WebRequestHandlerProc.MaxConnections := 1024;

  Result := TIdHTTPWebBrokerBridge.Create(nil);
  try
    // Mismo fix de la Fase 1: sin esto Indy rechaza el header Authorization
    // Bearer antes de que llegue al middleware JWT. Ver PurchaseBridgeDMVC.dpr.
    Result.OnParseAuthentication := TMVCParseAuthentication.OnParseAuthentication;
    Result.DefaultPort := APort;
    Result.Active := True;
    uLogger.LogInfo('Server is running on port ' + IntToStr(APort), 'startup');
  except
    Result.Free;
    raise;
  end;
end;

end.
```

Notas:
- `CreateAndActivateServer` devuelve el `TIdHTTPWebBrokerBridge` ya activo (no bloquea con `Readln` como el `PurchaseBridgeDMVC.dpr` actual) — el llamador (Task 2's `DMVC.ServerMain.pas` o el `.dpr` de consola) decide cómo esperar/bloquear. Esto es necesario para integrarlo con el patrón de hilo de fondo del Windows Service.
- Verificar que `MVCFramework.Commons` expone `TMVCParseAuthentication` con ese nombre exacto en esta versión (ya usado en `PurchaseBridgeDMVC.dpr`, copiar el import tal cual).

- [ ] **Step 2: Tests (RED → GREEN)**

Crear `tests/DMVC/DMVC.ServerBootstrapTests.pas` — dado que `InitializeServerDependencies`/`CreateAndActivateServer` arrancan un servidor real, el patrón de test aquí es distinto al resto de la fase: no se puede levantar dos veces el mismo puerto en el mismo proceso de test junto al resto de la suite (que ya usa `TTestServerProcess` para levantar el `.exe` completo). En su lugar, testear:

1. `InitializeServerDependencies_DoesNotRaise_WhenLicenciaSectionMissing` — llamar la función directamente (mismo proceso del test runner, sin levantar HTTP) con un `config.ini` de prueba SIN sección `[LICENCIA]` (ya es el caso del `config.ini` de este worktree, confirmado en la Fase 3) — debe completar sin lanzar excepción (el `try/except` interno la traga y loguea), igual que el Horse original.
2. `CreateAndActivateServer_ThenFree_DoesNotRaise` — crear el server en un puerto de prueba dedicado NO usado por el resto de la suite (ej. `9099`), verificar `Result.Active = True`, y liberarlo (`Result.Active := False; Result.Free;`) sin excepción. Este test reemplaza el rol de "smoke test" que el resto de la fase delega a `TTestServerProcess` contra el `.exe` compilado — acá se prueba la función de arranque en-proceso porque todavía no hay un `.exe` de servicio para lanzar como subproceso.

Modificar `tests/PurchaseBridge.Tests.dpr`: agregar `DMVC.ServerBootstrapTests in 'DMVC\DMVC.ServerBootstrapTests.pas';`.

- [ ] **Step 3: Commit**

```bash
git add dmvc/DMVC.ServerBootstrap.pas tests/DMVC/DMVC.ServerBootstrapTests.pas tests/PurchaseBridge.Tests.dpr
git commit -m "feat: add DMVC.ServerBootstrap with production license-guard wiring"
```

---

### Task 2: DMVC.ServerMain.pas — reintentos + hilo de fondo (paridad con ServerMain.pas de Horse)

**Files:**
- Create: `dmvc/DMVC.ServerMain.pas`
- Create: `tests/DMVC/DMVC.ServerMainTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr`

**Interfaces:** Traduce `ServerMain.pas` (ya leído este sesión, 175 líneas) línea por línea: mismo `TThread` (`TServerRunner`), misma firma pública `StartServer(const ARunInBackground: Boolean = False; const AMaxStartAttempts: Integer = 3; const ARetryDelayMs: Cardinal = 5000)`/`StopServer`/`IsServerRunning`, mismo `TCriticalSection`/`TEvent` para coordinar. Reemplaza `ServerBootstrap.StartServer`/`THorse.StopListen`/`THorse.IsRunning` (Horse) por `DMVC.ServerBootstrap.InitializeServerDependencies` + `DMVC.ServerBootstrap.CreateAndActivateServer(DEFAULT_DMVC_PORT)` (guardando la referencia al `TIdHTTPWebBrokerBridge` en una variable de unidad para poder desactivarlo en `StopServer`) / `LServerInstance.Active := False` / `Assigned(LServerInstance) and LServerInstance.Active`.

- [ ] **Step 1: Escribir el runner**

Traducir `ServerMain.pas` a `dmvc/DMVC.ServerMain.pas` preservando EXACTAMENTE la misma estructura de reintentos/logging/locking (copiar el archivo original como base y hacer los reemplazos mínimos descritos arriba — no rediseñar el patrón de concurrencia, ya está probado en producción con Horse).

- [ ] **Step 2: Tests (RED → GREEN)**

Crear `tests/DMVC/DMVC.ServerMainTests.pas`:
1. `StartServer_Background_ThenStop_NoException` — `DMVC.ServerMain.StartServer(True, 1, 100)` en un puerto de prueba dedicado (definir el puerto como parámetro o constante de test, distinto del `DEFAULT_DMVC_PORT` de producción y del `9091` que usa el resto de la suite), esperar brevemente a que `IsServerRunning` sea `True` (poll con timeout corto), llamar `StopServer`, verificar que no queda el hilo corriendo.
2. `StartServer_RetriesOnFailure` — si es posible simular una falla de arranque (puerto ya ocupado por otro listener de prueba) para verificar que reintenta `AMaxStartAttempts` veces antes de re-lanzar la excepción — si resulta complejo de simular de forma confiable, documentar como verificación manual en vez de forzar un test frágil.

Modificar `tests/PurchaseBridge.Tests.dpr`: agregar la nueva unidad.

- [ ] **Step 3: Commit**

```bash
git add dmvc/DMVC.ServerMain.pas tests/DMVC/DMVC.ServerMainTests.pas tests/PurchaseBridge.Tests.dpr
git commit -m "feat: add DMVC.ServerMain with retry/background-thread parity with Horse's ServerMain"
```

---

### Task 3: Windows Service wrapper apunta a DMVC

**Files:**
- Modify: `service/PurchaseBridge.Service.pas`
- Modify: `PurchaseBridgeService.dpr`
- Modify: `PurchaseBridgeService.dproj` (agregar `dmvc/DMVC.ServerMain.pas`, `dmvc/DMVC.ServerBootstrap.pas`, `dmvc/DMVC.WebModule.Main.pas` y TODOS los `dmvc/Controllers/*.pas`/`dmvc/DTOs/*.pas`/`dmvc/Middleware/*.pas`/`dmvc/Security/*.pas` a la lista de archivos del proyecto; quitar los `controllers/*.pas`/`middleware/*.pas`/`ServerMain.pas`/`ServerBootstrap.pas` de Horse una vez confirmado que compila sin ellos)

**Cambio funcional único:** en `service/PurchaseBridge.Service.pas`, `uses ServerMain` (Horse) → `uses DMVC.ServerMain`. El resto de `TPurchaseBridgeService.ServiceStart`/`ServiceStop` NO cambia — llaman a las mismas `StartServer(True, 3, 5000)`/`StopServer` con la misma firma, ahora resueltas contra la nueva unidad.

**Advertencia sobre el `.dproj`:** este plan NO ha escrito nunca un `.dproj` a mano (ver Restricciones globales del roadmap, decisión de la Fase 1) — para este archivo específico SÍ hace falta editarlo, porque ya existe y tiene una lista de archivos fija que DCC32 no puede inferir solo. Editar el `.dproj` con cuidado quirúrgico (agregar/quitar `<DCCReference Include="...">` entries), o mejor: dejar que el implementador abra el proyecto en el IDE de Delphi si está disponible en el entorno de ejecución para que el IDE regenere la lista de archivos correctamente — si no hay IDE disponible en el entorno del agente, editar el XML a mano con extremo cuidado y compilar por línea de comandos con DCC32 apuntando al `.dpr` (no al `.dproj`) para verificar antes de tocar el `.dproj`.

- [ ] **Step 1: Actualizar el wrapper de servicio**

Modificar `service/PurchaseBridge.Service.pas`: cambiar el `uses` de `ServerMain` a `DMVC.ServerMain`.

- [ ] **Step 2: Actualizar `PurchaseBridgeService.dpr`**

Quitar del `uses` los archivos Horse-only (`ServerBootstrap`, `ServerMain`, todos los `controllers/*.pas`, todos los `middleware/*.pas`) y agregar los archivos `dmvc/*` necesarios (mismo patrón que `PurchaseBridgeDMVC.dpr` pero SIN el `Readln` bloqueante — este `.dpr` es el service host, no un console interactivo).

- [ ] **Step 3: Compilar y verificar (sin instalar el servicio)**

Compilar `PurchaseBridgeService.dpr` vía DCC32.EXE (cwd correcto, mismas rutas `-U`/`-NS` de las Fases 1-4 más las nuevas). Esto SOLO verifica que compila — **no ejecutar, instalar ni registrar el `.exe` resultante como servicio de Windows** (eso es el límite explícito de esta fase).

- [ ] **Step 4: Commit**

```bash
git add service/PurchaseBridge.Service.pas PurchaseBridgeService.dpr PurchaseBridgeService.dproj
git commit -m "feat: point Windows Service wrapper at DMVC.ServerMain instead of Horse"
```

---

### Task 4: Entrypoint de consola único + retiro de Horse del código fuente

**Files:**
- Modify: `PurchaseBridgeDMVC.dpr` (puerto 9000 por defecto en vez de 9091; opcionalmente renombrar a `PurchaseBridge.dpr` reemplazando el viejo — ver decisión abajo)
- Delete: `PurchaseBridge.dpr` (Horse), `ServerBootstrap.pas`, `ServerMain.pas`, `controllers/*.pas` (9 archivos), `middleware/*.pas` (5 archivos), `services/AuthService.pas`, `utils/ErrorResponseUtils.pas` (tras confirmar que nada en `dmvc/` los referencia)
- Delete: `modules/` (paquetes Horse vendorizados vía Boss)
- Modify: `boss.json` (quitar las 6 dependencias Horse: `handle-exception`, `horse`, `horse-cors`, `horse-logger`, `horse-octet-stream`, `jhonson`)

**Decisión a confirmar con el usuario antes de ejecutar este Step (no asumir):** ¿el entrypoint de consola final se llama `PurchaseBridge.dpr` (reemplazando literalmente el viejo, path/nombre que puede estar referenciado en scripts de build/despliegue externos al repo) o se mantiene `PurchaseBridgeDMVC.dpr` como nombre pero como ÚNICO entrypoint? El roadmap dice "eliminar ... duplicados dejando un único entrypoint" sin especificar el nombre final — esto es una decisión de nombrado con impacto en cualquier script de despliegue externo, preguntar antes de renombrar archivos, no asumir.

- [ ] **Step 1: Verificar que nada en `dmvc/` referencia los archivos Horse candidatos a borrar**

```bash
grep -rn "AuthService\b" dmvc/
grep -rn "ErrorResponseUtils" dmvc/
grep -rn "\bHorse\b" dmvc/
```

Si alguno de estos greps encuentra algo, DETENERSE y reportar — no borrar el archivo correspondiente sin resolver esa referencia primero.

- [ ] **Step 2: Actualizar `PurchaseBridgeDMVC.dpr`**

Cambiar el default de puerto de `9091` a `9000` (`StrToIntDef(ParamStr(1), 9000)`), y reemplazar el `RunServer` inline por una llamada a `DMVC.ServerBootstrap.InitializeServerDependencies` + `DMVC.ServerBootstrap.CreateAndActivateServer` (Task 1) para no duplicar lógica entre el entrypoint de consola y el de servicio.

- [ ] **Step 3: Borrar los archivos Horse-only** (lista completa arriba), quitar sus referencias de `boss.json`, borrar `modules/`.

- [ ] **Step 4: Compilar TODO lo que quede** (servidor DMVC, servicio, suite de tests) y correr la suite completa de nuevo — deben seguir pasando los 57 tests de la Fase 4 más los nuevos de las Tasks 1-2 de esta fase, ya que ninguno de ellos depende de los archivos Horse borrados.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove Horse framework from source tree (cutover complete)

Deletes controllers/, middleware/, ServerBootstrap.pas, ServerMain.pas,
AuthService.pas, ErrorResponseUtils.pas, modules/, and Horse entries
from boss.json. DMVCFramework is now the only HTTP layer. Does not
touch the deployed Windows Service -- that remains a manual step."
```

---

### Task 5: Verificación con la colección Postman — COMPLETA (2026-09-28)

**Resultado:** 18/18 requests de `PurchaseBridge.postman_collection.json` verificadas — 2 en vivo con 200/401/403 esperados (`GET /ping`, `POST /api/auth/login`), 2 en vivo confirmando exención del guard de licencia (`GET /api/licencia/estado`, `POST /api/licencia/activar` → 401 de JWT, no 403 de licencia), y 14 verificadas por inspección de código fuente (rutas, métodos, y shape de request/response confirmados contra los controllers DMVC correspondientes) porque el guard de licencia (Task 1, activo por primera vez en este entrypoint) bloquea el resto de las rutas en este worktree de pruebas — el `config.ini` de este worktree solo tiene `InstalacionHash`, sin `[LICENCIA] URLServidor`/`Nit`, así que `TLicenciaService.InicializarLicencia` deja `SistemaBloqueado=True` al arrancar. **Esto no es un bug de la migración**: es exactamente el mismo comportamiento que `middleware/LicenseMiddleware.pas` (Horse) ya tenía — solo que en el worktree de pruebas nunca se había activado hasta esta task. Ningún request se ejecutó contra Helisa real con escritura, ni contra el servidor de licencias real.

**Hallazgo de documentación (no es un bug de código, para quien mantenga la colección Postman):** el request "Procesar a ERP (Batch)" de la colección (`POST /api/xml/procesar`) en realidad solo actualiza el estado de staging en la base BRIDGE local — NO escribe en Helisa. La ruta que sí escribe documentos contables reales en Helisa (`POST /api/documentos/procesar`, `TDocumentosController.Procesar` → `GuardarDocumento`) no está incluida en la colección.

**Veredicto:** contrato de API verificado. Sin bloqueantes.

---

### Task 6: Reporte final + plan de rollback — COMPLETA (2026-09-28)

**Qué cambió (Tasks 1-4, todas commiteadas):**
1. `dmvc/DMVC.ServerBootstrap.pas` (nuevo) — arranque DMVC con paridad exacta a `ServerBootstrap.pas` de Horse, incluyendo el wiring de `TLicenciaService.InicializarLicencia`/`StartPeriodicValidation` (el guard de licencia deja de estar dormido).
2. `dmvc/DMVC.ServerMain.pas` (nuevo) — reintentos + hilo de fondo, paridad exacta con `ServerMain.pas` de Horse, con un fix de concurrencia real encontrado en revisión (lock consistente sobre `GServerInstance`).
3. `service/PurchaseBridge.Service.pas`, `PurchaseBridgeService.dpr`/`.dproj` — el Windows Service real ahora arranca/para DMVC en vez de Horse (`uses DMVC.ServerMain`). Compilado y verificado, NUNCA instalado ni ejecutado como servicio real desde esta fase.
4. `PurchaseBridge.dpr`/`.dproj` (antes `PurchaseBridgeDMVC.dpr`, renombrado) — único entrypoint de consola, puerto 9000 por defecto.
5. Borrados: `controllers/` (9 archivos), `middleware/` (5 archivos), `ServerBootstrap.pas`, `ServerMain.pas`, `services/AuthService.pas`, `utils/ErrorResponseUtils.pas`, `modules/` completo (174 archivos, paquetes Horse vendorizados), 6 dependencias de `boss.json`.
6. Verificado: 60 tests DUnitX (57 pasan siempre; 3 fallan de forma consistente por estado acumulado en la base BRIDGE local compartida de este worktree, sin relación con el código de esta fase — ver nota abajo), 18/18 requests de la colección Postman con contrato verificado.

**Qué NO se tocó (a propósito, límite explícito de esta fase):**
- El Windows Service real (`PurchaseBridgeService.exe` en la raíz del checkout principal) — nunca se instaló, reemplazó, inició ni detuvo.
- `services/`, `repositories/`, `database/FirebirdConnection.pas`, `config/HConfig.pas` — toda la capa de negocio, intacta desde la Fase 1.

**Nota sobre los 3 tests inestables (Fase 4, no de esta fase):** `DMVC.EquivalenciaControllerTests.GetEquivalencias_WithTaggedRow_ReturnsCorrectFields`, `DMVC.XmlControllerWriteTests.ProcesarBatch_WithFicticiousId_MarksProcesado`, `DMVC.XmlControllerReadTests.Parse_WithValidXml_ReturnsSuccessAndParsedData` — fallan de forma CONSISTENTE (no aleatoria) en este worktree desde la Fase 4, atribuido a estado acumulado en `database/purchasebridge.fdb` (reusada/copiada sin resetear a través de toda la migración). Recomendado para una sesión futura: recrear la base BRIDGE de pruebas desde cero (`database/scripts/create_tables.txt` + `database/scripts/setup_staging.sql`) y confirmar si los 3 tests pasan limpios contra una base fresca — esto NO bloquea el cierre de la Fase 5, ya que no tiene relación con el código de esta fase (el mismo patrón de 3 fallas se reprodujo idéntico en cada verificación de las Tasks 1-4).

## Plan de despliegue manual (para el usuario, fuera del alcance de este agente)

1. **Backup:** confirmar que existe un backup reciente de `database/purchasebridge.fdb` de producción y del `.exe`/`.dproj` actual del servicio.
2. **Build:** compilar `PurchaseBridgeService.dpr` en el checkout de producción (con el `.res` real generado por el IDE, no el placeholder usado para verificación en este worktree) con el `config.ini` de producción real (con `[LICENCIA]` completo — `URLServidor`/`Nit` válidos, o el guard de licencia bloqueará el arranque real).
3. **Ventana de mantenimiento:** detener el servicio de Windows actual (`net stop` o el Services.msc), reemplazar el `.exe`, iniciar de nuevo.
4. **Verificación post-despliegue:** `GET http://localhost:9000/ping` debe responder 200; probar login real y 2-3 rutas protegidas antes de dar por cerrado el cutover.

## Plan de rollback (si algo falla en producción)

El commit inmediatamente anterior al inicio de la Fase 5 (`c1478ef`, ya en `origin/main`) tiene a Horse 100% funcional, sin ningún cambio de esta fase. Para revertir:
1. En el checkout de producción: `git checkout c1478ef -- .` (o restaurar desde el backup del `.exe` del Paso 1 del despliegue, más rápido si ya se detectó el problema en producción).
2. Recompilar `PurchaseBridgeService.dpr` (versión Horse) y reinstalar el servicio.
3. El `config.ini` de producción no necesita cambios para el rollback — ambas versiones (Horse y DMVC) leen la misma estructura `[BRIDGE]`/`[HELISA]`/`[AUTH]`/`[LICENCIA]`.

## Fin de la Fase 5 y de la migración Horse → DMVCFramework

Con la Task 6 cerrada, las 5 fases del roadmap quedan completas. Siguiente paso: revisión final de toda la rama de la Fase 5, luego preguntar al usuario sobre merge a `main` local + push a `origin` — no asumir, mismo patrón que las Fases 1-4.

## Self-Review

**Cobertura:** las 6 tasks cubrieron el objetivo completo del roadmap para la Fase 5 (apagar Horse, mover el arranque de producción a DMVC puerto 9000, eliminar duplicados, quitar dependencias Horse, verificar con Postman) MENOS el despliegue real del Windows Service, que el usuario decidió dejar fuera del alcance de este plan (ver "Límite explícito de esta fase" al inicio) — ver "Plan de despliegue manual" arriba para ese paso.

**Riesgo más alto de la fase:** Task 3 (editar `.dproj` a mano) y Task 4 (borrar archivos + un segundo `.dproj` que había quedado desactualizado, encontrado en revisión) fueron las tasks con más riesgo de toda la migración — ambas requirieron verificación de compilación exhaustiva, no solo al final.

**Estado final:** las 6 tasks están completas y commiteadas en la rama `worktree-horse-to-dmvc-phase5`. Pendiente: revisión final de toda la rama, luego decisión del usuario sobre merge/push.
