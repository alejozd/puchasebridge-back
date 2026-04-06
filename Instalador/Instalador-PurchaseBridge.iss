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
Source: PurchaseBridgeService.exe; DestDir: {app}; Flags: ignoreversion
Source: config.ini; DestDir: {app}; Flags: ignoreversion
Source: PURCHASEBRIDGE.FDB; DestDir: {app}; Flags: ignoreversion

[Run]
Filename: {sys}\sc.exe; Parameters: "create PurchaseBridgeService binPath= ""{app}\PurchaseBridgeService.exe"" start= auto"; Flags: runhidden waituntilterminated
Filename: {sys}\sc.exe; Parameters: "description PurchaseBridgeService ""Servicio PurchaseBridge"""; Flags: runhidden waituntilterminated
Filename: {sys}\sc.exe; Parameters: failure PurchaseBridgeService reset= 0 actions= restart/60000/restart/60000/restart/60000; Flags: runhidden waituntilterminated


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

procedure UpdateConfigFile();
var
  FilePath: string;
  Lines: TStringList;
  i: Integer;
  InstallPath: string;
begin
  FilePath := ExpandConstant('{app}\config.ini');
  InstallPath := ExpandConstant('{app}') + '\PURCHASEBRIDGE.FDB';

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
    UpdateConfigFile();
    StartService();
  end;
end;
