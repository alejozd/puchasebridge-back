unit DMVC.Controllers.HelisaController;

interface

uses
  MVCFramework, MVCFramework.Commons,
  System.Generics.Collections,
  DMVC.DTOs.Helisa;

type
  [MVCPath('/')]
  THelisaController = class(TMVCController)
  public
    [MVCPath('/erp/productos')]
    [MVCPath('/api/erp/productos')]
    [MVCHTTPMethod([httpGET])]
    function GetProductos(const [MVCFromQueryString('search', '')] ASearch: String): TObjectList<TProductoHelisaDTO>;

    [MVCPath('/erp/unidades')]
    [MVCPath('/api/erp/unidades')]
    [MVCHTTPMethod([httpGET])]
    function GetUnidades: TObjectList<TUnidadHelisaDTO>;
  end;

implementation

uses
  System.SysUtils, FireDAC.Comp.Client, FirebirdConnection;

function THelisaController.GetProductos(const ASearch: String): TObjectList<TProductoHelisaDTO>;
var
  LQEmpresa, LQGlobal: TFDQuery;
  LItem: TProductoHelisaDTO;
  LSubcodigo: Integer;
begin
  if Trim(ASearch) = '' then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'El parámetro "search" es obligatorio');

  Result := TObjectList<TProductoHelisaDTO>.Create(True);
  try
    LQEmpresa := TFDQuery.Create(nil);
    try
      LQEmpresa.Connection := CrearConexionParticular('0');
      try
        LQEmpresa.SQL.Text :=
          'SELECT FIRST 20 CODIGO, SUBCODIGO, NOMBRE, REFERENCIA ' +
          'FROM INMAXXXX ' +
          'WHERE NOMBRE LIKE :FILTRO OR REFERENCIA LIKE :FILTRO ' +
          'ORDER BY NOMBRE';
        LQEmpresa.ParamByName('FILTRO').AsString := '%' + ASearch.ToUpper + '%';
        LQEmpresa.Open;

        LQGlobal := GetHelisaQuery;
        try
          LQGlobal.SQL.Text := 'SELECT SIGLA FROM INTUXXXX WHERE CODIGO = :SUBCODIGO';

          while not LQEmpresa.Eof do
          begin
            LSubcodigo := LQEmpresa.FieldByName('SUBCODIGO').AsInteger;

            LItem := TProductoHelisaDTO.Create;
            LItem.Codigo := LQEmpresa.FieldByName('CODIGO').AsInteger;
            LItem.Subcodigo := LSubcodigo;
            LItem.Nombre := LQEmpresa.FieldByName('NOMBRE').AsString;
            LItem.Referencia := LQEmpresa.FieldByName('REFERENCIA').AsString;
            LItem.Unidad := LSubcodigo;

            LQGlobal.Close;
            LQGlobal.ParamByName('SUBCODIGO').AsInteger := LSubcodigo;
            LQGlobal.Open;
            if not LQGlobal.IsEmpty then
              LItem.UnidadDefault := LQGlobal.FieldByName('SIGLA').AsString
            else
              LItem.UnidadDefault := '';

            Result.Add(LItem);
            LQEmpresa.Next;
          end;
        finally
          if Assigned(LQGlobal.Connection) then LQGlobal.Connection.Free;
          LQGlobal.Free;
        end;
      finally
        if Assigned(LQEmpresa.Connection) then LQEmpresa.Connection.Free;
      end;
    finally
      LQEmpresa.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function THelisaController.GetUnidades: TObjectList<TUnidadHelisaDTO>;
var
  LQ: TFDQuery;
  LItem: TUnidadHelisaDTO;
begin
  Result := TObjectList<TUnidadHelisaDTO>.Create(True);
  try
    LQ := GetHelisaQuery;
    try
      LQ.SQL.Text := 'SELECT CODIGO, NOMBRE, SIGLA FROM INTUXXXX ORDER BY NOMBRE';
      LQ.Open;
      while not LQ.Eof do
      begin
        LItem := TUnidadHelisaDTO.Create;
        LItem.Codigo := LQ.FieldByName('CODIGO').AsString;
        LItem.Nombre := LQ.FieldByName('NOMBRE').AsString;
        LItem.Sigla := LQ.FieldByName('SIGLA').AsString;
        Result.Add(LItem);
        LQ.Next;
      end;
    finally
      if Assigned(LQ.Connection) then LQ.Connection.Free;
      LQ.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
