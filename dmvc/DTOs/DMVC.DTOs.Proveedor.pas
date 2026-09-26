unit DMVC.DTOs.Proveedor;

interface

uses
  MVCFramework.Serializer.Commons;

type
  [MVCNameCase(ncCamelCase)]
  TProveedorDTO = class
  private
    fExiste: Boolean;
    fCodigo: String;
  public
    property Existe: Boolean read fExiste write fExiste;
    property Codigo: String read fCodigo write fCodigo;
  end;

implementation

end.
