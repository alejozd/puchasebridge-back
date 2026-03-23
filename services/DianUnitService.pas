unit DianUnitService;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.SyncObjs,
  Xml.XMLIntf;

type
  TDianUnitService = class
  private
    class var FUnitMap: TDictionary<string, string>;
    class var FLock: TCriticalSection;
    class procedure Initialize;
    class function GetLocalName(const ANode: IXMLNode): string;
  public
    class function GetUnitName(const ACode: string): string;
    class constructor Create;
    class destructor Destroy;
  end;

implementation

uses
  System.IOUtils,
  System.Variants,
  Xml.XMLDoc,
  Xml.adomxmldom,
  Xml.xmldom;

{ TDianUnitService }

class constructor TDianUnitService.Create;
begin
  FLock := TCriticalSection.Create;
end;

class destructor TDianUnitService.Destroy;
begin
  if Assigned(FUnitMap) then
    FUnitMap.Free;
  FLock.Free;
end;

class function TDianUnitService.GetLocalName(const ANode: IXMLNode): string;
var
  LName: string;
  LPos: Integer;
begin
  Result := ANode.LocalName;
  if Result = '' then
  begin
    LName := ANode.NodeName;
    LPos := Pos(':', LName);
    if LPos > 0 then
      Result := Copy(LName, LPos + 1, MaxInt)
    else
      Result := LName;
  end;
end;

class procedure TDianUnitService.Initialize;
var
  LXMLDoc: TXMLDocument;
  LXMLIntf: IXMLDocument;
  LRootNode, LSimpleCodeList, LRow, LValue, LSimpleValue: IXMLNode;
  I, J, K: Integer;
  LPath: string;
  LCode, LName: string;
  LAttr: string;
  LMap: TDictionary<string, string>;
begin
  if Assigned(FUnitMap) then
    Exit;

  FLock.Enter;
  try
    if Assigned(FUnitMap) then
      Exit;

    LMap := TDictionary<string, string>.Create;
    try
      LPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'examples');
      LPath := TPath.Combine(LPath, 'ToolBox');
      LPath := TPath.Combine(LPath, 'Listas de valores');
      LPath := TPath.Combine(LPath, 'UnidadesMedida-2.1.gc');

      if not TFile.Exists(LPath) then
      begin
        LPath := TPath.Combine(GetCurrentDir, 'examples');
        LPath := TPath.Combine(LPath, 'ToolBox');
        LPath := TPath.Combine(LPath, 'Listas de valores');
        LPath := TPath.Combine(LPath, 'UnidadesMedida-2.1.gc');
      end;

      if TFile.Exists(LPath) then
      begin
        LXMLDoc := TXMLDocument.Create(nil);
        LXMLDoc.DOMVendor := GetDOMVendor(sAdom4XmlVendor);
        LXMLDoc.LoadFromFile(LPath);
        LXMLDoc.Active := True;
        LXMLIntf := LXMLDoc;

        LRootNode := LXMLIntf.DocumentElement;

        LSimpleCodeList := nil;
        for I := 0 to LRootNode.ChildNodes.Count - 1 do
        begin
          if (LRootNode.ChildNodes[I].NodeType = ntElement) and
             SameText(GetLocalName(LRootNode.ChildNodes[I]), 'SimpleCodeList') then
          begin
            LSimpleCodeList := LRootNode.ChildNodes[I];
            Break;
          end;
        end;

        if LSimpleCodeList <> nil then
        begin
          for I := 0 to LSimpleCodeList.ChildNodes.Count - 1 do
          begin
            LRow := LSimpleCodeList.ChildNodes[I];
            if (LRow.NodeType = ntElement) and SameText(GetLocalName(LRow), 'Row') then
            begin
              LCode := '';
              LName := '';
              for J := 0 to LRow.ChildNodes.Count - 1 do
              begin
                LValue := LRow.ChildNodes[J];
                if (LValue.NodeType = ntElement) and SameText(GetLocalName(LValue), 'Value') then
                begin
                  LAttr := VarToStr(LValue.Attributes['ColumnRef']);
                  if LAttr = '' then
                     LAttr := VarToStr(LValue.Attributes['gc:ColumnRef']);

                  if SameText(LAttr, 'code') then
                  begin
                    LSimpleValue := nil;
                    for K := 0 to LValue.ChildNodes.Count - 1 do
                      if (LValue.ChildNodes[K].NodeType = ntElement) and
                         SameText(GetLocalName(LValue.ChildNodes[K]), 'SimpleValue') then
                      begin
                        LSimpleValue := LValue.ChildNodes[K];
                        Break;
                      end;
                    if LSimpleValue <> nil then
                      LCode := LSimpleValue.Text.Trim;
                  end
                  else if SameText(LAttr, 'name') then
                  begin
                    LSimpleValue := nil;
                    for K := 0 to LValue.ChildNodes.Count - 1 do
                      if (LValue.ChildNodes[K].NodeType = ntElement) and
                         SameText(GetLocalName(LValue.ChildNodes[K]), 'SimpleValue') then
                      begin
                        LSimpleValue := LValue.ChildNodes[K];
                        Break;
                      end;
                    if LSimpleValue <> nil then
                      LName := UpperCase(LSimpleValue.Text.Trim);
                  end;
                end;
              end;
              if (LCode <> '') and (LName <> '') then
                LMap.AddOrSetValue(LCode, LName);
            end;
          end;
        end;
      end;
    except
      // silent fail
    end;
    FUnitMap := LMap;
  finally
    FLock.Leave;
  end;
end;

class function TDianUnitService.GetUnitName(const ACode: string): string;
var
  LCleanCode: string;
begin
  if not Assigned(FUnitMap) then
    Initialize;

  LCleanCode := ACode.Trim;
  FLock.Enter;
  try
    if (FUnitMap = nil) or not FUnitMap.TryGetValue(LCleanCode, Result) then
      Result := ACode;

    if Result = '' then
      Result := ACode;
  finally
    FLock.Leave;
  end;
end;

end.
