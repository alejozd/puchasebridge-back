unit DMVC.DTOs.Equivalencia;

interface

uses
  MVCFramework.Serializer.Commons;

type
  [MVCNameCase(ncCamelCase)]
  TEquivalenciaDTO = class
  private
    fCodigoH: Integer;
    fSubCodigoH: Integer;
    fNombreH: String;
    fReferenciaH: String;
    fUnidadH: String;
    fReferenciaP: String;
    fUnidadP: String;
    fFactor: Double;
  public
    property CodigoH: Integer read fCodigoH write fCodigoH;
    property SubCodigoH: Integer read fSubCodigoH write fSubCodigoH;
    property NombreH: String read fNombreH write fNombreH;
    property ReferenciaH: String read fReferenciaH write fReferenciaH;
    property UnidadH: String read fUnidadH write fUnidadH;
    property ReferenciaP: String read fReferenciaP write fReferenciaP;
    property UnidadP: String read fUnidadP write fUnidadP;
    property Factor: Double read fFactor write fFactor;
  end;

implementation

end.
