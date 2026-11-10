#Requires -Version 5.1
<#
.SYNOPSIS
  Install the release archive on a desk that is not the operator's, look where Windows looks, start
  the installed copy, and take it away again the way the list of installed apps would.

.DESCRIPTION
  QS77. The suite installs into places of its own - a temporary folder, a registry key under a test's
  name - because an entry under the real key is an app in the list of whoever runs it. So the suite
  cannot say the one thing a user would: that the archive, unzipped on a real profile, installs
  there, starts from there, and leaves again.

  This says it, on the guest. The archive release.cmd built is unzipped there and installed with
  `--install --quiet` under the guest user's own token, which the log names - a medium one means no
  administrator was asked. Then the program folder, the Start menu shortcut and the uninstall entry
  are read back; the installed copy is started and has to reach its first interactive frame; the
  entry's own QuietUninstallString is run, which is what a deployment runs; and the three are read
  back again, gone, with the settings folder still there.

  A machine-wide install is asked for too, without elevation, and has to be refused with 740 -
  the code a deployment tool reads as "run this as an administrator".

.PARAMETER Archive
  The archive to install. The newest in artifacts\release unless given.

.PARAMETER Former
  An archive of the client from before it was renamed Aduzi (QS384), installed first with a saved
  session in its data folder. The Aduzi install over it then has to take away the old program folder,
  shortcut and entry, and its first start has to show that session, moved to %AppData%\Aduzi.

.NOTES
  Credentials and the .vmx come from a file outside this tree. vm-guest.ps1 says which.
#>
[CmdletBinding()]
param(
    [string] $Archive,

    [string] $Former,

    [string] $Vmx
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Tool = 'install-vm'
$script:RepoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'vm-guest.ps1')

if (-not $Archive) {
    $newest = Get-ChildItem -Path (Join-Path $script:RepoRoot 'artifacts\release') -Filter '*.zip' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newest) { $Archive = $newest.FullName }
}
if (-not $Archive -or -not (Test-Path -LiteralPath $Archive)) {
    Refuse 'there is no archive to install' 'Build one with release.cmd first.'
}
if ($Former -and -not (Test-Path -LiteralPath $Former)) {
    Refuse "there is no former archive at $Former" 'Name a quickshell-<version>-win-x64 archive built before the rename.'
}

$vmxPath = Connect-Guest -Vmx $Vmx

$stage = Join-Path ([IO.Path]::GetTempPath()) 'quickshell-vm-install'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
$null = New-Item -ItemType Directory -Path $stage

$null = Invoke-VmRun -Guest -Arguments @('createDirectoryInGuest', $vmxPath, $script:GuestSync)
Clear-GuestFile -Names @('install.log', 'release.zip', 'former.zip', 'install.ps1', 'install.cmd')

# Everything the guest does is in one script, and it writes one log: a line per thing read back, each
# saying ok or FAIL, and a verdict last. Single-quoted, so nothing in it is this host's to expand.
@'
$ErrorActionPreference = 'Stop'
$sync = '@SYNC@'
$log = Join-Path $sync 'install.log'
$script:failed = 0

function Say([string] $line) { Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }
function Check([bool] $held, [string] $what) {
    if ($held) { Say "ok    $what" } else { Say "FAIL  $what"; $script:failed++ }
}

