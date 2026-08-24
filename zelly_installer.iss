#define MyAppVersion "1.0.22"
#define MyAppName "ZELLY"
#define MyAppExe "tezzro.exe"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Zelly
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=C:\Users\Muhammadi\Desktop
OutputBaseFilename=ZellySetup_{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
; Silent install uchun (auto-update ishlashi uchun kerak)
DisableProgramGroupPage=yes
PrivilegesRequiredOverridesAllowed=dialog

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Asosiy exe
Source: "C:\Users\Muhammadi\Zelly\tezzro\build\windows\x64\runner\Release\tezzro.exe"; DestDir: "{app}"; Flags: ignoreversion
; Barcha DLL va qo'shimcha fayllar
Source: "C:\Users\Muhammadi\Zelly\tezzro\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Versiya fayli — auto-update uchun MUHIM, bo'lmasa yangilanish ishlamaydi
Source: "C:\Users\Muhammadi\Zelly\tezzro\version.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
