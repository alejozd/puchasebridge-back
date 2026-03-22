# PurchaseBridge Node Backend (Express)

Migración del backend Delphi/Horse hacia Node.js + Express con arquitectura por capas.

## Arquitectura

- `src/routes`: definición de rutas HTTP.
- `src/controllers`: capa HTTP (request/response).
- `src/services`: lógica de negocio.
- `src/repositories`: acceso a datos Firebird.
- `src/config`: configuración, logger y conexión DB.
- `src/middlewares`: auth y manejo de errores.

## Requisitos

- Node.js 20+
- Firebird accesible para bases Helisa y Bridge

## Configuración

1. Copiar variables de entorno:
   ```bash
   cp .env.example .env
   ```
2. Ajustar credenciales y rutas Firebird en `.env`.

## Ejecución

```bash
npm install
npm run dev
```

Servidor por defecto en `http://localhost:9000`.

## Scripts

- `npm start`: producción.
- `npm run dev`: desarrollo con nodemon.

## Notas de migración

- Se replicaron las rutas y estructura de respuesta del proyecto Delphi.
- La autenticación conserva un token en memoria (igual que la sesión en memoria de Delphi).
- Se mantuvieron consultas SQL equivalentes hacia tablas Helisa y PurchaseBridge.
- **Supuesto documentado:** para operaciones Helisa complejas (OCMA/OCTR/DOCU) se ejecutan consultas SQL equivalentes, pero pueden requerir ajuste fino por versión específica del esquema Helisa en cada instalación.