try {
    # By the integrity level's SID and not its name, which whoami translates: a guest in another
    # language says Medium in that language.
    $sid = [regex]::Match((whoami /groups | Out-String), 'S-1-16-(\d+)').Groups[1].Value
    $level = switch ($sid) { '8192' { 'Medium' } '12288' { 'High' } '16384' { 'System' } default { "unknown (S-1-16-$sid)" } }
    Say "token $level"
    Check ($level -eq 'Medium') 'installed under a token with no administrator in it'

    # QS384: a copy installed under the old name, with a saved session, for the Aduzi install to replace.
    $formerZip = Join-Path $sync 'former.zip'
    $upgrading = Test-Path -LiteralPath $formerZip
    $formerData = Join-Path $env:APPDATA 'quickshell'
    $formerFolder = Join-Path $env:LOCALAPPDATA 'Programs\quickshell'
    $formerShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'quickshell.lnk'
    $formerKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\quickshell'
    $probe = 'qs384-upgrade-probe'

    if ($upgrading) {
        # A data folder under the new name already there is left alone by design, so none may be.
        foreach ($stale in @($formerData, (Join-Path $env:APPDATA 'Aduzi'))) {
            if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Recurse -Force }
        }

        $old = Join-Path $sync 'former'
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($formerZip, $old)
        $oldProgram = Join-Path $old 'quickshell\quickshell.exe'
        Check (Test-Path -LiteralPath $oldProgram) 'the former archive unzips to quickshell\quickshell.exe'

        $oldInstall = Start-Process -FilePath $oldProgram -ArgumentList '--install', '--quiet' -Wait -PassThru
        Check ($oldInstall.ExitCode -eq 0) "the former copy installs under its own name (it exited $($oldInstall.ExitCode))"
        Check ((Test-Path -LiteralPath $formerKey) -and (Test-Path -LiteralPath $formerShortcut) -and (Test-Path -LiteralPath $formerFolder)) 'the former copy has its folder, shortcut and entry'

        $null = New-Item -ItemType Directory -Path $formerData -Force
        # Without a byte-order mark, as the client writes it; Set-Content -Encoding UTF8 would add one.
        [IO.File]::WriteAllText((Join-Path $formerData 'sessions.json'),
            '{ "name": "", "children": [ { "name": "' + $probe + '", "host": "192.0.2.7", "settings": { "user": "probe" } } ] }',
            (New-Object Text.UTF8Encoding($false)))
    }

    $download = Join-Path $sync 'download'
    if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Recurse -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $sync 'release.zip'), $download)
    $portable = Join-Path $download 'aduzi\aduzi.exe'
    Check (Test-Path -LiteralPath $portable) "the archive unzips to one folder with aduzi.exe in it"

    $everyone = Start-Process -FilePath $portable -ArgumentList '--install', '--all-users', '--quiet' -Wait -PassThru
    Check ($everyone.ExitCode -eq 740) "--install --all-users without an administrator exits 740 (it exited $($everyone.ExitCode))"

    $installing = Start-Process -FilePath $portable -ArgumentList '--install', '--quiet' -Wait -PassThru
    Check ($installing.ExitCode -eq 0) "--install --quiet exits 0 (it exited $($installing.ExitCode))"

    $folder = Join-Path $env:LOCALAPPDATA 'Programs\Aduzi'
    $program = Join-Path $folder 'aduzi.exe'
    $files = @(Get-ChildItem -LiteralPath $folder -File -Recurse -ErrorAction SilentlyContinue).Count
    $archived = @(Get-ChildItem -LiteralPath (Join-Path $download 'aduzi') -File -Recurse).Count
    Check (Test-Path -LiteralPath $program) "the program is at $program"
    Check ($files -eq $archived - 1) "every file but the marker was installed ($files of $archived)"
    Check (-not (Test-Path -LiteralPath (Join-Path $folder 'aduzi.portable'))) 'the installed copy is not portable'

    $shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Aduzi.lnk'
    $link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
    Check (Test-Path -LiteralPath $shortcut) "the Start menu has $shortcut"
    Check ($link.TargetPath -eq $program) "it starts $($link.TargetPath)"
    Check ($link.WorkingDirectory -eq '%USERPROFILE%') "it starts in $($link.WorkingDirectory)"

    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Aduzi'
    $entry = Get-ItemProperty -LiteralPath $key
    Say "entry $($entry.DisplayName) $($entry.DisplayVersion), $($entry.EstimatedSize) KB, from $($entry.InstallLocation)"
    Check ($entry.DisplayName -eq 'Aduzi' -and $entry.InstallLocation -eq $folder) 'the list of installed apps names it and where it is'

    if ($upgrading) {
        Check (-not (Test-Path -LiteralPath $formerFolder)) "the former program folder is gone: $formerFolder"
        Check (-not (Test-Path -LiteralPath $formerShortcut)) 'the former Start menu shortcut is gone'
        Check (-not (Test-Path -LiteralPath $formerKey)) 'the former uninstall entry is gone, so one app is listed'
    }

    # The installed copy has to start, and a start is a frame with the shell's prompt on it.
    $report = Join-Path $sync 'installed-start.json'
    if (Test-Path -LiteralPath $report) { Remove-Item -LiteralPath $report -Force }
    $running = Start-Process -FilePath $program -ArgumentList '--startup-report', $report -PassThru
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path -LiteralPath $report) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
    Check (Test-Path -LiteralPath $report) 'the installed copy started and drew its first screen, Home or a shell'
    if (Test-Path -LiteralPath $report) { Say "start $((Get-Content -LiteralPath $report -Raw).Trim())" }

    if ($upgrading) {
        # The session saved under the old name, read by the new window: found by name in its
        # accessibility tree, not inferred from a file having moved.
        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
        $ae = [Windows.Automation.AutomationElement]
        $byProcess = New-Object Windows.Automation.PropertyCondition($ae::ProcessIdProperty, $running.Id)
        $byName = New-Object Windows.Automation.PropertyCondition($ae::NameProperty, $probe)
        $seen = $null
        $deadline = (Get-Date).AddSeconds(30)
        while (-not $seen -and (Get-Date) -lt $deadline) {
            $window = $ae::RootElement.FindFirst([Windows.Automation.TreeScope]::Children, $byProcess)
            if ($window) { $seen = $window.FindFirst([Windows.Automation.TreeScope]::Descendants, $byName) }
            if (-not $seen) { Start-Sleep -Milliseconds 500 }
        }
        Check ($null -ne $seen) "the new window shows the session saved under the old name ($probe)"
        if (-not $seen) {
            # What was there instead, so a miss says whether the window, the list or the row was absent.
            $windows = $ae::RootElement.FindAll([Windows.Automation.TreeScope]::Children, $byProcess)
            Say "      windows of pid $($running.Id): $(@($windows | ForEach-Object { $_.Current.Name }) -join ' | ')"
            foreach ($w in $windows) {
                $list = $w.FindFirst([Windows.Automation.TreeScope]::Descendants,
                    (New-Object Windows.Automation.PropertyCondition($ae::AutomationIdProperty, 'SessionsList')))
                if ($list) {
                    $rows = $list.FindAll([Windows.Automation.TreeScope]::Children, [Windows.Automation.Condition]::TrueCondition)
                    Say "      SessionsList rows: $(@($rows | ForEach-Object { $_.Current.Name }) -join ' | ')"
                } else { Say '      no SessionsList in it' }
            }
        }
        if ($seen) { Say "seen  $($seen.Current.ControlType.ProgrammaticName) '$($seen.Current.Name)'" }
        Check (-not (Test-Path -LiteralPath $formerData)) "%AppData%\quickshell was moved, not copied"
        Check ((Test-Path -LiteralPath (Join-Path $env:APPDATA 'Aduzi\sessions.json')) -and
               ((Get-Content -LiteralPath (Join-Path $env:APPDATA 'Aduzi\sessions.json') -Raw) -match $probe)) '%AppData%\Aduzi holds the saved session'
    }

    Stop-Process -Id $running.Id -Force -ErrorAction SilentlyContinue
    $running.WaitForExit()

    # Standing in for somebody's saved sessions, which an uninstall must not reach.
    $settings = Join-Path $env:APPDATA 'Aduzi'
    $null = New-Item -ItemType Directory -Path $settings -Force
    $kept = Join-Path $settings 'install-vm-kept.txt'
    Set-Content -LiteralPath $kept -Value 'an uninstall leaves this'

    # Exactly what the entry says to run, through cmd the way a deployment runs a command line.
    $removing = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList '/d', '/c', $entry.QuietUninstallString -Wait -PassThru
    Check ($removing.ExitCode -eq 0) "the entry's QuietUninstallString exits 0 (it exited $($removing.ExitCode))"

    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ((Test-Path -LiteralPath $folder) -and $clock.Elapsed.TotalSeconds -lt 30) { Start-Sleep -Milliseconds 250 }
    Check (-not (Test-Path -LiteralPath $folder)) "the program folder is gone ($([math]::Round($clock.Elapsed.TotalSeconds, 1)) s after the uninstall returned)"
    Check (-not (Test-Path -LiteralPath $shortcut)) 'the Start menu shortcut is gone'
    Check (-not (Test-Path -LiteralPath $key)) 'the uninstall entry is gone'
    Check (Test-Path -LiteralPath $kept) "the settings folder is still there: $settings"

    Remove-Item -LiteralPath $kept -Force
}
catch {
    Say "FAIL  $($_.Exception.Message)"
    $script:failed++
}

