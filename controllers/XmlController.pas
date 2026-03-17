unit XmlController;

interface

procedure Registry;

implementation

uses
  Horse,
  System.JSON,
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Types,
  Web.HTTPApp,
  Web.ReqFiles;

type
  TFileInfo = record
    FileName: string;
    Size: Int64;
    LastModified: TDateTime;
  end;

procedure List(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LPath: string;
  LFiles: TStringDynArray;
  LFile: string;
  LJSONList: TJSONArray;
  LJSONObj: TJSONObject;
  LFileInfoList: TList<TFileInfo>;
  LFileInfo: TFileInfo;
begin
  try
    LPath := TPath.Combine('PurchaseBridge', 'Input');
    if not TDirectory.Exists(LPath) then
    begin
      Res.Send(TJSONArray.Create);
      Exit;
    end;

    LFiles := TDirectory.GetFiles(LPath, '*.xml');

    LFileInfoList := TList<TFileInfo>.Create;
    try
      for LFile in LFiles do
      begin
        LFileInfo.FileName := TPath.GetFileName(LFile);
        LFileInfo.Size := TFile.GetSize(LFile);
        LFileInfo.LastModified := TFile.GetLastWriteTime(LFile);
        LFileInfoList.Add(LFileInfo);
      end;

      LFileInfoList.Sort(TComparer<TFileInfo>.Construct(
        function(const Left, Right: TFileInfo): Integer
        begin
          if Left.LastModified < Right.LastModified then
            Result := 1
          else if Left.LastModified > Right.LastModified then
            Result := -1
          else
            Result := 0;
        end));

      LJSONList := TJSONArray.Create;
      try
        for LFileInfo in LFileInfoList do
        begin
          LJSONObj := TJSONObject.Create;
          LJSONObj.AddPair('fileName', LFileInfo.FileName);
          LJSONObj.AddPair('size', TJSONNumber.Create(LFileInfo.Size));
          LJSONObj.AddPair('lastModified', FormatDateTime('yyyy-mm-dd HH:nn:ss', LFileInfo.LastModified));
          LJSONList.AddElement(LJSONObj);
        end;
        Res.Send(LJSONList);
      except
        LJSONList.Free;
        raise;
      end;
    finally
      LFileInfoList.Free;
    end;
  except
    on E: Exception do
    begin
      LJSONObj := TJSONObject.Create;
      LJSONObj.AddPair('success', TJSONBool.Create(False));
      LJSONObj.AddPair('message', E.Message);
      Res.Status(500).Send(LJSONObj);
    end;
  end;
end;

procedure Upload(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LFile: TAbstractWebRequestFile;
  LPath, LFileName, LFullFile: string;
  LResponse: TJSONObject;
  I: Integer;
  LFound: Boolean;
  LFileStream: TFileStream;
begin
  LFound := False;
  LFile := nil;

  try
    for I := 0 to Req.RawWebRequest.Files.Count - 1 do
    begin
      if SameText(Req.RawWebRequest.Files[I].FieldName, 'file') then
      begin
        LFile := Req.RawWebRequest.Files[I];
        LFound := True;
        Break;
      end;
    end;

    if not LFound then
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'No file uploaded with field name "file"');
      Res.Status(400).Send(LResponse);
      Exit;
    end;

    LFileName := LFile.FileName;
    if not SameText(ExtractFileExt(LFileName), '.xml') then
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'The file must have a .xml extension');
      Res.Status(400).Send(LResponse);
      Exit;
    end;

    LPath := TPath.Combine('PurchaseBridge', 'Input');
    if not TDirectory.Exists(LPath) then
      TDirectory.CreateDirectory(LPath);

    LFullFile := TPath.Combine(LPath, LFileName);

    LFile.Stream.Position := 0;
    LFileStream := TFileStream.Create(LFullFile, fmCreate);
    try
      LFileStream.CopyFrom(LFile.Stream, LFile.Stream.Size);
    finally
      LFileStream.Free;
    end;

    LResponse := TJSONObject.Create;
    LResponse.AddPair('success', TJSONBool.Create(True));
    LResponse.AddPair('message', 'XML uploaded successfully');
    LResponse.AddPair('fileName', LFileName);
    LResponse.AddPair('path', LFullFile.Replace('\', '/'));
    Res.Send(LResponse);
  except
    on E: Exception do
    begin
      LResponse := TJSONObject.Create;
      LResponse.AddPair('success', TJSONBool.Create(False));
      LResponse.AddPair('message', 'Error saving file: ' + E.Message);
      Res.Status(500).Send(LResponse);
    end;
  end;
end;

procedure Registry;
begin
  THorse.Get('/xml/list', List);
  THorse.Post('/xml/upload', Upload);
end;

end.
