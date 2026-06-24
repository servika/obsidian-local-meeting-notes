; Inno Setup script for AI Meeting Notes (Windows).
; Built by build-app.ps1 when ISCC.exe is on PATH:
;   ISCC /DMyAppVersion=0.1.0 /DMyAppDir=publish\app /Opublish scripts\installer.iss

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef MyAppDir
  #define MyAppDir "..\publish\app"
#endif

[Setup]
AppName=AI Meeting Notes
AppVersion={#MyAppVersion}
AppPublisher=Serg Bataev
DefaultDirName={autopf}\AI Meeting Notes
DefaultGroupName=AI Meeting Notes
UninstallDisplayIcon={app}\MeetingNotes.App.exe
OutputBaseFilename=AI-Meeting-Notes-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Files]
Source: "{#MyAppDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AI Meeting Notes"; Filename: "{app}\MeetingNotes.App.exe"
Name: "{autodesktop}\AI Meeting Notes"; Filename: "{app}\MeetingNotes.App.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\MeetingNotes.App.exe"; Description: "Launch AI Meeting Notes"; Flags: nowait postinstall skipifsilent