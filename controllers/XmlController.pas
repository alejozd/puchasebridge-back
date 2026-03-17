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
  Web.HTTPApp,
  Web.ReqFiles;

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
  THorse.Post('/xml/upload', Upload);
end;

end.
