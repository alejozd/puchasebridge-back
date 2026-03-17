unit XmlParserService;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Xml.XMLDoc,
  Xml.adomxmldom,
  Xml.xmldom,
  Xml.XMLIntf;

type
  TProductInfo = record
    Descripcion: string;
    Referencia: string;
    Cantidad: Double;
    ValorUnitario: Double;
    ValorTotal: Double;
    Impuesto: Double;
  end;

  TProviderInfo = record
    NIT: string;
    Nombre: string;
    Direccion: string;
  end;

  TInvoiceTotals = record
    Subtotal: Double;
    ImpuestoTotal: Double;
    Total: Double;
  end;

  TParsedInvoice = record
    Provider: TProviderInfo;
    Products: TArray<TProductInfo>;
    Totals: TInvoiceTotals;
  end;

  TXmlParserService = class
  private
    class function FindNodeByLocalName(ANode: IXMLNode; const ALocalName: string): IXMLNode;
    class function FindNodeByLocalNameRecursive(ANode: IXMLNode; const ALocalName: string): IXMLNode;
    class function GetNodeTextByLocalName(ANode: IXMLNode; const ALocalName: string): string;
    class function GetNodeDoubleByLocalName(ANode: IXMLNode; const ALocalName: string): Double;
    class function CreateXMLDoc(const AXML: string): IXMLDocument;
  public
    class function Parse(const XMLContent: string): TParsedInvoice;
  end;

implementation

{ TXmlParserService }

class function TXmlParserService.CreateXMLDoc(const AXML: string): IXMLDocument;
var
  LXMLDoc: TXMLDocument;
begin
  LXMLDoc := TXMLDocument.Create(nil);
  LXMLDoc.DOMVendor := GetDOMVendor(sAdom4XmlVendor);
  LXMLDoc.LoadFromXML(AXML);
  LXMLDoc.Active := True;
  Result := LXMLDoc;
end;

class function TXmlParserService.FindNodeByLocalName(ANode: IXMLNode; const ALocalName: string): IXMLNode;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to ANode.ChildNodes.Count - 1 do
  begin
    if SameText(ANode.ChildNodes[I].LocalName, ALocalName) then
    begin
      Result := ANode.ChildNodes[I];
      Break;
    end;
  end;
end;

class function TXmlParserService.FindNodeByLocalNameRecursive(ANode: IXMLNode; const ALocalName: string): IXMLNode;
var
  I: Integer;
begin
  Result := FindNodeByLocalName(ANode, ALocalName);
  if Result <> nil then
    Exit;

  for I := 0 to ANode.ChildNodes.Count - 1 do
  begin
    Result := FindNodeByLocalNameRecursive(ANode.ChildNodes[I], ALocalName);
    if Result <> nil then
      Exit;
  end;
end;

class function TXmlParserService.GetNodeTextByLocalName(ANode: IXMLNode; const ALocalName: string): string;
var
  LNode: IXMLNode;
begin
  Result := '';
  LNode := FindNodeByLocalName(ANode, ALocalName);
  if LNode <> nil then
    Result := LNode.Text;
end;

class function TXmlParserService.GetNodeDoubleByLocalName(ANode: IXMLNode; const ALocalName: string): Double;
var
  LStr: string;
  LFormatSettings: TFormatSettings;
begin
  Result := 0;
  LStr := GetNodeTextByLocalName(ANode, ALocalName);
  if LStr <> '' then
  begin
    LFormatSettings := TFormatSettings.Invariant;
    TryTextToFloat(LStr.Replace(',', ''), Result, LFormatSettings);
  end;
end;

class function TXmlParserService.Parse(const XMLContent: string): TParsedInvoice;
var
  XMLDoc: IXMLDocument;
  RootNode: IXMLNode;
  AttachmentNode: IXMLNode;
  DescriptionNode: IXMLNode;
  InnerXML: string;
  I, J: Integer;
  ProductList: TList<TProductInfo>;
  Product: TProductInfo;
  LineNode: IXMLNode;
  ItemNode: IXMLNode;
  SupplierNode: IXMLNode;
  PartyNode: IXMLNode;
  TaxSchemeNode: IXMLNode;
  Node, TaxTotalNode, LegalTotalNode, AddressNode: IXMLNode;
