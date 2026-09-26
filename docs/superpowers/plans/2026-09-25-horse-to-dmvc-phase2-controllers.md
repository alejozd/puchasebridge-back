# Fase 2 — Controllers de bajo riesgo (Equivalencia, Proveedor) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrar `EquivalenciaController` (3 rutas: list/create/delete) y `ProveedorController` (1 ruta: get-by-nit) de Horse a DMVCFramework, agregándolos al servidor paralelo `PurchaseBridgeDMVC.exe` (puerto 9091) creado en la Fase 1, sin tocar Horse ni reescribir la lógica de negocio existente (`services/EquivalenciaService.pas`, `repositories/ProveedorRepository.pas`).

**Architecture:** Los nuevos controllers DMVC (`TEquivalenciaController`, `TProveedorController`) llaman DIRECTAMENTE a las unidades procedurales `EquivalenciaService`/`ProveedorRepository` ya existentes — NO se introduce una capa de DI/interfaces/ActiveRecord nueva, porque esas unidades son funciones sueltas sobre `TFDQuery` crudo (no hay entidades ActiveRecord que envolver) y la Restricción Global del roadmap prohíbe reescribirlas. Esto difiere del patrón de NexoPago (que sí usa `TMVCRepository<T>`/DI) solo porque la forma de la capa de datos es distinta — no es un patrón nuevo a mantener, es una adaptación puntual.

**Tech Stack:** Delphi (RAD Studio 23.0), DMVCFramework 3.4.3 Aluminium, DUnitX. Mismas rutas de compilación de la Fase 1 (ver Global Constraints).

## Global Constraints

- No modificar ningún archivo existente de Horse (`controllers/EquivalenciaController.pas`, `controllers/ProveedorController.pas`, `services/EquivalenciaService.pas`, `repositories/ProveedorRepository.pas`, `ServerBootstrap.pas`, `modules/`, etc.) — estas unidades siguen sirviendo al servidor Horse en el puerto 9000 sin cambios.
- Las funciones procedurales `EquivalenciaService.ListarEquivalencias/CrearEquivalencia/EliminarEquivalencia` y `ProveedorRepository.ObtenerProveedorPorNit` se **reutilizan tal cual**, llamándolas directamente desde los controllers DMVC nuevos. No se crean interfaces `IEquivalenciaService`/`IProveedorService` ni se registra DI para ellas.
- **Formato de error**: por decisión explícita del usuario (2026-09-25), los controllers migrados usan `EMVCException.Create(HTTP_STATUS.XXX, 'mensaje')` con el shape de error ESTÁNDAR de DMVCFramework — NO se replica el shape legado `{success:false, message, detail}` de Horse. El frontend se adaptará en la Fase 5 (cutover).
- **Shape de respuesta de éxito**: se usa el idiomático de DMVC (DTOs serializados con `[MVCNameCase(ncCamelCase)]`, listados como array JSON plano) en vez de los wrappers ad-hoc de Horse (`{"equivalencias": [...]}`). También se normaliza la inconsistencia de casing preexistente en Horse (`subcodigoH` en el output de `List` vs `subCodigoH` en el input de `Create` — ver hallazgo de exploración) a `subCodigoH` consistente en ambos DTOs. Esto es intencional, no un descuido.
- **Comportamiento de negocio interno preservado tal cual, incluyendo una inconsistencia preexistente**: `ListarEquivalencias`/`EliminarEquivalencia` reciben los query-params `referenciaP`/`unidadP` pero internamente filtran por las columnas `REFERENCIAH`/`UNIDADH` (no `REFERENCIAP`/`UNIDADP`) — esto viene del Horse original (`EquivalenciaService.pas` líneas ~ListarEquivalencias/EliminarEquivalencia) y NO se corrige en esta fase (es un cambio de comportamiento, no de framework — fuera de alcance). Cada Task de este plan que toque estas funciones debe dejar un comentario explícito en el código nuevo señalando esto.
- Rutas: cada acción migrada expone AMBAS variantes (`/xxx` y `/api/xxx`) igual que Horse, usando dos atributos `[MVCPath]` apilados sobre el mismo método.
- Tests contra datos reales: los tests de `Create`/`Delete` de Equivalencia usan valores de `referenciaP`/`unidadP` claramente marcados como de prueba (prefijo `__PHASE2TEST__`) y limpian lo que crean (create → verificar → delete → verificar). El test de Proveedor usa un NIT claramente inexistente (`'000000000-TEST'`) y solo verifica la rama `existe=false` — no depende de datos reales de Helisa.
- Registro de controllers nuevos: se agregan a `dmvc/DMVC.WebModule.Main.pas` (mismo `TMVCEngine` de la Fase 1, mismo puerto 9091), nunca un WebModule/engine nuevo.
- Compilador y rutas `-U`/`-I`: idénticas a la Fase 1 (ver `docs/superpowers/plans/2026-09-12-horse-to-dmvc-roadmap.md`, sección Restricciones globales) — DCC32 en `C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\DCC32.EXE`, fuentes DMVC en `C:\Users\Alejo\Downloads\delphimvcframework-master\sources` + `lib\loggerpro` + `lib\swagdoc\Source`.
- Regla de nombres de unidad Delphi (de la Fase 1): el nombre de unidad debe coincidir EXACTO con el nombre físico del archivo, incluidos los puntos. Todos los archivos nuevos de este plan ya están nombrados correctamente para esto (verificar antes de compilar si algo no cuadra).
- El arnés de pruebas es el mismo `tests/PurchaseBridge.Tests.dpr` de la Fase 1 — cada Task agrega sus unidades de test al `uses` existente, nunca crea un runner nuevo. El patrón `TTestServerProcess` (`tests/DMVC/DMVC.TestServerProcess.pas`) se reutiliza tal cual para lanzar `PurchaseBridgeDMVC.exe` y esperar a que responda — no se modifica.

