# Horse → DMVCFramework Migration Roadmap

> Este documento es el mapa de las 5 fases. Cada fase tiene (o tendrá) su propio
> plan detallado en `docs/superpowers/plans/`, siguiendo
> `superpowers:writing-plans`, ejecutado con
> `superpowers:subagent-driven-development`. No se escribe el detalle
> paso-a-paso de las 5 fases de una sola vez: cada plan detallado se redacta
> cuando la fase anterior ya está mergeada y verificada, para no planear sobre
> supuestos que la fase previa pudo invalidar.

**Proyecto de referencia:** F:\Proyectos\NexoPago\Backend (DMVCFramework 3.4.3
"Aluminium", instalado como paquetes IDE `dmvcframeworkDT`/`dmvcframeworkRT` +
unit search path a las fuentes).

**Framework origen:** Horse 3.1.9 vendorizado vía Boss en `modules/`.

**Restricciones globales**
- No romper producción: `PurchaseBridge.dpr` / `PurchaseBridgeService.dpr`
  (Horse) siguen funcionando hasta la Fase 5 (cutover).
- Motor de datos sin cambios: Firebird vía FireDAC (`database/FirebirdConnection.pas`),
  reutilizado tal cual por los controllers/services migrados.
- `AuthService`, `LicenseService` y el resto de la capa de negocio en
  `services/`/`repositories/` NO se reescriben — solo cambia el "pegamento" HTTP
  (controllers, middlewares, serialización).
- Todo código Delphi nuevo usa DUnitX para TDD (no existía framework de test
  automatizado en este repo; se introduce en la Fase 1).
- Compilador: `C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\DCC32.EXE`.
  DUnitX vendorizado en `C:\Program Files (x86)\Embarcadero\Studio\23.0\source\DunitX`.
  Fuentes de DMVCFramework en `C:\Users\Alejo\Downloads\delphimvcframework-master\sources`.
  Compilar contra DMVCFramework requiere además estas rutas `-U` (dependencias
  vendorizadas junto al framework, descubierto en la Fase 1 Task 2):
  `C:\Users\Alejo\Downloads\delphimvcframework-master\lib\loggerpro` y
  `C:\Users\Alejo\Downloads\delphimvcframework-master\lib\swagdoc\Source`.
- Regla de nombres de unidad Delphi: DCC32 exige que el nombre de unidad
  coincida EXACTO con el nombre físico del archivo, incluidos los puntos. Un
  unit `A.B` debe vivir en un archivo `A.B.pas` (no `B.pas`), sin excepción —
  ver [[feedback_delphi_unit_naming]] en memoria del proyecto.

---

## Fase 1 — Esqueleto DMVC en paralelo (sin tocar Horse)

**Objetivo:** Un segundo servidor DMVC mínimo (`/ping`), corriendo en un puerto
distinto (9091), compilable y con test automatizado, sin tocar ningún archivo
de Horse ni el servicio de Windows.

**Archivos nuevos:** `dmvc/DMVC.WebModule.Main.pas` (sin `.dfm`, WebModule 100% por código),
`dmvc/Controllers/DMVC.Controllers.PingController.pas`, `PurchaseBridgeDMVC.dpr`,
`tests/PurchaseBridge.Tests.dpr`, `tests/Sample/SanityTests.pas`,
`tests/DMVC/DMVC.TestServerProcess.pas`, `tests/DMVC/DMVC.PingControllerTests.pas`
(sin `.dproj` — verificación vía DCC32.EXE directo, ver Restricciones globales).

**Plan detallado:** `2026-09-12-horse-to-dmvc-phase1-skeleton.md` (completo, mergeado).

## Fase 2 — Controllers de bajo riesgo