begin
  Result := Default(TParsedInvoice);
  XMLDoc := CreateXMLDoc(XMLContent);
  RootNode := XMLDoc.DocumentElement;

  // Handle AttachedDocument container
  if SameText(RootNode.LocalName, 'AttachedDocument') then
  begin
    AttachmentNode := FindNodeByLocalNameRecursive(RootNode, 'Attachment');
    if AttachmentNode <> nil then
    begin
      DescriptionNode := FindNodeByLocalNameRecursive(AttachmentNode, 'Description');
      if DescriptionNode <> nil then
      begin
        InnerXML := DescriptionNode.Text;
        if InnerXML.Contains('<Invoice') then
        begin
          XMLDoc := CreateXMLDoc(InnerXML);
          RootNode := XMLDoc.DocumentElement;
        end;
      end;
    end;
  end;

  // 1. Extract Provider Info
  SupplierNode := FindNodeByLocalName(RootNode, 'AccountingSupplierParty');
  if SupplierNode <> nil then
  begin
    PartyNode := FindNodeByLocalName(SupplierNode, 'Party');
    if PartyNode <> nil then
    begin
      // NIT
      TaxSchemeNode := FindNodeByLocalName(PartyNode, 'PartyTaxScheme');
      if TaxSchemeNode <> nil then
        Result.Provider.NIT := GetNodeTextByLocalName(TaxSchemeNode, 'CompanyID');

      // Nombre
      Node := FindNodeByLocalName(PartyNode, 'PartyName');
      if Node <> nil then
        Result.Provider.Nombre := GetNodeTextByLocalName(Node, 'Name');

      if Result.Provider.Nombre = '' then
      begin
        Node := FindNodeByLocalName(PartyNode, 'PartyLegalEntity');
        if Node <> nil then
          Result.Provider.Nombre := GetNodeTextByLocalName(Node, 'RegistrationName');
      end;

      // Direccion
      AddressNode := FindNodeByLocalName(PartyNode, 'PhysicalLocation');
      if AddressNode <> nil then
        AddressNode := FindNodeByLocalName(AddressNode, 'Address');

      if AddressNode = nil then
      begin
        Node := FindNodeByLocalName(PartyNode, 'PartyTaxScheme');
        if Node <> nil then
          AddressNode := FindNodeByLocalName(Node, 'RegistrationAddress');
      end;

      if AddressNode <> nil then
      begin
        Node := FindNodeByLocalName(AddressNode, 'AddressLine');
        if Node <> nil then
          Result.Provider.Direccion := GetNodeTextByLocalName(Node, 'Line');
      end;
    end;
  end;

  // 2. Extract Products from InvoiceLine
  ProductList := TList<TProductInfo>.Create;
  try
    for I := 0 to RootNode.ChildNodes.Count - 1 do
    begin
      LineNode := RootNode.ChildNodes[I];
      if SameText(LineNode.LocalName, 'InvoiceLine') then
      begin
        Product := Default(TProductInfo);

        // Cantidad
        Product.Cantidad := GetNodeDoubleByLocalName(LineNode, 'InvoicedQuantity');

        // Valor Total Linea
        Product.ValorTotal := GetNodeDoubleByLocalName(LineNode, 'LineExtensionAmount');

        // Impuestos de la linea
        TaxTotalNode := FindNodeByLocalName(LineNode, 'TaxTotal');
        if TaxTotalNode <> nil then
          Product.Impuesto := GetNodeDoubleByLocalName(TaxTotalNode, 'TaxAmount');

        ItemNode := FindNodeByLocalName(LineNode, 'Item');
        if ItemNode <> nil then
        begin
          Product.Descripcion := GetNodeTextByLocalName(ItemNode, 'Description');

          Node := FindNodeByLocalName(ItemNode, 'SellersItemIdentification');
          if Node <> nil then
            Product.Referencia := GetNodeTextByLocalName(Node, 'ID');
        end;

        // Valor Unitario
        Node := FindNodeByLocalName(LineNode, 'Price');
        if Node <> nil then
          Product.ValorUnitario := GetNodeDoubleByLocalName(Node, 'PriceAmount');

        ProductList.Add(Product);
      end;
    end;
    Result.Products := ProductList.ToArray;
  finally
    ProductList.Free;
  end;

  // 3. Totales de la Factura
  LegalTotalNode := FindNodeByLocalName(RootNode, 'LegalMonetaryTotal');
  if LegalTotalNode <> nil then
  begin
    Result.Totals.Subtotal := GetNodeDoubleByLocalName(LegalTotalNode, 'LineExtensionAmount');
    Result.Totals.Total := GetNodeDoubleByLocalName(LegalTotalNode, 'PayableAmount');
  end;

  TaxTotalNode := FindNodeByLocalName(RootNode, 'TaxTotal');
  if TaxTotalNode <> nil then
    Result.Totals.ImpuestoTotal := GetNodeDoubleByLocalName(TaxTotalNode, 'TaxAmount');
end;

end.
