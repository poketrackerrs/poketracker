; Inno Setup script for PokeTracker (Windows installer + auto-update target)
#define MyAppName "PokeTracker"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Bay Group USA"
#define MyAppExeName "poketracker.exe"
#define ReleaseDir "C:\PokeTracker\build\windows\x64\runner\Release"

[Setup]
; Stable AppId so updates replace the same install (do not change).
AppId={{B7E1A2C4-1F3D-4E8A-9C2B-7A6D5E4F3210}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; Per-user install to LocalAppData so updates never need an admin prompt.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=C:\PokeTracker\dist
OutputBaseFilename=PokeTracker-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Close the app if it's running (so an update can overwrite files).
CloseApplications=yes
RestartApplications=no

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{userprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch PokeTracker"; Flags: nowait postinstall skipifsilent
