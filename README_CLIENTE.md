# PurchaseBridge - Guía del Administrador del Sistema

Esta documentación proporciona las instrucciones necesarias para la instalación, configuración y mantenimiento de **PurchaseBridge**, el sistema de integración entre facturación electrónica DIAN y el ERP Helisa.

## 1. 📦 Requisitos del Sistema

*   **Sistema Operativo:** Windows 10 o Windows Server 2016 (o superior).
*   **Arquitectura:** 32 bits o 64 bits (el servicio se ejecuta en 32 bits).
*   **Dependencias:**
    *   Firebird 3.0+ instalado y en ejecución.
    *   Acceso a la base de datos del ERP Helisa.
*   **Red:**
    *   Puerto **9000** disponible (TCP).
    *   Conexión a Internet (para validación de licencia).

## 2. 📂 Estructura de Carpetas Sugerida

Se recomienda instalar la aplicación en `C:\PurchaseBridge\`. La estructura esperada es:

```text
C:\PurchaseBridge\
├── PurchaseBridgeService.exe  # Ejecutable del Servicio de Windows
├── config.ini                 # Archivo de configuración
├── www\                       # Archivos del Frontend (React)
│   ├── index.html
│   └── assets\
├── Input\                     # Carpeta para colocar XMLs a procesar
├── Processed\                 # Carpeta donde se mueven los XMLs procesados
├── Logs\                      # Registro de eventos (app.log)
└── Scripts\                   # Scripts de mantenimiento (opcional)
```

## 3. 🚀 Instalación Paso a Paso

### Paso 1: Copiar Archivos
Copie el contenido de la carpeta de distribución a `C:\PurchaseBridge\`. Asegúrese de que el usuario que ejecuta el servicio tenga permisos de lectura/escritura sobre esta carpeta.

### Paso 2: Configuración Inicial
Edite el archivo `config.ini` con las credenciales de la base de datos y la licencia:

```ini
[HELISA]
Empresa=1
; Otras configuraciones detectadas automáticamente del registro

[LICENCIA]
Nit=123456789
App=purchasebridge
URLServidor=https://api.zdevs.uk

[LOGGING]
LogLevel=INFO
```

### Paso 3: Instalar el Servicio de Windows
Abra una consola de comandos (**PowerShell** o **CMD**) como **Administrador** y ejecute:

```powershell
# Crear el servicio
sc.exe create PurchaseBridgeService binPath= "C:\PurchaseBridge\PurchaseBridgeService.exe" start= auto

# Iniciar el servicio
sc.exe start PurchaseBridgeService
```

### Paso 4: Abrir Puerto en Firewall
Para permitir el acceso al frontend desde otros equipos, ejecute el siguiente comando en PowerShell (como Administrador):

```powershell
New-NetFirewallRule -DisplayName "PurchaseBridge" -Direction Inbound -LocalPort 9000 -Protocol TCP -Action Allow
```

## 4. 🌐 Acceso y Uso

### Acceso al Frontend
Desde cualquier navegador en la red local, acceda a:
`http://<IP_DEL_SERVIDOR>:9000`

### Flujo de Trabajo Básico
1.  Coloque los archivos XML de la DIAN en la carpeta `C:\PurchaseBridge\Input\`.
2.  El sistema detectará y procesará los archivos automáticamente.
3.  Verifique el estado del procesamiento en la interfaz web.
4.  Los archivos procesados se moverán a `C:\PurchaseBridge\Processed\`.

## 5. 🛠️ Mantenimiento Básico

### Verificación de Estado (Health Check)
Puede verificar si el servidor responde correctamente accediendo a:
`http://localhost:9000/ping`

### Logs del Sistema
Los eventos y errores se registran en formato JSON en:
`C:\PurchaseBridge\Logs\app.log`

### Rotación de Logs
Se recomienda configurar una tarea programada en Windows para comprimir o eliminar logs antiguos de la carpeta `Logs\` cada 30 días para evitar el llenado del disco.

## 6. 🆘 Solución de Problemas Comunes

*   **El servicio no inicia:**
    *   Verifique `Logs\app.log` para mensajes de error.
    *   Asegúrese de que el puerto 9000 no esté siendo usado por otra aplicación (`netstat -ano | findstr :9000`).
    *   Verifique que la ruta de la base de datos en `config.ini` sea correcta.
*   **El Frontend no carga (404 o error de conexión):**
    *   Asegúrese de que la carpeta `www\` exista y contenga el archivo `index.html`.
    *   Verifique el Firewall de Windows.
*   **Error de Licencia (Sistema Bloqueado):**
    *   Asegúrese de que el servidor tenga salida a internet para conectar con `https://api.zdevs.uk`.
    *   Verifique que el NIT en `config.ini` sea el asignado para su licencia.

## 7. 📞 Soporte y Versión

*   **Versión:** 1.0.0
*   **Desarrollado por:** Equipo de Integraciones
*   **Soporte Técnico:** soporte@ejemplo.com
