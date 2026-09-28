; Inno Setup script for the Aimify desktop app.
; Build the app first, then compile this:
;   flutter build windows --release --dart-define=AIMIFY_API_URL=https://www.aimify.app
;   (copy build\windows\x64\runner\Release to dist\aimify-production)
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\aimify.iss

#define AppName "Aimify"
#define AppVersion "1.0.0"
#define AppPublisher "Aimify"
#define AppExe "aimify_desktop.exe"
#define SourceDir "..\dist\aimify-production"

[Setup]
AppId={{6F1D2A0C-4C57-4B0E-9B5A-A1F1D0A11F01}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
; Installs to C:\Program Files\Aimify (the 64-bit Program Files folder),
; which needs administrator rights - Windows asks for them once.
PrivilegesRequired=admin
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=Aimify-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Brand: the Aimify mark on the installer, the setup .exe and the uninstaller.
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardImageFile=assets\wizard-side-1x.bmp,assets\wizard-side-2x.bmp
WizardSmallImageFile=assets\wizard-small-1x.bmp,assets\wizard-small-2x.bmp
UninstallDisplayIcon={app}\{#AppExe}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
; App-local Visual C++ runtime, so the app starts on a clean machine.
Source: "C:\Windows\System32\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "C:\Windows\System32\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "C:\Windows\System32\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
