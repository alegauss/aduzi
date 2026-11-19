#Requires -Version 5.1
<#
.SYNOPSIS
  Puts the .NET SDK global.json names in the guest, where run-tests-vm.cmd and the other guest
  runners build (QS394). Run once per SDK pin; running it again changes nothing that is already right.

.DESCRIPTION
  global.json pins one SDK patch, because that patch decides the runtime a release ships and
  THIRD-PARTY-NOTICES.md lists that runtime at that version. A guest without it builds nothing:
  dotnet refuses before restore, and the runner reports no test application at all.

  The SDK goes where the guest's others are, %LOCALAPPDATA%\Microsoft\dotnet of the account vmrun
  runs as, which is the DOTNET_ROOT every runner sets. Microsoft's dotnet-install.ps1 is fetched on
  the host and carried in; it downloads the SDK in the guest and checks it against the hash the
  release publishes. Nothing else is installed or removed: the SDKs already there stay.
#>
[CmdletBinding()]
param(
    [string] $Vmx
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Tool = 'provision-guest-sdk'
$script:RepoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'vm-guest.ps1')

$version = (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'global.json') -Raw | ConvertFrom-Json).sdk.version
if (-not $version) { Refuse 'global.json names no SDK version' }

$stage = Join-Path ([IO.Path]::GetTempPath()) 'quickshell-vm-sdk'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
$null = New-Item -ItemType Directory -Path $stage

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -UseBasicParsing -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile (Join-Path $stage 'dotnet-install.ps1')

@"
`$ErrorActionPreference = 'Stop'
`$root = Join-Path `$env:LOCALAPPDATA 'Microsoft\dotnet'
if (Test-Path -LiteralPath (Join-Path `$root 'sdk\$version\dotnet.dll')) { 'OK'; exit 0 }
& '$script:GuestSync\dotnet-install.ps1' -Version $version -InstallDir `$root -NoPath
if (-not (Test-Path -LiteralPath (Join-Path `$root 'sdk\$version\dotnet.dll'))) { 'REFUSED the SDK is not where it was installed'; exit 2 }
'OK placed SDK $version'
"@ | Set-Content -LiteralPath (Join-Path $stage 'sdk.ps1') -Encoding ascii

@"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$script:GuestSync\sdk.ps1" > "$script:GuestSync\sdk.log" 2>&1
exit /b %ERRORLEVEL%
"@ | Set-Content -LiteralPath (Join-Path $stage 'sdk.cmd') -Encoding ascii

$vmxPath = Connect-Guest -Vmx $Vmx
$null = Invoke-VmRun -Guest -Arguments @('createDirectoryInGuest', $vmxPath, $script:GuestSync)

foreach ($file in @('dotnet-install.ps1', 'sdk.ps1', 'sdk.cmd')) {
    $sent = Invoke-VmRun -Guest -Arguments @('copyFileFromHostToGuest', $vmxPath, (Join-Path $stage $file), "$script:GuestSync\$file")
    if (-not $sent.Ok) { Refuse "could not copy $file into the guest: $($sent.Output)" }
}

Write-Host "  guest       placing the .NET SDK $version"
$ran = Invoke-VmRun -Guest -Arguments @('runProgramInGuest', $vmxPath, "$script:GuestSync\sdk.cmd")

$log = Join-Path $stage 'sdk.log'
$null = Invoke-VmRun -Guest -Arguments @('copyFileFromGuestToHost', $vmxPath, "$script:GuestSync\sdk.log", $log)
$said = if (Test-Path -LiteralPath $log) { (Read-ConsoleText $log).Trim() } else { '' }
$last = ($said -split "`r?`n" | Select-Object -Last 1)

if (-not $ran.Ok -or $last -notmatch '^OK') {
    Refuse "the SDK was not placed in the guest: $said $($ran.Output)" 'The guest needs to reach dotnetcli.azureedge.net and builds.dotnet.microsoft.com.'
}

$done = $last -replace '^OK ?', ''
Write-Host "  guest       $(if ($done) { $done } else { "SDK $version already placed" })"
exit 0
