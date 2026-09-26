unit DMVC.DTOs.EquivalenciaCreate;

interface

uses
  MVCFramework.Serializer.Commons,
  MVCFramework.Nullables;

type
  [MVCNameCase(ncCamelCase)]
  TEquivalenciaCreateDTO = class
  private
    fCodigoH: NullableInt32;
    fSubCodigoH: NullableInt32;
    fNombreH: NullableString;
    fReferenciaH: NullableString;
    fUnidadH: NullableString;
    fReferenciaP: NullableString;
    fUnidadP: NullableString;
    fFactor: NullableDouble;
  public
    property CodigoH: NullableInt32 read fCodigoH write fCodigoH;
    property SubCodigoH: NullableInt32 read fSubCodigoH write fSubCodigoH;
    property NombreH: NullableString read fNombreH write fNombreH;
    property ReferenciaH: NullableString read fReferenciaH write fReferenciaH;
    property UnidadH: NullableString read fUnidadH write fUnidadH;
    property ReferenciaP: NullableString read fReferenciaP write fReferenciaP;
    property UnidadP: NullableString read fUnidadP write fUnidadP;
    property Factor: NullableDouble read fFactor write fFactor;
  end;

implementation

end.
