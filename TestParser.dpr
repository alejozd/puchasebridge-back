program TestParser;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  uLogger in 'utils/uLogger.pas',
  XmlParserService in 'services/XmlParserService.pas';

var
  XMLContent: string;
  ParsedInvoice: TParsedInvoice;
  I: Integer;
begin
  try
    if not FileExists('PurchaseBridge/Input/factura.xml') then
    begin
      Log('File not found: PurchaseBridge/Input/factura.xml', llError);
      Halt(1);
    end;

    XMLContent := TFile.ReadAllText('PurchaseBridge/Input/factura.xml', TEncoding.UTF8);
    ParsedInvoice := TXmlParserService.Parse(XMLContent);

    Log('Proveedor:', llInfo);
    Log('  NIT: ' + ParsedInvoice.Provider.NIT, llInfo);
    Log('  Nombre: ' + ParsedInvoice.Provider.Nombre, llInfo);
    Log('  Direccion: ' + ParsedInvoice.Provider.Direccion, llInfo);

    Log('Productos: ' + IntToStr(Length(ParsedInvoice.Products)), llInfo);
    for I := 0 to Length(ParsedInvoice.Products) - 1 do
    begin
      Log('  - ' + ParsedInvoice.Products[I].Descripcion, llInfo);
      Log('    Referencia: ' + ParsedInvoice.Products[I].Referencia, llInfo);
      Log(Format('    Cantidad: %.2f', [ParsedInvoice.Products[I].Cantidad]), llInfo);
      Log(Format('    Valor Unitario: %.2f', [ParsedInvoice.Products[I].ValorUnitario]), llInfo);
      Log(Format('    Impuesto: %.2f', [ParsedInvoice.Products[I].Impuesto]), llInfo);
    end;

    Log('Totales:', llInfo);
    Log(Format('  Subtotal: %.2f', [ParsedInvoice.Totals.Subtotal]), llInfo);
    Log(Format('  Impuesto Total: %.2f', [ParsedInvoice.Totals.ImpuestoTotal]), llInfo);
    Log(Format('  Total: %.2f', [ParsedInvoice.Totals.Total]), llInfo);

  except
    on E: Exception do
      Log(E.ClassName + ': ' + E.Message, llError);
  end;
end.
