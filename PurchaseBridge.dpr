program PurchaseBridge;

{$APPTYPE CONSOLE}

uses
  Horse,
  Horse.CORS,
  Horse.Jhonson,
  Horse.OctetStream,
  Horse.HandleException,
  Horse.Logger,
  System.SysUtils,
  HConfig in 'config\HConfig.pas',
  FirebirdConnection in 'database\FirebirdConnection.pas',
  ProveedorRepository in 'repositories\ProveedorRepository.pas',
  ProductoRepository in 'repositories\ProductoRepository.pas',
  XMLFacturaService in 'services\XMLFacturaService.pas',
  ImportController in 'controllers\ImportController.pas',
  ProveedorController in 'controllers\ProveedorController.pas',
  XmlController in 'controllers\XmlController.pas';

begin
  // Initialize configuration at startup
  try
    THConfig.GetInstance;
    Writeln('Configuracion cargada correctamente.');
  except
    on E: Exception do
    begin
      Writeln('Error cargando configuracion: ' + E.Message);
      Exit;
    end;
  end;

  THorse
    .Use(CORS)
    .Use(Jhonson())
    .Use(OctetStream)
    .Use(HandleException)
    .Use(THorseLoggerManager.HorseCallback());

  THorse.Get('/ping',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      Res.Send('pong');
    end);

  ImportController.Registry;
  ProveedorController.Registry;
  XmlController.Registry;

  THorse.Listen(9000,
    procedure
    begin
      Writeln('Server is running on port ' + IntToStr(THorse.Port));
      Writeln('Press Enter to stop the server...');
    end);
end.