---

### Task 1: DTOs de Equivalencia + ruta GET (listado)

**Files:**
- Create: `dmvc/DTOs/DMVC.DTOs.Equivalencia.pas`
- Create: `dmvc/Controllers/DMVC.Controllers.EquivalenciaController.pas`
- Modify: `dmvc/DMVC.WebModule.Main.pas` (registrar el nuevo controller)
- Create: `tests/DMVC/DMVC.EquivalenciaControllerTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr` (agregar la unidad de test al `uses`)

**Interfaces:**
- Consumes: `EquivalenciaService.ListarEquivalencias(const AReferenciaH, AUnidadH: string; ALimite: Integer): TFDQuery` (unidad existente `services/EquivalenciaService.pas`, sin cambios). `TTestServerProcess` de la Fase 1 (`tests/DMVC/DMVC.TestServerProcess.pas`) para lanzar el server en los tests.
- Produces: `TEquivalenciaDTO` (campos `CodigoH: Integer`, `SubCodigoH: Integer`, `NombreH: String`, `ReferenciaH: String`, `UnidadH: String`, `ReferenciaP: String`, `UnidadP: String`, `Factor: Double`) — la Task 2 reutiliza este mismo DTO para el body de entrada del `POST` (ver nota en Task 2 sobre por qué se necesita un DTO de entrada separado). `TEquivalenciaController` con la ruta GET ya registrada — la Task 2 AGREGA métodos a esta misma clase (no crea una nueva).

- [ ] **Step 1: Escribir el DTO**

Crear `dmvc/DTOs/DMVC.DTOs.Equivalencia.pas`:

```pascal
unit DMVC.DTOs.Equivalencia;

interface

uses
  MVCFramework.Serializer.Commons;

type
  [MVCNameCase(ncCamelCase)]
  TEquivalenciaDTO = class
  private
    fCodigoH: Integer;
    fSubCodigoH: Integer;
    fNombreH: String;
    fReferenciaH: String;
    fUnidadH: String;
    fReferenciaP: String;
    fUnidadP: String;
    fFactor: Double;
  public
    property CodigoH: Integer read fCodigoH write fCodigoH;
    property SubCodigoH: Integer read fSubCodigoH write fSubCodigoH;
    property NombreH: String read fNombreH write fNombreH;
    property ReferenciaH: String read fReferenciaH write fReferenciaH;
    property UnidadH: String read fUnidadH write fUnidadH;
    property ReferenciaP: String read fReferenciaP write fReferenciaP;
    property UnidadP: String read fUnidadP write fUnidadP;
    property Factor: Double read fFactor write fFactor;
  end;

end.
```

- [ ] **Step 2: Escribir el controller con la ruta de listado**

Crear `dmvc/Controllers/DMVC.Controllers.EquivalenciaController.pas`:

```pascal
unit DMVC.Controllers.EquivalenciaController;

interface

uses
  MVCFramework, MVCFramework.Commons,
  System.Generics.Collections,
  DMVC.DTOs.Equivalencia;

type
  TEquivalenciaController = class(TMVCController)
  public
    [MVCPath('/equivalencias')]
    [MVCPath('/api/equivalencias')]
    [MVCHTTPMethod([httpGET])]
    function GetEquivalencias(
      const [MVCFromQueryString('referenciaP', '')] AReferenciaP: String;
      const [MVCFromQueryString('unidadP', '')] AUnidadP: String;
      const [MVCFromQueryString('limite', 50)] ALimite: Integer): TObjectList<TEquivalenciaDTO>;
  end;

implementation

uses
  EquivalenciaService;

function TEquivalenciaController.GetEquivalencias(const AReferenciaP, AUnidadP: String;
  const ALimite: Integer): TObjectList<TEquivalenciaDTO>;
var
  LQuery: TObject; // placeholder de tipo, ver nota abajo
begin
  Result := TObjectList<TEquivalenciaDTO>.Create(True);
  // NOTA: EquivalenciaService.ListarEquivalencias(AReferenciaH, AUnidadH, ALimite) filtra
  // internamente por las columnas REFERENCIAH/UNIDADH, no REFERENCIAP/UNIDADP, pese a que
  // el nombre de los parametros sugiere lo contrario. Este comportamiento viene de Horse
  // (services/EquivalenciaService.pas) y se preserva tal cual a proposito: no es un bug de
  // esta migracion, es un comportamiento preexistente fuera de alcance de la Fase 2.
end;

end.
```

