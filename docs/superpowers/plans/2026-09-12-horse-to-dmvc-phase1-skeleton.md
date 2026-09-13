# Fase 1 — Esqueleto DMVCFramework en paralelo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Levantar un segundo servidor HTTP mínimo con DMVCFramework (endpoint `/ping`) que corre en paralelo al servidor Horse existente, sin tocar ningún archivo de Horse, verificado con una prueba automatizada DUnitX (primera prueba automatizada de este repo).

**Architecture:** `PurchaseBridgeDMVC.dpr` es un programa consola independiente que levanta `TIdHTTPWebBrokerBridge` en el puerto 9091, con un `TWebModule` (`dmvc/DMVC.WebModule.Main.pas`) que crea un `TMVCEngine` y registra `TPingController`. Un proyecto de pruebas DUnitX (`tests/PurchaseBridge.Tests.dpr`) compila aparte, lanza el `.exe` del servidor como proceso hijo, espera a que `/ping` responda y valida el body JSON.

**Tech Stack:** Delphi (RAD Studio 23.0), DMVCFramework 3.4.3 Aluminium (fuente en `C:\Users\Alejo\Downloads\delphimvcframework-master\sources`), DUnitX (vendorizado con RAD Studio en `C:\Program Files (x86)\Embarcadero\Studio\23.0\source\DunitX`), Indy (incluido con RAD Studio).

## Global Constraints

- No modificar ningún archivo existente de Horse (`PurchaseBridge.dpr`, `PurchaseBridgeService.dpr`, `ServerBootstrap.pas`, `ServerMain.pas`, `controllers/`, `middleware/`, `modules/`) en esta fase.
- Puerto del servidor DMVC en esta fase: **9091** (Horse sigue en 9000, sin colisión).
- Compilador: `"C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\DCC32.EXE"`.
- Todo código nuevo Delphi vive bajo `dmvc/` (servidor) y `tests/` (pruebas), nunca mezclado con las carpetas de Horse.
- No se crean archivos `.dproj` a mano en esta fase (formato MSBuild propietario, propenso a error si se escribe manualmente); la verificación de cada paso se hace compilando con `DCC32.EXE` directo. Abrir los `.dpr` en la IDE de Delphi y guardar generará los `.dproj` automáticamente cuando el usuario los necesite para editar en la IDE.

---

### Task 1: Arnés de pruebas DUnitX (sanity check)

**Files:**
- Create: `tests/Sample/SanityTests.pas`
- Create: `tests/PurchaseBridge.Tests.dpr`

**Interfaces:**
- Produces: proyecto ejecutable `tests/bin/PurchaseBridge.Tests.exe` que corre todas las unidades `[TestFixture]` listadas en el `uses` de `PurchaseBridge.Tests.dpr`. Las tareas siguientes agregan sus propias unidades de test a ese `uses`.

- [ ] **Step 1: Escribir el test trivial**

Crear `tests/Sample/SanityTests.pas`. Nota: DCC32 exige que el nombre de unidad
coincida exactamente con el nombre físico del archivo (`E1038` si no coincide,
incluidos los segmentos con punto) — como el archivo se llama `SanityTests.pas`,
la unidad se declara sin namespace, `unit SanityTests;`, aunque viva en la
carpeta `Sample\`:

```pascal
unit SanityTests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSanityTests = class
  public
    [Test]
    procedure TestHarnessIsWorking;
  end;

implementation

procedure TSanityTests.TestHarnessIsWorking;
begin
  Assert.AreEqual(2, 1 + 1);
end;

end.
```

- [ ] **Step 2: Crear el runner DUnitX**

Crear `tests/PurchaseBridge.Tests.dpr`:

```pascal
program PurchaseBridge.Tests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  SanityTests in 'Sample\SanityTests.pas';

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
begin
  try
    runner := TDUnitX.CreateRunner;
    runner.UseRTTI := True;
    logger := TDUnitXConsoleLogger.Create(true);
    runner.AddLogger(logger);
    runner.FailsOnNoAsserts := False;

    results := runner.Execute;
    if not results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    System.Write('Done.. press <Enter> key to quit.');
    System.Readln;
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
end.
```

- [ ] **Step 3: Compilar**

Run:
```
"C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\DCC32.EXE" -B -Q ^
  -U"C:\Program Files (x86)\Embarcadero\Studio\23.0\source\DunitX" ^
  -I"C:\Program Files (x86)\Embarcadero\Studio\23.0\source\DunitX" ^
  -E"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase1\tests\bin" ^
  "F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase1\tests\PurchaseBridge.Tests.dpr"