**Objetivo:** Migrar `EquivalenciaController` (list/create/delete) y
`ProveedorController` (get-by-nit) a clases `TMVCController` con DTOs propios,
usando `EMVCException` con el shape de error estándar de DMVC (decisión del
usuario, 2026-09-25 — Horse's `{success,message,detail}` no se replica).

**Decisión de arquitectura (NO DI)**: a diferencia de NexoPago (que usa
`TMVCRepository<T>`/DI), los controllers de esta fase llaman DIRECTAMENTE a
las unidades procedurales existentes `EquivalenciaService.pas`/
`ProveedorRepository.pas` — no hay entidades ActiveRecord que envolver en este
repo, y la Restricción Global prohíbe reescribirlas. Serialización vía DTOs
con `[MVCNameCase(ncCamelCase)]` (RTTI nativo de DMVC), sin `TJSONObject` a
mano salvo en `TPingController` (Fase 1, endpoint trivial sin DTO).

**Cambios de status HTTP vs. Horse (pendiente para el frontend en la Fase 5)**:
`CreateEquivalencia` responde 200 donde Horse respondía 201; `DeleteEquivalencia`
responde 404 en not-found donde Horse respondía 200 con `{success:false}`.

**Archivos:** `dmvc/Controllers/DMVC.Controllers.EquivalenciaController.pas`,
`dmvc/Controllers/DMVC.Controllers.ProveedorController.pas`,
`dmvc/DTOs/DMVC.DTOs.Equivalencia.pas`, `dmvc/DTOs/DMVC.DTOs.EquivalenciaCreate.pas`,
`dmvc/DTOs/DMVC.DTOs.Proveedor.pas`, tests en `tests/DMVC/` (6 tests DUnitX
en total con las Fase 1: sanity, ping, 3 de Equivalencia, 1 de Proveedor).

**Plan detallado:** `2026-09-25-horse-to-dmvc-phase2-controllers.md` (completo, mergeado).

**Depende de:** Fase 1 (WebModule/engine ya creado).

## Fase 3 — Middlewares transversales

**Objetivo:** Portar CORS dinámico, logger HTTP, guard de licencia y auth
(Bearer/JWT) a `IMVCMiddleware`, reusando `AuthService.ValidateToken` y
`LicenseService.SistemaBloqueado` sin reescribirlos. Incluye el middleware de
archivos estáticos (SPA) con `Handled := True` en vez de
`EHorseCallbackInterrupted`.

**Nota de riesgo de auth heredado de Horse (decidir explícitamente antes de
implementar)**: en Horse, `AuthMiddleware.IsPublicFrontendPath` trata como
público todo lo que NO empiece por `/api` (`middleware/AuthMiddleware.pas`).
La Fase 2 replicó fielmente ambas variantes de ruta de Horse (`/equivalencia`
y `/api/equivalencia`, etc.) sin decidir aún cómo se protegerán con auth. Si
esta fase porta ese mismo predicado de "público si no empieza por /api" sin
cambios, el servidor DMVC heredaría un DELETE de Equivalencia y un GET de
Proveedor SIN autenticación en sus variantes de ruta "bare". Además, como los
controllers ya usan `[MVCPath('/')]` a nivel de clase (obligatorio, ver nota
de la Fase 1/2), NO se puede proteger por prefijo de ruta a nivel de
controller — hay que decidir la protección por ruta/acción individual, o
eliminar las variantes "bare" y dejar solo `/api/...`. Los tests DUnitX de
la Fase 2 no envían header `Authorization` — el arnés de tests necesitará
soporte para tokens Bearer en la Fase 3 (y `/ping` debe seguir siendo público
para que `WaitForReady` funcione).

**Archivos:** `dmvc/Middleware/DMVC.Middleware.AuthMiddleware.pas`,
`dmvc/Middleware/DMVC.Middleware.CORSMiddleware.pas`,
`dmvc/Middleware/DMVC.Middleware.LicenseMiddleware.pas`,
`dmvc/Middleware/DMVC.Middleware.HttpLoggerMiddleware.pas`,
`dmvc/Middleware/DMVC.Middleware.StaticFilesMiddleware.pas` (nombres con
namespace punteado consistente con el resto de `dmvc/`, ver regla de nombres
de unidad en Restricciones globales — un archivo `AuthMiddleware.pas` sin
puntos NO puede declarar `unit DMVC.Middleware.AuthMiddleware;`).

**Depende de:** Fase 2 (necesita al menos un controller protegido para probar
auth end-to-end).

**Plan detallado:** `2026-09-26-horse-to-dmvc-phase3-middlewares.md` (completo, mergeado).

## Fase 4 — Controllers de alto riesgo/volumen (completa, mergeada 2026-09-28)

**Objetivo:** Migrar `HelisaController`, `LicenciaController`,
`XmlValidationController`, `ImportController`, `DocumentosController`,
`XmlController` (9 rutas, dividido en Task 6a lectura / 6b escritura por
tamaño). `AuthController` NO se migró como controller propio — su única ruta
(`POST /auth/login`) ya estaba completamente superada por el middleware JWT de
la Fase 3; en su lugar se agregó `GET /api/auth/me` (nuevo, Task 5) para
reemplazar el payload `{usuario,empresa}` que el login de Horse solía incluir.

**Incluye el caso especial de upload binario** (`horse-octet-stream` en Horse
→ `Context.Request.Files` de `TMVCWebRequest` en DMVC, Task 6b).

**6 tasks, ejecutadas una por una con commit + aprobación entre cada una** (a
pedido del usuario, sesión con cuota semanal ajustada). Cada task pasó por
implementador + revisor + fix antes de commitear. Revisión final de toda la
rama confirmó cero archivos Horse tocados en las 6 tasks. Dos bugs reales
encontrados en código Horse PREEXISTENTE (no tocados, fuera de alcance,
documentados en memoria del proyecto para seguimiento aparte):
`services/XMLFacturaService.pas` probablemente falla en silencio con facturas
DIAN reales (no maneja el sobre `AttachedDocument` ni namespaces `cac`/`cbc`
reales), y `services/HelisaService.pas`'s `ObtenerSiglaUnidad` dispara un bug
real del driver FireDAC/Firebird ("Attempt to reclose a closed cursor") con
códigos de unidad inexistentes.

**Plan detallado:** `2026-09-26-horse-to-dmvc-phase4-controllers.md` (completo, mergeado).

**Depende de:** Fase 3 (necesita todos los middlewares ya migrados).

## Fase 5 — Cutover

**Objetivo:** Apagar Horse. Mover `ServerMain.pas`/`PurchaseBridgeService.pas`
para arrancar el engine DMVC en el puerto 9000 (el de producción), eliminar
`PurchaseBridge.dpr`/`PurchaseBridgeDMVC.dpr` duplicados dejando un único
entrypoint, quitar dependencias Horse de `boss.json` y `modules/`, verificar
con `PurchaseBridge.postman_collection.json` contra el servidor DMVC.

**Pendiente de la Fase 3 (guard de licencia dormido)**: `DMVC.Middleware.License.pas`
(Fase 3, Task 2) está correctamente implementado pero es un no-op en el
servidor paralelo — nada en `PurchaseBridgeDMVC.dpr` llama a
`TLicenciaService.InicializarLicencia`/`StartPeriodicValidation` (Horse sí lo
hace, `ServerBootstrap.pas:178-179`), así que `FSistemaBloqueado` nunca se
activa. Esto fue deliberado: `InicializarLicencia` hace una llamada de red real
y bloquea todo el sistema (`BloquearSistema`, fail-closed) si `[LICENCIA]
URLServidor` no está configurado — activarlo en el entorno de pruebas de las
Fases 3-4 habría roto todos los tests. En la Fase 5, con el `config.ini` de
producción real (con `[LICENCIA]` válido), agregar la misma llamada a
`InicializarLicencia`/`StartPeriodicValidation` en el arranque de
`PurchaseBridgeDMVC.dpr` (o su equivalente tras el cutover), replicando el
orden de `ServerBootstrap.pas`.

**Depende de:** Fase 4 completa y verificada.

---

## Progreso

- [x] Fase 1 — Esqueleto DMVC en paralelo
- [x] Fase 2 — Controllers de bajo riesgo
- [x] Fase 3 — Middlewares transversales
- [x] Fase 4 — Controllers de alto riesgo/volumen
- [x] Fase 5 — Cutover
