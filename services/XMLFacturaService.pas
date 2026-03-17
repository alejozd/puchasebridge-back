unit XMLFacturaService;

interface

uses
  System.SysUtils, System.Classes, Xml.XMLDoc, Xml.XMLIntf, System.Generics.Collections;

type
  TProductoXML = record
    Referencia: string;
    Descripcion: string;
  end;

  TFacturaXML = record
    NitProveedor: string;
    Anio: string;
    Productos: TArray<TProductoXML>;
  end;

  TXMLFacturaService = class
  public
    class function Parsear(XMLContent: string): TFacturaXML;
  end;

implementation

{ TXMLFacturaService }

class function TXMLFacturaService.Parsear(XMLContent: string): TFacturaXML;
var
  XML: IXMLDocument;
  Node, ItemNode, SubNode: IXMLNode;
  i: Integer;
  ListaProductos: TList<TProductoXML>;
  Producto: TProductoXML;
  IssueDate: string;
begin
  XML := LoadXMLData(XMLContent);
  XML.Active := True;

  // Extraction of NitProveedor
  // <cbc:CompanyID schemeAgencyID="195" schemeID="5" schemeName="31">860002536</cbc:CompanyID>
  // Usually located within cac:AccountingSupplierParty/cac:Party/cac:PartyTaxScheme/cbc:CompanyID
  // or cac:AccountingSupplierParty/cac:Party/cac:PartyTaxScheme/cac:RegistrationAddress/cbc:ID
  // The prompt says: <cbc:CompanyID ...>860002536</cbc:CompanyID>

  Node := XML.DocumentElement.ChildNodes.FindNode('cac:AccountingSupplierParty');
  if Node <> nil then
  begin
    Node := Node.ChildNodes.FindNode('cac:Party');
    if Node <> nil then
    begin
       Node := Node.ChildNodes.FindNode('cac:PartyTaxScheme');
       if Node <> nil then
       begin
         SubNode := Node.ChildNodes.FindNode('cbc:CompanyID');
         if SubNode <> nil then
           Result.NitProveedor := SubNode.Text;
       end;
    end;
  end;

  // Extraction of Year from IssueDate
  // <cbc:IssueDate>2024-05-22</cbc:IssueDate>
  SubNode := XML.DocumentElement.ChildNodes.FindNode('cbc:IssueDate');
  if SubNode <> nil then
  begin
    IssueDate := SubNode.Text; // Expected YYYY-MM-DD
    if Length(IssueDate) >= 4 then
      Result.Anio := Copy(IssueDate, 1, 4)
    else
      Result.Anio := FormatDateTime('yyyy', Now);
  end
  else
    Result.Anio := FormatDateTime('yyyy', Now);

  // Extraction of Products
  // Each product is in a <cac:InvoiceLine>
  ListaProductos := TList<TProductoXML>.Create;
  try
    for i := 0 to XML.DocumentElement.ChildNodes.Count - 1 do
    begin
      Node := XML.DocumentElement.ChildNodes[i];
      if Node.NodeName = 'cac:InvoiceLine' then
      begin
        ItemNode := Node.ChildNodes.FindNode('cac:Item');
        if ItemNode <> nil then
        begin
          Producto.Descripcion := '';
          Producto.Referencia := '';

          // <cbc:Description>
          SubNode := ItemNode.ChildNodes.FindNode('cbc:Description');
          if SubNode <> nil then
            Producto.Descripcion := SubNode.Text;

          // <cac:SellersItemIdentification><cbc:ID>
          SubNode := ItemNode.ChildNodes.FindNode('cac:SellersItemIdentification');
          if SubNode <> nil then
          begin
            SubNode := SubNode.ChildNodes.FindNode('cbc:ID');
            if SubNode <> nil then
              Producto.Referencia := SubNode.Text;
          end;

          ListaProductos.Add(Producto);
        end;
      end;
    end;
    Result.Productos := ListaProductos.ToArray;
  finally
    ListaProductos.Free;
  end;
end;

end.
