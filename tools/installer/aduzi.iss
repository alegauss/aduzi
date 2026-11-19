; Aduzi's Setup.exe (QS393). Built by tools\release.ps1, which passes every define below; by hand:
;
;   ISCC.exe /DPayload=<published folder> /DAppVersion=0.1.0 /DOutputName=aduzi-0.1.0-win-x64-setup tools\installer\aduzi.iss
;
; A wizard in front of the installer the client already is, not a second one. Installation.cs writes
; the program folder, the Start menu shortcut and the entry in the list of installed apps, retires an
; install made under the quickshell name, and refuses while the installed copy runs. Setup unpacks
; the build to {tmp} and runs `aduzi.exe --install --quiet` from there, so a copy installed by this
; wizard and one installed from the palette are the same install, removed by the same code.
;
; That is why there is no [Icons], no [Registry], no directory page and no uninstaller here: the
; client decides where it lives, and the entry it writes is what Installed apps runs to remove it.
;
; Every relative path resolves against this file's folder.

#ifndef Payload
  #define Payload "..\..\artifacts\publish\aduzi"
#endif
#ifndef AppVersion
  #define AppVersion GetVersionNumbersString(Payload + "\aduzi.exe")
#endif
#ifndef OutputName
  #define OutputName "aduzi-" + AppVersion + "-win-x64-setup"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\artifacts\release"
#endif