if ($script:failed -eq 0) { Say 'verdict pass' } else { Say "verdict FAIL ($($script:failed))" }
'@.Replace('@SYNC@', $script:GuestSync) | Set-Content -LiteralPath (Join-Path $stage 'install.ps1') -Encoding UTF8

@"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$script:GuestSync\install.ps1"
exit /b 0
"@ | Set-Content -LiteralPath (Join-Path $stage 'install.cmd') -Encoding ascii

Write-Host "  archive     $Archive"

$sent = Invoke-VmRun -Guest -Arguments @('copyFileFromHostToGuest', $vmxPath, (Resolve-Path -LiteralPath $Archive).Path, "$script:GuestSync\release.zip")
if (-not $sent.Ok) { Refuse "could not copy the archive into the guest: $($sent.Output)" }

if ($Former) {
    Write-Host "  former      $Former"
    $sent = Invoke-VmRun -Guest -Arguments @('copyFileFromHostToGuest', $vmxPath, (Resolve-Path -LiteralPath $Former).Path, "$script:GuestSync\former.zip")
    if (-not $sent.Ok) { Refuse "could not copy the former archive into the guest: $($sent.Output)" }
}

foreach ($file in @('install.ps1', 'install.cmd')) {
    $sent = Invoke-VmRun -Guest -Arguments @('copyFileFromHostToGuest', $vmxPath, (Join-Path $stage $file), "$script:GuestSync\$file")
    if (-not $sent.Ok) { Refuse "could not copy $file into the guest: $($sent.Output)" }
}

