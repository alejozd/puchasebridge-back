unit XmlParserService;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.DateUtils,
  Xml.XMLDoc,
  Xml.adomxmldom,
  Xml.xmldom,
  Xml.XMLIntf;

type
  TProductInfo = record
    IDLinea: string;
    Descripcion: string;
    Referencia: string;
    ReferenciaEstandar: string;
    Cantidad: Double;
    Unidad: string;
    PrecioBase: Double;
    ValorUnitario: Double;
    ValorTotal: Double;
    Impuesto: Double;
    ImpuestoPorcentaje: Double;
    Descuento: Double;
    DescuentoPorcentaje: Double;
  end;

  TProviderInfo = record
    NIT: string;
    Nombre: string;
    NombreLegal: string;
    TipoIdentificacion: string;
    Direccion: string;
  end;

  TInvoiceTotals = record
    Subtotal: Double;
    TaxExclusiveAmount: Double;
    TaxInclusiveAmount: Double;
    ImpuestoTotal: Double;
    Total: Double;
  end;

  TParsedInvoice = record
    Provider: TProviderInfo;
    Products: TArray<TProductInfo>;
    Totals: TInvoiceTotals;
    FechaEmision: TDateTime;
  end;

  TXmlParserService = class
  private
    class function FindNodeByLocalName(ANode: IXMLNode; const ALocalName: string): IXMLNode;
    class function FindNodeByLocalNameRecursive(ANode: IXMLNode; const ALocalName: string): IXMLNode;
    class function GetNodeTextByLocalName(ANode: IXMLNode; const ALocalName: string): string;
    class function GetNodeDoubleByLocalName(ANode: IXMLNode; const ALocalName: string): Double;
    class function GetNodeAttributeValue(ANode: IXMLNode; const AAttributeName: string): string;
    class function CreateXMLDoc(const AXML: string): IXMLDocument;

    class function ParseProveedor(ARootNode: IXMLNode): TProviderInfo;
    class function ParseProductos(ARootNode: IXMLNode): TArray<TProductInfo>;
    class function ParseTotales(ARootNode: IXMLNode): TInvoiceTotals;
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
    TryStrToFloat(LStr.Replace(',', ''), Result, LFormatSettings);
  end;
end;

class function TXmlParserService.GetNodeAttributeValue(ANode: IXMLNode; const AAttributeName: string): string;
var
  LAttr: IXMLNode;
begin
  Result := '';
  if ANode <> nil then
  begin
    LAttr := ANode.AttributeNodes.FindNode(AAttributeName);
    if LAttr <> nil then
      Result := LAttr.Text;
  end;
end;

class function TXmlParserService.ParseProveedor(ARootNode: IXMLNode): TProviderInfo;
var
  SupplierNode, PartyNode, Node, AddressNode, TaxSchemeNode: IXMLNode;
begin
  Result := Default(TProviderInfo);
  SupplierNode := FindNodeByLocalName(ARootNode, 'AccountingSupplierParty');
  if SupplierNode = nil then
    Exit;

  PartyNode := FindNodeByLocalName(SupplierNode, 'Party');
  if PartyNode = nil then
    Exit;

  // NIT y Tipo de identificación
  TaxSchemeNode := FindNodeByLocalName(PartyNode, 'PartyTaxScheme');
  if TaxSchemeNode <> nil then
  begin
    Node := FindNodeByLocalName(TaxSchemeNode, 'CompanyID');
    if Node <> nil then
    begin
      Result.NIT := Node.Text;
      Result.TipoIdentificacion := GetNodeAttributeValue(Node, 'schemeName');
      if Result.TipoIdentificacion = '' then
        Result.TipoIdentificacion := GetNodeAttributeValue(Node, 'schemeID');
    end;
    Result.NombreLegal := GetNodeTextByLocalName(TaxSchemeNode, 'RegistrationName');
  end;

  // Nombre (Ruta típica cac:PartyName/cbc:Name)
  Node := FindNodeByLocalName(PartyNode, 'PartyName');
  if Node <> nil then
    Result.Nombre := GetNodeTextByLocalName(Node, 'Name');

  if Result.Nombre = '' then
  begin
    Node := FindNodeByLocalName(PartyNode, 'PartyLegalEntity');
    if Node <> nil then
    begin
      Result.Nombre := GetNodeTextByLocalName(Node, 'RegistrationName');
      if Result.NombreLegal = '' then
        Result.NombreLegal := GetNodeTextByLocalName(Node, 'RegistrationName');
    end;
  end
  else
  begin
    Node := FindNodeByLocalName(PartyNode, 'PartyLegalEntity');
    if (Node <> nil) and (Result.NombreLegal = '') then
      Result.NombreLegal := GetNodeTextByLocalName(Node, 'RegistrationName');
  end;

  // Direccion
  AddressNode := FindNodeByLocalName(PartyNode, 'PhysicalLocation');
  if AddressNode <> nil then
    AddressNode := FindNodeByLocalName(AddressNode, 'Address');

  if AddressNode = nil then
  begin
    if TaxSchemeNode <> nil then
      AddressNode := FindNodeByLocalName(TaxSchemeNode, 'RegistrationAddress');
  end;

  if AddressNode <> nil then
  begin
    Node := FindNodeByLocalName(AddressNode, 'AddressLine');
    if Node <> nil then
      Result.Direccion := GetNodeTextByLocalName(Node, 'Line');
  end;
end;