**IMPORTANTE — no copiar el cuerpo de `GetEquivalencias` tal cual**: el bloque de arriba tiene una variable `LQuery: TObject` de relleno porque este plan no puede predecir con certeza si `TFDQuery` requiere una unit adicional en el `uses` de este archivo (`FireDAC.Comp.Client`) sin verificarlo en el compilador real. Implementa así:

```pascal
uses
  EquivalenciaService, FireDAC.Comp.Client;

function TEquivalenciaController.GetEquivalencias(const AReferenciaP, AUnidadP: String;
  const ALimite: Integer): TObjectList<TEquivalenciaDTO>;
var
  LQuery: TFDQuery;
  LItem: TEquivalenciaDTO;
begin
  Result := TObjectList<TEquivalenciaDTO>.Create(True);
  // Ver nota de comportamiento preexistente en el Global Constraints de este plan:
  // EquivalenciaService.ListarEquivalencias filtra por REFERENCIAH/UNIDADH, no por
  // REFERENCIAP/UNIDADP, aunque asi se llamen los query-params de esta ruta. Preservado
  // a proposito (viene de Horse, no es un bug introducido aqui).
  LQuery := EquivalenciaService.ListarEquivalencias(AReferenciaP, AUnidadP, ALimite);
  try
    while not LQuery.Eof do
    begin
      LItem := TEquivalenciaDTO.Create;
      LItem.CodigoH := LQuery.FieldByName('CODIGOH').AsInteger;
      LItem.SubCodigoH := LQuery.FieldByName('SUBCODIGOH').AsInteger;
      LItem.NombreH := LQuery.FieldByName('NOMBREH').AsString;
      LItem.ReferenciaH := LQuery.FieldByName('REFERENCIAH').AsString;
      LItem.UnidadH := LQuery.FieldByName('UNIDADH').AsString;
      LItem.ReferenciaP := LQuery.FieldByName('REFERENCIAP').AsString;
      LItem.UnidadP := LQuery.FieldByName('UNIDADP').AsString;
      LItem.Factor := LQuery.FieldByName('FACTOR').AsFloat;
      Result.Add(LItem);
      LQuery.Next;
    end;
  finally
    LQuery.Free;
  end;
end;
```

- [ ] **Step 3: Registrar el controller en el WebModule**

Modificar `dmvc/DMVC.WebModule.Main.pas`. El archivo actual (Fase 1) es:

```pascal
implementation

uses
  DMVC.Controllers.PingController;

constructor TPurchaseBridgeDMVCWebModule.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEngine := TMVCEngine.Create(Self);
  FEngine.AddController(TPingController);
end;
```

Cambiar a:

```pascal
implementation

uses
  DMVC.Controllers.PingController,
  DMVC.Controllers.EquivalenciaController;

constructor TPurchaseBridgeDMVCWebModule.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEngine := TMVCEngine.Create(Self);
  FEngine.AddController(TPingController);
  FEngine.AddController(TEquivalenciaController);
end;
```

- [ ] **Step 4: Escribir el test que falla (RED)**

Antes de escribir el test, revisa `tests/DMVC/DMVC.PingControllerTests.pas` de la Fase 1 (ya existe en este worktree) para copiar el patrón exacto de `Setup`/`TearDown` con `TTestServerProcess` — no lo reinventes.

Crear `tests/DMVC/DMVC.EquivalenciaControllerTests.pas`:

```pascal
unit DMVC.EquivalenciaControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TEquivalenciaControllerTests = class
  private
    FServer: TTestServerProcess;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetEquivalencias_ReturnsJsonArray;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, IdHTTP;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TEquivalenciaControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
end;

procedure TEquivalenciaControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TEquivalenciaControllerTests.GetEquivalencias_ReturnsJsonArray;
var
  LHttp: TIdHTTP;
  LBody: string;
  LJson: TJSONValue;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LBody := LHttp.Get(Format('http://localhost:%d/api/equivalencias?limite=5', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LBody);
    try
      Assert.IsTrue(LJson is TJSONArray, 'La respuesta debe ser un array JSON, no un objeto envuelto');
    finally
      LJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

end.
```

Modificar `tests/PurchaseBridge.Tests.dpr`, agregando al `uses` (después de la última unidad de test de la Fase 1, `DMVC.PingControllerTests in 'DMVC\DMVC.PingControllerTests.pas'`):

