# PurchaseBridge - Integración ERP & DIAN XML

Backend REST desarrollado en Delphi utilizando el framework **Horse** y **FireDAC** para la conexión con bases de datos Firebird del sistema contable **ERP**.

El objetivo principal es procesar facturas electrónicas de la DIAN (Colombia) en formato XML, extrayendo información de proveedores y productos para validar su existencia en el sistema contable.

## Características

- **Singleton de Configuración**: Lectura eficiente del registro de Windows una sola vez al inicio.
- **Thread-Safe**: Implementación segura para entornos multihilo.
- **Parsing XML**: Extracción inteligente de datos desde facturas UBL/DIAN.
- **Seguridad**: Protección contra SQL Injection mediante validación de parámetros y consultas parametrizadas.

## Requisitos

- **Delphi 11+** (o versión compatible con Horse).
- **Boss** (Dependency Manager para Delphi).
- **Firebird 3.0+**.

## Estructura del Proyecto

- `config/`: Gestión de configuración (Singleton).
- `controllers/`: Definición de rutas y manejo de peticiones HTTP.
- `database/`: Gestión de conexiones FireDAC.
- `repositories/`: Capa de persistencia y consultas a Firebird.
- `services/`: Lógica de negocio (Parsing XML).

## Endpoints

### 1. Validar Proveedor
Verifica la existencia de un proveedor por su NIT en la tabla correspondiente al año.

- **GET** `/proveedor/:nit`
- **Query Params**: `anio` (opcional, por defecto el actual).
- **Respuesta**:
  ```json
  {
    "existe": true,
    "codigo": "123"
  }
  ```

### 2. Procesar Factura XML
Analiza un XML de la DIAN y valida el proveedor y cada uno de los productos.

- **POST** `/factura/xml`
- **Body**: XML de la factura (Raw).
- **Respuesta**:
  ```json
  {
    "proveedor": {
      "nit": "860002536",
      "existe": true,
      "codigo": "P001"
    },
    "productos": [
      {
        "referencia": "O60691031",
        "descripcion": "LAVAMANOS ALUVIA 60 CM",
        "existe": true
      }
    ]
  }
  ```

## Pruebas con Postman

1. Importa el archivo `PurchaseBridge.postman_collection.json` en Postman.
2. Asegúrate de que el servidor está corriendo en el puerto 9000.
3. Ejecuta las peticiones de prueba incluidas.