class function TXmlParserService.ParseProductos(ARootNode: IXMLNode): TArray<TProductInfo>;
var
  I, J: Integer;
  LineNode, ItemNode, Node, TaxTotalNode, TaxSubtotalNode, TaxCategoryNode: IXMLNode;
  AllowanceNode: IXMLNode;
  ProductList: TList<TProductInfo>;
  Product: TProductInfo;
begin
  ProductList := TList<TProductInfo>.Create;
  try
    for I := 0 to ARootNode.ChildNodes.Count - 1 do
    begin
      LineNode := ARootNode.ChildNodes[I];
      if SameText(LineNode.LocalName, 'InvoiceLine') then
      begin
        Product := Default(TProductInfo);

        Product.IDLinea := GetNodeTextByLocalName(LineNode, 'ID');

        Node := FindNodeByLocalName(LineNode, 'InvoicedQuantity');
        if Node <> nil then
        begin
          Product.Cantidad := GetNodeDoubleByLocalName(LineNode, 'InvoicedQuantity');
          Product.Unidad := GetNodeAttributeValue(Node, 'unitCode');
        end;

        Product.ValorTotal := GetNodeDoubleByLocalName(LineNode, 'LineExtensionAmount');

        // Descuentos de la linea
        AllowanceNode := FindNodeByLocalName(LineNode, 'AllowanceCharge');
        if AllowanceNode <> nil then
        begin
          Node := FindNodeByLocalName(AllowanceNode, 'ChargeIndicator');
          if (Node <> nil) and SameText(Node.Text, 'false') then
          begin
            Product.Descuento := GetNodeDoubleByLocalName(AllowanceNode, 'Amount');
            Product.DescuentoPorcentaje := GetNodeDoubleByLocalName(AllowanceNode, 'MultiplierFactorNumeric');
          end;
        end;

        // Impuestos de la linea
        TaxTotalNode := FindNodeByLocalName(LineNode, 'TaxTotal');
        if TaxTotalNode <> nil then
        begin
          Product.Impuesto := GetNodeDoubleByLocalName(TaxTotalNode, 'TaxAmount');
          TaxSubtotalNode := FindNodeByLocalName(TaxTotalNode, 'TaxSubtotal');
          if TaxSubtotalNode <> nil then
          begin
            TaxCategoryNode := FindNodeByLocalName(TaxSubtotalNode, 'TaxCategory');
            if TaxCategoryNode <> nil then
              Product.ImpuestoPorcentaje := GetNodeDoubleByLocalName(TaxCategoryNode, 'Percent');
          end;
        end;

        ItemNode := FindNodeByLocalName(LineNode, 'Item');
        if ItemNode <> nil then
        begin
          Product.Descripcion := GetNodeTextByLocalName(ItemNode, 'Description');

          Node := FindNodeByLocalName(ItemNode, 'SellersItemIdentification');
          if Node <> nil then
            Product.Referencia := GetNodeTextByLocalName(Node, 'ID');

          Node := FindNodeByLocalName(ItemNode, 'StandardItemIdentification');
          if Node <> nil then
            Product.ReferenciaEstandar := GetNodeTextByLocalName(Node, 'ID');
        end;

        // Valor Unitario
        Node := FindNodeByLocalName(LineNode, 'Price');
        if Node <> nil then
        begin
          Product.ValorUnitario := GetNodeDoubleByLocalName(Node, 'PriceAmount');
          Product.PrecioBase := GetNodeDoubleByLocalName(Node, 'PriceAmount');
        end;

        ProductList.Add(Product);
      end;
    end;
    Result := ProductList.ToArray;
  finally
    ProductList.Free;
  end;
end;

class function TXmlParserService.ParseTotales(ARootNode: IXMLNode): TInvoiceTotals;
var
  LegalTotalNode, TaxTotalNode: IXMLNode;
begin
  Result := Default(TInvoiceTotals);
  LegalTotalNode := FindNodeByLocalName(ARootNode, 'LegalMonetaryTotal');
  if LegalTotalNode <> nil then
  begin
    Result.Subtotal := GetNodeDoubleByLocalName(LegalTotalNode, 'LineExtensionAmount');
    Result.TaxExclusiveAmount := GetNodeDoubleByLocalName(LegalTotalNode, 'TaxExclusiveAmount');
    Result.TaxInclusiveAmount := GetNodeDoubleByLocalName(LegalTotalNode, 'TaxInclusiveAmount');
    Result.Total := GetNodeDoubleByLocalName(LegalTotalNode, 'PayableAmount');
  end;

  TaxTotalNode := FindNodeByLocalName(ARootNode, 'TaxTotal');
  if TaxTotalNode <> nil then
    Result.ImpuestoTotal := GetNodeDoubleByLocalName(TaxTotalNode, 'TaxAmount');
end;

class function TXmlParserService.Parse(const XMLContent: string): TParsedInvoice;
var
  XMLDoc: IXMLDocument;
  RootNode: IXMLNode;
  AttachmentNode: IXMLNode;
  DescriptionNode: IXMLNode;
  InnerXML: string;
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

  Result.Provider := ParseProveedor(RootNode);
  Result.Products := ParseProductos(RootNode);
  Result.Totals := ParseTotales(RootNode);

  // Extract IssueDate
  DescriptionNode := FindNodeByLocalName(RootNode, 'IssueDate');
  if DescriptionNode <> nil then
  begin
    try
      Result.FechaEmision := ISO8601ToDate(DescriptionNode.Text);
    except
      if not TryStrToDate(DescriptionNode.Text, Result.FechaEmision, TFormatSettings.Invariant) then
         Result.FechaEmision := Now;
    end;
  end
  else
    Result.FechaEmision := Now;
end;

end.
