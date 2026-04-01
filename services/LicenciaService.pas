unit LicenciaService;

interface

uses
  System.JSON,
  System.SysUtils,
  System.DateUtils,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FirebirdConnection,
  Horse;

function Activar(const ANit, AInstalacionId: string): TJSONObject;
function Validar(const ANit, AInstalacionId: string): TJSONObject;

implementation

function Activar(const ANit, AInstalacionId: string): TJSONObject;
var
  LQ: TFDQuery;
  LEstado: string;
  LFechaExp: TDateTime;
  LDiasRestantes: Integer;
  LId: Integer;
begin
  LQ := GetBridgeQuery;
  try
    LQ.SQL.Text := 'SELECT ID, ESTADO, FECHA_ACTIVACION, FECHA_EXPIRACION, DIAS_DEMO FROM clientes WHERE nit = :nit';
    LQ.ParamByName('nit').AsString := ANit;
    LQ.Open;

    if LQ.IsEmpty then
    begin
      // Crear cliente demo
      LEstado := 'demo';
      var LDiasDemo := 15;
      var LFechaActivacion := Now;
      LFechaExp := IncDay(LFechaActivacion, LDiasDemo);
      LDiasRestantes := LDiasDemo;

      LQ.Close;
      LQ.SQL.Text := 'INSERT INTO clientes (nit, instalacion_id, estado, fecha_activacion, fecha_expiracion, dias_demo) ' +
                     'VALUES (:nit, :instalacion_id, :estado, :fecha_activacion, :fecha_expiracion, :dias_demo)';
      LQ.ParamByName('nit').AsString := ANit;
      LQ.ParamByName('instalacion_id').AsString := AInstalacionId;
      LQ.ParamByName('estado').AsString := LEstado;
      LQ.ParamByName('fecha_activacion').AsDateTime := LFechaActivacion;
      LQ.ParamByName('fecha_expiracion').AsDateTime := LFechaExp;
      LQ.ParamByName('dias_demo').AsInteger := LDiasDemo;
      LQ.ExecSQL;
    end
    else
    begin
      LId := LQ.FieldByName('ID').AsInteger;
      LEstado := LQ.FieldByName('ESTADO').AsString;
      LFechaExp := LQ.FieldByName('FECHA_EXPIRACION').AsDateTime;

      // Evaluar estado si ya expiró
      if (LEstado <> 'bloqueado') and (Now > LFechaExp) then
      begin
        LEstado := 'bloqueado';

        LQ.Close;
        LQ.SQL.Text := 'UPDATE clientes SET estado = :estado, instalacion_id = :instalacion_id WHERE id = :id';
        LQ.ParamByName('estado').AsString := LEstado;
        LQ.ParamByName('instalacion_id').AsString := AInstalacionId;
        LQ.ParamByName('id').AsInteger := LId;
        LQ.ExecSQL;
      end
      else
      begin
        LQ.Close;
        LQ.SQL.Text := 'UPDATE clientes SET instalacion_id = :instalacion_id WHERE id = :id';
        LQ.ParamByName('instalacion_id').AsString := AInstalacionId;
        LQ.ParamByName('id').AsInteger := LId;
        LQ.ExecSQL;
      end;

      if Now > LFechaExp then
        LDiasRestantes := 0
      else
        LDiasRestantes := DaysBetween(LFechaExp, Now);
    end;

    Result := TJSONObject.Create;
    Result.AddPair('estado', LEstado);
    Result.AddPair('expira', FormatDateTime('yyyy-mm-dd', LFechaExp));
    Result.AddPair('dias_restantes', TJSONNumber.Create(LDiasRestantes));
  finally
    LQ.Free;
  end;
end;

function Validar(const ANit, AInstalacionId: string): TJSONObject;
var
  LQ: TFDQuery;
  LEstado: string;
  LFechaExp: TDateTime;
  LDiasRestantes: Integer;
  LId: Integer;
begin
  LQ := GetBridgeQuery;
  try
    LQ.SQL.Text := 'SELECT ID, ESTADO, FECHA_ACTIVACION, FECHA_EXPIRACION, DIAS_DEMO FROM clientes WHERE nit = :nit';
    LQ.ParamByName('nit').AsString := ANit;
    LQ.Open;

    if LQ.IsEmpty then
      raise EHorseException.New.Status(THTTPStatus.NotFound).Error('no_autorizado');

    LId := LQ.FieldByName('ID').AsInteger;
    LEstado := LQ.FieldByName('ESTADO').AsString;
    LFechaExp := LQ.FieldByName('FECHA_EXPIRACION').AsDateTime;

    // Lógica de validación
    if (LEstado <> 'bloqueado') and (Now > LFechaExp) then
    begin
      LEstado := 'bloqueado';

      // Actualizar estado en la BD
      LQ.Close;
      LQ.SQL.Text := 'UPDATE clientes SET estado = :estado WHERE id = :id';
      LQ.ParamByName('estado').AsString := LEstado;
      LQ.ParamByName('id').AsInteger := LId;
      LQ.ExecSQL;
    end;

    if Now > LFechaExp then
      LDiasRestantes := 0
    else
      LDiasRestantes := DaysBetween(LFechaExp, Now);

    Result := TJSONObject.Create;
    Result.AddPair('estado', LEstado);
    Result.AddPair('expira', FormatDateTime('yyyy-mm-dd', LFechaExp));
    Result.AddPair('dias_restantes', TJSONNumber.Create(LDiasRestantes));
  finally
    LQ.Free;
  end;
end;

end.
