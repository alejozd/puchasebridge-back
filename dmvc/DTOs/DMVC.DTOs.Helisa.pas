unit DMVC.DTOs.Helisa;

interface

uses
  MVCFramework.Serializer.Commons;

type
  [MVCNameCase(ncCamelCase)]
  TProductoHelisaDTO = class
  private
    fCodigo: Integer;
    fSubcodigo: Integer;
    fNombre: String;
    fReferencia: String;
    fUnidad: Integer;
    fUnidadDefault: String;
  public
    property Codigo: Integer read fCodigo write fCodigo;
    property Subcodigo: Integer read fSubcodigo write fSubcodigo;
    property Nombre: String read fNombre write fNombre;
    property Referencia: String read fReferencia write fReferencia;
    property Unidad: Integer read fUnidad write fUnidad;
    property UnidadDefault: String read fUnidadDefault write fUnidadDefault;
  end;

  [MVCNameCase(ncCamelCase)]
  TUnidadHelisaDTO = class
  private
    fCodigo: String;
    fNombre: String;
    fSigla: String;
  public
    property Codigo: String read fCodigo write fCodigo;
    property Nombre: String read fNombre write fNombre;
    property Sigla: String read fSigla write fSigla;
  end;

implementation

end.