```
Expected: `0 Error(s)` en la salida de DCC32.

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase1\tests\bin\PurchaseBridge.Tests.exe" -exitbehavior:continue < NUL`
Expected: reporte con `1 test`, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add tests/Sample/SanityTests.pas tests/PurchaseBridge.Tests.dpr
git commit -m "test: add DUnitX harness for PurchaseBridge"
```

---

### Task 2: Servidor DMVC mínimo con endpoint /ping (TDD)

**Files:**
- Create: `tests/DMVC/TestServerProcess.pas`
- Create: `tests/DMVC/PingControllerTests.pas`
- Modify: `tests/PurchaseBridge.Tests.dpr` (agregar dos unidades al `uses`)
- Create: `dmvc/DMVC.WebModule.Main.pas`
- Create: `dmvc/Controllers/DMVC.Controllers.PingController.pas`
- Create: `PurchaseBridgeDMVC.dpr`

**Interfaces:**
- Consumes: nada de Horse. Nada de tareas previas salvo el arnés DUnitX de la Task 1.
- Produces: `TTestServerProcess` (`Start(AExePath: string; APort: Integer)`, `Stop`, `WaitForReady(APort: Integer; ATimeoutMs: Integer = 8000): Boolean`) — lo reutilizarán las Fases 2-4 para probar cada controller nuevo contra el mismo `.exe`. `TPingController` con ruta `GET /ping` — patrón de referencia para todos los controllers de las fases siguientes.

- [ ] **Step 1: Escribir el helper de proceso de prueba**

Crear `tests/DMVC/TestServerProcess.pas`:

```pascal
unit DMVC.TestServerProcess;

interface

uses
  Winapi.Windows, System.SysUtils, System.Diagnostics, IdHTTP;

type
  TTestServerProcess = class
  private
    FProcessInfo: TProcessInformation;
    FRunning: Boolean;
  public
    procedure Start(const AExePath: string; APort: Integer);
    procedure Stop;
    function WaitForReady(APort: Integer; ATimeoutMs: Integer = 8000): Boolean;
  end;

implementation

procedure TTestServerProcess.Start(const AExePath: string; APort: Integer);
var
  LStartupInfo: TStartupInfo;
begin
  FillChar(FProcessInfo, SizeOf(FProcessInfo), 0);
  FillChar(LStartupInfo, SizeOf(LStartupInfo), 0);
  LStartupInfo.cb := SizeOf(LStartupInfo);
  if not CreateProcess(PChar(AExePath), nil, nil, nil, False,
    CREATE_NEW_CONSOLE, nil, PChar(ExtractFilePath(AExePath)), LStartupInfo, FProcessInfo) then
    RaiseLastOSError;
  FRunning := True;
end;

procedure TTestServerProcess.Stop;
begin
  if FRunning then
  begin
    TerminateProcess(FProcessInfo.hProcess, 0);
    WaitForSingleObject(FProcessInfo.hProcess, 3000);
    CloseHandle(FProcessInfo.hProcess);
    CloseHandle(FProcessInfo.hThread);
    FRunning := False;
  end;
end;

function TTestServerProcess.WaitForReady(APort: Integer; ATimeoutMs: Integer): Boolean;
var
  LHttp: TIdHTTP;
  LStopwatch: TStopwatch;
begin
  Result := False;
  LHttp := TIdHTTP.Create(nil);
  try
    LHttp.ConnectTimeout := 300;
    LHttp.ReadTimeout := 300;
    LStopwatch := TStopwatch.StartNew;
    while LStopwatch.ElapsedMilliseconds < ATimeoutMs do
    begin
      try
        LHttp.Get(Format('http://localhost:%d/ping', [APort]));
        Exit(True);
      except
        Sleep(200);
      end;
    end;
  finally
    LHttp.Free;
  end;
