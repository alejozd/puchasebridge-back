#define MyAppName "PurchaseBridge"
#define MyAppVersion "1.0"
#define MyAppPublisher "ZDevs"

[Setup]
AppId={{A1B2C3D4-1234-5678-ABCD-123456789000}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={pf}\PurchaseBridge
DefaultGroupName={#MyAppName}
OutputDir=Output
OutputBaseFilename=PurchaseBridgeInstaller
Compression=lzma
SolidCompression=true
PrivilegesRequired=admin
SetupIconFile=assets\PurchaseICO.ico
ShowLanguageDialog=no
LanguageDetectionMethod=locale
WizardImageFile=assets\Imagen_lateral.bmp
WizardSmallImageFile=assets\Imagen_supderecha.bmp
VersionInfoVersion=1.0
VersionInfoCompany=ZambranoSoft
VersionInfoProductName=PurchaseBridge
VersionInfoProductVersion=1.0

[Files]
; === BACKEND ===
Source: PurchaseBridgeService.exe; DestDir: {app}; Flags: ignoreversion restartreplace
Source: config.ini; DestDir: {app}; Flags: ignoreversion
Source: PURCHASEBRIDGE.FDB; DestDir: {app}; Flags: ignoreversion

; === FRONTEND (NUEVO) ===
; Carpeta www completa con todos los archivos estáticos de React
Source: www\*; DestDir: {app}\www; Flags: ignoreversion recursesubdirs createallsubdirs
Source: www\assets\*.*; DestDir: {app}\www\assets; Flags: ignoreversion recursesubdirs

; === SCRIPTS DE MANTENIMIENTO (OPCIONAL PERO RECOMENDADO) ===
; Source: Scripts\Rotate-Logs.ps1; DestDir: {app}\Scripts; Flags: ignoreversion
; Source: Scripts\Health-Check.ps1; DestDir: {app}\Scripts; Flags: ignoreversion
[Run]
; Instalar servicio de Windows
Filename: {sys}\sc.exe; Parameters: "create PurchaseBridgeService binPath= ""{app}\PurchaseBridgeService.exe"" start= auto"; Flags: runhidden waituntilterminated
Filename: {sys}\sc.exe; Parameters: "description PurchaseBridgeService ""Servicio PurchaseBridge - Parser de facturas XML"""; Flags: runhidden waituntilterminated
Filename: {sys}\sc.exe; Parameters: failure PurchaseBridgeService reset= 0 actions= restart/60000/restart/60000/restart/60000; Flags: runhidden waituntilterminated

; Abrir frontend en navegador tras instalación (opcional)
; Filename: "http://localhost:9000"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: {sys}\sc.exe; Parameters: stop PurchaseBridgeService; Flags: runhidden waituntilterminated skipifdoesntexist
Filename: {sys}\sc.exe; Parameters: delete PurchaseBridgeService; Flags: runhidden waituntilterminated skipifdoesntexist

[Languages]
Name: spanish; MessagesFile: compiler:Languages\Spanish.isl

[Code]
var
  EmpresaPage: TInputQueryWizardPage;

procedure InitializeWizard;
begin
  EmpresaPage := CreateInputQueryPage(
    wpSelectDir,
    'Configuración inicial',
    'Ingrese los datos requeridos',
    'Estos datos son necesarios para configurar el sistema'
  );

  EmpresaPage.Add('Código de Empresa:', False);
  EmpresaPage.Add('NIT:', False);
end;

function EsNumeroValido(const Valor: string): Boolean;
var
  Num: Integer;
begin
  Result := False;

  try
    Num := StrToInt(Valor);

    if (Num >= 0) and (Num <= 100) then
    begin
      if IntToStr(Num) = Valor then
        Result := True;
    end;

  except
    Result := False;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;

  if CurPageID = EmpresaPage.ID then
  begin
    if not EsNumeroValido(Trim(EmpresaPage.Values[0])) then
    begin
      MsgBox('El código de empresa debe ser un número entre 0 y 100 sin ceros a la izquierda.', mbError, MB_OK);
      Result := False;
      exit;
    end;

    if Trim(EmpresaPage.Values[1]) = '' then
    begin
      MsgBox('Debe ingresar el NIT.', mbError, MB_OK);
      Result := False;
      exit;
    end;
  end;
end;

// ? VALIDACIÓN: Verificar que la carpeta www existe ANTES de instalar
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  WwwPath: string;
begin
  Result := '';
  WwwPath := ExpandConstant('{src}\www');

  if not DirExists(WwwPath) then
  begin
    Result := 'Error: La carpeta "www" con el frontend no fue encontrada en el origen de instalación.' + #13#10 +
              'Por favor, compile el frontend con "npm run build" y copie la carpeta "dist" como "www" junto al instalador.';
    Exit;
  end;

  // Verificar que index.html existe (validación básica)
  if not FileExists(WwwPath + '\index.html') then
  begin
    Result := 'Error: El archivo "www\index.html" no fue encontrado. El frontend parece incompleto.';
    Exit;
  end;
end;

procedure UpdateConfigFile();
var
  FilePath: string;
  Lines: TStringList;
  i: Integer;
  InstallPath: string;
begin
  FilePath := ExpandConstant('{app}\config.ini');
  InstallPath := ExpandConstant('{app}') + '\PURCHASEBRIDGE.FDB';

  if not FileExists(FilePath) then Exit;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FilePath);

    for i := 0 to Lines.Count - 1 do
    begin
      if Pos('Empresa=', Lines[i]) = 1 then
        Lines[i] := 'Empresa=' + EmpresaPage.Values[0];

      if Pos('Path=', Lines[i]) = 1 then
        Lines[i] := 'Path=' + InstallPath;

      if Pos('Nit=', Lines[i]) = 1 then
        Lines[i] := 'Nit=' + EmpresaPage.Values[1];
    end;

    Lines.SaveToFile(FilePath);
  finally
    Lines.Free;
  end;
end;

procedure StartService();
var
  ResultCode: Integer;
begin
  Sleep(3000);

  // Forma más robusta (Windows nativo)
  if not Exec(
    ExpandConstant('{sys}\sc.exe'),
    'start PurchaseBridgeService',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
  begin
    MsgBox('No se pudo iniciar el servicio automáticamente. Inícielo manualmente.', mbError, MB_OK);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    CreateRequiredFolders();
    UpdateConfigFile();
    StartService();
  end;
end;
