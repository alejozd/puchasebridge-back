from datetime import datetime, timedelta
import math

def days_between(d1, d2):
    # Simulating Delphi's DaysBetween which returns whole days
    # DaysBetween(ANow, AExp)
    diff = d1 - d2
    return abs(diff.days)

def format_date(dt):
    return dt.strftime('%Y-%m-%d')

class LicenciaLogic:
    def __init__(self, db=None):
        self.db = db or {} # nit -> data

    def activar(self, nit, instalacion_id, now=None):
        if now is None:
            now = datetime.now()

        client = self.db.get(nit)

        if not client:
            # Crear demo
            estado = 'demo'
            dias_demo = 15
            fecha_activacion = now
            fecha_expiracion = now + timedelta(days=dias_demo)

            self.db[nit] = {
                'nit': nit,
                'instalacion_id': instalacion_id,
                'estado': estado,
                'fecha_activacion': fecha_activacion,
                'fecha_expiracion': fecha_expiracion,
                'dias_demo': dias_demo
            }
            dias_restantes = dias_demo
        else:
            # Actualizar
            client['instalacion_id'] = instalacion_id
            estado = client['estado']
            fecha_expiracion = client['fecha_expiracion']

            # Re-evaluar estado si ya expiró
            if estado != 'bloqueado' and now > fecha_expiracion:
                estado = 'bloqueado'
                client['estado'] = 'bloqueado'

            if now > fecha_expiracion:
                dias_restantes = 0
            else:
                dias_restantes = days_between(fecha_expiracion, now)

        return {
            'estado': estado,
            'expira': format_date(fecha_expiracion),
            'dias_restantes': dias_restantes
        }

    def validar(self, nit, instalacion_id, now=None):
        if now is None:
            now = datetime.now()

        client = self.db.get(nit)
        if not client:
            return "no_autorizado"

        estado = client['estado']
        fecha_expiracion = client['fecha_expiracion']

        if estado != 'bloqueado':
            if now > fecha_expiracion:
                estado = 'bloqueado'
                client['estado'] = 'bloqueado'

        if now > fecha_expiracion:
            dias_restantes = 0
        else:
            dias_restantes = days_between(fecha_expiracion, now)

        return {
            'estado': estado,
            'expira': format_date(fecha_expiracion),
            'dias_restantes': dias_restantes
        }

def test_licensing():
    logic = LicenciaLogic()
    now = datetime(2025, 1, 1)

    # 1. Activar nuevo (demo)
    res = logic.activar("900123456", "GUID-1", now=now)
    assert res['estado'] == 'demo'
    assert res['dias_restantes'] == 15
    assert res['expira'] == '2025-01-16'
    print("Test 1 Passed: Activar nuevo (demo)")

    # 2. Validar demo (mismo día)
    res = logic.validar("900123456", "GUID-1", now=now)
    assert res['estado'] == 'demo'
    assert res['dias_restantes'] == 15
    print("Test 2 Passed: Validar demo (mismo día)")

    # 3. Validar demo (10 días después)
    ten_days_later = now + timedelta(days=10)
    res = logic.validar("900123456", "GUID-1", now=ten_days_later)
    assert res['estado'] == 'demo'
    assert res['dias_restantes'] == 5
    print("Test 3 Passed: Validar demo (10 días después)")

    # 4. Validar expirado (16 días después)
    expired_date = now + timedelta(days=16)
    res = logic.validar("900123456", "GUID-1", now=expired_date)
    assert res['estado'] == 'bloqueado'
    assert res['dias_restantes'] == 0
    print("Test 4 Passed: Validar expirado")

    # 5. Activar existente (actualizar GUID) - ya está bloqueado por el test anterior
    res = logic.activar("900123456", "GUID-2", now=now)
    assert res['estado'] == 'bloqueado'
    assert logic.db['900123456']['instalacion_id'] == 'GUID-2'
    print("Test 5 Passed: Activar existente (actualizar GUID)")

    # 6. Caso Activo (Simulado)
    logic.db['900123456']['estado'] = 'activo'
    logic.db['900123456']['fecha_expiracion'] = now + timedelta(days=30)
    res = logic.validar("900123456", "GUID-2", now=now)
    assert res['estado'] == 'activo'
    assert res['dias_restantes'] == 30
    print("Test 6 Passed: Caso Activo")

if __name__ == "__main__":
    test_licensing()
