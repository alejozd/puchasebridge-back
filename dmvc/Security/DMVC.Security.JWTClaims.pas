unit DMVC.Security.JWTClaims;

interface

uses
  MVCFramework.JWT;

procedure SetupPurchaseBridgeJWTClaims(const JWT: TJWT);

implementation

uses
  System.SysUtils;

procedure SetupPurchaseBridgeJWTClaims(const JWT: TJWT);
begin
  JWT.Claims.Issuer := 'PurchaseBridge';
  JWT.Claims.IssuedAt := Now;
  JWT.Claims.NotBefore := Now - EncodeTime(0, 1, 0, 0); // 1 min de tolerancia hacia atras
  JWT.Claims.ExpirationTime := Now + EncodeTime(8, 0, 0, 0); // sesion de 8 horas
end;

end.
