unit DianUnitService;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.SyncObjs,
  System.Variants,
  Xml.XMLDoc,
  Xml.adomxmldom,
  Xml.xmldom,
  Xml.XMLIntf;

type
  TDianUnitService = class
  private
    class var FUnitMap: TDictionary<string, string>;
    class var FLock: TCriticalSection;
    class procedure Initialize;
  public
    class function GetUnitName(const ACode: string): string;
    class constructor Create;
    class destructor Destroy;
  end;

implementation

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

class procedure TDianUnitService.Initialize;
var
  LXMLIntf: IXMLDocument;
  LRootNode, LSimpleCodeList, LRow, LValue, LSimpleValue: IXMLNode;
  I, J, K: Integer;
  LPath: string;
  LCode, LName: string;
begin
  if Assigned(FUnitMap) then
    Exit;

  FLock.Enter;
  try
    if Assigned(FUnitMap) then
      Exit;

    FUnitMap := TDictionary<string, string>.Create;

    LPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'examples');
    LPath := TPath.Combine(LPath, 'ToolBox');
    LPath := TPath.Combine(LPath, 'Listas de valores');
    LPath := TPath.Combine(LPath, 'UnidadesMedida-2.1.gc');

    // If not found in executable path, try relative to current dir (for dev environment)
    if not TFile.Exists(LPath) then
    begin
      LPath := TPath.Combine(GetCurrentDir, 'examples');
      LPath := TPath.Combine(LPath, 'ToolBox');
      LPath := TPath.Combine(LPath, 'Listas de valores');
      LPath := TPath.Combine(LPath, 'UnidadesMedida-2.1.gc');
    end;

    if not TFile.Exists(LPath) then
      Exit;

    try
      LXMLIntf := NewXMLDocument;
      LXMLIntf.DOMVendor := sAdom4XmlVendor;
      LXMLIntf.LoadFromFile(LPath);
      LXMLIntf.Active := True;

      LRootNode := LXMLIntf.DocumentElement;

      // Find SimpleCodeList
      LSimpleCodeList := nil;
      for I := 0 to LRootNode.ChildNodes.Count - 1 do
      begin
        if SameText(LRootNode.ChildNodes[I].LocalName, 'SimpleCodeList') then
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
          if (LRow.NodeType = ntElement) and SameText(LRow.LocalName, 'Row') then
          begin
            LCode := '';
            LName := '';
            for J := 0 to LRow.ChildNodes.Count - 1 do
            begin
              LValue := LRow.ChildNodes[J];
              if (LValue.NodeType = ntElement) and SameText(LValue.LocalName, 'Value') then
              begin
                if SameText(VarToStr(LValue.Attributes['ColumnRef']), 'code') then
                begin
                  LSimpleValue := nil;
                  for K := 0 to LValue.ChildNodes.Count - 1 do
                    if (LValue.ChildNodes[K].NodeType = ntElement) and SameText(LValue.ChildNodes[K].LocalName, 'SimpleValue') then
                    begin
                      LSimpleValue := LValue.ChildNodes[K];
                      Break;
                    end;
                  if LSimpleValue <> nil then
                    LCode := LSimpleValue.Text;
                end
                else if SameText(VarToStr(LValue.Attributes['ColumnRef']), 'name') then
                begin
                  LSimpleValue := nil;
                  for K := 0 to LValue.ChildNodes.Count - 1 do
                    if (LValue.ChildNodes[K].NodeType = ntElement) and SameText(LValue.ChildNodes[K].LocalName, 'SimpleValue') then
                    begin
                      LSimpleValue := LValue.ChildNodes[K];
                      Break;
                    end;
                  if LSimpleValue <> nil then
                    LName := LSimpleValue.Text;
                end;
              end;
            end;
            if (LCode <> '') and (LName <> '') then
              FUnitMap.AddOrSetValue(LCode, LName);
          end;
        end;
      end;
    except
      // Fail silently, map will remain empty or partially filled
    end;
  finally
    FLock.Leave;
  end;
end;

class function TDianUnitService.GetUnitName(const ACode: string): string;
begin
  if not Assigned(FUnitMap) then
    Initialize;

  FLock.Enter;
  try
    if not FUnitMap.TryGetValue(ACode, Result) then
      Result := ACode;

    if Result = '' then
      Result := 'N/A';
  finally
    FLock.Leave;
  end;
end;

end.
