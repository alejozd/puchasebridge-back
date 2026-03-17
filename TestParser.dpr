program TestParser;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  XmlParserService in 'services/XmlParserService.pas';

var
  XMLContent: string;
  ParsedInvoice: TParsedInvoice;
  I: Integer;
begin
  try
    if not FileExists('PurchaseBridge/Input/factura.xml') then
    begin
      Writeln('File not found: PurchaseBridge/Input/factura.xml');
      Halt(1);
    end;

    XMLContent := TFile.ReadAllText('PurchaseBridge/Input/factura.xml', TEncoding.UTF8);
    ParsedInvoice := TXmlParserService.Parse(XMLContent);

    Writeln('Proveedor:');
    Writeln('  NIT: ', ParsedInvoice.Provider.NIT);
    Writeln('  Nombre: ', ParsedInvoice.Provider.Nombre);
    Writeln('  Direccion: ', ParsedInvoice.Provider.Direccion);

    Writeln('Productos: ', Length(ParsedInvoice.Products));
    for I := 0 to Length(ParsedInvoice.Products) - 1 do
    begin
      Writeln('  - ', ParsedInvoice.Products[I].Descripcion);
      Writeln('    Referencia: ', ParsedInvoice.Products[I].Referencia);
      Writeln('    Cantidad: ', ParsedInvoice.Products[I].Cantidad:0:2);
      Writeln('    Valor Unitario: ', ParsedInvoice.Products[I].ValorUnitario:0:2);
      Writeln('    Impuesto: ', ParsedInvoice.Products[I].Impuesto:0:2);
    end;

    Writeln('Totales:');
    Writeln('  Subtotal: ', ParsedInvoice.Totals.Subtotal:0:2);
    Writeln('  Impuesto Total: ', ParsedInvoice.Totals.ImpuestoTotal:0:2);
    Writeln('  Total: ', ParsedInvoice.Totals.Total:0:2);

  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
