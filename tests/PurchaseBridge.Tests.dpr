program PurchaseBridge.Tests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.DApt,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Stan.Pool,
  SanityTests in 'Sample\SanityTests.pas',
  DMVC.TestServerProcess in 'DMVC\DMVC.TestServerProcess.pas',
  DMVC.PingControllerTests in 'DMVC\DMVC.PingControllerTests.pas',
  DMVC.EquivalenciaControllerTests in 'DMVC\DMVC.EquivalenciaControllerTests.pas',
  DMVC.ProveedorControllerTests in 'DMVC\DMVC.ProveedorControllerTests.pas',
  DMVC.CORSMiddlewareTests in 'DMVC\DMVC.CORSMiddlewareTests.pas',
  DMVC.LicenseMiddlewareTests in 'DMVC\DMVC.LicenseMiddlewareTests.pas',
  DMVC.StaticAppMiddlewareTests in 'DMVC\DMVC.StaticAppMiddlewareTests.pas';

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
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := EXIT_ERRORS;
    end;
  end;
end.