```pascal
  DMVC.EquivalenciaControllerTests in 'DMVC\DMVC.EquivalenciaControllerTests.pas';
```
(mover el `;` final del `uses` a esta línea, igual que se hizo en la Fase 1 Task 2).

- [ ] **Step 5: Compilar el runner de tests y confirmar RED**

Run (usa las mismas rutas `-U`/`-I` de DUnitX de la Fase 1 — ver `docs/superpowers/plans/2026-09-12-horse-to-dmvc-phase1-skeleton.md` Task 1 Step 3 si necesitas el comando completo):
```
"C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\DCC32.EXE" -B -Q ^
  -U"C:\Program Files (x86)\Embarcadero\Studio\23.0\source\DunitX" ^
  -I"C:\Program Files (x86)\Embarcadero\Studio\23.0\source\DunitX" ^
  -E"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase2\tests\bin" ^
  "F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase2\tests\PurchaseBridge.Tests.dpr"
```
Expected: `0 Error(s)` (el test compila porque solo depende de `TTestServerProcess`, no del controller nuevo).

Run: `"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase2\tests\bin\PurchaseBridge.Tests.exe" -exitbehavior:continue < NUL`
Expected: el servidor arranca bien (Fase 1 sigue viva) pero `GetEquivalencias_ReturnsJsonArray` FALLA porque `/api/equivalencias` todavía no existe en el server compilado (404) — esto es el RED esperado. Si el servidor no ha sido recompilado con el controller nuevo, este test debe fallar; si por error ya pasa, algo está mal (verifica que `bin\PurchaseBridgeDMVC.exe` no esté ya reconstruido con el Step 6 antes de este punto).

- [ ] **Step 6: Compilar el servidor con el controller nuevo**

Run:
```
"C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\DCC32.EXE" -B -Q ^
  -U"C:\Users\Alejo\Downloads\delphimvcframework-master\sources";"C:\Users\Alejo\Downloads\delphimvcframework-master\lib\loggerpro";"C:\Users\Alejo\Downloads\delphimvcframework-master\lib\swagdoc\Source";"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase2\dmvc";"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase2\dmvc\Controllers";"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase2\dmvc\DTOs";"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase2\services";"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase2\database" ^
  -I"C:\Users\Alejo\Downloads\delphimvcframework-master\sources" ^
  -E"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase2\bin" ^
  "F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase2\PurchaseBridgeDMVC.dpr"
```
Nota: se agregaron `services` y `database` al `-U` porque `EquivalenciaController.pas`(DMVC) ahora depende de `EquivalenciaService.pas`, que a su vez depende de `FirebirdConnection.pas`. Si DCC32 se queja de otra unit no encontrada (p.ej. `HConfig.pas`, `uPaths.pas`), agrega también `config` y `utils` a esta lista de `-U` — son las carpetas donde viven esas dependencias transitivas en este repo.

Expected: `0 Error(s)`.

- [ ] **Step 7: Re-ejecutar el test — debe pasar (GREEN)**

Run: `"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase2\tests\bin\PurchaseBridge.Tests.exe" -exitbehavior:continue < NUL`
Expected: todos los tests pasan (Fase 1: sanity + ping; Fase 2: `GetEquivalencias_ReturnsJsonArray`), 0 failed.

- [ ] **Step 8: Verificación manual**

Run: el server (`bin\PurchaseBridgeDMVC.exe`), en otra terminal: `curl http://localhost:9091/api/equivalencias` y `curl http://localhost:9091/equivalencias` (ambas rutas deben responder 200 con un array JSON, aunque esté vacío).

- [ ] **Step 9: Commit**

```bash
git add dmvc/DTOs/DMVC.DTOs.Equivalencia.pas dmvc/Controllers/DMVC.Controllers.EquivalenciaController.pas dmvc/DMVC.WebModule.Main.pas tests/DMVC/DMVC.EquivalenciaControllerTests.pas tests/PurchaseBridge.Tests.dpr
git commit -m "feat: migrate Equivalencia list endpoint to DMVCFramework"
```

---

### Task 2: Equivalencia — rutas POST (crear) y DELETE

**Files:**
- Create: `dmvc/DTOs/DMVC.DTOs.EquivalenciaCreate.pas`
- Modify: `dmvc/Controllers/DMVC.Controllers.EquivalenciaController.pas` (agregar 2 métodos a la clase existente)
- Modify: `tests/DMVC/DMVC.EquivalenciaControllerTests.pas` (agregar 1 test)

**Interfaces:**
- Consumes: `EquivalenciaService.CrearEquivalencia(ACodigoH, ASubCodigoH: Integer; ANombreH, AReferenciaP, AUnidadP, AUnidadH, AReferenciaH: string; AFactor: Double): Integer` y `EquivalenciaService.EliminarEquivalencia(const AReferenciaH, AUnidadH: string): Boolean` (unidad existente, sin cambios). `TEquivalenciaController` de la Task 1 (se le agregan métodos, no se recrea la clase).
- Produces: nada nuevo que otras tasks consuman — Task 3 es independiente (Proveedor).

