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
  end;

  TProviderInfo = record
    NIT: string;
  end;

  TParsedInvoice = record
    Provider: TProviderInfo;
    Products: TArray<TProductInfo>;
  end;

  TXmlParserService = class
  private
    class function FindNodeByLocalName(ANode: IXMLNode; const ALocalName: string): IXMLNode;
    class function FindNodeByLocalNameRecursive(ANode: IXMLNode; const ALocalName: string): IXMLNode;
    class function GetNodeTextByLocalName(ANode: IXMLNode; const ALocalName: string): string;
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

class function TXmlParserService.Parse(const XMLContent: string): TParsedInvoice;
var
  XMLDoc: IXMLDocument;
  RootNode: IXMLNode;
  AttachmentNode: IXMLNode;
  DescriptionNode: IXMLNode;
  InnerXML: string;
  I: Integer;
  ProductList: TList<TProductInfo>;
  Product: TProductInfo;
  LineNode: IXMLNode;
  ItemNode: IXMLNode;
  SupplierNode: IXMLNode;
  PartyNode: IXMLNode;
  TaxSchemeNode: IXMLNode;
  Node: IXMLNode;
begin
  Result := Default(TParsedInvoice);
  XMLDoc := CreateXMLDoc(XMLContent);
  RootNode := XMLDoc.DocumentElement;

  // Handle AttachedDocument container
  // Use LocalName to be namespace-prefix agnostic
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
          // Load the inner Invoice XML
          XMLDoc := CreateXMLDoc(InnerXML);
          RootNode := XMLDoc.DocumentElement;
        end;
      end;
    end;
  end;

  // 1. Extract Provider NIT
  // Path: AccountingSupplierParty / Party / PartyTaxScheme / CompanyID
  SupplierNode := FindNodeByLocalName(RootNode, 'AccountingSupplierParty');
  if SupplierNode <> nil then
  begin
    PartyNode := FindNodeByLocalName(SupplierNode, 'Party');
    if PartyNode <> nil then
    begin
      TaxSchemeNode := FindNodeByLocalName(PartyNode, 'PartyTaxScheme');
      if TaxSchemeNode <> nil then
      begin
        Result.Provider.NIT := GetNodeTextByLocalName(TaxSchemeNode, 'CompanyID');
      end;
    end;
  end;

  // Fallback: try to find CompanyID anywhere if not found in the expected path
  if Result.Provider.NIT = '' then
  begin
    Node := FindNodeByLocalNameRecursive(RootNode, 'CompanyID');
    if Node <> nil then
      Result.Provider.NIT := Node.Text;
  end;

  // 2. Extract Products from InvoiceLine
  ProductList := TList<TProductInfo>.Create;
  try
    for I := 0 to RootNode.ChildNodes.Count - 1 do
    begin
      LineNode := RootNode.ChildNodes[I];
      if SameText(LineNode.LocalName, 'InvoiceLine') then
      begin
        ItemNode := FindNodeByLocalName(LineNode, 'Item');
        if ItemNode <> nil then
        begin
          Product.Descripcion := GetNodeTextByLocalName(ItemNode, 'Description');

          Product.Referencia := '';
          Node := FindNodeByLocalName(ItemNode, 'SellersItemIdentification');
          if Node <> nil then
          begin
            Product.Referencia := GetNodeTextByLocalName(Node, 'ID');
          end;

          ProductList.Add(Product);
        end;
      end;
    end;
    Result.Products := ProductList.ToArray;
  finally
    ProductList.Free;
  end;
end;

end.
