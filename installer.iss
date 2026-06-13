; GPU_BUILD produces the universal installer (CUDA bundled, auto CPU/GPU
; selection at runtime — works on machines with or without an NVIDIA GPU).
; The plain build is a smaller CPU-only installer, not currently published.
#ifdef GPU_BUILD
#define DistDir "dist-gpu\uttr-win"
#define OutputName "uttr-win-setup"
#else
#define DistDir "dist\uttr-win"
#define OutputName "uttr-win-cpu-setup"
#endif

[Setup]
AppName=uttr-win
AppVersion=0.1.0
AppPublisher=uttr-win
AppPublisherURL=https://github.com/SanjuEpic/free-wispr-flow
DefaultDirName={autopf}\uttr-win
DefaultGroupName=uttr-win
UninstallDisplayIcon={app}\uttr-win.exe
OutputBaseFilename={#OutputName}
Compression=lzma2/max
SolidCompression=yes
PrivilegesRequired=lowest
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"
Name: "startup"; Description: "Start uttr-win when Windows starts"; GroupDescription: "Startup:"

[Files]
Source: "{#DistDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\uttr-win"; Filename: "{app}\uttr-win.exe"
Name: "{group}\Uninstall uttr-win"; Filename: "{uninstallexe}"
Name: "{autodesktop}\uttr-win"; Filename: "{app}\uttr-win.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "uttr-win"; ValueData: """{app}\uttr-win.exe"""; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\uttr-win.exe"; Description: "Launch uttr-win"; Flags: nowait postinstall skipifsilent