end;

end.
```

- [ ] **Step 2: Escribir el test que falla**

Crear `tests/DMVC/PingControllerTests.pas`:

```pascal
unit DMVC.PingControllerTests;

interface

uses
  DUnitX.TestFramework, DMVC.TestServerProcess;

type
  [TestFixture]
  TPingControllerTests = class
  private
    FServer: TTestServerProcess;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetPing_ReturnsOkStatus;
  end;

implementation

uses
  System.SysUtils, System.JSON, IdHTTP;

const
  TEST_PORT = 9091;
  SERVER_EXE = 'F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase1\bin\PurchaseBridgeDMVC.exe';

procedure TPingControllerTests.Setup;
begin
  FServer := TTestServerProcess.Create;
  FServer.Start(SERVER_EXE, TEST_PORT);
  Assert.IsTrue(FServer.WaitForReady(TEST_PORT),
    'El servidor DMVC no respondió a tiempo en /ping');
end;

procedure TPingControllerTests.TearDown;
begin
  FServer.Stop;
  FServer.Free;
end;

procedure TPingControllerTests.GetPing_ReturnsOkStatus;
var
  LHttp: TIdHTTP;
  LBody: string;
  LJson: TJSONObject;
begin
  LHttp := TIdHTTP.Create(nil);
  try
    LBody := LHttp.Get(Format('http://localhost:%d/ping', [TEST_PORT]));
    Assert.AreEqual(200, LHttp.ResponseCode);
    LJson := TJSONObject.ParseJSONValue(LBody) as TJSONObject;
    try
      Assert.AreEqual('ok', LJson.GetValue<string>('status'));
    finally
      LJson.Free;
    end;
  finally
    LHttp.Free;
  end;
end;

end.
```

Modificar `tests/PurchaseBridge.Tests.dpr`, agregando al `uses` (después de `Sample.SanityTests in 'Sample\SanityTests.pas',`):

```pascal
  DMVC.TestServerProcess in 'DMVC\TestServerProcess.pas',
  DMVC.PingControllerTests in 'DMVC\PingControllerTests.pas';
```//! el `;` final del `uses` se mueve a esta última línea

- [ ] **Step 3: Compilar y correr el test — debe fallar (RED)**

Run (recompilar el runner de tests, el server aún no existe):
```
"C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\DCC32.EXE" -B -Q ^
  -U"C:\Program Files (x86)\Embarcadero\Studio\23.0\source\DunitX" ^
  -I"C:\Program Files (x86)\Embarcadero\Studio\23.0\source\DunitX" ^
  -E"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase1\tests\bin" ^
  "F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase1\tests\PurchaseBridge.Tests.dpr"

"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase1\tests\bin\PurchaseBridge.Tests.exe" -exitbehavior:continue < NUL
```
Expected: `TPingControllerTests.GetPing_ReturnsOkStatus` FALLA con el mensaje `El servidor DMVC no respondió a tiempo en /ping` (o una excepción de `CreateProcess` si `bin\PurchaseBridgeDMVC.exe` no existe todavía — ambos son el rojo esperado).

- [ ] **Step 4: Implementar el controller**

Crear `dmvc/Controllers/DMVC.Controllers.PingController.pas`:

```pascal
unit DMVC.Controllers.PingController;

interface

uses
  MVCFramework, MVCFramework.Commons;

type
  [MVCPath('/ping')]
  TPingController = class(TMVCController)
  public
    [MVCPath]
    [MVCHTTPMethod([httpGET])]
    procedure Ping;
  end;

implementation

uses
  System.JSON;

procedure TPingController.Ping;
begin
  Render(TJSONObject.Create.AddPair('status', 'ok'));
end;

end.
```

- [ ] **Step 5: Implementar el WebModule**

Crear `dmvc/DMVC.WebModule.Main.pas`:

```pascal
unit DMVC.WebModule.Main;

interface

uses
  System.SysUtils, System.Classes, Web.HTTPApp,
  MVCFramework;

type
  TPurchaseBridgeDMVCWebModule = class(TWebModule)
  private
    FEngine: TMVCEngine;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  WebModuleClass: TComponentClass = TPurchaseBridgeDMVCWebModule;