**Nota de por qué un DTO de entrada separado**: `TEquivalenciaDTO` (Task 1) representa una fila COMPLETA con `ID` implícito de la base de datos; el body de `POST /equivalencia` no incluye `ID` y necesita distinguir "campo no enviado" de "campo enviado en 0/vacío" para replicar la validación exacta de Horse (`codigoH is required`, `referenciaP cannot be empty`, etc.). Por eso los campos van con `Nullable*` en el DTO de entrada.

- [ ] **Step 1: Escribir el DTO de entrada**

Crear `dmvc/DTOs/DMVC.DTOs.EquivalenciaCreate.pas`:

```pascal
unit DMVC.DTOs.EquivalenciaCreate;

interface

uses
  MVCFramework.Serializer.Commons,
  MVCFramework.Nullables;

type
  [MVCNameCase(ncCamelCase)]
  TEquivalenciaCreateDTO = class
  private
    fCodigoH: NullableInt32;
    fSubCodigoH: NullableInt32;
    fNombreH: NullableString;
    fReferenciaH: NullableString;
    fUnidadH: NullableString;
    fReferenciaP: NullableString;
    fUnidadP: NullableString;
    fFactor: NullableDouble;
  public
    property CodigoH: NullableInt32 read fCodigoH write fCodigoH;
    property SubCodigoH: NullableInt32 read fSubCodigoH write fSubCodigoH;
    property NombreH: NullableString read fNombreH write fNombreH;
    property ReferenciaH: NullableString read fReferenciaH write fReferenciaH;
    property UnidadH: NullableString read fUnidadH write fUnidadH;
    property ReferenciaP: NullableString read fReferenciaP write fReferenciaP;
    property UnidadP: NullableString read fUnidadP write fUnidadP;
    property Factor: NullableDouble read fFactor write fFactor;
  end;

end.
```

- [ ] **Step 2: Escribir el test que falla (RED) para create+delete**

Modificar `tests/DMVC/DMVC.EquivalenciaControllerTests.pas`: agregar un método de test nuevo a la clase `TEquivalenciaControllerTests` (junto a `GetEquivalencias_ReturnsJsonArray`, misma clase, mismo `Setup`/`TearDown`):

En la sección `type`, dentro de `TEquivalenciaControllerTests`, agregar:
```pascal
    [Test]
    procedure CreateThenDeleteEquivalencia_RoundTrips;
```

En `implementation`, agregar el cuerpo:
**CORRECCIÓN (post Task 1, con evidencia real de la base de pruebas — no copiar los valores originales de abajo, usar los corregidos):**
1. `UNIDADH` es `VARCHAR(5)` en el schema real (`database/scripts/create_tables.txt`) — el tag `__PHASE2TEST__UNI` (18 caracteres) NO CABE. Usar un tag corto de máximo 5 caracteres, p.ej. `P2T2` (el fix de la Task 1 ya usó `P2TU` para su propio tag — usa uno DISTINTO para no chocar con filas que ese test pueda dejar, aunque ese test limpia después de sí mismo).
2. Más importante — **`referenciaH`/`unidadH` deben enviarse en el body con el MISMO valor que `referenciaP`/`unidadP`**. Motivo: `EliminarEquivalencia` (llamada por el `DELETE`) filtra internamente por las columnas `REFERENCIAH`/`UNIDADH` (ver la nota de comportamiento preexistente en Global Constraints) — si el POST de este test solo llena `REFERENCIAP`/`UNIDADP` y deja `REFERENCIAH`/`UNIDADH` vacíos (comportamiento por defecto si no se envían en el body), el `DELETE` posterior no va a encontrar la fila (busca por `REFERENCIAH`/`UNIDADH`, que quedaron vacíos) y el test fallaría con 404 en el `Delete`. Esto no es un bug del test, es una consecuencia directa de la inconsistencia preexistente que este plan decidió preservar — el test tiene que trabajar CON ella, no ignorarla.

