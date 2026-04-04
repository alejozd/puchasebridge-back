unit ConfigCrypto;

interface

const
  CONFIG_SECRET = 'Alejandro123*-+';

function EncodeBase64WithSecret(const AValue, ASecret: string): string;
function DecodeBase64WithSecret(const AEncodedValue, ASecret: string): string;
function DecodeIfEncoded(const AValue, ASecret: string): string;

implementation

uses
  System.SysUtils,
  System.NetEncoding,
  System.StrUtils;

const
  ENCODED_PREFIX = 'ENC:';

function EncodeBase64WithSecret(const AValue, ASecret: string): string;
var
  Payload: string;
begin
  Payload := ASecret + ':' + AValue;
  Result := ENCODED_PREFIX + TNetEncoding.Base64.Encode(Payload);
end;

function DecodeBase64WithSecret(const AEncodedValue, ASecret: string): string;
var
  Decoded: string;
  SecretPrefix: string;
begin
  SecretPrefix := ASecret + ':';
  Decoded := TNetEncoding.Base64.Decode(AEncodedValue);

  if StartsText(SecretPrefix, Decoded) then
    Result := Copy(Decoded, Length(SecretPrefix) + 1, MaxInt)
  else
    Result := '';
end;

function DecodeIfEncoded(const AValue, ASecret: string): string;
var
  EncodedPart: string;
  DecodedValue: string;
begin
  Result := AValue;

  if not StartsText(ENCODED_PREFIX, AValue) then
    Exit;

  EncodedPart := Copy(AValue, Length(ENCODED_PREFIX) + 1, MaxInt);

  try
    DecodedValue := DecodeBase64WithSecret(EncodedPart, ASecret);
    if DecodedValue <> '' then
      Result := DecodedValue;
  except
    // Compatibilidad con valores antiguos o mal formados.
    Result := AValue;
  end;
end;

end.