[Setup]
; Kept from the first release on. With Uninstallable=no Setup writes nothing against it, but it is
; what /LOG and a future uninstallable setup would recognise the product by.
AppId={{15610531-1325-44DB-B937-082FD104808A}
AppName=Aduzi
AppVersion={#AppVersion}
AppVerName=Aduzi {#AppVersion}
AppPublisher=Alexandre Oliveira
AppPublisherURL=https://alegauss.com/aduzi/
AppSupportURL=https://github.com/alegauss/aduzi/issues
VersionInfoVersion={#AppVersion}
VersionInfoDescription=Aduzi Setup

; For the person running it, with no administrator prompt - the same default `--install` has. The
; dialog lets somebody who can elevate choose every user instead, which is `--install --all-users`.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; The client picks the folder ({autopf}\Aduzi either way) and owns the uninstall entry.
CreateAppDir=no
Uninstallable=no
DisableProgramGroupPage=yes
DisableReadyPage=no

; Inno 6 hides the welcome page by default. It is the first thing this wizard has to say.
DisableWelcomePage=no

MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

SetupIconFile=..\..\assets\quickshell.ico
WizardStyle=modern
Compression=lzma2/ultra64
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}

; Nothing Setup writes is in use: the payload goes to {tmp}, and a running installed copy is the
; client's to refuse, which PrepareToInstall says in words before the install is attempted.
CloseApplications=no

; In the language Windows is in, with no dialog to ask; one is shown only where neither matches.
ShowLanguageDialog=auto

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"; \
    InfoBeforeFile: "before-en.txt"; InfoAfterFile: "after-en.txt"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"; \
    InfoBeforeFile: "before-pt.txt"; InfoAfterFile: "after-pt.txt"

[Messages]
english.WelcomeLabel2=This will install [name/ver], an SSH client for Windows: sessions, keys, SFTP, port forwards, tabs and split panes.%n%nThe next page says exactly what is installed and where. Close Aduzi if it is open before you continue.
; Appended by Setup under the reason PrepareToInstall gives, where its own "click Cancel to exit"
; contradicted the reason's "choose Back" - and Back does retry.
english.CannotContinue=Setup cannot continue until this is resolved.
brazilianportuguese.CannotContinue=O instalador não pode continuar até que isso seja resolvido.
brazilianportuguese.WelcomeLabel2=Este assistente vai instalar o [name/ver], um cliente SSH para Windows: sessões, chaves, SFTP, túneis, abas e painéis divididos.%n%nA próxima página diz exatamente o que será instalado e onde. Feche o Aduzi, se estiver aberto, antes de continuar.

[CustomMessages]
english.Running=Aduzi is open. Close every Aduzi window, then choose Back and Install to try again.%n%nSetup does not close it for you: an open session would lose whatever it was doing.
brazilianportuguese.Running=O Aduzi está aberto. Feche todas as janelas do Aduzi e escolha Voltar e Instalar para tentar de novo.%n%nO assistente não o fecha por você: uma sessão aberta perderia o que estava fazendo.
english.NeedsAdmin=Installing for every user needs an administrator, and Setup is not running as one. Run Setup again and choose "Install for all users", or install for yourself only.
brazilianportuguese.NeedsAdmin=Instalar para todos os usuários exige um administrador, e o assistente não está rodando como um. Rode o assistente de novo e escolha "Instalar para todos os usuários", ou instale só para você.
english.Failed=Aduzi was not installed (code %1). Nothing was changed: an install either replaces the copy that was there whole or leaves it as it was.%n%nThe message Aduzi showed before this one says why. Fix that, then run Setup again.
brazilianportuguese.Failed=O Aduzi não foi instalado (código %1). Nada foi alterado: uma instalação substitui a cópia anterior inteira ou a deixa como estava.%n%nA mensagem que o Aduzi mostrou antes desta diz o motivo. Resolva isso e rode o assistente de novo.
english.Installing=Installing Aduzi in its folder, Start menu and Installed apps...
brazilianportuguese.Installing=Instalando o Aduzi na pasta, no Menu Iniciar e em Aplicativos instalados...

[Files]
; The build, without the marker that would make it a portable copy. recursesubdirs because the
; runtime has folders of its own.
Source: "{#Payload}\*"; DestDir: "{tmp}\aduzi"; Excludes: "aduzi.portable"; \
    Flags: recursesubdirs createallsubdirs ignoreversion

; The same aduzi.exe again, stored once (MergeDuplicateFiles), and here for its AfterInstall: the last
; file entry is the one point where every file is in place and the [Run] entries have not yet been
; judged. Run from ssPostInstall instead, the install came after the finish page had already asked
; Installed and been told no - measured: the page offered no "launch Aduzi" box.
Source: "{#Payload}\aduzi.exe"; DestDir: "{tmp}\aduzi"; Flags: ignoreversion; AfterInstall: RunTheInstall

[Run]
; runasoriginaluser: an install for everyone ran elevated, and the window it opens belongs to the
; person at the desk, not to the administrator's token. skipifsilent, because a deployment does not
; put a window in somebody's session.
Filename: "{autopf}\Aduzi\aduzi.exe"; WorkingDir: "{%USERPROFILE}"; \
    Description: "{cm:LaunchProgram,Aduzi}"; \
    Flags: nowait postinstall skipifsilent runasoriginaluser; Check: Installed

[Code]
var
  // What `aduzi.exe --install` answered: 0 done, 740 needs an administrator, anything else not done.
  InstallCode: Integer;

function Installed: Boolean;
begin
  Result := InstallCode = 0;
end;

/// Whether a process is running from the installed copy's own path - the client's own refusal,
/// asked before the install rather than read back from an exit code that cannot say why.
function InstalledCopyRunning: Boolean;
var
  Path: string;
  Locator, Service, Found: Variant;
begin
  Result := False;
  Path := ExpandConstant('{autopf}\Aduzi\aduzi.exe');
  if not FileExists(Path) then
    Exit;

  // WQL wants every backslash doubled. A query that fails - WMI off, a policy - answers "not
  // running", and the client's own check still refuses, with the generic message below.
  StringChangeEx(Path, '\', '\\', True);
  StringChangeEx(Path, '''', '\''', True);
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Service := Locator.ConnectServer('.', 'root\CIMV2');
    Found := Service.ExecQuery(
      'SELECT ProcessId FROM Win32_Process WHERE Name = ''aduzi.exe'' AND ExecutablePath = '''
      + Path + '''');
    Result := Found.Count > 0;
  except
    Result := False;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  InstallCode := -1;
  if InstalledCopyRunning then
    Result := CustomMessage('Running');
end;

procedure RunTheInstall;
var
  Arguments: string;
begin
  Arguments := '--install --quiet';
  if IsAdminInstallMode then
    Arguments := Arguments + ' --all-users';

  WizardForm.StatusLabel.Caption := CustomMessage('Installing');

  if not Exec(ExpandConstant('{tmp}\aduzi\aduzi.exe'), Arguments, ExpandConstant('{tmp}\aduzi'),
              SW_HIDE, ewWaitUntilTerminated, InstallCode) then
    InstallCode := 1;

  // Under --quiet the client's reason is only an exit code. With somebody watching, the same install
  // is asked once more without it, so the client's own dialog names the reason - a file in use, a
  // former install still running - in its own words. A retry that succeeds is simply the install.
  if (InstallCode <> 0) and (InstallCode <> 740) and not WizardSilent then
  begin
    StringChangeEx(Arguments, ' --quiet', '', True);
    if not Exec(ExpandConstant('{tmp}\aduzi\aduzi.exe'), Arguments, ExpandConstant('{tmp}\aduzi'),
                SW_SHOW, ewWaitUntilTerminated, InstallCode) then
      InstallCode := 1;
  end;

  if InstallCode = 740 then
    SuppressibleMsgBox(CustomMessage('NeedsAdmin'), mbError, MB_OK, IDOK)
  else if InstallCode <> 0 then
    SuppressibleMsgBox(FmtMessage(CustomMessage('Failed'), [IntToStr(InstallCode)]),
                       mbError, MB_OK, IDOK);
end;

/// The page after installing teaches the first steps; a failed install has none to teach.
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = wpInfoAfter) and (InstallCode <> 0);
end;

/// Setup's own exit code says what the client's did, so a silent deployment sees a failure too.
function GetCustomSetupExitCode: Integer;
begin
  if InstallCode > 0 then
    Result := InstallCode
  else
    Result := 0;
end;
