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

## Configuración del Sistema

Para evitar la exposición de credenciales sensibles, el sistema utiliza un archivo de configuración `config.ini` que debe ubicarse en la misma carpeta que el ejecutable.

### Archivo config.ini

Crea un archivo llamado `config.ini` con la siguiente estructura:

```ini
[ERP]
User=USUARIO-ERP
Pass=tu_password_ERP

[BRIDGE]
User=SYSDBA
Pass=tu_password_bridge
Path=F:\Proyectos\delphi_backend\purchasebridge\backend\database\purchasebridge.fdb
```

> **Nota:** El archivo `config.ini` está incluido en el `.gitignore` para prevenir que tus contraseñas se suban al repositorio.

## Estructura del Proyecto

- `config/`: Gestión de configuración (Singleton).
- `controllers/`: Definición de rutas y manejo de peticiones HTTP.
- `database/`: Gestión de conexiones FireDAC.
- `repositories/`: Capa de persistencia y consultas a Firebird.
- `services/`: Lógica de negocio (Parsing XML).

## Pruebas con Postman

1. Importa el archivo `PurchaseBridge.postman_collection.json` en Postman.
2. Asegúrate de que el servidor está corriendo en el puerto 9000.
3. Ejecuta las peticiones de prueba incluidas.

## Prueba

Esta es una línea de prueba.

## Ejecución como Windows Service

Además del ejecutable de consola (`PurchaseBridge.dpr`), ahora existe un proyecto de servicio nativo (`PurchaseBridgeService.dpr`) que reutiliza la misma lógica de arranque/parada en `ServerMain.pas`.

### Flujo de arranque/parada

- `StartServer(...)` inicializa configuración, licencia, middleware, rutas y arranca Horse.
- `StopServer` detiene Horse de forma segura con `THorse.StopListen`.
- En el servicio (`service/PurchaseBridge.Service.pas`):
  - `ServiceStart` llama `StartServer(True, 3, 5000)` para iniciar en hilo separado.
  - `ServiceStop` llama `StopServer` para detenerlo limpiamente.

### Instalación rápida con sc.exe

```bat
sc create PurchaseBridgeService binPath= "C:\PurchaseBridge\PurchaseBridgeService.exe"
sc start PurchaseBridgeService
sc stop PurchaseBridgeService
```

> Ejecuta la consola de Windows como Administrador para crear/iniciar/detener servicios.