implementation

uses
  DMVC.Controllers.PingController;

constructor TPurchaseBridgeDMVCWebModule.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEngine := TMVCEngine.Create(Self);
  FEngine.AddController(TPingController);
end;

destructor TPurchaseBridgeDMVCWebModule.Destroy;
begin
  FEngine.Free;
  inherited;
end;

end.
```

- [ ] **Step 6: Implementar el entrypoint del servidor**

Crear `PurchaseBridgeDMVC.dpr`:

```pascal
program PurchaseBridgeDMVC;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Web.WebReq,
  Web.WebBroker,
  IdHTTPWebBrokerBridge,
  DMVC.WebModule.Main in 'dmvc\DMVC.WebModule.Main.pas',
  DMVC.Controllers.PingController in 'dmvc\Controllers\DMVC.Controllers.PingController.pas';

procedure RunServer(APort: Integer);
var
  LServer: TIdHTTPWebBrokerBridge;
begin
  Writeln(Format('Starting PurchaseBridge DMVC server on port %d', [APort]));
  LServer := TIdHTTPWebBrokerBridge.Create(nil);
  try
    LServer.DefaultPort := APort;
    LServer.Active := True;
    Readln;
  finally
    LServer.Free;
  end;
end;

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    if WebRequestHandler <> nil then
      WebRequestHandler.WebModuleClass := WebModuleClass;
    WebRequestHandlerProc.MaxConnections := 1024;
    RunServer(9091);
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
```

- [ ] **Step 7: Compilar el servidor**

Run:
```
"C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\DCC32.EXE" -B -Q ^
  -U"C:\Users\Alejo\Downloads\delphimvcframework-master\sources";"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase1\dmvc";"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase1\dmvc\Controllers" ^
  -I"C:\Users\Alejo\Downloads\delphimvcframework-master\sources" ^
  -E"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase1\bin" ^
  "F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase1\PurchaseBridgeDMVC.dpr"
```
Expected: `0 Error(s)`, genera `bin\PurchaseBridgeDMVC.exe`.

- [ ] **Step 8: Re-ejecutar el test — debe pasar (GREEN)**

Run: `"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase1\tests\bin\PurchaseBridge.Tests.exe" -exitbehavior:continue < NUL`
Expected: `2 tests`, `0 failed` (el sanity check de la Task 1 + `GetPing_ReturnsOkStatus`).

- [ ] **Step 9: Verificación manual**

Run: `"F:\Proyectos\delphi_backend\purchasebridge\backend\.claude\worktrees\horse-to-dmvc-phase1\bin\PurchaseBridgeDMVC.exe"` (queda esperando en consola), en otra terminal: `curl http://localhost:9091/ping`
Expected: `{"status":"ok"}`. Cerrar el proceso con Ctrl+C o `taskkill`.

- [ ] **Step 10: Commit**

```bash
git add dmvc PurchaseBridgeDMVC.dpr tests/DMVC tests/PurchaseBridge.Tests.dpr
git commit -m "feat: add minimal DMVCFramework server with /ping controller alongside Horse"
```

---

## Self-Review

**Cobertura:** Task 1 cubre "arnés de pruebas nuevo" (requisito global de TDD). Task 2 cubre "esqueleto DMVC mínimo, puerto 9091, sin tocar Horse" (objetivo de Fase 1 en el roadmap) y deja `TTestServerProcess`/`TPingController` como base reusable documentada para las Fases 2-4.

**Placeholders:** ninguno — todo paso de código trae la unidad completa.

**Consistencia de tipos:** `TTestServerProcess.Start/Stop/WaitForReady` se define una sola vez (Task 2, Step 1) y se consume igual en `PingControllerTests.pas`; `TPingController`/`TPurchaseBridgeDMVCWebModule` con los mismos nombres en Steps 4-6.

## Próximo paso

Cuando esta fase esté mergeada y verificada, se redacta
`2026-09-12-horse-to-dmvc-phase2-controllers-bajo-riesgo.md` con el mismo
formato, usando `TTestServerProcess` y el patrón de `TPingController` como base
para `EquivalenciaController` y `ProveedorController`.