```pascal
procedure TEquivalenciaControllerTests.CreateThenDeleteEquivalencia_RoundTrips;
const
  TEST_REF = 'P2T2REF'; // cabe en REFERENCIAP(50)/REFERENCIAH(40)
  TEST_UNI = 'P2T2'; // 4 caracteres — DEBE caber en UNIDADH VARCHAR(5)
var
  LHttp: TIdHTTP;
  LBodyJson: TJSONObject;
  LPostBody: TStringStream;
  LResponse: string;
  LDeleteUrl: string;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    // 1. Crear — referenciaH/unidadH se envian IGUALES a referenciaP/unidadP a
    // proposito, para que el DELETE (que filtra por REFERENCIAH/UNIDADH, ver
    // nota de comportamiento preexistente) despues SI encuentre la fila.
    LBodyJson := TJSONObject.Create;
    try
      LBodyJson.AddPair('codigoH', TJSONNumber.Create(999999));
      LBodyJson.AddPair('subCodigoH', TJSONNumber.Create(1));
      LBodyJson.AddPair('nombreH', 'Test Phase2');
      LBodyJson.AddPair('referenciaH', TEST_REF);
      LBodyJson.AddPair('unidadH', TEST_UNI);
      LBodyJson.AddPair('referenciaP', TEST_REF);
      LBodyJson.AddPair('unidadP', TEST_UNI);
      LBodyJson.AddPair('factor', TJSONNumber.Create(1.5));

      LPostBody := TStringStream.Create(LBodyJson.ToJSON, TEncoding.UTF8);
      try
        LHttp.Request.ContentType := 'application/json';
        LResponse := LHttp.Post(Format('http://localhost:%d/api/equivalencia', [TEST_PORT]), LPostBody);
        Assert.AreEqual(200, LHttp.ResponseCode, 'Create debe responder 200/OK: ' + LResponse);
      finally
        LPostBody.Free;
      end;
    finally
      LBodyJson.Free;
    end;

    // 2. Borrar lo recien creado (limpieza) y verificar que el borrado reporta exito
    LDeleteUrl := Format('http://localhost:%d/api/equivalencia?referenciaP=%s&unidadP=%s',
      [TEST_PORT, TEST_REF, TEST_UNI]);
    LResponse := LHttp.Delete(LDeleteUrl);
    Assert.AreEqual(200, LHttp.ResponseCode, 'Delete debe responder 200/OK: ' + LResponse);
  finally
    LHttp.Free;
  end;
end;
```

**Antes de implementar**: recompila y corre el test ahora (mismos comandos del Task 1 Steps 5-7, mismas rutas) — debe fallar con 404 en el POST (RED), porque los métodos `CreateEquivalencia`/`DeleteEquivalencia` todavía no existen en el controller.

- [ ] **Step 3: Agregar los métodos al controller**

Modificar `dmvc/Controllers/DMVC.Controllers.EquivalenciaController.pas`. Cambiar el `uses` de la sección `interface` para agregar el nuevo DTO:

```pascal
uses
  MVCFramework, MVCFramework.Commons,
  System.Generics.Collections,
  DMVC.DTOs.Equivalencia,
  DMVC.DTOs.EquivalenciaCreate;
```

Agregar estos dos métodos a la declaración de la clase `TEquivalenciaController` (junto a `GetEquivalencias`):

```pascal
    [MVCPath('/equivalencia')]
    [MVCPath('/api/equivalencia')]
    [MVCHTTPMethod([httpPOST])]
    function CreateEquivalencia(const [MVCFromBody] ADatos: TEquivalenciaCreateDTO): IMVCResponse;

    [MVCPath('/equivalencia')]
    [MVCPath('/api/equivalencia')]
    [MVCHTTPMethod([httpDELETE])]
    function DeleteEquivalencia(
      const [MVCFromQueryString('referenciaP', '')] AReferenciaP: String;
      const [MVCFromQueryString('unidadP', '')] AUnidadP: String): IMVCResponse;
```

Agregar las implementaciones en la sección `implementation` (después de `GetEquivalencias`):

```pascal
function TEquivalenciaController.CreateEquivalencia(const ADatos: TEquivalenciaCreateDTO): IMVCResponse;
begin
  if not ADatos.CodigoH.HasValue then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'codigoH is required');
  if (not ADatos.ReferenciaP.HasValue) or (Trim(ADatos.ReferenciaP.Value) = '') then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'referenciaP cannot be empty');
  if (not ADatos.UnidadP.HasValue) or (Trim(ADatos.UnidadP.Value) = '') then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'unidadP cannot be empty');
  if (not ADatos.Factor.HasValue) or (ADatos.Factor.Value <= 0) then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'factor must be greater than 0');

  // Ver nota de comportamiento preexistente en Global Constraints: los nombres
  // de parametro de EquivalenciaService.CrearEquivalencia no corresponden 1:1
  // con las columnas que terminan usandose; se pasan en el mismo orden que
  // usaba el controller Horse original para no alterar el comportamiento.
  EquivalenciaService.CrearEquivalencia(
    ADatos.CodigoH.Value,
    ADatos.SubCodigoH.ValueOrDefault,
    ADatos.NombreH.ValueOrDefault,
    ADatos.ReferenciaP.Value,
    ADatos.UnidadP.Value,
    ADatos.UnidadH.ValueOrDefault,
    ADatos.ReferenciaH.ValueOrDefault,
    ADatos.Factor.Value);

  Result := OKResponse('Equivalencia creada correctamente');
end;

function TEquivalenciaController.DeleteEquivalencia(const AReferenciaP, AUnidadP: String): IMVCResponse;
var
  LSuccess: Boolean;
begin
  if Trim(AReferenciaP) = '' then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'El parámetro "referenciaP" es obligatorio');
  if Trim(AUnidadP) = '' then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'El parámetro "unidadP" es obligatorio');

  LSuccess := EquivalenciaService.EliminarEquivalencia(AReferenciaP, AUnidadP);
  if LSuccess then
    Result := OKResponse('Equivalencia eliminada correctamente')
  else
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'No se encontró la equivalencia para eliminar');
end;
```

