# PurchaseBridge - Integración ERP & DIAN XML

![Delphi 12](https://img.shields.io/badge/Delphi-12-blue.svg)
![Horse Framework](https://img.shields.io/badge/Framework-Horse-red.svg)
![React](https://img.shields.io/badge/Frontend-React-blue.svg)
![License](https://img.shields.io/badge/License-Proprietary-yellow.svg)

Backend REST de alto rendimiento desarrollado en **Delphi** utilizando el framework **Horse** y **FireDAC** para la integración con sistemas contables (Firebird).

El sistema automatiza el procesamiento de facturas electrónicas de la DIAN (Colombia) en formato XML (UBL 2.1), extrayendo metadatos de proveedores y productos para su validación y homologación en el ERP.

## 🏗️ Arquitectura y Stack Tecnológico

-   **Backend:** Delphi 12 (Modern Object Pascal).
-   **Framework Web:** [Horse](https://github.com/HashLoad/horse) (Minimalist web framework).
-   **Base de Datos:** Firebird 3.0+ / FireDAC.
-   **Frontend:** React + Vite (Desplegado como SPA en `/www`).
-   **Middleware:** Jhonson (JSON), CORS, HandleException, Auth (JWT), LicenseGuard.
-   **Logging:** Sistema de logs estructurados en JSON (uLogger).

## 📂 Estructura del Repositorio

-   `config/`: Gestión de configuración (Singleton con acceso a Registro y archivos INI).
-   `controllers/`: Endpoints REST organizados por dominio (XML, Proveedores, Licencia, etc.).
-   `database/`: Gestión de conexiones a Firebird.
-   `middleware/`: Capas de interceptación de peticiones (Seguridad, Logs, SPA Fallback).
-   `repositories/`: Capa de persistencia y consultas SQL.
-   `services/`: Lógica de negocio, parsing de XML UBL y servicios de validación.
-   `utils/`: Utilidades comunes (Logging, Gestión de Rutas, Respuestas de Error).
-   `service/`: Implementación del servicio nativo de Windows.
-   `www/`: Directorio para el build de producción del frontend.

## ⚙️ Configuración del Entorno de Desarrollo

### Backend (Delphi)
1.  Abrir el proyecto `PurchaseBridge.dproj` (Consola) o `PurchaseBridgeService.dproj` (Servicio) en Delphi 12.
2.  Instalar dependencias mediante **Boss**:
    ```bash
    boss install
    ```
3.  Configurar el archivo `config.ini` en la carpeta raíz (ver `README_CLIENTE.md` para detalles).
4.  Ejecutar en modo Debug (F9).

### Frontend (React)
1.  Navegar a la carpeta del proyecto frontend.
2.  Instalar dependencias:
    ```bash
    npm install
    ```
3.  Ejecutar en modo desarrollo con proxy al backend (puerto 9000):
    ```bash
    npm run dev
    ```

## 🏗️ Build de Producción

### Generación del Frontend
1.  Ejecutar `npm run build` en el proyecto React.
2.  Copiar el contenido de la carpeta `dist/` resultante al directorio `www/` del backend.

### Compilación del Backend
1.  En Delphi IDE, cambiar el Build Configuration a **Release**.
2.  Compilar el proyecto (`Shift + F9`).
3.  El ejecutable se generará en `Win32\Release` (o `Win64\Release`).

### Despliegue
Para instrucciones detalladas de instalación en el cliente final, consulte la [Guía del Administrador](README_CLIENTE.md).

## 📄 Licencia y Copyright

Copyright © 2024 - Todos los derechos reservados.
Este software es de código cerrado y propiedad exclusiva.
