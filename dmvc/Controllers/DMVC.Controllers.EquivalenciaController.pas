unit DMVC.Controllers.EquivalenciaController;

interface

uses
  MVCFramework, MVCFramework.Commons,
  System.Generics.Collections,
  DMVC.DTOs.Equivalencia;

type
  [MVCPath('/')]
  TEquivalenciaController = class(TMVCController)
  public
    [MVCPath('/equivalencias')]
    [MVCPath('/api/equivalencias')]
    [MVCHTTPMethod([httpGET])]
    function GetEquivalencias(
      const [MVCFromQueryString('referenciaP', '')] AReferenciaP: String;
      const [MVCFromQueryString('unidadP', '')] AUnidadP: String;
      const [MVCFromQueryString('limite', 50)] ALimite: Integer): TObjectList<TEquivalenciaDTO>;
  end;

implementation

uses
  EquivalenciaService, FireDAC.Comp.Client;

function TEquivalenciaController.GetEquivalencias(const AReferenciaP, AUnidadP: String;
  const ALimite: Integer): TObjectList<TEquivalenciaDTO>;
var
  LQuery: TFDQuery;
  LItem: TEquivalenciaDTO;
begin
  Result := TObjectList<TEquivalenciaDTO>.Create(True);
  // Ver nota de comportamiento preexistente en el Global Constraints de este plan:
  // EquivalenciaService.ListarEquivalencias filtra por REFERENCIAH/UNIDADH, no por
  // REFERENCIAP/UNIDADP, aunque asi se llamen los query-params de esta ruta. Preservado
  // a proposito (viene de Horse, no es un bug introducido aqui).
  LQuery := EquivalenciaService.ListarEquivalencias(AReferenciaP, AUnidadP, ALimite);
  try
    while not LQuery.Eof do
    begin
      LItem := TEquivalenciaDTO.Create;
      LItem.CodigoH := LQuery.FieldByName('CODIGOH').AsInteger;
      LItem.SubCodigoH := LQuery.FieldByName('SUBCODIGOH').AsInteger;
      LItem.NombreH := LQuery.FieldByName('NOMBREH').AsString;
      LItem.ReferenciaH := LQuery.FieldByName('REFERENCIAH').AsString;
      LItem.UnidadH := LQuery.FieldByName('UNIDADH').AsString;
      LItem.ReferenciaP := LQuery.FieldByName('REFERENCIAP').AsString;
      LItem.UnidadP := LQuery.FieldByName('UNIDADP').AsString;
      LItem.Factor := LQuery.FieldByName('FACTOR').AsFloat;
      Result.Add(LItem);
      LQuery.Next;
    end;
  finally
    LQuery.Free;
  end;
end;

end.