Agregar `System.SysUtils` (para `Trim`) al `uses` de la sección `implementation` si no está ya.

- [ ] **Step 4: Recompilar servidor y tests, confirmar GREEN**

Mismos comandos de compilación del Task 1 (Steps 5-6), luego correr `PurchaseBridge.Tests.exe` — deben pasar TODOS los tests, incluyendo `CreateThenDeleteEquivalencia_RoundTrips`.

- [ ] **Step 5: Verificación manual**

Con el server corriendo: `curl -X POST http://localhost:9091/api/equivalencia -H "Content-Type: application/json" -d "{\"codigoH\":1,\"referenciaP\":\"MANUALTEST\",\"unidadP\":\"UN\",\"factor\":1}"` → debe responder 200. Luego `curl -X DELETE "http://localhost:9091/api/equivalencia?referenciaP=MANUALTEST&unidadP=UN"` → debe responder 200. Confirma que no quedó el registro de prueba manual en la base (si `curl` no está disponible, usa `Invoke-RestMethod` de PowerShell con la sintaxis equivalente).

- [ ] **Step 6: Commit**

```bash
git add dmvc/DTOs/DMVC.DTOs.EquivalenciaCreate.pas dmvc/Controllers/DMVC.Controllers.EquivalenciaController.pas tests/DMVC/DMVC.EquivalenciaControllerTests.pas
git commit -m "feat: migrate Equivalencia create/delete endpoints to DMVCFramework"
```

---

### Task 3: Proveedor — DTO + ruta GET por NIT

**Files:**
- Create: `dmvc/DTOs/DMVC.DTOs.Proveedor.pas`
- Create: `dmvc/Controllers/DMVC.Controllers.ProveedorController.pas`
- Modify: `dmvc/DMVC.WebModule.Main.pas` (registrar el nuevo controller)
- Create: `tests/DMVC/DMVC.ProveedorControllerTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr` (agregar la unidad de test al `uses`)

**Interfaces:**
- Consumes: `ProveedorRepository.ObtenerProveedorPorNit(NitProveedor: string; Anio: string): TProveedorInfo` (unidad existente `repositories/ProveedorRepository.pas`, sin cambios; `TProveedorInfo` es un `record` con `Existe: Boolean` y `Codigo: string`).
- Produces: nada que otras tasks de esta fase consuman — es la última task de la Fase 2.

**Nota de comportamiento**: el `ProveedorController` de Horse NO maneja excepciones (si `ObtenerProveedorPorNit` falla, la petición explota sin capturar). En DMVC, una excepción no capturada en un controller también se propaga y el engine la convierte en un 500 JSON estándar — comportamiento equivalente, no hace falta try/except explícito aquí tampoco. No agregues manejo de errores que Horse no tenía.

- [ ] **Step 1: Escribir el DTO**

Crear `dmvc/DTOs/DMVC.DTOs.Proveedor.pas`:

```pascal
unit DMVC.DTOs.Proveedor;

interface

uses
  MVCFramework.Serializer.Commons;

type
  [MVCNameCase(ncCamelCase)]
  TProveedorDTO = class
  private
    fExiste: Boolean;
    fCodigo: String;
  public
    property Existe: Boolean read fExiste write fExiste;
    property Codigo: String read fCodigo write fCodigo;
  end;

end.
```

- [ ] **Step 2: Escribir el test que falla (RED)**

Crear `tests/DMVC/DMVC.ProveedorControllerTests.pas`:

```pascal
unit DMVC.ProveedorControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TProveedorControllerTests = class
  private
    FServer: TTestServerProcess;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetProveedor_NitInexistente_ReturnsExisteFalse;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, IdHTTP;

const
  TEST_PORT = 9091;

function ServerExePath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\bin\PurchaseBridgeDMVC.exe'));
end;

procedure TProveedorControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(ServerExePath, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT), 'El servidor DMVC no respondió a tiempo en /ping');
end;

procedure TProveedorControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TProveedorControllerTests.GetProveedor_NitInexistente_ReturnsExisteFalse;
var
  LHttp: TIdHTTP;
  LBody: string;
  LJson: TJSONObject;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LBody := LHttp.Get(Format('http://localhost:%d/api/proveedor/000000000-TEST', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LBody) as TJSONObject;
    try
      Assert.IsFalse(LJson.GetValue<Boolean>('existe'));
    finally
      LJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

end.
```

