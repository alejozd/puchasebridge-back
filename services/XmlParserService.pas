unit XmlParserService;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Xml.XMLDoc,
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
    class function GetNodeText(ANode: IXMLNode; const NodeName: string): string;
    class function FindNodeRecursive(ANode: IXMLNode; const NodeName: string): IXMLNode;
  public
    class function Parse(const XMLContent: string): TParsedInvoice;
  end;

implementation

{ TXmlParserService }

class function TXmlParserService.FindNodeRecursive(ANode: IXMLNode; const NodeName: string): IXMLNode;
var
  I: Integer;
begin
  Result := ANode.ChildNodes.FindNode(NodeName);
  if Result <> nil then
    Exit;

  for I := 0 to ANode.ChildNodes.Count - 1 do
  begin
    Result := FindNodeRecursive(ANode.ChildNodes[I], NodeName);
    if Result <> nil then
      Exit;
  end;
end;

class function TXmlParserService.GetNodeText(ANode: IXMLNode; const NodeName: string): string;
var
  LNode: IXMLNode;
begin
  Result := '';
  LNode := ANode.ChildNodes.FindNode(NodeName);
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
  XMLDoc := LoadXMLData(XMLContent);
  XMLDoc.Active := True;
  RootNode := XMLDoc.DocumentElement;

  // Handle AttachedDocument container
  if SameText(RootNode.NodeName, 'AttachedDocument') then
  begin
    AttachmentNode := FindNodeRecursive(RootNode, 'cac:Attachment');
    if AttachmentNode <> nil then
    begin
      DescriptionNode := FindNodeRecursive(AttachmentNode, 'cbc:Description');
      if DescriptionNode <> nil then
      begin
        InnerXML := DescriptionNode.Text;
        if InnerXML.Contains('<Invoice') then
        begin
          // Load the inner Invoice XML
          XMLDoc := LoadXMLData(InnerXML);
          XMLDoc.Active := True;
          RootNode := XMLDoc.DocumentElement;
        end;
      end;
    end;
  end;

  // 1. Extract Provider NIT
  // Path: cac:AccountingSupplierParty/cac:Party/cac:PartyTaxScheme/cbc:CompanyID
  SupplierNode := RootNode.ChildNodes.FindNode('cac:AccountingSupplierParty');
  if SupplierNode <> nil then
  begin
    PartyNode := SupplierNode.ChildNodes.FindNode('cac:Party');
    if PartyNode <> nil then
    begin
      TaxSchemeNode := PartyNode.ChildNodes.FindNode('cac:PartyTaxScheme');
      if TaxSchemeNode <> nil then
      begin
        Result.Provider.NIT := GetNodeText(TaxSchemeNode, 'cbc:CompanyID');
      end;
    end;
  end;

  // Fallback: try to find cbc:CompanyID anywhere if not found in the expected path
  if Result.Provider.NIT = '' then
  begin
    Node := FindNodeRecursive(RootNode, 'cbc:CompanyID');
    if Node <> nil then
      Result.Provider.NIT := Node.Text;
  end;

  // 2. Extract Products from cac:InvoiceLine
  ProductList := TList<TProductInfo>.Create;
  try
    for I := 0 to RootNode.ChildNodes.Count - 1 do
    begin
      LineNode := RootNode.ChildNodes[I];
      if SameText(LineNode.NodeName, 'cac:InvoiceLine') then
      begin
        ItemNode := LineNode.ChildNodes.FindNode('cac:Item');
        if ItemNode <> nil then
        begin
          Product.Descripcion := GetNodeText(ItemNode, 'cbc:Description');

          Product.Referencia := '';
          Node := ItemNode.ChildNodes.FindNode('cac:SellersItemIdentification');
          if Node <> nil then
          begin
            Product.Referencia := GetNodeText(Node, 'cbc:ID');
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
