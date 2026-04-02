unit LicenseService;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Net.URLClient,
  System.Net.HttpClient, System.Net.HttpClientComponent, System.Hash,
  System.DateUtils, Winapi.Windows, System.IOUtils, uLogger;

type
  TLicenciaInfo = class
  private
    FEstado: string;
    FExpira: TDateTime;
    FDiasRestantes: Integer;
    FMensaje: string;
  public
    property Estado: string read FEstado write FEstado;
    property Expira: TDateTime read FExpira write FExpira;
    property DiasRestantes: Integer read FDiasRestantes write FDiasRestantes;
    property Mensaje: string read FMensaje write FMensaje;
  end;

  TLicenciaService = class
  private
    FBaseURL: string;
    FNetHTTPClient: TNetHTTPClient;
    function Post(const AEndpoint: string; ABody: TJSONObject): TJSONObject;
  public
    constructor Create(const ABaseURL: string);
    destructor Destroy; override;
    function ValidarLicencia(const ANit, AInstalacionHash: string; out ALicenciaInfo: TLicenciaInfo): Boolean;
    function RegistrarLicencia(const ANit, AInstalacionHash, ACodigo: string; out ALicenciaInfo: TLicenciaInfo): Boolean;
    class function GenerarHashInstalacion: string;
  end;

implementation

{ TLicenciaService }

constructor TLicenciaService.Create(const ABaseURL: string);
begin
  FBaseURL := ABaseURL;
  if FBaseURL.EndsWith('/') then
    FBaseURL := Copy(FBaseURL, 1, Length(FBaseURL) - 1);

  FNetHTTPClient := TNetHTTPClient.Create(nil);
  FNetHTTPClient.ConnectionTimeout := 5000;
  FNetHTTPClient.ResponseTimeout := 10000;
end;

destructor TLicenciaService.Destroy;
begin
  FNetHTTPClient.Free;
  inherited;
end;

function TLicenciaService.Post(const AEndpoint: string; ABody: TJSONObject): TJSONObject;
var
  LResponse: IHTTPResponse;
  LSource: TStringStream;
  LURL: string;
  LHeaders: TNetHeaders;
begin
  Result := nil;
  LURL := FBaseURL + AEndpoint;
  LSource := TStringStream.Create(ABody.ToJSON, TEncoding.UTF8);
  try
    SetLength(LHeaders, 1);
    LHeaders[0] := TNetHeader.Create('Content-Type', 'application/json');

    Log('Enviando POST a: ' + LURL, llDebug);
    Log('Body: ' + ABody.ToJSON, llDebug);

    try
      LResponse := FNetHTTPClient.Post(LURL, LSource, nil, LHeaders);

      Log('Respuesta (' + IntToStr(LResponse.StatusCode) + '): ' + LResponse.ContentAsString, llDebug);

      if (LResponse.StatusCode >= 200) and (LResponse.StatusCode < 300) then
      begin
        Result := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
      end
      else
      begin
        Log('Error HTTP ' + IntToStr(LResponse.StatusCode) + ': ' + LResponse.ContentAsString, llError);
      end;
    except
      on E: Exception do
      begin
        Log('Excepcion en POST: ' + E.Message, llError);
      end;
    end;
  finally
    LSource.Free;
  end;
end;

function TLicenciaService.ValidarLicencia(const ANit, AInstalacionHash: string; out ALicenciaInfo: TLicenciaInfo): Boolean;
var
  LBody: TJSONObject;
  LRes: TJSONObject;
  LValue: TJSONValue;
begin
  Result := False;
  ALicenciaInfo := TLicenciaInfo.Create;

  LBody := TJSONObject.Create;
  try
    LBody.AddPair('nit', ANit);
    LBody.AddPair('instalacion_hash', AInstalacionHash);

    LRes := Post('/api/licencias/validar', LBody);
    if Assigned(LRes) then
    begin
      try
        if LRes.TryGetValue('estado', LValue) then
          ALicenciaInfo.Estado := LValue.Value
        else
          ALicenciaInfo.Estado := 'bloqueado';

        if LRes.TryGetValue('expira', LValue) then
          ALicenciaInfo.Expira := ISO8601ToDate(LValue.Value);

        if LRes.TryGetValue('dias_restantes', LValue) then
          ALicenciaInfo.DiasRestantes := StrToIntDef(LValue.Value, 0);

        Result := (ALicenciaInfo.Estado = 'activa') or (ALicenciaInfo.Estado = 'demo');
      finally
        LRes.Free;
      end;
    end;
  finally
    LBody.Free;
  end;
end;

function TLicenciaService.RegistrarLicencia(const ANit, AInstalacionHash, ACodigo: string; out ALicenciaInfo: TLicenciaInfo): Boolean;
var
  LBody: TJSONObject;
  LRes: TJSONObject;
  LValue: TJSONValue;
begin
  Result := False;
  ALicenciaInfo := TLicenciaInfo.Create;

  LBody := TJSONObject.Create;
  try
    LBody.AddPair('nit', ANit);
    LBody.AddPair('instalacion_hash', AInstalacionHash);
    LBody.AddPair('codigo', ACodigo);

    LRes := Post('/api/licencias/registrar', LBody);
    if Assigned(LRes) then
    begin
      try
        if LRes.TryGetValue('estado', LValue) then
          ALicenciaInfo.Estado := LValue.Value
        else
          ALicenciaInfo.Estado := 'bloqueado';

        if LRes.TryGetValue('expira', LValue) then
          ALicenciaInfo.Expira := ISO8601ToDate(LValue.Value);

        if LRes.TryGetValue('mensaje', LValue) then
          ALicenciaInfo.Mensaje := LValue.Value;

        Result := (ALicenciaInfo.Estado = 'activa');
      finally
        LRes.Free;
      end;
    end;
  finally
    LBody.Free;
  end;
end;

class function TLicenciaService.GenerarHashInstalacion: string;
var
  LCompName: array[0..MAX_COMPUTERNAME_LENGTH] of Char;
  LSize: DWORD;
  LUserName: array[0..255] of Char;
  LVolumeName, LFileSystemName: array[0..MAX_PATH] of Char;
  LSerialNumber, LMaxComponentLength, LFileSystemFlags: DWORD;
  LCombinedInfo: string;
begin
  LSize := MAX_COMPUTERNAME_LENGTH + 1;
  GetComputerName(LCompName, LSize);

  LSize := 256;
  GetUserName(LUserName, LSize);

  GetVolumeInformation('C:\', LVolumeName, MAX_PATH, @LSerialNumber, LMaxComponentLength, LFileSystemFlags, LFileSystemName, MAX_PATH);

  LCombinedInfo := string(LCompName) + '|' + string(LUserName) + '|' + IntToHex(LSerialNumber, 8);

  Result := THashSHA2.GetHashString(LCombinedInfo);
end;

end.