Write-Host '  installing, starting and uninstalling it in the guest' -ForegroundColor Cyan

# -interactive, because the installed copy is started and a window needs the logged-in desk.
$ran = Invoke-VmRun -Guest -Arguments @('runProgramInGuest', $vmxPath, '-interactive', "$script:GuestSync\install.cmd")
if (-not $ran.Ok) {
    if ($ran.Output -match 'logged in interactively') {
        Refuse 'the guest has no interactive desktop session' 'Log in at the guest console once, and leave it unlocked.'
    }
    Refuse "the guest never finished: $($ran.Output)"
}

$results = Join-Path $script:RepoRoot 'TestResults\vm'
if (-not (Test-Path -LiteralPath $results)) { $null = New-Item -ItemType Directory -Path $results -Force }
$log = Join-Path $results 'install.log'
if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

$back = Invoke-VmRun -Guest -Arguments @('copyFileFromGuestToHost', $vmxPath, "$script:GuestSync\install.log", $log)
if (-not $back.Ok) { Refuse 'the guest wrote no log, so what happened there is unknown' }

# Less the byte-order mark Windows PowerShell puts at the head of a UTF-8 file it creates.
$said = (Read-ConsoleText $log).Trim().TrimStart([char]0xFEFF)
foreach ($line in ($said -split "`r?`n")) {
    $colour = if ($line -like 'FAIL*' -or $line -like 'verdict FAIL*') { 'Red' } else { 'Gray' }
    Write-Host "  $line" -ForegroundColor $colour
}

if ($said -notmatch '(?m)^verdict pass\r?$') {
    Write-Host ''
    Write-Host "install-vm: FAILED - $log" -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host "install-vm: passed - $log" -ForegroundColor Green
exit 0
