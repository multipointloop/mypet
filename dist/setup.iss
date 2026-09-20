; MyPet Windows installer script (Inno Setup 6)
; Build: ISCC.exe "E:\desktop pet\dist\setup.iss"
; Produces: dist\MyPet-Setup-1.0.1.exe

#define MyAppName "MyPet"
#define MyAppVersion "1.0.1"
#define MyAppPublisher "MyPet"
#define MyAppExeName "mypet.exe"
#define ReleaseDir "..\mypet\build\windows\x64\runner\Release"

[Setup]
AppId={{8E7B6C3A-52F1-4B7D-9A34-1A2B3C4D5E6F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\MyPet
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=.
OutputBaseFilename=MyPet-Setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; \
    GroupDescription: "附加任务："; Flags: unchecked
Name: "autostart"; Description: "开机自动启动 MyPet"; \
    GroupDescription: "附加任务："; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: autostart

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; remove settings left behind
Type: filesandordirs; Name: "{app}\data"