Modificar `tests/PurchaseBridge.Tests.dpr`, agregando al `uses` (después de `DMVC.EquivalenciaControllerTests in 'DMVC\DMVC.EquivalenciaControllerTests.pas',`):

```pascal
  DMVC.ProveedorControllerTests in 'DMVC\DMVC.ProveedorControllerTests.pas';
```
(mover el `;` final a esta línea).

Recompilar el runner de tests (mismo comando del Task 1 Step 5) y correrlo — `GetProveedor_NitInexistente_ReturnsExisteFalse` debe fallar con 404 (ruta no existe todavía) — RED esperado.

- [ ] **Step 3: Escribir el controller**

Crear `dmvc/Controllers/DMVC.Controllers.ProveedorController.pas`:

```pascal
unit DMVC.Controllers.ProveedorController;

interface

uses
  MVCFramework,
  DMVC.DTOs.Proveedor;

type
  TProveedorController = class(TMVCController)
  public
    [MVCPath('/proveedor/($nit)')]
    [MVCPath('/api/proveedor/($nit)')]
    [MVCHTTPMethod([httpGET])]
    function GetProveedor(const nit: String;
      const [MVCFromQueryString('anio', '')] AAnio: String): TProveedorDTO;
  end;

implementation

uses
  ProveedorRepository;

function TProveedorController.GetProveedor(const nit: String; const AAnio: String): TProveedorDTO;
var
  LInfo: TProveedorInfo;
begin
  LInfo := ProveedorRepository.ObtenerProveedorPorNit(nit, AAnio);
  Result := TProveedorDTO.Create;
  Result.Existe := LInfo.Existe;
  if LInfo.Existe then
    Result.Codigo := LInfo.Codigo;
end;

end.
```

- [ ] **Step 4: Registrar el controller en el WebModule**

Modificar `dmvc/DMVC.WebModule.Main.pas` (que a esta altura ya tiene `TEquivalenciaController` de la Task 1):

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

- [ ] **Step 5: Compilar servidor y tests, confirmar GREEN**

Mismos comandos de compilación del Task 1 (Steps 5-6) — agrega `repositories` y `config` a la lista de `-U` del servidor si `ProveedorRepository.pas`/`HConfig.pas` no se encuentran (deberían estar ya cubiertos si seguiste la nota de la Task 1 Step 6, revisa igual).

Correr `PurchaseBridge.Tests.exe` — deben pasar TODOS los tests de la Fase 1 y la Fase 2 (5 en total: sanity, ping, equivalencias-list, equivalencias-create-delete, proveedor).

- [ ] **Step 6: Verificación manual**

`curl http://localhost:9091/api/proveedor/000000000-TEST` → `{"existe":false}`. Si tienes un NIT real de prueba a mano, verifica también la rama `existe:true` manualmente (no está automatizado — ver Global Constraints sobre no depender de datos reales de Helisa en los tests).

- [ ] **Step 7: Commit**

```bash
git add dmvc/DTOs/DMVC.DTOs.Proveedor.pas dmvc/Controllers/DMVC.Controllers.ProveedorController.pas dmvc/DMVC.WebModule.Main.pas tests/DMVC/DMVC.ProveedorControllerTests.pas tests/PurchaseBridge.Tests.dpr
git commit -m "feat: migrate Proveedor get-by-nit endpoint to DMVCFramework"
```

---

## Self-Review

**Cobertura:** Task 1 cubre el GET de listado de Equivalencia (objetivo del roadmap). Task 2 cubre POST/DELETE de Equivalencia. Task 3 cubre el único endpoint de Proveedor. Las 3 rutas + el único endpoint del roadmap para esta fase quedan cubiertas: `EquivalenciaController` (3 rutas) y `ProveedorController` (1 ruta).

**Placeholders:** el bloque intermedio de la Task 1 Step 2 con `LQuery: TObject` es intencional — está marcado explícitamente como "no copiar tal cual" y seguido inmediatamente por el código real completo a implementar. No es un placeholder de omisión (el código real está completo), es una nota pedagógica sobre por qué el primer bloque no es el correcto.

**Consistencia de tipos:** `TEquivalenciaDTO` (Task 1) y `TEquivalenciaCreateDTO` (Task 2) son deliberadamente DTOs distintos (ver nota en Task 2). `TTestServerProcess`/`ServerExePath` se reutilizan idénticos en las 3 tasks, copiados del patrón de la Fase 1 — mismo nombre, misma firma. `TProveedorInfo` (record existente, no se toca) se mapea 1:1 a `TProveedorDTO` (nuevo) en `GetProveedor`.

## Próximo paso

Cuando esta fase esté mergeada y verificada, se redacta el plan detallado de la Fase 3 (middlewares transversales: CORS, logger, licencia, auth) siguiendo el mismo formato, usando el patrón de controllers protegidos de `TEquivalenciaController`/`TProveedorController` para probar auth end-to-end.
