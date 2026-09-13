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

---

## Fase 1 — Esqueleto DMVC en paralelo (sin tocar Horse)

**Objetivo:** Un segundo servidor DMVC mínimo (`/ping`), corriendo en un puerto
distinto (9091), compilable y con test automatizado, sin tocar ningún archivo
de Horse ni el servicio de Windows.

**Archivos nuevos:** `dmvc/DMVC.WebModule.pas/.dfm`, `dmvc/Controllers/PingController.pas`,
`PurchaseBridgeDMVC.dpr`, `PurchaseBridgeDMVC.dproj`, `tests/PurchaseBridge.Tests.dpr`,
`tests/PurchaseBridge.Tests.dproj`, `tests/DMVC/PingControllerTests.pas`.

**Plan detallado:** `2026-09-12-horse-to-dmvc-phase1-skeleton.md` (listo, siguiente paso).

## Fase 2 — Controllers de bajo riesgo

**Objetivo:** Migrar `EquivalenciaController` y `ProveedorController` (rutas
simples, sin upload de archivos) a clases `TMVCController` con DTOs propios,
validando el patrón de error `EMVCException` y el DI por constructor con los
`services`/`repositories` existentes.

**Archivos:** `dmvc/Controllers/EquivalenciaController.pas`,
`dmvc/Controllers/ProveedorController.pas`, `dmvc/DTOs/EquivalenciaDTOs.pas`,
`dmvc/DTOs/ProveedorDTOs.pas`, tests correspondientes en `tests/DMVC/`.

**Depende de:** Fase 1 (WebModule/engine ya creado).

## Fase 3 — Middlewares transversales

**Objetivo:** Portar CORS dinámico, logger HTTP, guard de licencia y auth
(Bearer/JWT) a `IMVCMiddleware`, reusando `AuthService.ValidateToken` y
`LicenseService.SistemaBloqueado` sin reescribirlos. Incluye el middleware de
archivos estáticos (SPA) con `Handled := True` en vez de
`EHorseCallbackInterrupted`.

**Archivos:** `dmvc/Middleware/AuthMiddleware.pas`, `dmvc/Middleware/CORSMiddleware.pas`,
`dmvc/Middleware/LicenseMiddleware.pas`, `dmvc/Middleware/HttpLoggerMiddleware.pas`,
`dmvc/Middleware/StaticFilesMiddleware.pas`.

**Depende de:** Fase 2 (necesita al menos un controller protegido para probar
auth end-to-end).

## Fase 4 — Controllers de alto riesgo/volumen

**Objetivo:** Migrar `AuthController`, `HelisaController`, `DocumentosController`,
`ImportController`, `XmlController` (9 rutas), `XmlValidationController` y
`LicenciaController`. Incluye el caso especial de upload binario
(`horse-octet-stream` → manejo nativo de `TMVCWebRequest` en DMVC).

**Depende de:** Fase 3 (necesita todos los middlewares ya migrados).

## Fase 5 — Cutover

**Objetivo:** Apagar Horse. Mover `ServerMain.pas`/`PurchaseBridgeService.pas`
para arrancar el engine DMVC en el puerto 9000 (el de producción), eliminar
`PurchaseBridge.dpr`/`PurchaseBridgeDMVC.dpr` duplicados dejando un único
entrypoint, quitar dependencias Horse de `boss.json` y `modules/`, verificar
con `PurchaseBridge.postman_collection.json` contra el servidor DMVC.

**Depende de:** Fase 4 completa y verificada.

---

## Progreso

- [ ] Fase 1 — Esqueleto DMVC en paralelo
- [ ] Fase 2 — Controllers de bajo riesgo
- [ ] Fase 3 — Middlewares transversales
- [ ] Fase 4 — Controllers de alto riesgo/volumen
- [ ] Fase 5 — Cutover
