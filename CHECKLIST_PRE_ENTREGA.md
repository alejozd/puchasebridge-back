# Checklist de Validación Pre-Entrega (PurchaseBridge)

Utilice este checklist para verificar la correcta preparación del paquete de entrega y su validación posterior a la instalación.

## 📦 1. Preparación del Paquete (Lado Desarrollador)

- [ ] **Build del Frontend:** Se ejecutó `npm run build` y el contenido de `dist/` se copió a la carpeta `www/`.
- [ ] **Compilación Release:** El backend (`PurchaseBridgeService.exe`) se compiló en modo **Release**.
- [ ] **Dependencias:** El archivo `config.ini` de ejemplo está incluido.
- [ ] **Directorios:** El paquete incluye las carpetas `www/` y `assets/` (si aplica).
- [ ] **Instalador (Opcional):** Si existe un script de instalador, se verificó su funcionamiento en una máquina limpia.

## 🛠️ 2. Validación Post-Instalación (Lado Administrador)

### Configuración
- [ ] **Archivo INI:** Las credenciales del ERP en `config.ini` son válidas.
- [ ] **Licencia:** El NIT ingresado corresponde a la licencia activada.
- [ ] **Registro de Windows:** Helisa está correctamente registrado en el equipo (HKLM\Software\Helisa).

### Servicio y Red
- [ ] **Estado del Servicio:** El servicio "PurchaseBridgeService" figura como "En ejecución" en Windows Services.
- [ ] **Firewall:** Se creó la regla de entrada para el puerto 9000.
- [ ] **Health Check:** El endpoint `http://localhost:9000/ping` responde con `status: ok`.

### Funcionalidad
- [ ] **Acceso Web:** El frontend carga correctamente en un navegador (`http://localhost:9000`).
- [ ] **Procesamiento de XML:** Al colocar un archivo XML en la carpeta `Input\`, el sistema lo detecta (ver logs).
- [ ] **Movimiento de Archivos:** El archivo procesado se mueve correctamente a la carpeta `Processed\`.
- [ ] **Logs:** El archivo `Logs\app.log` se genera y registra las actividades iniciales sin errores críticos.

## 🆘 3. En caso de Fallo Crítico

- [ ] **Revisión de Logs:** Inspeccionar `Logs\app.log` para identificar la excepción.
- [ ] **Verificación de Puerto:** Asegurarse de que el puerto 9000 no esté ocupado (`netstat -ano | findstr :9000`).
- [ ] **Permisos:** El usuario del servicio tiene permisos de escritura en la carpeta de instalación.
